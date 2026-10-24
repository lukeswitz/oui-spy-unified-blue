package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbRequest
import java.nio.ByteBuffer
import java.util.concurrent.TimeoutException
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.le16
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.le32
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.sleep

// Passive AR9271 monitor receiver (Alfa AWUS036NHA, TL-WN722N v1): receive only, never transmits.
internal class Ar9271Adapter(
    private val conn: UsbDeviceConnection,
    private val intf: UsbInterface,
    private val fw: ByteArray,
    private val log: (String) -> Unit,
) {
    private class Aborted : RuntimeException()
    private class HtcFrame(val epid: Int, val off: Int, val len: Int)
    private class Entry(var ssid: String?, var rssi: Int, var channel: Int, var lastSeen: Long, var isAp: Boolean, var auth: Int = 0)

    @Volatile private var stop = false
    private var closing = false
    private lateinit var epRx: UsbEndpoint
    private lateinit var epCtlIn: UsbEndpoint
    private lateinit var epCtlOut: UsbEndpoint
    private val ctlBuf = ByteArray(64)
    private var wmiEp = -1
    private var wmiSeq = 0
    private val wq = IntArray(Ar9271Regs.MAX_WRITES * 2)
    private var wn = 0

    private var macVersion = 0
    private var macRev = 0
    private var eep = ByteArray(0)
    private val macAddr = ByteArray(6)
    private var rxChainMask = 1
    private var txChainMask = 1
    private var txGainHigh = false
    private var resetPowerOn = false
    private var awake = false
    private var htcResetInit = true
    private var monitorAttached = false
    private var curFreq = 0
    private var spurLogged = false
    private var hwReady = false

    private var rxRemain = 0
    private var rxPad = 0
    private var rxPartial: ByteArray? = null
    private var rxPartialLen = 0
    private val table = LinkedHashMap<String, Entry>()
    private var exploreAt = 0L

    fun abort() { stop = true }

    fun run(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        conn.claimInterface(intf, true)
        if (!findEndpoints()) throw IllegalStateException("AR9271: endpoints not found")
        try {
            htcBringUp()
            hwInit()
            startRadio()
            attachMonitor()
            setChannel(Ar9271Regs.CHANNELS[0], false)
            log("AR9271: receiver live")
            rxLoop(onBatch)
        } catch (e: Aborted) {
            log("AR9271: stopped")
        } finally {
            closing = true
            shutdown()
            conn.releaseInterface(intf)
        }
    }

    private fun findEndpoints(): Boolean {
        var rx: UsbEndpoint? = null
        var cin: UsbEndpoint? = null
        var cout: UsbEndpoint? = null
        for (i in 0 until intf.endpointCount) {
            val ep = intf.getEndpoint(i)
            val isIn = ep.direction == UsbConstants.USB_DIR_IN
            when {
                ep.endpointNumber == Ar9271Regs.EP_RX && isIn && ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK -> rx = ep
                ep.endpointNumber == Ar9271Regs.EP_REG_IN && isIn && ep.type == UsbConstants.USB_ENDPOINT_XFER_INT -> cin = ep
                ep.endpointNumber == Ar9271Regs.EP_REG_OUT && !isIn && ep.type == UsbConstants.USB_ENDPOINT_XFER_INT -> cout = ep
            }
        }
        epRx = rx ?: return false
        epCtlIn = cin ?: return false
        epCtlOut = cout ?: return false
        return true
    }

    private fun htcBringUp() {
        if (probeFirmware()) {
            log("AR9271: firmware already running")
        } else {
            downloadFirmware()
            waitReady()
            for (svc in Ar9271Regs.SERVICES) {
                val ep = connectService(svc)
                if (svc == Ar9271Regs.SVC_WMI_CONTROL) wmiEp = ep
            }
            configPipeCredits()
            htcSend(0, be16(Ar9271Regs.HTC_MSG_SETUP_COMPLETE))
            sleep(50)
        }
        val v = wmiRaw(Ar9271Regs.WMI_GET_FW_VERSION, ByteArray(0), Ar9271Regs.WMI_TIMEOUT)
        if (v.size < 4) throw IllegalStateException("AR9271: firmware version reply short")
        val major = be16At(v, 0)
        val minor = be16At(v, 2)
        if (major != Ar9271Regs.FW_MAJOR || minor < Ar9271Regs.FW_MINOR_MIN) {
            throw IllegalStateException("AR9271: unsupported firmware $major.$minor")
        }
        log("AR9271: firmware $major.$minor")
    }

    private fun probeFirmware(): Boolean {
        val epid = Ar9271Regs.HTC_WMI_EPID_PROBE // unverified: target hands out endpoint 1 to the first connected service
        val seq = 0x7a7a
        val body = ByteArray(4)
        putBe16(body, 0, Ar9271Regs.WMI_GET_FW_VERSION)
        putBe16(body, 2, seq)
        val f = htcFrame(epid, body)
        val n = conn.bulkTransfer(epCtlOut, f, f.size, 200)
        if (n != f.size) return false
        val end = System.currentTimeMillis() + 150
        while (System.currentTimeMillis() < end) {
            val r = readCtl(50) ?: continue
            val h = parseHtc(r) ?: continue
            if (h.epid == epid && h.len >= 4 && be16At(r, h.off) == Ar9271Regs.WMI_GET_FW_VERSION &&
                be16At(r, h.off + 2) == seq
            ) {
                wmiEp = epid
                return true
            }
        }
        return false
    }

    private fun downloadFirmware() {
        if (fw.isEmpty()) throw IllegalStateException("AR9271: firmware missing")
        var off = 0
        var addr = Ar9271Regs.FW_LOAD_ADDR
        val buf = ByteArray(Ar9271Regs.FW_CHUNK)
        while (off < fw.size) {
            val n = minOf(Ar9271Regs.FW_CHUNK, fw.size - off)
            System.arraycopy(fw, off, buf, 0, n)
            val r = conn.controlTransfer(
                Ar9271Regs.DIR_OUT, Ar9271Regs.FW_DOWNLOAD, addr ushr 8, 0, buf, n, Ar9271Regs.CTL_TIMEOUT,
            )
            if (r < 0) {
                throw IllegalStateException("AR9271: firmware download failed at $off (replug the adapter if it was already running)")
            }
            off += n
            addr += n
        }
        val r = conn.controlTransfer(
            Ar9271Regs.DIR_OUT, Ar9271Regs.FW_DOWNLOAD_COMP, Ar9271Regs.FW_TEXT_ADDR ushr 8, 0, null, 0,
            Ar9271Regs.CTL_TIMEOUT,
        )
        if (r < 0) throw IllegalStateException("AR9271: firmware start failed")
    }

    private fun waitReady() {
        val end = System.currentTimeMillis() + Ar9271Regs.READY_TIMEOUT
        while (System.currentTimeMillis() < end) {
            if (stop) throw Aborted()
            val r = readCtl(200) ?: continue
            val h = parseHtc(r) ?: continue
            if (h.epid == 0 && h.len >= 2 && be16At(r, h.off) == Ar9271Regs.HTC_MSG_READY) return
        }
        throw IllegalStateException("AR9271: target not ready after firmware start")
    }

    private fun connectService(svc: Int): Int {
        val wmiSvc = svc == Ar9271Regs.SVC_WMI_CONTROL
        val m = ByteArray(10)
        putBe16(m, 0, Ar9271Regs.HTC_MSG_CONNECT_SERVICE)
        putBe16(m, 2, svc)
        m[6] = (if (wmiSvc) Ar9271Regs.PIPE_WMI_DL else Ar9271Regs.PIPE_DATA_DL).toByte()
        m[7] = (if (wmiSvc) Ar9271Regs.PIPE_WMI_UL else Ar9271Regs.PIPE_DATA_UL).toByte()
        htcSend(0, m)
        val end = System.currentTimeMillis() + Ar9271Regs.CTL_TIMEOUT
        while (System.currentTimeMillis() < end) {
            if (stop) throw Aborted()
            val r = readCtl(200) ?: continue
            val h = parseHtc(r) ?: continue
            if (h.epid != 0 || h.len < 8) continue
            if (be16At(r, h.off) != Ar9271Regs.HTC_MSG_CONNECT_RESPONSE || be16At(r, h.off + 2) != svc) continue
            if (u8(r, h.off + 4) != 0) throw IllegalStateException("AR9271: service 0x%x refused".format(svc))
            return u8(r, h.off + 5)
        }
        throw IllegalStateException("AR9271: service 0x%x connect timeout".format(svc))
    }

    private fun configPipeCredits() {
        val m = ByteArray(4)
        putBe16(m, 0, Ar9271Regs.HTC_MSG_CONFIG_PIPE)
        m[2] = Ar9271Regs.HTC_TX_PIPE.toByte()
        m[3] = Ar9271Regs.HTC_CREDITS.toByte()
        htcSend(0, m)
        val end = System.currentTimeMillis() + 300
        while (System.currentTimeMillis() < end) {
            val r = readCtl(100) ?: continue
            val h = parseHtc(r) ?: continue
            if (h.epid == 0 && h.len >= 2 && be16At(r, h.off) == Ar9271Regs.HTC_MSG_CONFIG_PIPE_RESPONSE) return
        }
    }

    private fun htcFrame(epid: Int, payload: ByteArray): ByteArray {
        val b = ByteArray(Ar9271Regs.HTC_HDR_LEN + payload.size)
        b[0] = epid.toByte()
        putBe16(b, 2, payload.size)
        System.arraycopy(payload, 0, b, Ar9271Regs.HTC_HDR_LEN, payload.size)
        return b
    }

    private fun htcSend(epid: Int, payload: ByteArray) {
        val f = htcFrame(epid, payload)
        val n = conn.bulkTransfer(epCtlOut, f, f.size, Ar9271Regs.CTL_TIMEOUT) // unverified: bulkTransfer on an interrupt endpoint
        if (n != f.size) throw IllegalStateException("AR9271: control OUT failed ($n)")
    }

    private fun readCtl(timeoutMs: Int): ByteArray? {
        val n = conn.bulkTransfer(epCtlIn, ctlBuf, ctlBuf.size, timeoutMs)
        return if (n > 0) ctlBuf.copyOf(n) else null
    }

    private fun parseHtc(b: ByteArray): HtcFrame? {
        val n = b.size
        if (n < Ar9271Regs.HTC_HDR_LEN) return null
        var o = 0
        if (u8(b, 0) == 0 && (u8(b, 1) and Ar9271Regs.HTC_FLAG_TRAILER) != 0 && n >= 12 &&
            be32At(b, 0) == Ar9271Regs.HTC_WATCHDOG_PATTERN
        ) {
            o = 4
        }
        val epid = u8(b, o)
        if (epid == Ar9271Regs.HTC_PANIC_EPID) throw IllegalStateException("AR9271: firmware panic")
        val trailer = if (epid != 0 && (u8(b, o + 1) and Ar9271Regs.HTC_FLAG_TRAILER) != 0) u8(b, o + 4) else 0
        val len = n - o - Ar9271Regs.HTC_HDR_LEN - trailer
        if (len < 0) return null
        return HtcFrame(epid, o + Ar9271Regs.HTC_HDR_LEN, len)
    }

    private fun wmiRaw(cmd: Int, payload: ByteArray, timeoutMs: Int): ByteArray {
        wmiSeq = (wmiSeq + 1) and 0xffff
        val seq = wmiSeq
        val body = ByteArray(4 + payload.size)
        putBe16(body, 0, cmd)
        putBe16(body, 2, seq)
        System.arraycopy(payload, 0, body, 4, payload.size)
        htcSend(wmiEp, body)
        val end = System.currentTimeMillis() + timeoutMs
        while (true) {
            if (stop && !closing) throw Aborted()
            val left = end - System.currentTimeMillis()
            if (left <= 0) break
            val r = readCtl(minOf(left, 250L).toInt()) ?: continue
            val h = parseHtc(r) ?: continue
            if (h.epid != wmiEp || h.len < 4) continue
            if ((be16At(r, h.off) and Ar9271Regs.WMI_EVENT_FLAG) != 0 || be16At(r, h.off + 2) != seq) continue
            return r.copyOfRange(h.off + 4, h.off + h.len)
        }
        throw IllegalStateException("AR9271: WMI command 0x%x timed out".format(cmd))
    }

    private fun wmi(cmd: Int, payload: ByteArray = ByteArray(0)): ByteArray {
        flushWrites()
        return wmiRaw(cmd, payload, Ar9271Regs.WMI_TIMEOUT)
    }

    private fun flushWrites() {
        if (wn == 0) return
        val p = ByteArray(wn * 8)
        for (i in 0 until wn * 2) putBe32(p, i * 4, wq[i])
        wn = 0
        wmiRaw(Ar9271Regs.WMI_REG_WRITE, p, Ar9271Regs.REG_TIMEOUT)
    }

    private fun rw(reg: Int, v: Int) {
        wq[wn * 2] = reg
        wq[wn * 2 + 1] = v
        wn++
        if (wn == Ar9271Regs.MAX_WRITES) flushWrites()
    }

    private fun rr(reg: Int): Int {
        flushWrites()
        val r = wmiRaw(Ar9271Regs.WMI_REG_READ, be32(reg), Ar9271Regs.REG_TIMEOUT)
        if (r.size < 4) throw IllegalStateException("AR9271: register read short")
        return be32At(r, 0)
    }

    private fun rrMulti(addrs: IntArray): IntArray {
        flushWrites()
        val p = ByteArray(addrs.size * 4)
        for (i in addrs.indices) putBe32(p, i * 4, addrs[i])
        val r = wmiRaw(Ar9271Regs.WMI_REG_READ, p, Ar9271Regs.REG_TIMEOUT)
        if (r.size < p.size) throw IllegalStateException("AR9271: multi register read short")
        return IntArray(addrs.size) { be32At(r, it * 4) }
    }

    private fun rmw(reg: Int, set: Int, clr: Int) = rw(reg, (rr(reg) and clr.inv()) or set)

    private fun rmwField(reg: Int, mask: Int, shift: Int, v: Int) = rmw(reg, (v shl shift) and mask, mask)

    private fun delayMs(ms: Int) {
        flushWrites()
        sleep(ms)
    }

    private fun waitReg(reg: Int, mask: Int, want: Int, timeoutMs: Int): Boolean {
        val end = System.currentTimeMillis() + timeoutMs
        do {
            if ((rr(reg) and mask) == want) return true
        } while (System.currentTimeMillis() < end)
        return false
    }

    private fun writeTable(t: LongArray) {
        var i = 0
        while (i + 1 < t.size) {
            rw(t[i].toInt(), t[i + 1].toInt())
            i += 2
        }
    }

    private fun hwInit() {
        readRevisions()
        setResetReg(RESET_POWER_ON)
        setPowerAwake()
        loadEeprom()
        hwReady = true
    }

    private fun readRevisions() {
        val srev = rr(Ar9271Regs.AR_SREV)
        if ((srev and Ar9271Regs.SREV_ID_MASK) != Ar9271Regs.SREV_ID_MASK) {
            throw IllegalStateException("AR9271: unexpected chip id 0x%08x".format(srev))
        }
        macVersion = (srev and Ar9271Regs.SREV_VERSION2) ushr Ar9271Regs.SREV_VERSION2_SHIFT
        macRev = (srev and Ar9271Regs.SREV_REVISION2) ushr Ar9271Regs.SREV_REVISION2_SHIFT
        if (macVersion != Ar9271Regs.SREV_VERSION_9271) {
            throw IllegalStateException("AR9271: unsupported chip version 0x%x".format(macVersion))
        }
        log("AR9271: chip revision $macRev")
    }

    private fun setResetReg(type: Int) {
        rw(Ar9271Regs.AR_RTC_FORCE_WAKE, Ar9271Regs.RTC_FORCE_WAKE_EN or Ar9271Regs.RTC_FORCE_WAKE_ON_INT)
        val t = if (!resetPowerOn) RESET_POWER_ON else type
        val ok = if (t == RESET_POWER_ON) setResetPowerOn() else setReset(t)
        if (!ok) throw IllegalStateException("AR9271: chip reset failed")
    }

    private fun setResetPowerOn(): Boolean {
        rw(Ar9271Regs.AR_RTC_FORCE_WAKE, Ar9271Regs.RTC_FORCE_WAKE_EN or Ar9271Regs.RTC_FORCE_WAKE_ON_INT)
        rw(Ar9271Regs.AR_RC, Ar9271Regs.RC_AHB)
        rw(Ar9271Regs.AR_RTC_RESET, 0)
        delayMs(1)
        rw(Ar9271Regs.AR_RC, 0)
        rw(Ar9271Regs.AR_RTC_RESET, 1)
        if (!waitReg(Ar9271Regs.AR_RTC_STATUS, Ar9271Regs.RTC_STATUS_M, Ar9271Regs.RTC_STATUS_ON, Ar9271Regs.WAIT_TIMEOUT_MS)) {
            return false
        }
        val ok = setReset(RESET_WARM)
        if (ok) resetPowerOn = true
        return ok
    }

    private fun setReset(type: Int): Boolean {
        rw(Ar9271Regs.AR_RTC_FORCE_WAKE, Ar9271Regs.RTC_FORCE_WAKE_EN or Ar9271Regs.RTC_FORCE_WAKE_ON_INT)
        val pending = rr(Ar9271Regs.AR_INTR_SYNC_CAUSE) and
            (Ar9271Regs.SYNC_LOCAL_TIMEOUT or Ar9271Regs.SYNC_RADM_CPL_TIMEOUT)
        if (pending != 0) {
            rw(Ar9271Regs.AR_INTR_SYNC_ENABLE, 0)
            rw(Ar9271Regs.AR_RC, Ar9271Regs.RC_HOSTIF or Ar9271Regs.RC_AHB)
        } else {
            rw(Ar9271Regs.AR_RC, Ar9271Regs.RC_AHB)
        }
        var rst = Ar9271Regs.RTC_RC_MAC_WARM
        if (type == RESET_COLD) rst = rst or Ar9271Regs.RTC_RC_MAC_COLD
        rw(Ar9271Regs.AR_RTC_RC, rst)
        delayMs(1)
        rw(Ar9271Regs.AR_RTC_RC, 0)
        if (!waitReg(Ar9271Regs.AR_RTC_RC, Ar9271Regs.RTC_RC_M, 0, Ar9271Regs.WAIT_TIMEOUT_MS)) return false
        rw(Ar9271Regs.AR_RC, 0)
        return true
    }

    private fun initPll() {
        rw(Ar9271Regs.AR_RTC_PLL_CONTROL, Ar9271Regs.PLL_CONTROL_2G)
        delayMs(1)
        rw(Ar9271Regs.AR9271_CORE_CLOCK, Ar9271Regs.AR9271_CORE_CLOCK_117MHZ)
        delayMs(1)
        rw(Ar9271Regs.AR_RTC_SLEEP_CLK, Ar9271Regs.RTC_FORCE_DERIVED_CLK)
    }

    private fun setPowerAwake() {
        if (awake) return
        if ((rr(Ar9271Regs.AR_RTC_STATUS) and Ar9271Regs.RTC_STATUS_M) == Ar9271Regs.RTC_STATUS_SHUTDOWN) {
            setResetReg(RESET_POWER_ON)
            initPll()
        }
        rmw(Ar9271Regs.AR_RTC_FORCE_WAKE, Ar9271Regs.RTC_FORCE_WAKE_EN, 0)
        delayMs(1)
        var up = false
        for (i in 0 until POWER_UP_POLLS) {
            if ((rr(Ar9271Regs.AR_RTC_STATUS) and Ar9271Regs.RTC_STATUS_M) == Ar9271Regs.RTC_STATUS_ON) {
                up = true
                break
            }
            delayMs(1)
            rmw(Ar9271Regs.AR_RTC_FORCE_WAKE, Ar9271Regs.RTC_FORCE_WAKE_EN, 0)
        }
        if (!up) throw IllegalStateException("AR9271: chip failed to wake")
        rmw(Ar9271Regs.AR_STA_ID1, 0, Ar9271Regs.STA_ID1_PWR_SAV)
        awake = true
    }

    private fun loadEeprom() {
        val magic = eepromWord(0)
        if (magic != Ar9271Regs.EEP_MAGIC) {
            throw IllegalStateException("AR9271: EEPROM magic 0x%04x unsupported".format(magic))
        }
        val words = IntArray(Ar9271Regs.EEP_WORDS)
        var i = 0
        while (i < words.size) {
            val n = minOf(Ar9271Regs.MAX_MULTI_READ, words.size - i)
            val addrs = IntArray(n) {
                Ar9271Regs.AR_EEPROM_BASE + ((Ar9271Regs.EEP_START_WORD + i + it) shl Ar9271Regs.EEPROM_WORD_SHIFT)
            }
            val vals = try {
                rrMulti(addrs)
            } catch (e: IllegalStateException) {
                IntArray(n) { eepromWord(Ar9271Regs.EEP_START_WORD + i + it) } // multi read unsupported by this firmware
            }
            for (j in 0 until n) words[i + j] = vals[j] and 0xffff
            i += n
        }
        eep = ByteArray(words.size * 2)
        for (w in words.indices) {
            eep[w * 2] = words[w].toByte()
            eep[w * 2 + 1] = (words[w] ushr 8).toByte()
        }
        val el = minOf(le16(eep, Ar9271Regs.EEP_BASE_LENGTH) / 2, words.size)
        var sum = 0
        for (w in 0 until el) sum = sum xor words[w]
        if (sum != 0xffff) throw IllegalStateException("AR9271: EEPROM checksum 0x%x".format(sum))
        val version = le16(eep, Ar9271Regs.EEP_BASE_VERSION)
        if (((version and 0xf000) ushr 12) != Ar9271Regs.EEP_VER_MAJOR || eepRev() < Ar9271Regs.EEP_MIN_REV) {
            throw IllegalStateException("AR9271: EEPROM version 0x%04x unsupported".format(version))
        }
        txGainHigh = ee(Ar9271Regs.EEP_BASE_TXGAIN_TYPE) == Ar9271Regs.EEP_TXGAIN_HIGH_POWER
        val chipMask = 3
        val rx = ee(Ar9271Regs.EEP_BASE_RX_MASK) and chipMask
        val tx = ee(Ar9271Regs.EEP_BASE_TX_MASK) and chipMask
        rxChainMask = if (rx != 0) rx else chipMask
        txChainMask = if (tx != 0) tx else chipMask
        System.arraycopy(eep, Ar9271Regs.EEP_BASE_MAC, macAddr, 0, 6)
        val allZero = macAddr.all { it.toInt() == 0 }
        if (allZero || (macAddr[0].toInt() and 1) != 0) {
            macAddr[0] = 0x02
            for (k in 1..4) macAddr[k] = 0
            macAddr[5] = 0x01
        }
    }

    private fun eepromWord(off: Int): Int {
        rr(Ar9271Regs.AR_EEPROM_BASE + (off shl Ar9271Regs.EEPROM_WORD_SHIFT))
        val busy = Ar9271Regs.EEPROM_STATUS_BUSY or Ar9271Regs.EEPROM_STATUS_PROT_ACCESS
        if (!waitReg(Ar9271Regs.AR_EEPROM_STATUS_DATA, busy, 0, Ar9271Regs.WAIT_TIMEOUT_MS)) {
            throw IllegalStateException("AR9271: EEPROM read timed out")
        }
        return rr(Ar9271Regs.AR_EEPROM_STATUS_DATA) and Ar9271Regs.EEPROM_STATUS_VAL
    }

    private fun ee(i: Int): Int = eep[i].toInt() and 0xff
    private fun eeLe32(i: Int): Int = le32(eep, i)
    private fun modal(off: Int): Int = ee(Ar9271Regs.EEP_MODAL + off)
    private fun eepRev(): Int = le16(eep, Ar9271Regs.EEP_BASE_VERSION) and 0x0fff

    private fun hwReset(freq: Int, fast: Boolean) {
        setPowerAwake()
        if (fast && fastChannelChange(freq)) {
            curFreq = freq
            return
        }
        hwResetFull(freq)
        curFreq = freq
    }

    private fun hwResetFull(freq: Int) {
        var defAnt = rr(Ar9271Regs.AR_DEF_ANTENNA)
        if (defAnt == 0) defAnt = 1
        val staId1 = rr(Ar9271Regs.AR_STA_ID1) and Ar9271Regs.STA_ID1_BASE_RATE_11B
        val ledMask = Ar9271Regs.LED_ASSOC_CTL or Ar9271Regs.LED_MODE_SEL or Ar9271Regs.LED_BLINK_THRESH_SEL or
            Ar9271Regs.LED_BLINK_SLOW
        val ledState = rr(Ar9271Regs.AR_CFG_LED) and ledMask
        rw(Ar9271Regs.AR_PHY_ACTIVE, Ar9271Regs.PHY_ACTIVE_DIS)
        if (htcResetInit) {
            rw(Ar9271Regs.AR9271_RESET_POWER_DOWN_CONTROL, Ar9271Regs.AR9271_RADIO_RF_RST)
            delayMs(1)
        }
        chipReset()
        if (htcResetInit) {
            htcResetInit = false
            rw(Ar9271Regs.AR9271_RESET_POWER_DOWN_CONTROL, Ar9271Regs.AR9271_GATE_MAC_CTL)
            delayMs(1)
        }
        rmw(Ar9271Regs.AR_GPIO_INPUT_EN_VAL, Ar9271Regs.GPIO_JTAG_DISABLE, 0)
        processIni()
        rw(Ar9271Regs.AR_PHY_MODE, Ar9271Regs.PHY_MODE_DYNAMIC)
        initMfp()
        setDeltaSlope(freq)
        spurMitigate(freq)
        setBoardValues()
        resetOpmode(staId1, defAnt)
        rfSetFreq(freq)
        initInterruptMasks()
        initGlobalSettings()
        rmw(Ar9271Regs.AR_STA_ID1, Ar9271Regs.STA_ID1_PRESERVE_SEQNUM, 0)
        setDma()
        rw(Ar9271Regs.AR_OBS, Ar9271Regs.OBS_VALUE)
        rmwField(Ar9271Regs.AR_RIMT, Ar9271Regs.RIMT_LAST, 0, Ar9271Regs.RIMT_LAST_VALUE)
        rmwField(Ar9271Regs.AR_RIMT, Ar9271Regs.RIMT_FIRST, 16, Ar9271Regs.RIMT_FIRST_VALUE)
        initBb()
        initCal()
        rw(Ar9271Regs.AR_CFG_LED, ledState or Ar9271Regs.CFG_SCLK_32KHZ)
        rw(Ar9271Regs.AR_CFG, Ar9271Regs.CFG_SWRB or Ar9271Regs.CFG_SWTB)
        flushWrites()
    }

    private fun chipReset() {
        val cold = rr(Ar9271Regs.AR_Q_TXE) != 0 || (rr(Ar9271Regs.AR_CR) and Ar9271Regs.CR_RXE) != 0
        setResetReg(if (cold) RESET_COLD else RESET_WARM)
        setPowerAwake()
        initPll()
    }

    private fun processIni() {
        rw(Ar9271Regs.AR_PHY_BASE, 7)
        rw(Ar9271Regs.AR_PHY_ADC_SERIAL_CTL, Ar9271Regs.SEL_EXTERNAL_RADIO)
        rw(Ar9271Regs.AR_PHY_ADC_SERIAL_CTL, Ar9271Regs.SEL_INTERNAL_ADDAC)
        writeTable(Ar9271Regs.INI_MODES_2G_HT20)
        writeTable(if (txGainHigh) Ar9271Regs.INI_TXGAIN_HIGH else Ar9271Regs.INI_TXGAIN_NORMAL)
        if (macRev == 0) {
            rmw(Ar9271Regs.AR_PHY_SPECTRAL_SCAN, Ar9271Regs.SPECTRAL_SCAN_ENA, 0)
            rmwField(Ar9271Regs.AR_PHY_RF_CTL3, Ar9271Regs.RF_CTL3_TX_END_TO_ADC_ON, Ar9271Regs.RF_CTL3_TX_END_TO_ADC_ON_SHIFT, 0xa)
        }
        writeTable(Ar9271Regs.INI_COMMON)
        rmw(Ar9271Regs.AR_DIAG_SW, Ar9271Regs.DIAG_RX_DIS or Ar9271Regs.DIAG_RX_ABORT, 0)
        val mode2 = rr(Ar9271Regs.AR_PCU_MISC_MODE2) and Ar9271Regs.MODE2_ADHOC_MCAST_KEYID_ENABLE.inv()
        rw(Ar9271Regs.AR_PCU_MISC_MODE2, mode2 or Ar9271Regs.MODE2_CFP_IGNORE)
        val dacFifo = rr(Ar9271Regs.AR_PHY_TURBO) and Ar9271Regs.PHY_FC_ENABLE_DAC_FIFO
        rw(
            Ar9271Regs.AR_PHY_TURBO,
            Ar9271Regs.PHY_FC_HT_EN or Ar9271Regs.PHY_FC_SHORT_GI_40 or Ar9271Regs.PHY_FC_SINGLE_HT_LTF1 or
                Ar9271Regs.PHY_FC_WALSH or dacFifo,
        )
        rw(Ar9271Regs.AR_2040_MODE, 0)
        rw(Ar9271Regs.AR_GTXTO, 25 shl Ar9271Regs.TIMEOUT_LIMIT_SHIFT)
        rw(Ar9271Regs.AR_CST, 0xf shl Ar9271Regs.TIMEOUT_LIMIT_SHIFT)
        rw(Ar9271Regs.AR_PHY_RX_CHAINMASK, rxChainMask)
        rw(Ar9271Regs.AR_PHY_CAL_CHAINMASK, rxChainMask)
        rw(Ar9271Regs.AR_SELFGEN_MASK, txChainMask)
    }

    private fun initMfp() {
        rmwField(Ar9271Regs.AR_AES_MUTE_MASK1, Ar9271Regs.AES_MUTE_FC_MGMT_MASK, Ar9271Regs.AES_MUTE_FC_MGMT_SHIFT, 0xc7ff)
    }

    private fun deltaSlope(coefScaled: Int): IntArray {
        var exp = 31
        while (exp > 0) {
            if (((coefScaled ushr exp) and 1) != 0) break
            exp--
        }
        exp = 14 - (exp - Ar9271Regs.COEF_SCALE_S)
        val man = coefScaled + (1 shl (Ar9271Regs.COEF_SCALE_S - exp - 1))
        return intArrayOf(man ushr (Ar9271Regs.COEF_SCALE_S - exp), exp - 16)
    }

    private fun setDeltaSlope(freq: Int) {
        var coef = Ar9271Regs.DELTA_SLOPE_CLOCK_SCALED / freq
        val a = deltaSlope(coef)
        rmwField(Ar9271Regs.AR_PHY_TIMING3, Ar9271Regs.TIMING3_DSC_MAN, Ar9271Regs.TIMING3_DSC_MAN_SHIFT, a[0])
        rmwField(Ar9271Regs.AR_PHY_TIMING3, Ar9271Regs.TIMING3_DSC_EXP, Ar9271Regs.TIMING3_DSC_EXP_SHIFT, a[1])
        coef = (9 * coef) / 10
        val b = deltaSlope(coef)
        rmwField(Ar9271Regs.AR_PHY_HALFGI, Ar9271Regs.HALFGI_DSC_MAN, Ar9271Regs.HALFGI_DSC_MAN_SHIFT, b[0])
        rmwField(Ar9271Regs.AR_PHY_HALFGI, Ar9271Regs.HALFGI_DSC_EXP, Ar9271Regs.HALFGI_DSC_EXP_SHIFT, b[1])
    }

    private fun spurMitigate(freq: Int) {
        rmw(Ar9271Regs.AR_PHY_FORCE_CLKEN_CCK, 0, Ar9271Regs.FORCE_CLKEN_CCK_MRC_MUX)
        for (i in 0 until Ar9271Regs.M_SPUR_COUNT) {
            val spur = le16(eep, Ar9271Regs.EEP_MODAL + Ar9271Regs.M_SPUR + 4 * i)
            if (spur == Ar9271Regs.SPUR_NONE) break
            val bb = spur / 10 + Ar9271Regs.SPUR_BASE_FREQ_2G - freq
            if (bb > -Ar9271Regs.SPUR_BOUND_HT20 && bb < Ar9271Regs.SPUR_BOUND_HT20) {
                if (!spurLogged) {
                    log("AR9271: EEPROM lists a spur in band, mitigation not applied") // unverified: spur masks not ported
                    spurLogged = true
                }
                break
            }
        }
    }

    private fun setBoardValues() {
        rw(Ar9271Regs.AR_PHY_SWITCH_COM, eeLe32(Ar9271Regs.EEP_MODAL + Ar9271Regs.M_ANT_CTRL_COMMON))
        rmw(Ar9271Regs.AR_PHY_SWITCH_CHAIN_0, eeLe32(Ar9271Regs.EEP_MODAL + Ar9271Regs.M_ANT_CTRL_CHAIN0), 0)
        val iqMask = Ar9271Regs.TIMING_CTRL4_IQCORR_Q_I_COFF or Ar9271Regs.TIMING_CTRL4_IQCORR_Q_Q_COFF
        val iq = ((modal(Ar9271Regs.M_IQCAL_I) shl Ar9271Regs.TIMING_CTRL4_IQCORR_Q_I_COFF_SHIFT) and
            Ar9271Regs.TIMING_CTRL4_IQCORR_Q_I_COFF) or
            ((modal(Ar9271Regs.M_IQCAL_Q) shl Ar9271Regs.TIMING_CTRL4_IQCORR_Q_Q_COFF_SHIFT) and
                Ar9271Regs.TIMING_CTRL4_IQCORR_Q_Q_COFF)
        rmw(Ar9271Regs.AR_PHY_TIMING_CTRL4, iq, iqMask)
        var atten = Ar9271Regs.TXRX_ATTEN_DEFAULT
        if (eepRev() >= Ar9271Regs.EEP_REV_ATTEN) {
            atten = modal(Ar9271Regs.M_TXRX_ATTEN)
            for (base in intArrayOf(Ar9271Regs.AR_PHY_GAIN_2GHZ, Ar9271Regs.AR_PHY_GAIN_2GHZ + 0x1000)) {
                rmwField(base, Ar9271Regs.GAIN_2GHZ_XATTEN1_MARGIN, Ar9271Regs.GAIN_2GHZ_XATTEN1_MARGIN_SHIFT, modal(Ar9271Regs.M_BSW_MARGIN))
                rmwField(base, Ar9271Regs.GAIN_2GHZ_XATTEN1_DB, Ar9271Regs.GAIN_2GHZ_XATTEN1_DB_SHIFT, modal(Ar9271Regs.M_BSW_ATTEN))
                rmwField(base, Ar9271Regs.GAIN_2GHZ_XATTEN2_MARGIN, Ar9271Regs.GAIN_2GHZ_XATTEN2_MARGIN_SHIFT, modal(Ar9271Regs.M_XATTEN2_MARGIN))
                rmwField(base, Ar9271Regs.GAIN_2GHZ_XATTEN2_DB, Ar9271Regs.GAIN_2GHZ_XATTEN2_DB_SHIFT, modal(Ar9271Regs.M_XATTEN2_DB))
            }
        }
        for (base in intArrayOf(Ar9271Regs.AR_PHY_RXGAIN, Ar9271Regs.AR_PHY_RXGAIN + 0x1000)) {
            rmwField(base, Ar9271Regs.RXGAIN_TXRX_ATTEN, Ar9271Regs.RXGAIN_TXRX_ATTEN_SHIFT, atten)
            rmwField(base, Ar9271Regs.RXGAIN_TXRX_MARGIN, Ar9271Regs.RXGAIN_TXRX_MARGIN_SHIFT, modal(Ar9271Regs.M_RXTX_MARGIN))
        }
        val modalVer = modal(Ar9271Regs.M_VERSION)
        if (modalVer >= Ar9271Regs.MODAL_VER_ANTDIV) {
            val c1 = modal(Ar9271Regs.M_OB_4_ANTDIV1) ushr 4
            val c2 = modal(Ar9271Regs.M_DB1_4_ANTDIV2) ushr 4
            var v = rr(Ar9271Regs.AR_PHY_MULTICHAIN_GAIN_CTL) and Ar9271Regs.ANT_DIV_CTL_ALL.inv()
            v = v or ((c1 shl Ar9271Regs.ANT_DIV_CTL_SHIFT) and Ar9271Regs.ANT_DIV_CTL)
            v = v or ((c2 shl Ar9271Regs.ANT_DIV_ALT_LNACONF_SHIFT) and Ar9271Regs.ANT_DIV_ALT_LNACONF)
            v = v or (((c2 ushr 2) shl Ar9271Regs.ANT_DIV_MAIN_LNACONF_SHIFT) and Ar9271Regs.ANT_DIV_MAIN_LNACONF)
            v = v or (((c1 ushr 1) shl Ar9271Regs.ANT_DIV_ALT_GAINTB_SHIFT) and Ar9271Regs.ANT_DIV_ALT_GAINTB)
            v = v or (((c1 ushr 2) shl Ar9271Regs.ANT_DIV_MAIN_GAINTB_SHIFT) and Ar9271Regs.ANT_DIV_MAIN_GAINTB)
            rw(Ar9271Regs.AR_PHY_MULTICHAIN_GAIN_CTL, v)
            var cck = rr(Ar9271Regs.AR_PHY_CCK_DETECT) and Ar9271Regs.CCK_DETECT_BB_ENABLE_ANT_FAST_DIV.inv()
            cck = cck or (((c1 ushr 3) shl Ar9271Regs.CCK_DETECT_BB_ENABLE_ANT_FAST_DIV_SHIFT) and
                Ar9271Regs.CCK_DETECT_BB_ENABLE_ANT_FAST_DIV)
            rw(Ar9271Regs.AR_PHY_CCK_DETECT, cck)
        }
        val ob0 = modal(Ar9271Regs.M_OB_0_1) and 0xf
        val ob1 = modal(Ar9271Regs.M_OB_0_1) ushr 4
        val ob2 = modal(Ar9271Regs.M_OB_2_3) and 0xf
        val db1 = modal(Ar9271Regs.M_DB1_0_1) and 0xf
        val db2 = modal(Ar9271Regs.M_DB2_0_1) and 0xf
        val obPsk = if (modalVer >= 1) ob1 else ob0
        val obQam = if (modalVer >= Ar9271Regs.MODAL_VER_OB_DB) ob2 else if (modalVer == 1) ob1 else ob0
        val db2Val = if (modalVer >= 1) db2 else db1
        analogRmw(Ar9271Regs.AR_AN_RF2G3, Ar9271Regs.AN_RF2G3_OB_CCK, Ar9271Regs.AN_RF2G3_OB_CCK_SHIFT, ob0)
        analogRmw(Ar9271Regs.AR_AN_RF2G3, Ar9271Regs.AN_RF2G3_OB_PSK, Ar9271Regs.AN_RF2G3_OB_PSK_SHIFT, obPsk)
        analogRmw(Ar9271Regs.AR_AN_RF2G3, Ar9271Regs.AN_RF2G3_OB_QAM, Ar9271Regs.AN_RF2G3_OB_QAM_SHIFT, obQam)
        analogRmw(Ar9271Regs.AR_AN_RF2G3, Ar9271Regs.AN_RF2G3_DB_1, Ar9271Regs.AN_RF2G3_DB_1_SHIFT, db1)
        analogRmw(Ar9271Regs.AR_AN_RF2G4, Ar9271Regs.AN_RF2G4_DB_2, Ar9271Regs.AN_RF2G4_DB_2_SHIFT, db2Val)
        rmwField(Ar9271Regs.AR_PHY_SETTLING, Ar9271Regs.SETTLING_SWITCH, Ar9271Regs.SETTLING_SWITCH_SHIFT, modal(Ar9271Regs.M_SWITCH_SETTLING))
        rmwField(Ar9271Regs.AR_PHY_DESIRED_SZ, Ar9271Regs.DESIRED_SZ_ADC, Ar9271Regs.DESIRED_SZ_ADC_SHIFT, modal(Ar9271Regs.M_ADC_DESIRED))
        val xpaOff = modal(Ar9271Regs.M_TX_END_XPA_OFF)
        val xpaOn = modal(Ar9271Regs.M_TX_FRAME_XPA_ON)
        val rfCtl4 = ((xpaOff shl Ar9271Regs.RF_CTL4_TX_END_XPAA_OFF_SHIFT) and Ar9271Regs.RF_CTL4_TX_END_XPAA_OFF) or
            ((xpaOff shl Ar9271Regs.RF_CTL4_TX_END_XPAB_OFF_SHIFT) and Ar9271Regs.RF_CTL4_TX_END_XPAB_OFF) or
            ((xpaOn shl Ar9271Regs.RF_CTL4_FRAME_XPAA_ON_SHIFT) and Ar9271Regs.RF_CTL4_FRAME_XPAA_ON) or
            ((xpaOn shl Ar9271Regs.RF_CTL4_FRAME_XPAB_ON_SHIFT) and Ar9271Regs.RF_CTL4_FRAME_XPAB_ON)
        rmw(Ar9271Regs.AR_PHY_RF_CTL4, rfCtl4, 0)
        rmwField(Ar9271Regs.AR_PHY_RF_CTL3, Ar9271Regs.RF_CTL3_TX_END_TO_A2_RX_ON, Ar9271Regs.RF_CTL3_TX_END_TO_A2_RX_ON_SHIFT, modal(Ar9271Regs.M_TX_END_RX_ON))
        rmwField(Ar9271Regs.AR_PHY_CCA, Ar9271Regs.CCA_THRESH62, Ar9271Regs.CCA_THRESH62_SHIFT, modal(Ar9271Regs.M_THRESH62))
        rmwField(Ar9271Regs.AR_PHY_EXT_CCA0, Ar9271Regs.EXT_CCA0_THRESH62, Ar9271Regs.EXT_CCA0_THRESH62_SHIFT, modal(Ar9271Regs.M_THRESH62))
        if (eepRev() >= Ar9271Regs.EEP_REV_RF_CTL2) {
            rmwField(Ar9271Regs.AR_PHY_RF_CTL2, Ar9271Regs.RF_CTL2_TX_END_DATA_START, Ar9271Regs.RF_CTL2_TX_END_DATA_START_SHIFT, modal(Ar9271Regs.M_TX_FRAME_DATA_START))
            rmwField(Ar9271Regs.AR_PHY_RF_CTL2, Ar9271Regs.RF_CTL2_TX_END_PA_ON, Ar9271Regs.RF_CTL2_TX_END_PA_ON_SHIFT, modal(Ar9271Regs.M_TX_FRAME_PA_ON))
        }
    }

    private fun analogRmw(reg: Int, mask: Int, shift: Int, v: Int) {
        rmwField(reg, mask, shift, v)
        delayMs(1)
    }

    private fun resetOpmode(staId1: Int, defAnt: Int) {
        val defaults = Ar9271Regs.STA_ID1_CRPT_MIC_ENABLE or Ar9271Regs.STA_ID1_MCAST_KSRCH
        rmw(Ar9271Regs.AR_STA_ID1, staId1 or Ar9271Regs.STA_ID1_RTS_USE_DEF or defaults, Ar9271Regs.STA_ID1_SADH_MASK.inv())
        rw(Ar9271Regs.AR_STA_ID0, le32(macAddr, 0))
        val id1 = (rr(Ar9271Regs.AR_STA_ID1) and Ar9271Regs.STA_ID1_SADH_MASK.inv()) or le16(macAddr, 4)
        rw(Ar9271Regs.AR_STA_ID1, id1)
        rw(Ar9271Regs.AR_BSSMSKL, -1)
        rw(Ar9271Regs.AR_BSSMSKU, 0xffff)
        rw(Ar9271Regs.AR_DEF_ANTENNA, defAnt)
        rw(Ar9271Regs.AR_BSS_ID0, 0)
        rw(Ar9271Regs.AR_BSS_ID1, 0)
        rw(Ar9271Regs.AR_ISR, -1)
        rw(Ar9271Regs.AR_RSSI_THR, Ar9271Regs.INIT_RSSI_THR)
        val set = if (monitorAttached) Ar9271Regs.STA_ID1_KSRCH_MODE else 0
        rmw(Ar9271Regs.AR_STA_ID1, set, Ar9271Regs.STA_ID1_STA_AP or Ar9271Regs.STA_ID1_ADHOC)
    }

    private fun rfSetFreq(freq: Int) {
        val synth = rr(Ar9271Regs.AR_PHY_SYNTH_CONTROL) and 0xc0000000.toInt()
        val chanSel = ((freq.toLong() * 0x10000L) / 15L).toInt()
        val txctl = rr(Ar9271Regs.AR_PHY_CCK_TX_CTRL)
        if (freq == 2484) {
            rw(Ar9271Regs.AR_PHY_CCK_TX_CTRL, txctl or Ar9271Regs.CCK_TX_CTRL_JAPAN)
        } else {
            rw(Ar9271Regs.AR_PHY_CCK_TX_CTRL, txctl and Ar9271Regs.CCK_TX_CTRL_JAPAN.inv())
        }
        rw(Ar9271Regs.AR_PHY_SYNTH_CONTROL, synth or (1 shl 29) or (1 shl 28) or chanSel)
    }

    private fun initInterruptMasks() {
        val imr = Ar9271Regs.IMR_TXERR or Ar9271Regs.IMR_TXURN or Ar9271Regs.IMR_RXERR or Ar9271Regs.IMR_RXORN or
            Ar9271Regs.IMR_BCNMISC or Ar9271Regs.IMR_RXINTM or Ar9271Regs.IMR_RXMINTR or Ar9271Regs.IMR_TXOK
        rw(Ar9271Regs.AR_IMR, imr)
        rw(Ar9271Regs.AR_IMR_S2, Ar9271Regs.IMR_S2_GTT)
        rw(Ar9271Regs.AR_INTR_SYNC_CAUSE, -1)
        rw(Ar9271Regs.AR_INTR_SYNC_ENABLE, Ar9271Regs.SYNC_DEFAULT)
        rw(Ar9271Regs.AR_INTR_SYNC_MASK, 0)
    }

    private fun initGlobalSettings() {
        rmw(Ar9271Regs.AR_PCU_MISC, Ar9271Regs.PCU_MIC_NEW_LOC_ENA, 0)
        rmw(Ar9271Regs.AR_USEC, Ar9271Regs.USEC_2G_OFDM - 1, Ar9271Regs.USEC_MASK)
    }

    private fun setDma() {
        rmw(Ar9271Regs.AR_AHB_MODE, Ar9271Regs.AHB_PREFETCH_RD_EN, 0)
        rmw(Ar9271Regs.AR_TXCFG, Ar9271Regs.DMASZ_128B, Ar9271Regs.DMASZ_MASK)
        rmwField(Ar9271Regs.AR_TXCFG, Ar9271Regs.FTRIG_MASK, Ar9271Regs.FTRIG_SHIFT, Ar9271Regs.FTRIG_256B_LEVEL)
        rmw(Ar9271Regs.AR_RXCFG, Ar9271Regs.DMASZ_128B, Ar9271Regs.DMASZ_MASK)
        rw(Ar9271Regs.AR_RXFIFO_CFG, Ar9271Regs.RXFIFO_CFG_VALUE)
    }

    private fun synthDelay() {
        val d = rr(Ar9271Regs.AR_PHY_RX_DELAY) and Ar9271Regs.RX_DELAY_MASK
        val us = d / 10 + Ar9271Regs.BASE_ACTIVATE_DELAY_US
        delayMs(maxOf(1, us / 1000))
    }

    private fun initBb() {
        rw(Ar9271Regs.AR_PHY_ACTIVE, Ar9271Regs.PHY_ACTIVE_EN)
        synthDelay()
    }

    private fun initCal() {
        // unverified: PA cal and periodic IQ/ADC cals skipped, HT20 closed-loop cal path assumed
        val agc = Ar9271Regs.AR_PHY_AGC_CONTROL
        rmw(Ar9271Regs.AR_PHY_CL_CAL_CTL, Ar9271Regs.CL_CAL_ENABLE, 0)
        rmw(Ar9271Regs.AR_PHY_CL_CAL_CTL, Ar9271Regs.CL_CAL_PARALLEL_ENABLE, 0)
        rmw(Ar9271Regs.AR_PHY_TURBO, Ar9271Regs.PHY_FC_DYN2040_EN, 0)
        rmw(agc, 0, Ar9271Regs.AGC_CONTROL_FLTR_CAL)
        rmw(Ar9271Regs.AR_PHY_TPCRG1, 0, Ar9271Regs.TPCRG1_PD_CAL_ENABLE)
        rmw(agc, Ar9271Regs.AGC_CONTROL_CAL, 0)
        if (!waitReg(agc, Ar9271Regs.AGC_CONTROL_CAL, 0, Ar9271Regs.CAL_TIMEOUT_MS)) {
            throw IllegalStateException("AR9271: offset calibration did not complete")
        }
        rmw(Ar9271Regs.AR_PHY_TURBO, 0, Ar9271Regs.PHY_FC_DYN2040_EN)
        rmw(Ar9271Regs.AR_PHY_CL_CAL_CTL, 0, Ar9271Regs.CL_CAL_PARALLEL_ENABLE)
        rmw(Ar9271Regs.AR_PHY_CL_CAL_CTL, 0, Ar9271Regs.CL_CAL_ENABLE)
        rmw(Ar9271Regs.AR_PHY_ADC_CTL, 0, Ar9271Regs.ADC_CTL_OFF_PWDADC)
        rmw(agc, Ar9271Regs.AGC_CONTROL_FLTR_CAL, 0)
        rmw(Ar9271Regs.AR_PHY_TPCRG1, Ar9271Regs.TPCRG1_PD_CAL_ENABLE, 0)
        rmw(agc, Ar9271Regs.AGC_CONTROL_CAL, 0)
        if (!waitReg(agc, Ar9271Regs.AGC_CONTROL_CAL, 0, Ar9271Regs.CAL_TIMEOUT_MS)) {
            throw IllegalStateException("AR9271: offset calibration did not complete")
        }
        rmw(Ar9271Regs.AR_PHY_ADC_CTL, Ar9271Regs.ADC_CTL_OFF_PWDADC, 0)
        rmw(Ar9271Regs.AR_PHY_CL_CAL_CTL, 0, Ar9271Regs.CL_CAL_ENABLE)
        rmw(agc, 0, Ar9271Regs.AGC_CONTROL_FLTR_CAL)
        loadNf()
        startNfCal()
    }

    private fun loadNf() {
        val agc = Ar9271Regs.AR_PHY_AGC_CONTROL
        val bbAgc = rr(agc)
        rmw(Ar9271Regs.AR_PHY_CCA, (Ar9271Regs.NF_NOMINAL_9271_2G shl 1) and Ar9271Regs.NF_MASK, Ar9271Regs.NF_MASK)
        if ((bbAgc and Ar9271Regs.AGC_CONTROL_NF) != 0) rmw(agc, 0, Ar9271Regs.AGC_CONTROL_NF)
        rmw(agc, 0, Ar9271Regs.AGC_CONTROL_ENABLE_NF)
        rmw(agc, 0, Ar9271Regs.AGC_CONTROL_NO_UPDATE_NF)
        rmw(agc, Ar9271Regs.AGC_CONTROL_NF, 0)
        val loaded = waitReg(agc, Ar9271Regs.AGC_CONTROL_NF, 0, Ar9271Regs.NF_LOAD_TIMEOUT_MS)
        if ((bbAgc and Ar9271Regs.AGC_CONTROL_NF) != 0) {
            if ((bbAgc and Ar9271Regs.AGC_CONTROL_ENABLE_NF) != 0) rmw(agc, Ar9271Regs.AGC_CONTROL_ENABLE_NF, 0)
            if ((bbAgc and Ar9271Regs.AGC_CONTROL_NO_UPDATE_NF) != 0) rmw(agc, Ar9271Regs.AGC_CONTROL_NO_UPDATE_NF, 0)
            rmw(agc, Ar9271Regs.AGC_CONTROL_NF, 0)
        }
        if (!loaded) return
        rmw(Ar9271Regs.AR_PHY_CCA, (Ar9271Regs.NF_LOAD_RESTORE shl 1) and Ar9271Regs.NF_MASK, Ar9271Regs.NF_MASK)
    }

    private fun startNfCal() {
        val agc = Ar9271Regs.AR_PHY_AGC_CONTROL
        rmw(agc, Ar9271Regs.AGC_CONTROL_ENABLE_NF, 0)
        rmw(agc, 0, Ar9271Regs.AGC_CONTROL_NO_UPDATE_NF)
        rmw(agc, Ar9271Regs.AGC_CONTROL_NF, 0)
    }

    private fun fastChannelChange(freq: Int): Boolean {
        if (curFreq == 0 || freq == curFreq) return false
        if (rr(Ar9271Regs.AR_CFG) == DEAD_BEEF) return false
        rw(Ar9271Regs.AR_PHY_RFBUS_REQ, Ar9271Regs.RFBUS_REQ_EN)
        if (!waitReg(Ar9271Regs.AR_PHY_RFBUS_GRANT, Ar9271Regs.RFBUS_GRANT_EN, Ar9271Regs.RFBUS_GRANT_EN, Ar9271Regs.WAIT_TIMEOUT_MS)) {
            rw(Ar9271Regs.AR_PHY_RFBUS_REQ, 0)
            return false
        }
        val dacFifo = rr(Ar9271Regs.AR_PHY_TURBO) and Ar9271Regs.PHY_FC_ENABLE_DAC_FIFO
        rw(
            Ar9271Regs.AR_PHY_TURBO,
            Ar9271Regs.PHY_FC_HT_EN or Ar9271Regs.PHY_FC_SHORT_GI_40 or Ar9271Regs.PHY_FC_SINGLE_HT_LTF1 or
                Ar9271Regs.PHY_FC_WALSH or dacFifo,
        )
        rw(Ar9271Regs.AR_2040_MODE, 0)
        rw(Ar9271Regs.AR_GTXTO, 25 shl Ar9271Regs.TIMEOUT_LIMIT_SHIFT)
        rw(Ar9271Regs.AR_CST, 0xf shl Ar9271Regs.TIMEOUT_LIMIT_SHIFT)
        rfSetFreq(freq)
        setDeltaSlope(freq)
        spurMitigate(freq)
        initBb()
        synthDelay()
        rw(Ar9271Regs.AR_PHY_RFBUS_REQ, 0)
        loadNf()
        startNfCal()
        loadAniRegs()
        return true
    }

    private fun loadAniRegs() {
        val t = Ar9271Regs.INI_ANI_2G_HT20
        var i = 0
        while (i + 1 < t.size) {
            val reg = t[i].toInt()
            var v = t[i + 1].toInt()
            if (reg == Ar9271Regs.AR_PHY_CCK_DETECT) {
                val keep = rr(reg) and Ar9271Regs.CCK_DETECT_WEAK_SIG_THR_CCK.inv()
                v = (v and Ar9271Regs.CCK_DETECT_WEAK_SIG_THR_CCK) or keep
            }
            rw(reg, v)
            i += 2
        }
    }

    private fun setRxFilter() {
        rw(Ar9271Regs.AR_RX_FILTER, if (monitorAttached) Ar9271Regs.RX_FILTER_MONITOR else Ar9271Regs.RX_FILTER_PRE_MONITOR)
        rw(Ar9271Regs.AR_PHY_ERR, 0)
        rmw(Ar9271Regs.AR_RXCFG, 0, Ar9271Regs.RXCFG_ZLFDMA)
        rw(Ar9271Regs.AR_MCAST_FIL0, -1)
        rw(Ar9271Regs.AR_MCAST_FIL1, -1)
    }

    private fun hostRxInit() {
        rw(Ar9271Regs.AR_CR, Ar9271Regs.CR_RXE)
        setRxFilter()
        // unverified: ACK/CTS disable is passive hardening beyond ath9k, no TX of any kind
        rmw(
            Ar9271Regs.AR_DIAG_SW,
            Ar9271Regs.DIAG_ACK_DIS or Ar9271Regs.DIAG_CTS_DIS,
            Ar9271Regs.DIAG_RX_DIS or Ar9271Regs.DIAG_RX_ABORT,
        )
    }

    private fun startRadio() {
        wmi(Ar9271Regs.WMI_FLUSH_RECV)
        hwReset(Ar9271Regs.freqOf(Ar9271Regs.CHANNELS[0]), false)
        wmi(Ar9271Regs.WMI_SET_MODE, be16(Ar9271Regs.HTC_MODE_11NG))
        wmi(Ar9271Regs.WMI_ATH_INIT)
        wmi(Ar9271Regs.WMI_START_RECV)
        hostRxInit()
        val cap = ByteArray(8)
        putBe32(cap, 0, 0xffff)
        cap[4] = 0xff.toByte()
        cap[6] = txChainMask.toByte()
        wmi(Ar9271Regs.WMI_TARGET_IC_UPDATE, cap)
    }

    private fun attachMonitor() {
        val vap = ByteArray(12)
        vap[0] = 0
        vap[1] = Ar9271Regs.HTC_M_MONITOR.toByte()
        System.arraycopy(macAddr, 0, vap, 2, 6)
        wmi(Ar9271Regs.WMI_VAP_CREATE, vap)
        val sta = ByteArray(22)
        System.arraycopy(macAddr, 0, sta, 0, 6)
        sta[14] = 1
        putBe16(sta, 19, 0xffff)
        wmi(Ar9271Regs.WMI_NODE_CREATE, sta)
        monitorAttached = true
        setRxFilter()
    }

    private fun detachMonitor() {
        val vap = ByteArray(12)
        vap[0] = 0
        System.arraycopy(macAddr, 0, vap, 2, 6)
        wmi(Ar9271Regs.WMI_VAP_REMOVE, vap)
        wmi(Ar9271Regs.WMI_NODE_REMOVE, byteArrayOf(0))
        monitorAttached = false
    }

    private fun setChannel(ch: Int, fast: Boolean) {
        wmi(Ar9271Regs.WMI_DISABLE_INTR)
        wmi(Ar9271Regs.WMI_DRAIN_TXQ_ALL)
        wmi(Ar9271Regs.WMI_STOP_RECV)
        hwReset(Ar9271Regs.freqOf(ch), fast)
        wmi(Ar9271Regs.WMI_START_RECV)
        hostRxInit()
        wmi(Ar9271Regs.WMI_SET_MODE, be16(Ar9271Regs.HTC_MODE_11NG))
        wmi(Ar9271Regs.WMI_ENABLE_INTR)
    }

    private fun shutdown() {
        if (wmiEp < 0 || !hwReady) return
        wn = 0
        try {
            wmi(Ar9271Regs.WMI_DISABLE_INTR)
            wmi(Ar9271Regs.WMI_DRAIN_TXQ_ALL)
            wmi(Ar9271Regs.WMI_STOP_RECV)
            if (monitorAttached) detachMonitor()
            setResetReg(RESET_WARM)
            initPll()
            setResetReg(RESET_COLD)
            initPll()
            rmw(Ar9271Regs.AR_STA_ID1, Ar9271Regs.STA_ID1_PWR_SAV, 0)
            rmw(Ar9271Regs.AR_RTC_FORCE_WAKE, 0, Ar9271Regs.RTC_FORCE_WAKE_EN)
            rw(Ar9271Regs.AR_RC, Ar9271Regs.RC_AHB or Ar9271Regs.RC_HOSTIF)
            flushWrites()
        } catch (e: IllegalStateException) {
            log("AR9271: shutdown incomplete: ${e.message}") // adapter unplugged or unresponsive
        }
    }

    private fun rxLoop(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val nbuf = 8
        val bufSz = Ar9271Regs.RX_BUF_SIZE
        val buffers = Array(nbuf) { ByteBuffer.allocateDirect(bufSz) }
        val reqs = ArrayList<UsbRequest>(nbuf)
        var ok = true
        for (i in 0 until nbuf) {
            val r = UsbRequest()
            if (!r.initialize(conn, epRx)) { ok = false; break }
            r.clientData = i
            buffers[i].clear()
            if (!r.queue(buffers[i])) { ok = false; break }
            reqs.add(r)
        }
        if (!ok) {
            releaseRequests(reqs)
            rxLoopSync(bufSz, onBatch)
            return
        }
        val scratch = ByteArray(bufSz)
        var hopIdx = 0
        var channel = Ar9271Regs.CHANNELS[0]
        var hopAt = System.currentTimeMillis()
        var emitAt = hopAt
        var lastRxAt = hopAt
        exploreAt = hopAt
        try {
            while (!stop) {
                val req = try { conn.requestWait(100L) } catch (e: TimeoutException) { null }
                val now = System.currentTimeMillis()
                if (req != null) {
                    val idx = req.clientData as? Int ?: -1
                    if (idx in 0 until nbuf) {
                        val b = buffers[idx]
                        val nbytes = b.position()
                        if (nbytes in 1..bufSz) {
                            lastRxAt = now
                            b.rewind(); b.get(scratch, 0, nbytes)
                            rxChunk(scratch, nbytes, channel)
                        }
                        b.clear()
                        if (!requeue(req, b)) req.close()
                    }
                }
                if (now - lastRxAt > STALL_MS) { reKickRx(); lastRxAt = now }
                if (now - emitAt > 2000) { emit(onBatch); emitAt = now }
                if (now - hopAt > DWELL_MS) {
                    hopIdx = nextHop(hopIdx, now)
                    channel = Ar9271Regs.CHANNELS[hopIdx]
                    setChannel(channel, true)
                    hopAt = System.currentTimeMillis()
                }
            }
        } finally {
            releaseRequests(reqs)
        }
        emit(onBatch)
    }

    private fun nextHop(cur: Int, now: Long): Int {
        val chs = Ar9271Regs.CHANNELS
        val active = table.values.mapTo(HashSet()) { it.channel }
        val explore = now - exploreAt > EXPLORE_MS
        var nx = (cur + 1) % chs.size
        if (active.isNotEmpty() && !explore) {
            var s = 0
            while (s < chs.size && chs[nx] !in active) {
                nx = (nx + 1) % chs.size
                s++
            }
        } else if (explore) {
            exploreAt = now
        }
        return nx
    }

    private fun reKickRx() {
        // unverified: stop/start recv + CR_RXE re-arm is the ath9k_htc analogue of the MT7612U RX toggle, not hardware-confirmed as the stall fix
        wmi(Ar9271Regs.WMI_STOP_RECV)
        wmi(Ar9271Regs.WMI_START_RECV)
        hostRxInit()
    }

    private fun requeue(req: UsbRequest, b: ByteBuffer): Boolean =
        try {
            req.queue(b)
        } catch (e: IllegalStateException) {
            false // request already closed after device detach
        }

    private fun releaseRequests(reqs: List<UsbRequest>) {
        for (r in reqs) {
            r.cancel()
            r.close()
        }
    }

    private fun rxLoopSync(bufSz: Int, onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val buf = ByteArray(bufSz)
        var hopIdx = 0
        var channel = Ar9271Regs.CHANNELS[0]
        var hopAt = System.currentTimeMillis()
        var emitAt = hopAt
        var lastRxAt = hopAt
        exploreAt = hopAt
        while (!stop) {
            val n = conn.bulkTransfer(epRx, buf, buf.size, 100)
            val now = System.currentTimeMillis()
            if (n > 0) { lastRxAt = now; rxChunk(buf, n, channel) }
            if (now - lastRxAt > STALL_MS) { reKickRx(); lastRxAt = now }
            if (now - emitAt > 2000) { emit(onBatch); emitAt = now }
            if (now - hopAt > DWELL_MS) {
                hopIdx = nextHop(hopIdx, now)
                channel = Ar9271Regs.CHANNELS[hopIdx]
                setChannel(channel, true)
                hopAt = System.currentTimeMillis()
            }
        }
        emit(onBatch)
    }

    private fun rxChunk(d: ByteArray, len: Int, ch: Int) {
        var index = 0
        if (rxRemain != 0) {
            val take = rxRemain - rxPad
            val part = rxPartial
            if (part != null && take >= 0 && take <= len && rxPartialLen + take <= part.size) {
                System.arraycopy(d, 0, part, rxPartialLen, take)
                rxPacket(part, 0, rxPartialLen + take, ch)
            }
            rxPartial = null
            index = rxRemain
            rxRemain = 0
        }
        val maxBuf = Ar9271Regs.RX_BUF_SIZE
        while (index + 4 <= len) {
            val pktLen = le16(d, index)
            val tag = le16(d, index + 2)
            if (tag != Ar9271Regs.RX_STREAM_TAG || pktLen > Ar9271Regs.RX_MAX_PKT) {
                rxPartial = null
                rxRemain = 0
                return
            }
            val pad = (4 - (pktLen and 3)) and 3
            val start = index + 4
            index += 4 + pktLen + pad
            if (index > maxBuf) {
                rxRemain = index - maxBuf
                rxPartialLen = maxBuf - start
                rxPad = pad
                if (rxPartialLen in 0..pktLen && start + rxPartialLen <= len) {
                    val part = ByteArray(pktLen)
                    System.arraycopy(d, start, part, 0, rxPartialLen)
                    rxPartial = part
                } else {
                    rxPartial = null
                }
            } else if (start + pktLen <= len) {
                rxPacket(d, start, pktLen, ch)
            }
        }
    }

    private fun rxPacket(b: ByteArray, off: Int, n: Int, ch: Int) {
        if (n < Ar9271Regs.HTC_HDR_LEN) return
        val epid = u8(b, off)
        if (epid == 0 || epid == wmiEp) return
        val trailer = if ((u8(b, off + 1) and Ar9271Regs.HTC_FLAG_TRAILER) != 0) u8(b, off + 4) else 0
        val plen = n - Ar9271Regs.HTC_HDR_LEN - trailer
        if (plen < Ar9271Regs.RX_STATUS_LEN + 20) return
        rxFrame(b, off + Ar9271Regs.HTC_HDR_LEN, plen, ch)
    }

    private fun rxFrame(b: ByteArray, off: Int, n: Int, ch: Int) {
        val dataLen = be16At(b, off + 8)
        if (dataLen != n - Ar9271Regs.RX_STATUS_LEN) return
        val status = u8(b, off + 10)
        if ((status and Ar9271Regs.RX_ERR_IGNORED.inv()) != 0) return
        val rssiRaw = b[off + 12].toInt()
        if (rssiRaw == Ar9271Regs.RSSI_BAD) return
        val d = off + Ar9271Regs.RX_STATUS_LEN
        val end = off + n - FCS_LEN
        if (end < d + 16) return
        val fc = u8(b, d)
        val flags = u8(b, d + 1)
        val type = (fc shr 2) and 3
        val sub = (fc shr 4) and 0xf
        val rssi = (Ar9271Regs.NOISE_FLOOR + rssiRaw).coerceIn(-120, -20) // unverified: signal = default noise floor + rs_rssi
        fun macAt(o: Int) = (0 until 6).joinToString(":") { "%02x".format(u8(b, d + o + it)) }
        fun group(o: Int) = u8(b, d + o) and 1 != 0
        fun touch(mac: String, isAp: Boolean, ssid: String?, channel: Int, auth: Int = 0) {
            if (mac == "ff:ff:ff:ff:ff:ff" || mac == "00:00:00:00:00:00") return
            if (mac.startsWith("01:00:5e") || mac.startsWith("33:33") || mac.startsWith("01:80:c2")) return
            val e = table.getOrPut(mac) { Entry(null, rssi, channel, 0, isAp) }
            e.isAp = e.isAp || isAp
            if (!ssid.isNullOrEmpty()) e.ssid = ssid
            if (rssi > e.rssi) e.rssi = rssi
            if (auth > e.auth) e.auth = auth
            e.channel = channel
            e.lastSeen = System.currentTimeMillis()
        }
        when (type) {
            0 -> {
                if (end < d + 24) return
                when (sub) {
                    8, 5 -> {
                        if (end < d + 36) return
                        var ssid: String? = null
                        var dsCh = 0
                        var i = d + 36
                        while (i + 2 <= end) {
                            val tag = u8(b, i)
                            val tl = u8(b, i + 1)
                            if (i + 2 + tl > end) break
                            if (tag == 0) ssid = decodeSsid(b, i + 2, tl)
                            if (tag == 3 && tl == 1) dsCh = u8(b, i + 2)
                            i += 2 + tl
                        }
                        val cap = u8(b, d + 34) or (u8(b, d + 35) shl 8)
                        val auth = wifiAuthMode(b, d + 36, end, cap and 0x10 != 0)
                        touch(macAt(16), true, ssid, if (dsCh in 1..13) dsCh else ch, auth)
                    }
                    4, 0, 1, 2, 3, 10, 11, 12 -> touch(macAt(10), false, null, ch)
                }
            }
            2 -> {
                if (end < d + 24) return
                val toDs = flags and 1 != 0
                val fromDs = flags and 2 != 0
                when {
                    toDs && !fromDs -> { if (!group(4)) touch(macAt(4), true, null, ch); touch(macAt(10), false, null, ch) }
                    !toDs && fromDs -> { if (!group(10)) touch(macAt(10), true, null, ch); touch(macAt(4), false, null, ch) }
                    !toDs && !fromDs -> { if (!group(16)) touch(macAt(16), true, null, ch); touch(macAt(10), false, null, ch) }
                    else -> touch(macAt(10), false, null, ch)
                }
            }
            1 -> if (sub == 11 || sub == 10) touch(macAt(10), false, null, ch)
        }
    }

    private fun decodeSsid(b: ByteArray, from: Int, len: Int): String? {
        if (len == 0) return ""
        val s = String(b, from, len, Charsets.UTF_8)
        return if (s.length <= 32 && s.none { it.code == 0xFFFD || it.isISOControl() }) s else null
    }

    private fun emit(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val now = System.currentTimeMillis()
        val fresh = 8000L
        val batch = table.entries
            .filter { now - it.value.lastSeen < fresh }
            .map { (mac, e) -> Mt7612uAdapter.ApSighting(mac, e.ssid, e.rssi, e.channel, Ar9271Regs.freqOf(e.channel), client = !e.isAp, authMode = e.auth) }
        table.entries.removeAll { now - it.value.lastSeen > 60_000L }
        if (batch.isNotEmpty()) onBatch(batch)
    }

    private fun u8(b: ByteArray, i: Int): Int = b[i].toInt() and 0xff
    private fun be16At(b: ByteArray, i: Int): Int = (u8(b, i) shl 8) or u8(b, i + 1)
    private fun be32At(b: ByteArray, i: Int): Int =
        (u8(b, i) shl 24) or (u8(b, i + 1) shl 16) or (u8(b, i + 2) shl 8) or u8(b, i + 3)

    private fun putBe16(b: ByteArray, i: Int, v: Int) {
        b[i] = (v ushr 8).toByte()
        b[i + 1] = v.toByte()
    }

    private fun putBe32(b: ByteArray, i: Int, v: Int) {
        b[i] = (v ushr 24).toByte()
        b[i + 1] = (v ushr 16).toByte()
        b[i + 2] = (v ushr 8).toByte()
        b[i + 3] = v.toByte()
    }

    private fun be16(v: Int): ByteArray = ByteArray(2).also { putBe16(it, 0, v) }
    private fun be32(v: Int): ByteArray = ByteArray(4).also { putBe32(it, 0, v) }

    companion object {
        const val DWELL_MS = 150L
        const val EXPLORE_MS = 2000L
        private const val STALL_MS = 4000L
        private const val RESET_POWER_ON = 0
        private const val RESET_WARM = 1
        private const val RESET_COLD = 2
        private const val POWER_UP_POLLS = 200
        private const val FCS_LEN = 4
        private const val DEAD_BEEF = 0xdeadbeef.toInt()
    }
}

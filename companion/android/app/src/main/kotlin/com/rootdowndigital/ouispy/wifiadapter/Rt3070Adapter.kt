package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbRequest
import java.nio.ByteBuffer
import java.util.concurrent.TimeoutException
import com.rootdowndigital.ouispy.wifiadapter.Rt3070Regs as Rg
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.le32
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.putLe32
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.sleep

// unverified: whole RT3070/RT5370/RT5372 (rt2800usb) bring-up is new and untested on hardware.
// Passive 2.4 GHz receiver: never queues a bulk-out frame.
internal class Rt3070Adapter(
    private val conn: UsbDeviceConnection,
    private val intf: UsbInterface,
    private val fw: ByteArray,
    private val log: (String) -> Unit,
) {
    @Volatile private var stop = false
    private lateinit var epRx: UsbEndpoint
    private var calBw20 = 0x08
    private var freqOffset = 0
    private var lnaGain = 0
    private var rssiOff0 = 0
    private var revLtF = false

    fun abort() { stop = true }

    fun run(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        conn.claimInterface(intf, true)
        if (!findEndpoint()) throw IllegalStateException("RT3070: bulk-IN endpoint not found")
        if (fw.size < Rg.FW_BLOCK) throw IllegalStateException("RT3070: rt2870.bin short (${fw.size} B)")

        loadFirmware()
        log("RT3070: firmware running")

        val rev = regRd(Rg.MAC_CSR0) and 0xffff
        revLtF = rev < Rg.REV_RT3070F
        log("RT3070: MAC_CSR0 rev=0x%04x".format(rev))
        readEeprom()
        log("RT3070: freq_off=$freqOffset lna_gain=$lnaGain rssi_off0=$rssiOff0")

        initRegisters()
        waitBbpRfReady()
        initBbp()
        initRfcsr()
        configChannel(Rg.HOP[0])
        enableRx()
        log("RT3070: receiver live ch ${Rg.HOP[0]}")
        rxLoop(onBatch)
    }

    private fun findEndpoint(): Boolean {
        for (i in 0 until intf.endpointCount) {
            val ep = intf.getEndpoint(i)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.direction == UsbConstants.USB_DIR_IN) {
                epRx = ep
                log("RT3070: RX EP=0x%02x maxIn=%d".format(ep.address, ep.maxPacketSize))
                return true
            }
        }
        return false
    }

    // unverified: sequence mirrors the Wardrive Go loader (first 4096 B of rt2870.bin, 64 B CSR chunks, autorun skip).
    private fun loadFirmware() {
        regWr(Rg.AUTOWAKEUP_CFG, 0)
        if (!waitCsrReady()) throw IllegalStateException("RT3070: MAC_CSR0 never ready")
        disableWpdma()

        val autorun = detectAutorun()
        log("RT3070: autorun=$autorun")
        if (!autorun) writeFirmwareImage()
        regWr(Rg.H2M_MAILBOX_CID, -1)
        regWr(Rg.H2M_MAILBOX_STATUS, -1)

        deviceMode(Rg.USB_MODE_FIRMWARE)
        sleep(10)
        regWr(Rg.H2M_MAILBOX_CSR, 0)

        val ready = pollPbfReady()
        disableWpdma()
        regWr(Rg.H2M_BBP_AGENT, 0)
        regWr(Rg.H2M_MAILBOX_CSR, 0)
        regWr(Rg.H2M_INT_SRC, 0)
        mcuBoot()
        sleep(1)
        if (!ready) throw IllegalStateException("RT3070: firmware did not start (PBF_SYS_CTRL not ready)")
    }

    private fun detectAutorun(): Boolean {
        val b = ByteArray(4)
        val n = conn.controlTransfer(Rg.IN_VENDOR, Rg.DEVICE_MODE, Rg.USB_MODE_AUTORUN, 0, b, 4, UsbIo.TIMEOUT)
        return n == 4 && (le32(b, 0) and 0x3) == 2
    }

    private fun writeFirmwareImage() {
        var off = 0
        while (off < Rg.FW_BLOCK) {
            val len = minOf(Rg.CSR_CACHE_SIZE, Rg.FW_BLOCK - off)
            val chunk = fw.copyOfRange(off, off + len)
            val r = conn.controlTransfer(Rg.OUT_VENDOR, Rg.MULTI_WRITE, 0, Rg.FIRMWARE_IMAGE_BASE + off, chunk, len, UsbIo.TIMEOUT)
            if (r < 0) throw IllegalStateException("RT3070: firmware chunk failed at $off rc=$r")
            off += len
        }
        log("RT3070: firmware image written ($off B)")
    }

    private fun mcuBoot() {
        val end = System.currentTimeMillis() + 100
        while ((regRd(Rg.H2M_MAILBOX_CSR) and Rg.H2M_OWNER) != 0 && System.currentTimeMillis() < end) sleep(1)
        regWr(Rg.H2M_MAILBOX_CSR, 0x01000000)
        regWr(Rg.HOST_CMD_CSR, Rg.MCU_BOOT_SIGNAL and 0xff)
    }

    private fun deviceMode(mode: Int) {
        conn.controlTransfer(Rg.OUT_VENDOR, Rg.DEVICE_MODE, mode, 0, null, 0, UsbIo.TIMEOUT)
    }

    private fun disableWpdma() {
        regClear(Rg.WPDMA_GLO_CFG, Rg.WPDMA_ENABLE_TX_DMA or Rg.WPDMA_ENABLE_RX_DMA)
    }

    private fun waitCsrReady(): Boolean {
        val end = System.currentTimeMillis() + 1000
        do {
            val v = regRd(Rg.MAC_CSR0)
            if (v != 0 && v != -1) return true
            sleep(1)
        } while (System.currentTimeMillis() < end)
        return false
    }

    private fun pollPbfReady(): Boolean {
        val end = System.currentTimeMillis() + 1000
        do {
            if (regRd(Rg.PBF_SYS_CTRL) and Rg.PBF_SYS_CTRL_READY != 0) return true
            sleep(1)
        } while (System.currentTimeMillis() < end)
        return false
    }

    private fun waitWpdma(): Boolean {
        val end = System.currentTimeMillis() + 1000
        do {
            if (regRd(Rg.WPDMA_GLO_CFG) and (Rg.WPDMA_TX_BUSY or Rg.WPDMA_RX_BUSY) == 0) return true
            sleep(10)
        } while (System.currentTimeMillis() < end)
        return false
    }

    private fun waitBbpRfReady() {
        val end = System.currentTimeMillis() + 1000
        while (regRd(Rg.MAC_STATUS_CFG) and 0x3 != 0 && System.currentTimeMillis() < end) sleep(10)
    }

    private fun usbReset() {
        waitCsrReady()
        regClear(Rg.PBF_SYS_CTRL, 0x2000)
        regWr(Rg.MAC_SYS_CTRL, 0x3)
        deviceMode(Rg.USB_MODE_RESET)
        regWr(Rg.MAC_SYS_CTRL, 0x0)
    }

    // unverified: full MAC register init; values transcribed from the Wardrive Go RT3070 monitor.
    private fun initRegisters() {
        regClear(Rg.WPDMA_GLO_CFG, 0x5)
        usbReset()
        regWr(Rg.LEGACY_BASIC_RATE, 0x0000013f)
        regWr(Rg.HT_BASIC_RATE, 0x00008003)
        regWr(Rg.MAC_SYS_CTRL, 0)
        regRmw(Rg.BCN_TIME_CFG, 0x0000ffff, 1600)
        regWr(Rg.RX_FILTR_CFG, Rg.RX_FILTR_INIT)
        var r = regRd(Rg.BKOFF_SLOT_CFG)
        r = setf(r, 0xff, 9); r = setf(r, 0xf00, 2)
        regWr(Rg.BKOFF_SLOT_CFG, r)
        regWr(Rg.TX_SW_CFG0, 0x00000400)
        if (revLtF) { regWr(Rg.TX_SW_CFG1, 0x00000000); regWr(Rg.TX_SW_CFG2, 0x0000002c) }
        else { regWr(Rg.TX_SW_CFG1, 0x00080606); regWr(Rg.TX_SW_CFG2, 0x00000000) }
        regWr(Rg.TX_LINK_CFG, 0x00001020)
        regWr(Rg.TX_TIMEOUT_CFG, 0x000a2090)
        r = regRd(Rg.MAX_LEN_CFG)
        r = setf(r, 0x0fff, 3839); r = setf(r, 0x3000, 3); r = setf(r, 0xfc000, 10); r = setf(r, 0xf00000, 10)
        regWr(Rg.MAX_LEN_CFG, r)
        regWr(Rg.LED_CFG, 0x7f031e46)
        regWr(Rg.PBF_MAX_PCNT, 0x1f3fbf9f)
        regWr(Rg.TX_RTY_CFG, 0x47d01f0f)
        regWr(Rg.AUTO_RSP_CFG, 0x00000013)
        regWr(Rg.CCK_PROT_CFG, 0x05740003); regWr(Rg.OFDM_PROT_CFG, 0x05740003)
        regWr(Rg.MM20_PROT_CFG, 0x03f44084); regWr(Rg.MM40_PROT_CFG, 0x03f54084)
        regWr(Rg.GF20_PROT_CFG, 0x03f44084); regWr(Rg.GF40_PROT_CFG, 0x03f54084)
        regWr(Rg.PBF_CFG, 0x00f40006)
        r = regRd(Rg.WPDMA_GLO_CFG)
        r = r and 0x00ff000f.inv(); r = setf(r, 0x03000000, 3)
        regWr(Rg.WPDMA_GLO_CFG, r)
        regWr(Rg.TXOP_CTRL_CFG, 0x0000583f)
        regWr(Rg.TXOP_HLDR_ET, 0x00000002)
        regWr(Rg.TX_RTS_CFG, 0x00092b20)
        regWr(Rg.EXP_ACK_TIME, 0x002400ca)
        regWr(Rg.XIFS_TIME_CFG, 0x33a41010)
        regWr(Rg.PWR_PIN_CFG, 0x00000003)
        regRmw(Rg.US_CYC_CNT, 0xff, 30)
        regWr(Rg.HT_FBK_CFG0, 0x65432100); regWr(Rg.HT_FBK_CFG1, 0xedcba980.toInt())
        regWr(Rg.LG_FBK_CFG0, 0xedcba988.toInt()); regWr(Rg.LG_FBK_CFG1, 0x00002100)
    }

    private fun initBbp() {
        for ((r, v) in Rg.BBP_EARLY) bbpWr(r, v)
        for ((r, v) in Rg.BBP_TABLE) bbpWr(r, v)
        bbpWr(103, if (revLtF) Rg.BBP103_REV_LT_F else Rg.BBP103_REV_GE_F)
    }

    private fun initRfcsr() {
        rfInitCal(30)
        for ((r, v) in Rg.RFCSR_TABLE) rfWr(r, v)
        if (revLtF) {
            var r = regRd(Rg.LDO_CFG0)
            r = setf(r, 0x03000000, 1); r = setf(r, 0x1c000000, 3)
            regWr(Rg.LDO_CFG0, r)
        }
        calBw20 = rxFilterCal()
        if (revLtF) rfWr(27, 0x03)
        normalModeSetup()
    }

    // unverified: RX filter calibration loop (BBP 24/25/55 + RFCSR 24).
    private fun rxFilterCal(): Int {
        var rf24 = 0x07
        rfWr(24, rf24)
        bbpWr(4, setf(bbpRd(4), 0x18, 0))
        rfWr(31, setf(rfRd(31), 0x20, 0))
        rfWr(22, setf(rfRd(22), 0x01, 1))
        bbpWr(24, 0)
        var passband = 0
        for (i in 0 until 100) { bbpWr(25, 0x90); sleep(1); passband = bbpRd(55); if (passband != 0) break }
        bbpWr(24, 0x06)
        var overtuned = 0
        for (i in 0 until 100) {
            bbpWr(25, 0x90); sleep(1)
            val stopband = bbpRd(55)
            if (passband - stopband <= 0x16) { rf24++; if (passband - stopband == 0x16) overtuned++ } else break
            rfWr(24, rf24)
        }
        if (overtuned != 0) rf24--
        rfWr(24, rf24)
        bbpWr(24, 0)
        rfWr(22, setf(rfRd(22), 0x01, 0))
        bbpWr(4, setf(bbpRd(4), 0x18, 0))
        return rf24
    }

    private fun normalModeSetup() {
        var rf = rfRd(17)
        rf = setf(rf, 0x08, 0); rf = setf(rf, 0x20, 1)
        rfWr(17, rf)
        rf = rfRd(27)
        rf = setf(rf, 0x03, if (revLtF) 3 else 0); rf = setf(rf, 0x04, 0); rf = setf(rf, 0x30, 0); rf = setf(rf, 0x40, 0)
        rfWr(27, rf)
    }

    private fun rfInitCal(reg: Int) {
        val v = rfRd(reg)
        rfWr(reg, v or 0x80); sleep(1); rfWr(reg, v and 0x80.inv())
    }

    // unverified: 2.4 GHz channel switch (RFCSR N/K table + BBP + TX_BAND_CFG), no HT40.
    private fun configChannel(ch: Int) {
        val idx = ch - 1
        rfWr(2, Rg.RF_N[idx])
        rfWr(3, setf(rfRd(3), 0x0f, Rg.RF_K[idx]))
        rfWr(6, setf(rfRd(6), 0x03, 2))
        rfWr(12, setf(rfRd(12), 0x1f, 0))
        rfWr(13, setf(rfRd(13), 0x1f, 0))
        var rf = rfRd(1)
        rf = setf(rf, 0x04, 0); rf = setf(rf, 0x10, 1); rf = setf(rf, 0x40, 1)
        rf = setf(rf, 0x08, 0); rf = setf(rf, 0x20, 1); rf = setf(rf, 0x80, 1)
        rfWr(1, rf)
        rfWr(23, setf(rfRd(23), 0x7f, freqOffset and 0x7f))
        rfWr(24, setf(rfRd(24), 0x7f, calBw20))
        rfWr(31, setf(rfRd(31), 0x7f, calBw20))
        rfWr(7, setf(rfRd(7), 0x01, 1))
        rf = rfRd(30)
        rfWr(30, rf or 0x80); sleep(1); rfWr(30, rf and 0x80.inv())

        bbpWr(82, 0x84); bbpWr(75, 0x50)
        var r = regRd(Rg.TX_BAND_CFG)
        r = setf(r, 0x01, 0); r = setf(r, 0x02, 0); r = setf(r, 0x04, 1)
        regWr(Rg.TX_BAND_CFG, r)

        regWr(Rg.TX_PIN_CFG, 0x02 or 0x100 or 0x200 or 0x10000 or 0x40000)
        bbpWr(4, setf(bbpRd(4), 0x18, 0))
        bbpWr(3, setf(bbpRd(3), 0x20, 0))
        sleep(1)
        regRd(Rg.CH_IDLE_STA); regRd(Rg.CH_BUSY_STA); regRd(Rg.CH_BUSY_STA_SEC)
    }

    private fun enableRx() {
        waitWpdma()
        regWr(Rg.USB_DMA_CFG, Rg.USB_DMA_CFG_TX_BULK_EN or Rg.USB_DMA_CFG_RX_BULK_EN or Rg.USB_DMA_CFG_RX_AGG_TIMEOUT)
        regWr(Rg.MAC_SYS_CTRL, Rg.MAC_SYS_CTRL_ENABLE_TX)
        sleep(50)
        regSet(Rg.WPDMA_GLO_CFG, Rg.WPDMA_ENABLE_TX_DMA or Rg.WPDMA_ENABLE_RX_DMA or Rg.WPDMA_RX_WRITEBACK)
        regWr(Rg.MAC_SYS_CTRL, Rg.MAC_SYS_CTRL_ENABLE_TX or Rg.MAC_SYS_CTRL_ENABLE_RX)
        regWr(Rg.RX_FILTR_CFG, Rg.RX_FILTR_PROMISC)
        regWr(Rg.CH_TIME_CFG, 0x0000001f)
    }

    // unverified: no reference reKick for RT3070; re-arms MAC RX + USB RX bulk using only registers enableRx already writes.
    private fun reKickRx() {
        regClear(Rg.MAC_SYS_CTRL, Rg.MAC_SYS_CTRL_ENABLE_RX)
        regClear(Rg.USB_DMA_CFG, Rg.USB_DMA_CFG_RX_BULK_EN)
        sleep(5)
        regSet(Rg.USB_DMA_CFG, Rg.USB_DMA_CFG_RX_BULK_EN)
        regSet(Rg.MAC_SYS_CTRL, Rg.MAC_SYS_CTRL_ENABLE_RX)
    }

    private class Entry(var ssid: String?, var rssi: Int, var channel: Int, var lastSeen: Long, var isAp: Boolean, var auth: Int = 0)
    private class SightingTable { val map = LinkedHashMap<String, Entry>() }

    private fun rxLoop(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val nbuf = 24
        val bufSz = 4096
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
            reqs.forEach { runCatching { it.cancel() }; runCatching { it.close() } }
            rxLoopSync(bufSz, onBatch)
            return
        }
        val scratch = ByteArray(bufSz)
        val table = SightingTable()
        var hopIdx = 0
        var hopAt = System.currentTimeMillis()
        var emitAt = hopAt
        var diagAt = hopAt
        var rxBytes = 0L
        var rxBufs = 0L
        var lastRxAt = hopAt
        var exploreAt = hopAt
        try {
            while (!stop) {
                val req = try { conn.requestWait(100L) } catch (e: TimeoutException) { null }
                val now = System.currentTimeMillis()
                if (req != null) {
                    val idx = req.clientData as? Int ?: -1
                    if (idx in 0 until nbuf) {
                        val b = buffers[idx]
                        val nbytes = b.position()
                        var parseLen = 0
                        if (nbytes in 1..bufSz) {
                            rxBytes += nbytes
                            rxBufs++
                            lastRxAt = now
                            b.rewind(); b.get(scratch, 0, nbytes)
                            parseLen = nbytes
                        }
                        b.clear()
                        if (!runCatching { req.queue(b) }.getOrDefault(false)) {
                            runCatching { req.close() }
                            val nr = UsbRequest()
                            if (runCatching { nr.initialize(conn, epRx) }.getOrDefault(false)) {
                                nr.clientData = idx; b.clear()
                                if (runCatching { nr.queue(b) }.getOrDefault(false)) reqs[idx] = nr
                            }
                        }
                        if (parseLen > 0) runCatching { parseRx(scratch, parseLen, Rg.HOP[hopIdx], table) }
                    }
                }
                if (now - diagAt > 3000) {
                    log("RT3070 rx: bufs=$rxBufs bytes=$rxBytes tracked=${table.map.size} ch=${Rg.HOP[hopIdx]}")
                    diagAt = now
                    if (now - lastRxAt > 4000) {
                        runCatching { reKickRx() }
                        lastRxAt = now
                    }
                }
                if (now - emitAt > 2000) { emit(table, onBatch); emitAt = now }
                if (now - hopAt > DWELL_MS) {
                    hopIdx = nextHop(hopIdx, table, now, exploreAt).also { if (now - exploreAt > EXPLORE_MS) exploreAt = now }
                    runCatching { configChannel(Rg.HOP[hopIdx]) }
                    hopAt = now
                }
            }
        } finally {
            reqs.forEach { runCatching { it.cancel() }; runCatching { it.close() } }
        }
        emit(table, onBatch)
    }

    private fun rxLoopSync(bufSz: Int, onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val buf = ByteArray(bufSz)
        val table = SightingTable()
        var hopIdx = 0
        var hopAt = System.currentTimeMillis()
        var emitAt = hopAt
        var exploreAt = hopAt
        var lastRxAt = hopAt
        while (!stop) {
            val n = conn.bulkTransfer(epRx, buf, buf.size, 500)
            val now = System.currentTimeMillis()
            if (n > 0) { lastRxAt = now; runCatching { parseRx(buf, n, Rg.HOP[hopIdx], table) } }
            else if (now - lastRxAt > 4000) { runCatching { reKickRx() }; lastRxAt = now }
            if (now - emitAt > 2000) { emit(table, onBatch); emitAt = now }
            if (now - hopAt > DWELL_MS) {
                hopIdx = nextHop(hopIdx, table, now, exploreAt).also { if (now - exploreAt > EXPLORE_MS) exploreAt = now }
                runCatching { configChannel(Rg.HOP[hopIdx]) }
                hopAt = now
            }
        }
        emit(table, onBatch)
    }

    private fun nextHop(hopIdx: Int, table: SightingTable, now: Long, exploreAt: Long): Int {
        val active = table.map.values.mapTo(HashSet()) { it.channel }
        val explore = now - exploreAt > EXPLORE_MS
        var nx = (hopIdx + 1) % Rg.HOP.size
        if (active.isNotEmpty() && !explore) {
            var s = 0
            while (s < Rg.HOP.size && Rg.HOP[nx] !in active) { nx = (nx + 1) % Rg.HOP.size; s++ }
        }
        return nx
    }

    // unverified: RX layout (rxinfo word 0 = pkt len, RXWI 16 B, rxd trailer at 4+pktLen) per Wardrive Go; one MPDU per bulk buffer.
    private fun parseRx(b: ByteArray, n: Int, ch: Int, table: SightingTable) {
        fun u8(i: Int) = b[i].toInt() and 0xff
        if (n < 4 + 16 + 24) return
        val rxPktLen = le32(b, 0) and 0xffff
        val rxwi = 4
        val mpduLen = (le32(b, rxwi) ushr 16) and 0xfff
        val rssiRaw = b[rxwi + 8].toInt()
        val d = rxwi + 16
        val end = minOf(n, d + mpduLen)
        if (mpduLen < 24 || d + 24 > end) return

        val rxd = if (4 + rxPktLen + 4 <= n) le32(b, 4 + rxPktLen) else 0
        val good = (rxd and 0x100) == 0
        val pad = if (rxd and 0x4000 != 0) 2 else 0
        val rssi = if (rssiRaw != 0) (-12 - rssiOff0 - lnaGain - rssiRaw).coerceIn(-120, -20) else -120

        fun macAt(off: Int) = (0 until 6).joinToString(":") { "%02x".format(u8(off + it)) }
        fun group(off: Int) = u8(off) and 1 != 0
        fun touch(mac: String, isAp: Boolean, ssid: String?, auth: Int = 0) {
            if (mac == "ff:ff:ff:ff:ff:ff" || mac == "00:00:00:00:00:00") return
            if (mac.startsWith("01:00:5e") || mac.startsWith("33:33") || mac.startsWith("01:80:c2")) return
            val e = table.map.getOrPut(mac) { Entry(null, rssi, ch, 0, isAp) }
            e.isAp = e.isAp || isAp
            if (!ssid.isNullOrEmpty()) e.ssid = ssid
            if (rssi > e.rssi) e.rssi = rssi
            if (auth > e.auth) e.auth = auth
            e.channel = ch
            e.lastSeen = System.currentTimeMillis()
        }

        val fc = u8(d)
        val flags = u8(d + 1)
        val type = (fc shr 2) and 3
        val sub = (fc shr 4) and 0xf
        when (type) {
            0 -> when (sub) {
                8, 5 -> {
                    val ieStart = d + 36 + pad
                    val ssid = readSsid(b, ieStart, end)
                    val cap = if (d + 35 + pad < end) (u8(d + 34 + pad) or (u8(d + 35 + pad) shl 8)) else 0
                    val auth = wifiAuthMode(b, ieStart, end, cap and 0x10 != 0)
                    if (good || !ssid.isNullOrEmpty()) touch(macAt(d + 16), true, ssid, auth)
                }
                4, 0, 1, 2, 3, 10, 11, 12 -> if (good) touch(macAt(d + 10), false, null)
            }
            2 -> {
                if (!good) return
                val toDs = flags and 1 != 0
                val fromDs = flags and 2 != 0
                when {
                    toDs && !fromDs -> { if (!group(d + 4)) touch(macAt(d + 4), true, null); touch(macAt(d + 10), false, null) }
                    !toDs && fromDs -> { if (!group(d + 10)) touch(macAt(d + 10), true, null); touch(macAt(d + 4), false, null) }
                    !toDs && !fromDs -> { if (!group(d + 16)) touch(macAt(d + 16), true, null); touch(macAt(d + 10), false, null) }
                    else -> touch(macAt(d + 10), false, null)
                }
            }
            1 -> if (good && (sub == 11 || sub == 10)) touch(macAt(d + 10), false, null)
        }
    }

    private fun readSsid(b: ByteArray, from: Int, end: Int): String? {
        var i = from
        while (i + 2 <= end) {
            val tag = b[i].toInt() and 0xff
            val tl = b[i + 1].toInt() and 0xff
            if (i + 2 + tl > end) break
            if (tag == 0) {
                if (tl == 0) return ""
                val s = String(b, i + 2, tl, Charsets.UTF_8)
                return if (s.length <= 32 && s.none { it.code == 0xFFFD || it.isISOControl() }) s else null
            }
            i += 2 + tl
        }
        return null
    }

    private fun emit(table: SightingTable, onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val now = System.currentTimeMillis()
        val batch = table.map.entries
            .filter { now - it.value.lastSeen < FRESH_MS }
            .map { (mac, e) -> Mt7612uAdapter.ApSighting(mac, e.ssid, e.rssi, e.channel, Rg.freqOf(e.channel), client = !e.isAp, authMode = e.auth) }
        table.map.entries.removeAll { now - it.value.lastSeen > 60_000L }
        if (batch.isNotEmpty()) onBatch(batch)
    }

    // unverified: EEPROM/eFuse read (calibration words: freq offset, LNA gain, RSSI offset 0).
    private fun readEeprom() {
        val ee = ByteArray(512)
        val efuse = (regRd(Rg.EFUSE_CTRL) and Rg.EFUSE_SEL) != 0
        if (efuse) {
            var i = 0
            while (i < 256) {
                var reg = regRd(Rg.EFUSE_CTRL)
                reg = setf(reg, Rg.EFUSE_ADDR_MASK, i)
                reg = reg and Rg.EFUSE_MODE_MASK.inv()
                reg = reg or Rg.EFUSE_KICK
                regWr(Rg.EFUSE_CTRL, reg)
                val end = System.currentTimeMillis() + 50
                while ((regRd(Rg.EFUSE_CTRL) and Rg.EFUSE_KICK) != 0 && System.currentTimeMillis() < end) sleep(1)
                for (k in 0 until 4) {
                    val v = regRd(Rg.EFUSE_DATA[k])
                    val o = (i + k * 2) * 2
                    if (o + 4 <= 512) putLe32(ee, o, v)
                }
                i += 8
            }
        } else {
            val n = conn.controlTransfer(Rg.IN_VENDOR, Rg.EEPROM_READ, 0, 0, ee, ee.size, 2000)
            if (n <= 0) log("RT3070: EEPROM read returned $n, using defaults")
        }
        fun ew(word: Int) = (ee[word * 2].toInt() and 0xff) or ((ee[word * 2 + 1].toInt() and 0xff) shl 8)
        fun s8(v: Int) = if (v and 0x80 != 0) v - 256 else v
        freqOffset = ew(Rg.EE_FREQ_OFFSET_WORD) and 0xff
        val lg = ew(Rg.EE_LNA_GAIN_WORD) and 0xff
        lnaGain = if (lg == 0xff) 0 else s8(lg)
        val ro = ew(Rg.EE_RSSI_OFFSET0_WORD) and 0xff
        rssiOff0 = if (ro == 0xff) 0 else s8(ro)
        log("RT3070: EEPROM(${if (efuse) "efuse" else "93c46"}) read")
    }

    private fun regWr(addr: Int, v: Int) {
        val b = ByteArray(4); putLe32(b, 0, v)
        conn.controlTransfer(Rg.OUT_VENDOR, Rg.MULTI_WRITE, 0, addr, b, 4, UsbIo.TIMEOUT)
    }

    private fun regRd(addr: Int): Int {
        val b = ByteArray(4)
        return if (conn.controlTransfer(Rg.IN_VENDOR, Rg.MULTI_READ, 0, addr, b, 4, UsbIo.TIMEOUT) == 4) le32(b, 0) else 0
    }

    private fun regSet(addr: Int, bits: Int) = regWr(addr, regRd(addr) or bits)
    private fun regClear(addr: Int, bits: Int) = regWr(addr, regRd(addr) and bits.inv())
    private fun regRmw(addr: Int, mask: Int, v: Int) = regWr(addr, setf(regRd(addr), mask, v))

    private fun csrIdle(reg: Int, busy: Int): Boolean {
        val end = System.currentTimeMillis() + 50
        do { if (regRd(reg) and busy == 0) return true; sleep(1) } while (System.currentTimeMillis() < end)
        return false
    }

    private fun bbpWr(reg: Int, v: Int) {
        csrIdle(Rg.BBP_CSR_CFG, Rg.BBP_CSR_BUSY)
        regWr(Rg.BBP_CSR_CFG, (v and 0xff) or ((reg and 0xff) shl 8) or Rg.BBP_CSR_BUSY or Rg.BBP_CSR_MODE)
    }

    private fun bbpRd(reg: Int): Int {
        csrIdle(Rg.BBP_CSR_CFG, Rg.BBP_CSR_BUSY)
        regWr(Rg.BBP_CSR_CFG, ((reg and 0xff) shl 8) or Rg.BBP_CSR_BUSY or Rg.BBP_CSR_READ or Rg.BBP_CSR_MODE)
        csrIdle(Rg.BBP_CSR_CFG, Rg.BBP_CSR_BUSY)
        return regRd(Rg.BBP_CSR_CFG) and 0xff
    }

    private fun rfWr(reg: Int, v: Int) {
        csrIdle(Rg.RF_CSR_CFG, Rg.RF_CSR_BUSY)
        regWr(Rg.RF_CSR_CFG, (v and 0xff) or ((reg and 0x3f) shl 8) or Rg.RF_CSR_WRITE or Rg.RF_CSR_BUSY)
    }

    private fun rfRd(reg: Int): Int {
        csrIdle(Rg.RF_CSR_CFG, Rg.RF_CSR_BUSY)
        regWr(Rg.RF_CSR_CFG, ((reg and 0x3f) shl 8) or Rg.RF_CSR_BUSY)
        csrIdle(Rg.RF_CSR_CFG, Rg.RF_CSR_BUSY)
        return regRd(Rg.RF_CSR_CFG) and 0xff
    }

    private fun setf(reg: Int, mask: Int, v: Int) = (reg and mask.inv()) or ((v shl Integer.numberOfTrailingZeros(mask)) and mask)

    companion object {
        const val DWELL_MS = 350L
        const val EXPLORE_MS = 2000L
        const val FRESH_MS = 8000L
    }
}

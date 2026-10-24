package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbRequest
import java.nio.ByteBuffer
import java.util.concurrent.TimeoutException

// unverified: never run on hardware.
class RtlSdrDevice(
    private val conn: UsbDeviceConnection,
    private val intf: UsbInterface,
    private val log: (String) -> Unit
) {
    private class TunerFail(msg: String) : Exception(msg)

    private enum class Chip { NONE, R820T, R828D }

    @Volatile private var stop = false
    private var chip = Chip.NONE
    private var isV4 = false
    private var isV4L = false
    private var rtlXtal = RtlSdrRegs.XTAL_HZ
    private var tunXtal = RtlSdrRegs.XTAL_HZ
    private var rate = 0L
    private var freq = 0L
    private var i2cAddr = RtlSdrRegs.R820T_I2C
    private val regs = IntArray(RtlSdrRegs.R82XX_NUM_REGS)
    private var input = 0
    private var intFreq = 0
    private var filCalCode = 0
    private var hasLock = false

    // unverified:
    fun open(): Boolean {
        if (!conn.claimInterface(intf, true)) {
            log("RTL-SDR: claimInterface failed")
            return false
        }
        if (writeReg(RtlSdrRegs.BLOCK_USB, RtlSdrRegs.USB_SYSCTL, 0x09, 1) < 0) log("RTL-SDR: dummy write failed")
        initBaseband()
        val raw = conn.rawDescriptors
        val manufact = if (raw != null && raw.size > RtlSdrRegs.DEV_DESC_I_PRODUCT) usbString(raw[RtlSdrRegs.DEV_DESC_I_MANUFACTURER].toInt() and 0xff) else ""
        val product = if (raw != null && raw.size > RtlSdrRegs.DEV_DESC_I_PRODUCT) usbString(raw[RtlSdrRegs.DEV_DESC_I_PRODUCT].toInt() and 0xff) else ""
        val blog = manufact == RtlSdrRegs.USB_STR_MANUFACT
        isV4 = blog && product == RtlSdrRegs.USB_STR_V4
        isV4L = blog && product == RtlSdrRegs.USB_STR_V4L
        repeater(true)
        chip = when {
            i2cReadReg(RtlSdrRegs.R820T_I2C, RtlSdrRegs.R82XX_CHECK_ADDR) == RtlSdrRegs.R82XX_CHECK_VAL -> Chip.R820T
            i2cReadReg(RtlSdrRegs.R828D_I2C, RtlSdrRegs.R82XX_CHECK_ADDR) == RtlSdrRegs.R82XX_CHECK_VAL -> Chip.R828D
            else -> Chip.NONE
        }
        if (chip == Chip.NONE) {
            repeater(false)
            log("RTL-SDR: no R820T/R828D tuner found (mfr='$manufact' prod='$product')")
            return false
        }
        log("RTL-SDR: tuner=$chip v4=$isV4 v4l=$isV4L mfr='$manufact' prod='$product'")
        tunXtal = rtlXtal
        i2cAddr = if (chip == Chip.R828D) RtlSdrRegs.R828D_I2C else RtlSdrRegs.R820T_I2C
        if (chip == Chip.R828D && !isV4) tunXtal = RtlSdrRegs.R828D_XTAL_HZ
        demodWrite(1, 0xb1, 0x1a, 1)
        demodWrite(0, 0x08, 0x4d, 1)
        setIfFreq(RtlSdrRegs.IF_HZ)
        demodWrite(1, 0x15, 0x01, 1)
        val ok = try {
            r82Init()
            true
        } catch (e: TunerFail) {
            log("RTL-SDR: tuner init failed: ${e.message}")
            false
        }
        repeater(false)
        return ok
    }

    fun setSampleRate(hz: Int) {
        if (hz <= RtlSdrRegs.MIN_RATE || hz > RtlSdrRegs.MAX_RATE || (hz > RtlSdrRegs.RATE_GAP_LO && hz <= RtlSdrRegs.RATE_GAP_HI)) {
            log("RTL-SDR: invalid sample rate $hz")
            return
        }
        var ratio = (rtlXtal.toLong() shl 22) / hz
        ratio = ratio and 0x0ffffffcL
        val realRatio = ratio or ((ratio and 0x08000000L) shl 1)
        rate = (rtlXtal.toLong() shl 22) / realRatio
        if (chip != Chip.NONE) {
            repeater(true)
            try {
                r82SetBandwidth(rate.toInt())
                setIfFreq(intFreq)
                if (freq != 0L) setCenterFreq(freq)
            } catch (e: TunerFail) {
                log("RTL-SDR: set bandwidth failed: ${e.message}")
            }
            repeater(false)
        }
        demodWrite(1, 0x9f, (ratio shr 16).toInt() and 0xffff, 2)
        demodWrite(1, 0xa1, ratio.toInt() and 0xffff, 2)
        demodWrite(1, 0x3f, 0, 1)
        demodWrite(1, 0x3e, 0, 1)
        demodWrite(1, 0x01, 0x14, 1)
        demodWrite(1, 0x01, 0x10, 1)
    }

    fun setCenterFreq(hz: Long) {
        if (chip == Chip.NONE) return
        if (hz <= 0L || hz > 0xffffffffL) {
            log("RTL-SDR: invalid frequency $hz")
            return
        }
        if (hz < 24_000_000L && chip == Chip.R820T && !isV4L) {
            log("RTL-SDR: $hz Hz needs direct sampling, not supported")
            return
        }
        repeater(true)
        freq = try {
            r82SetFreq(hz)
            hz
        } catch (e: TunerFail) {
            log("RTL-SDR: set freq failed: ${e.message}")
            0L
        } finally {
            repeater(false)
        }
    }

    fun setGain(tenthDb: Int) {
        if (chip == Chip.NONE) return
        repeater(true)
        try {
            r82SetGain(true, tenthDb)
        } catch (e: TunerFail) {
            log("RTL-SDR: set gain failed: ${e.message}")
        } finally {
            repeater(false)
        }
    }

    fun setAgc(on: Boolean) {
        if (chip == Chip.NONE) return
        repeater(true)
        try {
            r82SetGain(!on, 0)
        } catch (e: TunerFail) {
            log("RTL-SDR: set agc failed: ${e.message}")
        } finally {
            repeater(false)
        }
    }

    fun readIq(onIq: (ByteArray, Int) -> Unit) {
        stop = false
        writeReg(RtlSdrRegs.BLOCK_USB, RtlSdrRegs.USB_EPA_CTL, 0x1002, 2)
        writeReg(RtlSdrRegs.BLOCK_USB, RtlSdrRegs.USB_EPA_CTL, 0x0000, 2)
        val ep = findIqEndpoint()
        if (ep == null) {
            log("RTL-SDR: no bulk IN endpoint")
            return
        }
        if (!asyncLoop(ep, onIq)) syncLoop(ep, onIq)
    }

    fun abort() {
        stop = true
    }

    private fun findIqEndpoint(): UsbEndpoint? {
        var fallback: UsbEndpoint? = null
        for (i in 0 until intf.endpointCount) {
            val ep = intf.getEndpoint(i)
            if (ep.type != UsbConstants.USB_ENDPOINT_XFER_BULK || ep.direction != UsbConstants.USB_DIR_IN) continue
            if (ep.address == RtlSdrRegs.EP_IQ_IN) return ep
            if (fallback == null) fallback = ep
        }
        return fallback
    }

    private fun asyncLoop(ep: UsbEndpoint, onIq: (ByteArray, Int) -> Unit): Boolean {
        val nbuf = IQ_REQUESTS
        val bufSz = IQ_BUF_SIZE
        val buffers = Array(nbuf) { ByteBuffer.allocateDirect(bufSz) }
        val reqs = ArrayList<UsbRequest>(nbuf)
        for (i in 0 until nbuf) {
            val r = UsbRequest()
            if (!r.initialize(conn, ep)) {
                reqs.forEach { runCatching { it.cancel() }; runCatching { it.close() } }
                return false
            }
            r.clientData = i
            buffers[i].clear()
            if (!r.queue(buffers[i])) {
                runCatching { r.close() }
                reqs.forEach { runCatching { it.cancel() }; runCatching { it.close() } }
                return false
            }
            reqs.add(r)
        }
        val scratch = ByteArray(bufSz)
        try {
            while (!stop) {
                val req = try { conn.requestWait(100L) } catch (e: TimeoutException) { null }
                if (req == null) continue
                val idx = req.clientData as? Int ?: continue
                if (idx !in 0 until nbuf) continue
                val b = buffers[idx]
                val n = b.position()
                if (n in 1..bufSz) {
                    b.rewind()
                    b.get(scratch, 0, n)
                    onIq(scratch, n)
                }
                b.clear()
                if (!runCatching { req.queue(b) }.getOrDefault(false)) {
                    runCatching { req.close() }
                    val nr = UsbRequest()
                    if (runCatching { nr.initialize(conn, ep) }.getOrDefault(false)) {
                        nr.clientData = idx
                        b.clear()
                        if (runCatching { nr.queue(b) }.getOrDefault(false)) reqs[idx] = nr
                    }
                }
            }
        } finally {
            reqs.forEach { runCatching { it.cancel() }; runCatching { it.close() } }
        }
        return true
    }

    private fun syncLoop(ep: UsbEndpoint, onIq: (ByteArray, Int) -> Unit) {
        val buf = ByteArray(IQ_BUF_SIZE)
        while (!stop) {
            val n = conn.bulkTransfer(ep, buf, buf.size, 500)
            if (n > 0) onIq(buf, n)
        }
    }

    private fun usbCtrl(type: Int, value: Int, index: Int, buf: ByteArray, len: Int): Int =
        conn.controlTransfer(type, 0, value, index, buf, len, RtlSdrRegs.CTRL_TIMEOUT)

    private fun usbString(idx: Int): String {
        if (idx == 0) return ""
        val buf = ByteArray(255)
        val lang = conn.controlTransfer(RtlSdrRegs.STD_DIR_IN, RtlSdrRegs.STD_REQ_GET_DESCRIPTOR, RtlSdrRegs.STD_DT_STRING, 0, buf, buf.size, RtlSdrRegs.CTRL_TIMEOUT)
        if (lang < 4) return ""
        val langId = (buf[2].toInt() and 0xff) or ((buf[3].toInt() and 0xff) shl 8)
        val n = conn.controlTransfer(RtlSdrRegs.STD_DIR_IN, RtlSdrRegs.STD_REQ_GET_DESCRIPTOR, RtlSdrRegs.STD_DT_STRING or idx, langId, buf, buf.size, RtlSdrRegs.CTRL_TIMEOUT)
        val sb = StringBuilder()
        var i = 2
        while (i + 1 < n) {
            val lo = buf[i].toInt() and 0xff
            val hi = buf[i + 1].toInt() and 0xff
            sb.append(if (hi == 0 && lo < 0x80) lo.toChar() else '?')
            i += 2
        }
        return sb.toString()
    }

    private fun readReg(block: Int, addr: Int, len: Int): Int {
        val d = ByteArray(2)
        usbCtrl(RtlSdrRegs.CTRL_IN, addr, block shl 8, d, len)
        return ((d[1].toInt() and 0xff) shl 8) or (d[0].toInt() and 0xff)
    }

    private fun writeReg(block: Int, addr: Int, v: Int, len: Int): Int {
        val d = ByteArray(2)
        d[0] = (if (len == 1) v and 0xff else (v shr 8) and 0xff).toByte()
        d[1] = (v and 0xff).toByte()
        return usbCtrl(RtlSdrRegs.CTRL_OUT, addr, (block shl 8) or 0x10, d, len)
    }

    private fun demodRead(page: Int, addr: Int, len: Int): Int {
        val d = ByteArray(2)
        usbCtrl(RtlSdrRegs.CTRL_IN, (addr shl 8) or 0x20, page, d, len)
        return ((d[1].toInt() and 0xff) shl 8) or (d[0].toInt() and 0xff)
    }

    private fun demodWrite(page: Int, addr: Int, v: Int, len: Int): Boolean {
        val d = ByteArray(2)
        d[0] = (if (len == 1) v and 0xff else (v shr 8) and 0xff).toByte()
        d[1] = (v and 0xff).toByte()
        val r = usbCtrl(RtlSdrRegs.CTRL_OUT, (addr shl 8) or 0x20, 0x10 or page, d, len)
        demodRead(0x0a, 0x01, 1)
        return r == len
    }

    private fun repeater(on: Boolean) {
        demodWrite(1, 0x01, if (on) 0x18 else 0x10, 1)
    }

    private fun i2cWrite(addr: Int, data: ByteArray, len: Int): Int =
        usbCtrl(RtlSdrRegs.CTRL_OUT, addr, (RtlSdrRegs.BLOCK_IIC shl 8) or 0x10, data, len)

    private fun i2cRead(addr: Int, data: ByteArray, len: Int): Int =
        usbCtrl(RtlSdrRegs.CTRL_IN, addr, RtlSdrRegs.BLOCK_IIC shl 8, data, len)

    private fun i2cReadReg(addr: Int, reg: Int): Int {
        val one = byteArrayOf(reg.toByte())
        i2cWrite(addr, one, 1)
        val d = ByteArray(1)
        i2cRead(addr, d, 1)
        return d[0].toInt() and 0xff
    }

    private fun setGpioOutput(gpio: Int) {
        val bit = 1 shl gpio
        writeReg(RtlSdrRegs.BLOCK_SYS, RtlSdrRegs.GPD, readReg(RtlSdrRegs.BLOCK_SYS, RtlSdrRegs.GPD, 1) and bit.inv(), 1)
        writeReg(RtlSdrRegs.BLOCK_SYS, RtlSdrRegs.GPOE, readReg(RtlSdrRegs.BLOCK_SYS, RtlSdrRegs.GPOE, 1) or bit, 1)
    }

    private fun setGpioBit(gpio: Int, on: Boolean) {
        val bit = 1 shl gpio
        val r = readReg(RtlSdrRegs.BLOCK_SYS, RtlSdrRegs.GPO, 1)
        writeReg(RtlSdrRegs.BLOCK_SYS, RtlSdrRegs.GPO, if (on) r or bit else r and bit.inv(), 1)
    }

    private fun setFir() {
        val fir = RtlSdrRegs.FIR_DEFAULT
        val out = IntArray(RtlSdrRegs.FIR_BYTES)
        for (i in 0 until 8) out[i] = fir[i] and 0xff
        var i = 0
        while (i < 8) {
            val v0 = fir[8 + i]
            val v1 = fir[8 + i + 1]
            val o = 8 + i * 3 / 2
            out[o] = (v0 shr 4) and 0xff
            out[o + 1] = ((v0 shl 4) or ((v1 shr 8) and 0x0f)) and 0xff
            out[o + 2] = v1 and 0xff
            i += 2
        }
        for (k in out.indices) demodWrite(1, RtlSdrRegs.FIR_DEMOD_REG + k, out[k], 1)
    }

    private fun initBaseband() {
        writeReg(RtlSdrRegs.BLOCK_USB, RtlSdrRegs.USB_SYSCTL, 0x09, 1)
        writeReg(RtlSdrRegs.BLOCK_USB, RtlSdrRegs.USB_EPA_MAXPKT, 0x0002, 2)
        writeReg(RtlSdrRegs.BLOCK_USB, RtlSdrRegs.USB_EPA_CTL, 0x1002, 2)
        writeReg(RtlSdrRegs.BLOCK_SYS, RtlSdrRegs.DEMOD_CTL_1, 0x22, 1)
        writeReg(RtlSdrRegs.BLOCK_SYS, RtlSdrRegs.DEMOD_CTL, 0xe8, 1)
        demodWrite(1, 0x01, 0x14, 1)
        demodWrite(1, 0x01, 0x10, 1)
        demodWrite(1, 0x15, 0x00, 1)
        demodWrite(1, 0x16, 0x0000, 2)
        for (i in 0 until 6) demodWrite(1, 0x16 + i, 0x00, 1)
        setFir()
        demodWrite(0, 0x19, 0x05, 1)
        demodWrite(1, 0x93, 0xf0, 1)
        demodWrite(1, 0x94, 0x0f, 1)
        demodWrite(1, 0x11, 0x00, 1)
        demodWrite(1, 0x04, 0x00, 1)
        demodWrite(0, 0x61, 0x60, 1)
        demodWrite(0, 0x06, 0x80, 1)
        demodWrite(1, 0xb1, 0x1b, 1)
        demodWrite(0, 0x0d, 0x83, 1)
    }

    private fun setIfFreq(hz: Int) {
        val v = -(hz.toDouble() * 4194304.0 / rtlXtal.toDouble()).toInt()
        demodWrite(1, 0x19, (v shr 16) and 0x3f, 1)
        demodWrite(1, 0x1a, (v shr 8) and 0xff, 1)
        demodWrite(1, 0x1b, v and 0xff, 1)
    }

    private fun r82Write(reg: Int, vals: IntArray) {
        var start = reg - RtlSdrRegs.R82XX_SHADOW_START
        var from = 0
        var n = vals.size
        if (start < 0) {
            from = -start
            n += start
            start = 0
        }
        if (n > 0) {
            if (n > RtlSdrRegs.R82XX_NUM_REGS - start) n = RtlSdrRegs.R82XX_NUM_REGS - start
            for (k in 0 until n) regs[start + k] = vals[from + k]
        }
        var r = reg
        var pos = 0
        var left = vals.size
        while (left > 0) {
            val size = minOf(left, RtlSdrRegs.R82XX_MAX_I2C_MSG - 1)
            val buf = ByteArray(size + 1)
            buf[0] = r.toByte()
            for (k in 0 until size) buf[1 + k] = vals[pos + k].toByte()
            val rc = i2cWrite(i2cAddr, buf, size + 1)
            if (rc != size + 1) throw TunerFail("i2c wr rc=$rc reg=0x${r.toString(16)}")
            r += size
            left -= size
            pos += size
        }
    }

    private fun r82WriteReg(reg: Int, v: Int) = r82Write(reg, intArrayOf(v and 0xff))

    private fun r82WriteMask(reg: Int, v: Int, mask: Int) {
        val idx = reg - RtlSdrRegs.R82XX_SHADOW_START
        if (idx < 0 || idx >= RtlSdrRegs.R82XX_NUM_REGS) throw TunerFail("shadow reg 0x${reg.toString(16)}")
        r82WriteReg(reg, (regs[idx] and mask.inv()) or (v and mask))
    }

    private fun bitrev(b: Int): Int {
        var x = b and 0xff
        var r = 0
        for (i in 0 until 8) {
            r = (r shl 1) or (x and 1)
            x = x shr 1
        }
        return r
    }

    private fun r82Read(reg: Int, len: Int): IntArray {
        val one = byteArrayOf(reg.toByte())
        val w = i2cWrite(i2cAddr, one, 1)
        if (w != 1) throw TunerFail("i2c rd addr rc=$w reg=0x${reg.toString(16)}")
        val d = ByteArray(len)
        val r = i2cRead(i2cAddr, d, len)
        if (r != len) throw TunerFail("i2c rd rc=$r reg=0x${reg.toString(16)}")
        return IntArray(len) { bitrev(d[it].toInt()) }
    }

    private fun r82SetMux(freqHz: Long) {
        val mhz = (freqHz / 1_000_000L).toInt()
        val ranges = RtlSdrRegs.R82XX_FREQ_RANGES
        var i = 0
        while (i < ranges.size - 1) {
            if (mhz < ranges[i + 1][0]) break
            i++
        }
        val range = ranges[i]
        r82WriteMask(0x17, range[1], 0x08)
        r82WriteMask(0x1a, range[2], 0xc3)
        r82WriteReg(0x1b, range[3])
        r82WriteMask(0x10, range[4], 0x0b)
        r82WriteMask(0x08, 0x00, 0x3f)
        r82WriteMask(0x09, 0x00, 0x3f)
    }

    private fun r82SetPll(freqHz: Long) {
        val freqKhz = (freqHz + 500L) / 1000L
        val pllRef = tunXtal.toLong()
        val pllRefKhz = (pllRef + 500L) / 1000L
        val vcoMin = 1_770_000L
        val vcoMax = vcoMin * 2
        r82WriteMask(0x10, 0, 0x10)
        r82WriteMask(0x1a, 0x00, 0x0c)
        r82WriteMask(0x12, 0x06, 0xff)
        var mixDiv = 2
        var divNum = 0
        while (mixDiv <= 64) {
            if (freqKhz * mixDiv >= vcoMin && freqKhz * mixDiv < vcoMax) {
                var d = mixDiv
                while (d > 2) {
                    d = d shr 1
                    divNum++
                }
                break
            }
            mixDiv = mixDiv shl 1
        }
        var data = r82Read(0x00, 5)
        val vcoPowerRef = if (chip == Chip.R828D || isV4L) 1 else 2
        val fine = (data[4] and 0x30) shr 4
        if (fine > vcoPowerRef) divNum-- else if (fine < vcoPowerRef) divNum++
        r82WriteMask(0x10, ((divNum and 0xff) shl 5) and 0xff, 0xe0)
        val vcoFreq = freqHz * mixDiv
        val nint = vcoFreq / (2 * pllRef)
        var vcoFra = (vcoFreq - 2 * pllRef * nint) / 1000L
        if (nint > (128 / vcoPowerRef) - 1) throw TunerFail("no PLL values for $freqHz Hz")
        val ni = ((nint - 13) / 4) and 0xff
        val si = (nint - 4 * ni - 13) and 0xff
        r82WriteReg(0x14, (ni + (si shl 6)).toInt())
        r82WriteMask(0x12, if (vcoFra == 0L) 0x08 else 0x00, 0x08)
        var nSdm = 2L
        var sdm = 0L
        while (vcoFra > 1) {
            if (vcoFra > 2 * pllRefKhz / nSdm) {
                sdm += 32768L / (nSdm / 2)
                vcoFra -= 2 * pllRefKhz / nSdm
                if (nSdm >= 0x8000L) break
            }
            nSdm = nSdm shl 1
            if (nSdm > 0xffffL) break
        }
        r82WriteReg(0x16, ((sdm shr 8) and 0xff).toInt())
        r82WriteReg(0x15, (sdm and 0xff).toInt())
        for (i in 0 until 2) {
            data = r82Read(0x00, 3)
            if ((data[2] and 0x40) != 0) break
            if (i == 0) r82WriteMask(0x12, 0x06, 0xff)
        }
        if ((data[2] and 0x40) == 0) {
            hasLock = false
            log("RTL-SDR: PLL not locked at $freqHz Hz")
            return
        }
        hasLock = true
        r82WriteMask(0x1a, 0x08, 0x08)
    }

    private fun r82SetFreq(freqHz: Long) {
        val upconverting = (isV4 || isV4L) && freqHz < RtlSdrRegs.V4_UPCONVERT_HZ
        val tuneHz = if (upconverting) freqHz + RtlSdrRegs.V4_UPCONVERT_HZ else freqHz
        val loFreq = tuneHz + intFreq
        r82SetMux(loFreq)
        r82WriteMask(0x0c, 0x08, 0x9f)
        r82SetPll(loFreq)
        if (!hasLock) return
        if (isV4) {
            val openD = if (freqHz <= 2_200_000L || (freqHz >= 85_000_000L && freqHz <= 112_000_000L) || (freqHz >= 172_000_000L && freqHz <= 242_000_000L)) 0x00 else 0x08
            r82WriteMask(0x17, openD, 0x08)
            val band = if (freqHz <= RtlSdrRegs.V4_UPCONVERT_HZ) RtlSdrRegs.BAND_HF else if (freqHz < 250_000_000L) RtlSdrRegs.BAND_VHF else RtlSdrRegs.BAND_UHF
            if (band == RtlSdrRegs.BAND_HF) {
                r82WriteMask(0x1a, 0x40, 0xc3)
                r82WriteReg(0x1b, 0x00)
            }
            if (band != input) {
                input = band
                val cable2 = if (band == RtlSdrRegs.BAND_HF) 0x08 else 0x00
                r82WriteMask(0x06, cable2, 0x08)
                setGpioOutput(RtlSdrRegs.V4_GPIO_UPCONVERTER)
                setGpioBit(RtlSdrRegs.V4_GPIO_UPCONVERTER, cable2 == 0)
                r82WriteMask(0x05, if (band == RtlSdrRegs.BAND_VHF) 0x40 else 0x00, 0x40)
                r82WriteMask(0x05, if (band == RtlSdrRegs.BAND_UHF) 0x00 else 0x20, 0x20)
            }
        } else if (isV4L) {
            val band = if (freqHz <= RtlSdrRegs.V4_UPCONVERT_HZ) RtlSdrRegs.BAND_HF else RtlSdrRegs.BAND_UHF
            if (band == RtlSdrRegs.BAND_HF) {
                r82WriteMask(0x1a, 0x40, 0xc3)
                r82WriteReg(0x1b, 0x00)
            }
            if (band != input) {
                input = band
                val cable1 = if (band == RtlSdrRegs.BAND_HF) 0x40 else 0x00
                setGpioOutput(RtlSdrRegs.V4_GPIO_UPCONVERTER)
                setGpioBit(RtlSdrRegs.V4_GPIO_UPCONVERTER, cable1 == 0)
                r82WriteMask(0x05, cable1, 0x40)
                r82WriteMask(0x05, if (band == RtlSdrRegs.BAND_UHF) 0x00 else 0x20, 0x20)
            }
        } else {
            val airCable1 = if (freqHz > 345_000_000L) 0x00 else 0x60
            if (chip == Chip.R828D && airCable1 != input) {
                input = airCable1
                r82WriteMask(0x05, airCable1, 0x60)
            }
        }
    }

    private fun r82SetGain(manual: Boolean, gain: Int) {
        if (manual) {
            var total = 0
            var mixIdx = 0
            var lnaIdx = 0
            r82WriteMask(0x05, 0x10, 0x10)
            r82WriteMask(0x07, 0x00, 0x10)
            r82WriteMask(0x0c, 0x08, 0x9f)
            for (i in 0 until 15) {
                if (total >= gain) break
                total += RtlSdrRegs.R82XX_LNA_GAIN_STEPS[++lnaIdx]
                if (total >= gain) break
                total += RtlSdrRegs.R82XX_MIXER_GAIN_STEPS[++mixIdx]
            }
            r82WriteMask(0x05, lnaIdx, 0x0f)
            r82WriteMask(0x07, mixIdx, 0x0f)
        } else {
            r82WriteMask(0x05, 0x00, 0x10)
            r82WriteMask(0x07, 0x10, 0x10)
            r82WriteMask(0x0c, 0x0b, 0x9f)
        }
    }

    private fun r82SetBandwidth(bwIn: Int) {
        var bw = bwIn
        val lpf = RtlSdrRegs.R82XX_IF_LPF_BW
        var reg0a: Int
        var reg0b: Int
        if (bw > 7_000_000) {
            reg0a = 0x10
            reg0b = 0x0b
            intFreq = 4_570_000
        } else if (bw > 6_000_000) {
            reg0a = 0x10
            reg0b = 0x2a
            intFreq = 4_570_000
        } else if (bw > lpf[0] + RtlSdrRegs.R82XX_FILT_HP_BW1 + RtlSdrRegs.R82XX_FILT_HP_BW2) {
            reg0a = 0x10
            reg0b = 0x6b
            intFreq = 3_570_000
        } else {
            var realBw = 0
            reg0a = 0x00
            reg0b = 0x80
            intFreq = 2_300_000
            if (bw > lpf[0] + RtlSdrRegs.R82XX_FILT_HP_BW1) {
                bw -= RtlSdrRegs.R82XX_FILT_HP_BW2
                intFreq += RtlSdrRegs.R82XX_FILT_HP_BW2
                realBw += RtlSdrRegs.R82XX_FILT_HP_BW2
            } else {
                reg0b = reg0b or 0x20
            }
            if (bw > lpf[0]) {
                bw -= RtlSdrRegs.R82XX_FILT_HP_BW1
                intFreq += RtlSdrRegs.R82XX_FILT_HP_BW1
                realBw += RtlSdrRegs.R82XX_FILT_HP_BW1
            } else {
                reg0b = reg0b or 0x40
            }
            var i = 0
            while (i < lpf.size) {
                if (bw > lpf[i]) break
                i++
            }
            i = maxOf(i - 1, 0)
            reg0b = reg0b or (15 - i)
            realBw += lpf[i]
            intFreq -= realBw / 2
        }
        r82WriteMask(0x0a, reg0a, 0x10)
        r82WriteMask(0x0b, reg0b, 0xef)
    }

    private fun r82Init() {
        r82Write(RtlSdrRegs.R82XX_SHADOW_START, RtlSdrRegs.R82XX_INIT_ARRAY)
        r82SetTvStandard()
        r82SysFreqSel()
    }

    private fun r82SetTvStandard() {
        for (k in regs.indices) regs[k] = RtlSdrRegs.R82XX_INIT_ARRAY[k]
        r82WriteMask(0x0c, 0x00, 0x0f)
        r82WriteMask(0x13, RtlSdrRegs.R82XX_VER_NUM, 0x3f)
        r82WriteMask(0x1d, 0x00, 0x38)
        intFreq = RtlSdrRegs.IF_HZ
        for (i in 0 until 2) {
            r82WriteMask(0x0b, 0x6b, 0x60)
            r82WriteMask(0x0f, 0x04, 0x04)
            r82WriteMask(0x10, 0x00, 0x03)
            r82SetPll(RtlSdrRegs.R82XX_FILT_CAL_LO_KHZ * 1000L)
            if (!hasLock) return
            r82WriteMask(0x0b, 0x10, 0x10)
            r82WriteMask(0x0b, 0x00, 0x10)
            r82WriteMask(0x0f, 0x00, 0x04)
            filCalCode = r82Read(0x00, 5)[4] and 0x0f
            if (filCalCode != 0 && filCalCode != 0x0f) break
        }
        if (filCalCode == 0x0f) filCalCode = 0
        r82WriteMask(0x0a, 0x10 or filCalCode, 0x1f)
        r82WriteMask(0x0b, 0x6b, 0xef)
        r82WriteMask(0x07, 0x00, 0x80)
        r82WriteMask(0x06, 0x30, 0x30)
        r82WriteMask(0x1e, 0x60, 0x60)
        r82WriteMask(0x05, 0x80, 0x80)
        r82WriteMask(0x1f, 0x00, 0x80)
        r82WriteMask(0x0f, 0x00, 0x80)
        r82WriteMask(0x19, 0x60, 0x60)
    }

    private fun r82SysFreqSel() {
        r82WriteMask(0x1d, 0xe5, 0xc7)
        r82WriteMask(0x1c, 0x24, 0xf8)
        r82WriteReg(0x0d, 0x53)
        r82WriteReg(0x0e, 0x75)
        input = 0
        r82WriteMask(0x05, 0x00, 0x60)
        r82WriteMask(0x06, 0x00, 0x08)
        r82WriteMask(0x11, 0x38, 0x38)
        r82WriteMask(0x17, 0xa0, 0x30)
        r82WriteMask(0x0a, 0x40, 0x60)
        r82WriteMask(0x1d, 0x00, 0x38)
        r82WriteMask(0x1c, 0x00, 0x04)
        r82WriteMask(0x06, 0x00, 0x40)
        r82WriteMask(0x1a, 0x30, 0x30)
        r82WriteMask(0x1d, 0x18, 0x38)
        r82WriteMask(0x1c, 0x24, 0x04)
        r82WriteMask(0x1e, 14, 0x1f)
        r82WriteMask(0x1a, 0x20, 0x30)
    }

    private companion object {
        const val IQ_BUF_SIZE = 16384
        const val IQ_REQUESTS = 16
    }
}

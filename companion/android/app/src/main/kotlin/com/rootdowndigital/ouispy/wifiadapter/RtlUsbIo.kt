package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbDeviceConnection
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.sleep
import java.io.IOException
import java.io.InterruptedIOException

// Realtek vendor-request register I/O and power-sequence runner, flows from Linux rtw88 (SPDX GPL-2.0 OR BSD-3-Clause).
internal class RtlIo(private val conn: UsbDeviceConnection) {
    @Volatile var canceled = false
    private val buf = ByteArray(4)
    private var fails = 0

    fun r8(a: Int): Int = ctrlIn(a, 1)
    fun r16(a: Int): Int = ctrlIn(a, 2)
    fun r32(a: Int): Int = ctrlIn(a, 4)
    fun w8(a: Int, v: Int) = ctrlOut(a, v, 1)
    fun w16(a: Int, v: Int) = ctrlOut(a, v, 2)
    fun w32(a: Int, v: Int) = ctrlOut(a, v, 4)

    fun s8(a: Int, bits: Int) = w8(a, r8(a) or bits)
    fun c8(a: Int, bits: Int) = w8(a, r8(a) and bits.inv())
    fun s16(a: Int, bits: Int) = w16(a, r16(a) or bits)
    fun c16(a: Int, bits: Int) = w16(a, r16(a) and bits.inv())
    fun s32(a: Int, bits: Int) = w32(a, r32(a) or bits)
    fun c32(a: Int, bits: Int) = w32(a, r32(a) and bits.inv())

    fun m32(a: Int, mask: Int, data: Int) {
        val sh = Integer.numberOfTrailingZeros(mask)
        w32(a, (r32(a) and mask.inv()) or ((data shl sh) and mask))
    }

    fun m8(a: Int, mask: Int, data: Int) {
        val mk = mask and 0xff
        val sh = Integer.numberOfTrailingZeros(mk)
        w8(a, (r8(a) and mk.inv()) or ((data shl sh) and mk))
    }

    fun rm32(a: Int, mask: Int): Int = (r32(a) and mask) ushr Integer.numberOfTrailingZeros(mask)

    fun waitMask(a: Int, mask: Int, target: Int, tries: Int = 1000): Boolean {
        for (i in 0 until tries) {
            if (rm32(a, mask) == target) return true
        }
        return false
    }

    fun writeBlock(a: Int, data: ByteArray, off: Int, len: Int) {
        checkCancel()
        val n = conn.controlTransfer(Rtl88Regs.DIR_OUT, Rtl88Regs.VENDOR_REQ, a and 0xffff, 0, data, off, len, TIMEOUT)
        if (n != len) throw IOException("RTL: block write 0x${a.toString(16)} len $len returned $n")
    }

    private fun checkCancel() {
        if (canceled) throw InterruptedIOException("RTL: canceled")
    }

    private fun ctrlIn(a: Int, len: Int): Int {
        checkCancel()
        val n = conn.controlTransfer(Rtl88Regs.DIR_IN, Rtl88Regs.VENDOR_REQ, a and 0xffff, 0, buf, len, TIMEOUT)
        if (n != len) {
            fail("read", a, n)
            return 0
        }
        fails = 0
        var v = 0
        for (i in 0 until len) v = v or ((buf[i].toInt() and 0xff) shl (8 * i))
        return v
    }

    private fun ctrlOut(a: Int, v: Int, len: Int) {
        checkCancel()
        val b = ByteArray(len) { (v ushr (8 * it)).toByte() }
        val n = conn.controlTransfer(Rtl88Regs.DIR_OUT, Rtl88Regs.VENDOR_REQ, a and 0xffff, 0, b, len, TIMEOUT)
        if (n != len) fail("write", a, n) else fails = 0
    }

    private fun fail(what: String, a: Int, n: Int) {
        if (++fails > MAX_FAILS) throw IOException("RTL: $what 0x${a.toString(16)} failed ($n)")
    }

    companion object {
        const val TIMEOUT = 1000
        const val MAX_FAILS = 32
    }
}

internal class PwrCmd(val offset: Int, val kind: Int, val mask: Int, val value: Int)

internal const val PWR_WRITE = 1
internal const val PWR_POLL = 2
internal const val PWR_DELAY_US = 3
internal const val PWR_DELAY_MS = 4

internal fun pwrW(offset: Int, mask: Int, value: Int) = PwrCmd(offset, PWR_WRITE, mask, value)
internal fun pwrPoll(offset: Int, mask: Int, value: Int) = PwrCmd(offset, PWR_POLL, mask, value)
internal fun pwrDelayUs(us: Int) = PwrCmd(0, PWR_DELAY_US, 0, us)
internal fun pwrDelayMs(ms: Int) = PwrCmd(0, PWR_DELAY_MS, 0, ms)

internal fun runPwrSeq(io: RtlIo, flow: Array<PwrCmd>) {
    for (c in flow) {
        when (c.kind) {
            PWR_WRITE -> io.w8(c.offset, (io.r8(c.offset) and c.mask.inv()) or (c.value and c.mask))
            PWR_POLL -> {
                val end = System.currentTimeMillis() + 1000
                var ok = false
                while (!ok && System.currentTimeMillis() < end) {
                    ok = (io.r8(c.offset) and c.mask) == (c.value and c.mask)
                    if (!ok) sleep(1)
                }
                if (!ok) throw IllegalStateException("RTL: power sequence poll timeout at 0x${c.offset.toString(16)}")
            }
            PWR_DELAY_US -> sleep(1)
            PWR_DELAY_MS -> sleep(c.value)
        }
    }
}

internal object RtlEfuse {
    fun dump(io: RtlIo, physSize: Int, logSize: Int): ByteArray {
        io.w8(Rtl88Regs.EFUSE_ACCESS, 0x69)
        io.s16(Rtl88Regs.SYS_FUNC_EN, 1 shl 12)
        io.s16(Rtl88Regs.SYS_CLKR, (1 shl 5) or (1 shl 1))
        io.m32(Rtl88Regs.LDO_EFUSE_CTRL, (1 shl 8) or (1 shl 9), 0)
        var ctl = io.r32(Rtl88Regs.EFUSE_CTRL)
        val phy = ByteArray(physSize)
        for (addr in 0 until physSize) {
            ctl = (ctl and ((0xff or (0x3ff shl 8)).inv())) or ((addr and 0x3ff) shl 8)
            io.w32(Rtl88Regs.EFUSE_CTRL, ctl and (1 shl 31).inv())
            var n = 0
            do {
                ctl = io.r32(Rtl88Regs.EFUSE_CTRL)
                if (++n > 1000) throw IllegalStateException("RTL: efuse read timeout at $addr")
            } while ((ctl ushr 31) == 0)
            phy[addr] = ctl.toByte()
        }
        io.w8(Rtl88Regs.EFUSE_ACCESS, 0)
        return logical(phy, logSize)
    }

    private fun logical(phy: ByteArray, logSize: Int): ByteArray {
        val log = ByteArray(logSize) { 0xff.toByte() }
        var p = 0
        while (p + 1 < phy.size) {
            val h1 = phy[p].toInt() and 0xff
            val h2 = phy[p + 1].toInt() and 0xff
            if (h1 == 0xff || ((h1 and 0x1f) == 0xf && h2 == 0xff)) break
            val blk: Int
            val wen: Int
            if ((h1 and 0x1f) == 0xf) {
                blk = ((h2 and 0xf0) shr 1) or ((h1 shr 5) and 0x07)
                wen = h2 and 0xf
                p += 2
            } else {
                blk = (h1 and 0xf0) shr 4
                wen = h1 and 0xf
                p += 1
            }
            for (i in 0 until 4) {
                if ((wen and (1 shl i)) != 0) continue
                val li = (blk shl 3) + (i shl 1)
                if (p + 1 >= phy.size || li + 1 >= logSize) throw IllegalStateException("RTL: efuse map overflow")
                log[li] = phy[p]
                log[li + 1] = phy[p + 1]
                p += 2
            }
        }
        return log
    }
}

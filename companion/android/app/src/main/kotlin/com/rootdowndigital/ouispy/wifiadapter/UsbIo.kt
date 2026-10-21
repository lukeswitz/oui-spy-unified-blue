package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbDeviceConnection

// Little-endian control-transfer register I/O for the MT7612U over USB, modeled on
// mt76's vendor-request helpers (mt76u_rr / mt76u_wr). Own implementation.
internal class UsbIo(private val conn: UsbDeviceConnection) {

    fun regWrite(addr: Int, value: Int) =
        ctrlOut(Mt76Regs.VENDOR_WRITE, addr, le32(value))

    fun regRead(addr: Int): Int = ctrlIn(Mt76Regs.VENDOR_READ, addr)

    fun regSet(addr: Int, bits: Int) = regWrite(addr, regRead(addr) or bits)
    fun regClear(addr: Int, bits: Int) = regWrite(addr, regRead(addr) and bits.inv())
    fun regRmw(addr: Int, mask: Int, bits: Int) = regWrite(addr, (regRead(addr) and mask.inv()) or bits)

    fun cfgWrite(addr: Int, value: Int) =
        ctrlOut(Mt76Regs.VENDOR_WRITE_CFG, addr, le32(value))

    fun cfgRead(addr: Int): Int =
        conn.controlTransfer(Mt76Regs.DIR_IN, Mt76Regs.VENDOR_READ_CFG, hi(addr), lo(addr), read4, 4, TIMEOUT)
            .let { if (it == 4) le32(read4) else 0 }

    fun cfgSet(addr: Int, bits: Int) = cfgWrite(addr, cfgRead(addr) or bits)
    fun cfgClear(addr: Int, bits: Int) = cfgWrite(addr, cfgRead(addr) and bits.inv())

    fun eepromRead(offset: Int): Int =
        conn.controlTransfer(Mt76Regs.DIR_IN, Mt76Regs.VENDOR_READ_EEPROM, hi(offset), lo(offset), read4, 4, TIMEOUT)
            .let { if (it == 4) le32(read4) else 0 }

    // FCE DMA length/address writes split into two 16-bit control transfers (mt76u_single_wr).
    fun singleWriteFce(offset: Int, value: Int) {
        conn.controlTransfer(Mt76Regs.DIR_OUT, Mt76Regs.VENDOR_WRITE_FCE, value and 0xffff, offset, null, 0, TIMEOUT)
        conn.controlTransfer(Mt76Regs.DIR_OUT, Mt76Regs.VENDOR_WRITE_FCE, (value ushr 16) and 0xffff, offset + 2, null, 0, TIMEOUT)
    }

    fun devMode(reqType: Int, value: Int, data: ByteArray?) =
        conn.controlTransfer(reqType, Mt76Regs.VENDOR_DEV_MODE, value, 0, data, data?.size ?: 0, TIMEOUT)

    fun pollReg(addr: Int, mask: Int, want: Int, ms: Int): Boolean {
        val end = System.currentTimeMillis() + ms
        do {
            if ((regRead(addr) and mask) == want) return true
            sleep(5)
        } while (System.currentTimeMillis() < end)
        return false
    }

    fun pollCfg(addr: Int, mask: Int, want: Int, ms: Int): Boolean {
        val end = System.currentTimeMillis() + ms
        do {
            if ((cfgRead(addr) and mask) == want) return true
            sleep(2)
        } while (System.currentTimeMillis() < end)
        return false
    }

    private fun ctrlOut(req: Int, addr: Int, data: ByteArray) =
        conn.controlTransfer(Mt76Regs.DIR_OUT, req, hi(addr), lo(addr), data, data.size, TIMEOUT)

    private fun ctrlIn(req: Int, addr: Int): Int =
        conn.controlTransfer(Mt76Regs.DIR_IN, req, hi(addr), lo(addr), read4, 4, TIMEOUT)
            .let { if (it == 4) le32(read4) else 0 }

    private val read4 = ByteArray(4)
    private fun hi(a: Int) = (a ushr 16) and 0xffff
    private fun lo(a: Int) = a and 0xffff

    companion object {
        const val TIMEOUT = 1000

        fun le32(v: Int) = byteArrayOf(v.toByte(), (v ushr 8).toByte(), (v ushr 16).toByte(), (v ushr 24).toByte())
        fun le32(b: ByteArray, i: Int = 0): Int =
            (b[i].toInt() and 0xff) or ((b[i + 1].toInt() and 0xff) shl 8) or
                ((b[i + 2].toInt() and 0xff) shl 16) or ((b[i + 3].toInt() and 0xff) shl 24)
        fun le16(b: ByteArray, i: Int): Int = (b[i].toInt() and 0xff) or ((b[i + 1].toInt() and 0xff) shl 8)
        fun putLe32(b: ByteArray, i: Int, v: Int) {
            b[i] = v.toByte(); b[i + 1] = (v ushr 8).toByte(); b[i + 2] = (v ushr 16).toByte(); b[i + 3] = (v ushr 24).toByte()
        }
        fun sleep(ms: Int) {
            try {
                Thread.sleep(ms.toLong())
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
    }
}

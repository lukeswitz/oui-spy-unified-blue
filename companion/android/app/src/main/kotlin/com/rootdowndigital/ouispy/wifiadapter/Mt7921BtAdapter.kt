package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.sleep

internal class Mt7921BtAdapter(
    private val conn: UsbDeviceConnection,
    private val intf: UsbInterface,
    private val btFw: ByteArray,
    private val log: (String) -> Unit,
    private val onAdv: (String, String, Int, ByteArray) -> Unit = { _, _, _, _ -> },
) {
    @Volatile private var stop = false
    private val ifaceNum = intf.id
    private var epEvt: UsbEndpoint? = null

    fun abort() { stop = true }

    fun run() {
        if (!conn.claimInterface(intf, true)) {
            log("MT7921-BT: claim iface $ifaceNum failed")
            return
        }
        for (i in 0 until intf.endpointCount) {
            val ep = intf.getEndpoint(i)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_INT && ep.direction == UsbConstants.USB_DIR_IN) {
                val cur = epEvt
                if (cur == null || ep.maxPacketSize > cur.maxPacketSize) epEvt = ep
            }
        }
        val evt = epEvt
        if (evt == null) {
            log("MT7921-BT: no interrupt-IN endpoint on iface $ifaceNum")
            return
        }
        log("MT7921-BT: iface=%d evtEp=0x%02x".format(ifaceNum, evt.address))

        if (!setupFirmware()) {
            log("MT7921-BT: firmware setup failed")
            return
        }

        clearHalt(evt.address)
        hciCommand(0x0c03, ByteArray(0))
        val ev = readEvent(evt, 2000)
        if (ev == null) {
            log("MT7921-BT: HCI reset no event after firmware load")
            return
        }
        log("MT7921-BT: HCI reset ok")
        leScan(evt)
    }

    private fun leScan(evt: UsbEndpoint) {
        hciCommand(0x200b, byteArrayOf(0, 0x10, 0, 0x10, 0, 0, 0))
        readEvent(evt, 1000)
        hciCommand(0x200c, byteArrayOf(1, 0))
        readEvent(evt, 1000)
        log("MT7921-BT: LE scan enabled")

        val acc = ArrayList<Byte>(512)
        val buf = ByteArray(260)
        while (!stop) {
            val n = conn.bulkTransfer(evt, buf, buf.size, 500)
            if (n <= 0) continue
            for (i in 0 until n) acc.add(buf[i])
            drainEvents(acc)
        }
        hciCommand(0x200c, byteArrayOf(0, 0))
        log("MT7921-BT: LE scan stopped")
    }

    private fun drainEvents(acc: ArrayList<Byte>): Int {
        var reports = 0
        while (acc.size >= 2) {
            val plen = acc[1].toInt() and 0xff
            val total = plen + 2
            if (acc.size < total) break
            val ev = ByteArray(total) { acc[it] }
            repeat(total) { acc.removeAt(0) }
            if ((ev[0].toInt() and 0xff) == 0x3e && ev.size >= 4 && (ev[2].toInt() and 0xff) == 0x02) {
                reports += parseAdvReports(ev)
            }
        }
        return reports
    }

    private fun parseAdvReports(ev: ByteArray): Int {
        var p = 3
        if (p >= ev.size) return 0
        val num = ev[p++].toInt() and 0xff
        var done = 0
        for (r in 0 until num) {
            if (p + 9 > ev.size) break
            p++
            p++
            val addr = ev.copyOfRange(p, p + 6); p += 6
            val dlen = ev[p++].toInt() and 0xff
            if (p + dlen + 1 > ev.size) break
            val data = ev.copyOfRange(p, p + dlen); p += dlen
            val rssi = ev[p++].toInt()
            val mac = (5 downTo 0).joinToString(":") { "%02X".format(addr[it].toInt() and 0xff) }
            onAdv(mac, parseName(data), rssi, data)
            done++
        }
        return done
    }

    private fun parseName(data: ByteArray): String {
        var i = 0
        while (i + 1 < data.size) {
            val len = data[i].toInt() and 0xff
            if (len == 0) break
            val type = data[i + 1].toInt() and 0xff
            if ((type == 0x08 || type == 0x09) && i + 1 + len <= data.size) {
                return String(data, i + 2, len - 1, Charsets.UTF_8)
            }
            i += len + 1
        }
        return ""
    }

    private fun setupFirmware(): Boolean {
        val devId = regRead(Mt7921Regs.BT_DEV_ID_REG)
        log("MT7921-BT: dev_id=0x%08x".format(devId))

        val gd = Mt7921Regs.FW_ROM_PATCH_HEADER_SIZE
        val sectionNum = le32(btFw, gd + 12)
        log("MT7921-BT: fw ${btFw.size}B sections=$sectionNum")

        for (i in 0 until sectionNum) {
            val mapBase = gd + Mt7921Regs.FW_ROM_PATCH_GD_SIZE + Mt7921Regs.FW_ROM_PATCH_SEC_MAP_SIZE * i
            val secOffset = le32(btFw, mapBase + 4)
            var dlSize = le32(btFw, mapBase + 16)
            if (dlSize <= 0) continue

            val spec = ByteArray(Mt7921Regs.SEC_MAP_NEED_SEND_SIZE + 1)
            spec[0] = 0
            System.arraycopy(btFw, mapBase + Mt7921Regs.SEC_MAP_COMMON_SIZE, spec, 1, Mt7921Regs.SEC_MAP_NEED_SEND_SIZE)

            var retry = 20
            var skip = false
            while (retry > 0) {
                val flag = wmtSync(Mt7921Regs.WMT_PATCH_DWNLD, 0, spec) ?: return false
                val status = when (flag) {
                    2 -> Mt7921Regs.WMT_PATCH_DONE
                    1 -> Mt7921Regs.WMT_PATCH_PROGRESS
                    else -> Mt7921Regs.WMT_PATCH_UNDONE
                }
                if (status == Mt7921Regs.WMT_PATCH_UNDONE) break
                if (status == Mt7921Regs.WMT_PATCH_DONE) { skip = true; break }
                sleep(100)
                retry--
            }
            if (retry == 0) return false
            if (skip) continue

            var ptr = secOffset
            var remaining = dlSize
            var first = true
            while (remaining > 0) {
                val dlen = minOf(Mt7921Regs.WMT_DL_CHUNK, remaining)
                val flag = if (first) 1 else if (remaining - dlen <= 0) 3 else 2
                first = false
                val chunk = btFw.copyOfRange(ptr, ptr + dlen)
                val evtFlag = wmtSync(Mt7921Regs.WMT_PATCH_DWNLD, flag, chunk) ?: return false
                if (evtFlag == 1) return false
                ptr += dlen
                remaining -= dlen
            }
        }
        sleep(120)

        uhwRegWrite(Mt7921Regs.BT_EP_RST_OPT_REG, Mt7921Regs.BT_EP_RST_IN_OUT)

        val on = wmtSync(Mt7921Regs.WMT_FUNC_CTRL, 0, byteArrayOf(1))
        if (on == null) return false
        log("MT7921-BT: func ctrl on flag=$on")
        return true
    }

    private fun wmtSync(op: Int, flag: Int, data: ByteArray): Int? {
        val wc = ByteArray(5 + data.size)
        wc[0] = 1
        wc[1] = op.toByte()
        val dlen = data.size + 1
        wc[2] = (dlen and 0xff).toByte()
        wc[3] = ((dlen ushr 8) and 0xff).toByte()
        wc[4] = flag.toByte()
        System.arraycopy(data, 0, wc, 5, data.size)
        hciCommand(Mt7921Regs.WMT_OPCODE, wc)
        val ev = wmtEvent(2000) ?: return null
        if (ev.size < 7 || (ev[0].toInt() and 0xff) != Mt7921Regs.HCI_EV_WMT) return null
        if ((ev[3].toInt() and 0xff) != op) return null
        return ev[6].toInt() and 0xff
    }

    private fun wmtEvent(timeoutMs: Int): ByteArray? {
        val buf = ByteArray(64)
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline && !stop) {
            val n = conn.controlTransfer(
                Mt7921Regs.BT_WMT_EVT_TYPE, Mt7921Regs.BT_WMT_EVT_REQ,
                Mt7921Regs.BT_WMT_EVT_VALUE, 0, buf, buf.size, 500,
            )
            if (n > 0) return buf.copyOf(n)
            sleep(1)
        }
        return null
    }

    private fun regRead(reg: Int): Long {
        val buf = ByteArray(4)
        val n = conn.controlTransfer(
            Mt7921Regs.BT_REG_READ_TYPE, Mt7921Regs.BT_REG_READ_REQ,
            (reg ushr 16) and 0xffff, reg and 0xffff, buf, 4, 1000,
        )
        if (n < 4) return 0
        return le32(buf, 0).toLong() and 0xffffffffL
    }

    private fun uhwRegWrite(reg: Int, value: Int) {
        val buf = byteArrayOf(
            (value and 0xff).toByte(),
            ((value ushr 8) and 0xff).toByte(),
            ((value ushr 16) and 0xff).toByte(),
            ((value ushr 24) and 0xff).toByte(),
        )
        conn.controlTransfer(
            Mt7921Regs.BT_UHW_WRITE_TYPE, Mt7921Regs.BT_UHW_WRITE_REQ,
            (reg ushr 16) and 0xffff, reg and 0xffff, buf, 4, 1000,
        )
    }

    private fun hciCommand(opcode: Int, params: ByteArray) {
        val pkt = ByteArray(3 + params.size)
        pkt[0] = (opcode and 0xff).toByte()
        pkt[1] = (opcode ushr 8).toByte()
        pkt[2] = params.size.toByte()
        System.arraycopy(params, 0, pkt, 3, params.size)
        conn.controlTransfer(
            Mt7921Regs.BT_HCI_CMD_TYPE, Mt7921Regs.BT_HCI_CMD_REQ, 0x00, ifaceNum, pkt, pkt.size, 1000,
        )
    }

    private fun readEvent(ep: UsbEndpoint, timeoutMs: Int): ByteArray? {
        val buf = ByteArray(260)
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline && !stop) {
            val n = conn.bulkTransfer(ep, buf, buf.size, 300)
            if (n > 0) return buf.copyOf(n)
        }
        return null
    }

    private fun clearHalt(epAddr: Int) {
        conn.controlTransfer(0x02, 0x01, 0x00, epAddr, null, 0, 1000)
    }

    private fun le32(b: ByteArray, off: Int): Int =
        (b[off].toInt() and 0xff) or
            ((b[off + 1].toInt() and 0xff) shl 8) or
            ((b[off + 2].toInt() and 0xff) shl 16) or
            ((b[off + 3].toInt() and 0xff) shl 24)
}

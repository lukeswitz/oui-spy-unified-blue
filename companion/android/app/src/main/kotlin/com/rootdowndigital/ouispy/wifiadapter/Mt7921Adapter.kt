package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.le32
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.putLe32
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.sleep

internal class Mt7921Adapter(
    private val conn: UsbDeviceConnection,
    private val intf: UsbInterface,
    private val patchFw: ByteArray,
    private val ramFw: ByteArray,
    private val log: (String) -> Unit,
) {
    @Volatile private var stop = false
    private lateinit var epRx: UsbEndpoint
    private lateinit var epCmdOut: UsbEndpoint
    private var epCmdResp: UsbEndpoint? = null
    private var epFw: UsbEndpoint? = null
    private val inEps = ArrayList<UsbEndpoint>()
    private val rd4 = ByteArray(4)
    private var seq = 0

    fun abort() { stop = true }

    fun run(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        conn.claimInterface(intf, true)
        if (!findEndpoints()) throw IllegalStateException("MT7921: bulk endpoints not found")
        clearHalt(epCmdOut.address)
        clearHalt(epRx.address)
        epCmdResp?.let { clearHalt(it.address) }
        log("MT7921: eps rx=0x%02x out=0x%02x resp=0x%02x".format(epRx.address, epCmdOut.address, epCmdResp?.address ?: -1))

        val chipId = regRead(Mt7921Regs.HW_CHIPID) and 0xffff
        log("MT7921: chip id 0x%04x".format(chipId))
        if (chipId == 0x7961) {
            wfsysReset()
            powerOn()
            dmaInit()
            loadFirmware()
            log("MT7921: firmware downloaded")
            monitorRx(onBatch)
        } else {
            log("MT7921: firmware already loaded - unplug/replug the adapter for a fresh monitor session")
            while (!stop) sleep(1000)
        }
    }

    private fun monitorRx(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        clearHalt(epCmdOut.address)
        val nic = mcuCmd(Mt7921Regs.MCU_CE_GET_NIC_CAPAB, ByteArray(0), true, setQuery = Mt7921Regs.MCU_Q_SET)
        log("MT7921: nic-capab resp=%d".format(nic?.size ?: -1))

        val ci = ByteArray(76)
        ci[0] = 6
        ci[1] = 6
        ci[3] = 1
        ci[4] = 1
        val cr = mcuCmd(Mt7921Regs.MCU_EXT_CID, ci, true, extCid = Mt7921Regs.MCU_EXT_CHANNEL_SWITCH, setQuery = Mt7921Regs.MCU_Q_SET)
        log("MT7921: set-chan6 resp=%d".format(cr?.size ?: -1))

        val rf = ByteArray(68)
        rf[4] = 1
        putLe32(rf, 8, Mt7921Regs.FILTER_MONITOR)
        mcuCmd(Mt7921Regs.MCU_CE_SET_RX_FILTER, rf, false, setQuery = Mt7921Regs.MCU_Q_SET)
        log("MT7921: rxfilter sent, listening on 0x%02x".format(epRx.address))

        val buf = ByteArray(8192)
        var frames = 0
        var lastBeat = System.currentTimeMillis()
        while (!stop) {
            val n = conn.bulkTransfer(epRx, buf, buf.size, 500)
            val now = System.currentTimeMillis()
            if (now - lastBeat > 5000) {
                log("MT7921: listening, %d frames so far".format(frames))
                lastBeat = now
            }
            if (n <= 0) continue
            frames++
            if (frames <= 12) {
                val sb = StringBuilder()
                for (i in 0 until minOf(n, 64)) sb.append("%02x".format(buf[i].toInt() and 0xff))
                log("MT7921: rx #%d len=%d %s".format(frames, n, sb))
            }
        }
    }

    private fun findEndpoints(): Boolean {
        val bulkIn = ArrayList<UsbEndpoint>()
        val bulkOut = ArrayList<UsbEndpoint>()
        for (i in 0 until intf.endpointCount) {
            val ep = intf.getEndpoint(i)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                if (ep.direction == UsbConstants.USB_DIR_IN) bulkIn.add(ep) else bulkOut.add(ep)
            }
        }
        if (bulkIn.isEmpty() || bulkOut.isEmpty()) return false
        epRx = bulkIn[0]
        epCmdResp = bulkIn.getOrNull(1)
        epCmdOut = bulkOut[0]
        epFw = bulkOut.getOrNull(1)
        inEps.clear()
        inEps.addAll(bulkIn)
        return true
    }

    private fun regRead(addr: Int): Int =
        conn.controlTransfer(Mt7921Regs.DIR_IN, Mt7921Regs.VEND_READ_EXT,
            (addr ushr 16) and 0xffff, addr and 0xffff, rd4, 4, 1000)
            .let { if (it == 4) le32(rd4) else 0 }

    private fun regWrite(addr: Int, value: Int) =
        conn.controlTransfer(Mt7921Regs.DIR_OUT, Mt7921Regs.VEND_WRITE_EXT,
            (addr ushr 16) and 0xffff, addr and 0xffff, le4(value), 4, 1000)

    private fun regSet(addr: Int, bits: Int) = regWrite(addr, regRead(addr) or bits)
    private fun regClear(addr: Int, bits: Int) = regWrite(addr, regRead(addr) and bits.inv())
    private fun regRmw(addr: Int, mask: Int, bits: Int) = regWrite(addr, (regRead(addr) and mask.inv()) or bits)

    private fun uhwRead(addr: Int): Int =
        conn.controlTransfer(Mt7921Regs.UHW_DIR_IN, Mt7921Regs.VEND_DEV_MODE,
            (addr ushr 16) and 0xffff, addr and 0xffff, rd4, 4, 1000)
            .let { if (it == 4) le32(rd4) else 0 }

    private fun uhwWrite(addr: Int, value: Int) =
        conn.controlTransfer(Mt7921Regs.UHW_DIR_OUT, Mt7921Regs.VEND_WRITE,
            (addr ushr 16) and 0xffff, addr and 0xffff, le4(value), 4, 1000)

    private fun pollReg(addr: Int, mask: Int, want: Int, ms: Int): Boolean {
        val end = System.currentTimeMillis() + ms
        do {
            if ((regRead(addr) and mask) == want) return true
            sleep(5)
        } while (System.currentTimeMillis() < end)
        return false
    }

    private fun powerOn() {
        conn.controlTransfer(Mt7921Regs.DIR_OUT, Mt7921Regs.VEND_POWER_ON, 0x0, 0x1, null, 0, 1000)
        if (pollReg(Mt7921Regs.CONN_ON_MISC, Mt7921Regs.FW_PWR_ON, Mt7921Regs.FW_PWR_ON, 500)) {
            log("MT7921: power-on OK")
        } else {
            log("MT7921: power-on poll timeout (MT_CONN_ON_MISC)")
        }
    }

    private fun wfsysReset() {
        regSet(Mt7921Regs.UDMA_WLCFG_0, Mt7921Regs.WL_RX_FLUSH)
        pollReg(Mt7921Regs.UDMA_WLCFG_0, Mt7921Regs.WL_RX_BUSY or Mt7921Regs.WL_TX_BUSY, 0, 1000)
        uhwWrite(Mt7921Regs.SSUSB_EP_RST_OPT,
            uhwRead(Mt7921Regs.SSUSB_EP_RST_OPT) and Mt7921Regs.EP_RST_OPT_CLR.inv())
        uhwWrite(Mt7921Regs.CBTOP_WF_SUBSYS_RST,
            uhwRead(Mt7921Regs.CBTOP_WF_SUBSYS_RST) or Mt7921Regs.WF_WHOLE_PATH)
        sleep(1)
        uhwWrite(Mt7921Regs.CBTOP_WF_SUBSYS_RST,
            uhwRead(Mt7921Regs.CBTOP_WF_SUBSYS_RST) and Mt7921Regs.WF_WHOLE_PATH.inv())
        uhwWrite(Mt7921Regs.UDMA_CONN_INFRA_STATUS_SEL, 0)
        var ok = false
        for (i in 0 until 25) {
            if ((uhwRead(Mt7921Regs.UDMA_CONN_INFRA_STATUS) and Mt7921Regs.WFSYS_INIT_DONE) == Mt7921Regs.WFSYS_INIT_DONE) {
                ok = true
                break
            }
            sleep(100)
        }
        log(if (ok) "MT7921: wfsys reset done" else "MT7921: wfsys init-done timeout (continuing)")
    }

    private fun dmaInit() {
        val prefetch = intArrayOf(0, 1, 2, 3, 4, 16, 17)
        val base = intArrayOf(0x080, 0x0c0, 0x100, 0x140, 0x180, 0x280, 0x2c0)
        for (i in prefetch.indices) {
            val reg = Mt7921Regs.UWFDMA0_TX_RING_EXT_CTRL_BASE + (prefetch[i] shl 2)
            regRmw(reg, Mt7921Regs.WPDMA0_MAX_CNT_MASK or Mt7921Regs.WPDMA0_BASE_PTR_MASK, 4 or (base[i] shl 16))
        }
        regClear(Mt7921Regs.UWFDMA0_GLO_CFG, Mt7921Regs.GLO_OMIT_RX_INFO)
        regSet(Mt7921Regs.UWFDMA0_GLO_CFG,
            Mt7921Regs.GLO_OMIT_TX_INFO or Mt7921Regs.GLO_OMIT_RX_INFO_PFET2 or
                Mt7921Regs.GLO_FW_DWLD_BYPASS_DMASHDL or Mt7921Regs.GLO_TX_DMA_EN or Mt7921Regs.GLO_RX_DMA_EN)
        regRmw(Mt7921Regs.DMASHDL_REFILL, Mt7921Regs.DMASHDL_REFILL_MASK, 0xffe00000.toInt())
        regClear(Mt7921Regs.DMASHDL_PAGE, Mt7921Regs.DMASHDL_GROUP_SEQ_ORDER)
        regRmw(Mt7921Regs.DMASHDL_PKT_MAX_SIZE, Mt7921Regs.DMASHDL_PKT_MAX_SIZE_MASK, 1)
        for (i in 0 until 5) regWrite(Mt7921Regs.DMASHDL_GROUP_QUOTA_BASE + (i shl 2), 0x0fff0003)
        for (i in 5 until 16) regWrite(Mt7921Regs.DMASHDL_GROUP_QUOTA_BASE + (i shl 2), 0)
        regWrite(Mt7921Regs.DMASHDL_Q_MAP_BASE + 0, 0x32013201)
        regWrite(Mt7921Regs.DMASHDL_Q_MAP_BASE + 4, 0x32013201)
        regWrite(Mt7921Regs.DMASHDL_Q_MAP_BASE + 8, 0x55555444)
        regWrite(Mt7921Regs.DMASHDL_Q_MAP_BASE + 12, 0x55555444)
        regWrite(Mt7921Regs.DMASHDL_SCHED_SET_BASE + 0, 0x76540132)
        regWrite(Mt7921Regs.DMASHDL_SCHED_SET_BASE + 4, 0xFEDCBA98.toInt())
        regSet(Mt7921Regs.WFDMA_DUMMY_CR, Mt7921Regs.WFDMA_NEED_REINIT)

        regClear(Mt7921Regs.UDMA_WLCFG_0, Mt7921Regs.WL_RX_FLUSH)
        regSet(Mt7921Regs.UDMA_WLCFG_0,
            Mt7921Regs.WL_RX_EN or Mt7921Regs.WL_TX_EN or Mt7921Regs.WL_RX_MPSZ_PAD0 or Mt7921Regs.TICK_1US_EN)
        regRmw(Mt7921Regs.UDMA_WLCFG_1, Mt7921Regs.WL_TX_TMOUT_LMT, 50000 shl 8)
        regSet(Mt7921Regs.UDMA_WLCFG_0, Mt7921Regs.WL_TX_TMOUT_FUNC_EN)
        regClear(Mt7921Regs.UDMA_WLCFG_0, Mt7921Regs.WL_RX_AGG_TO or Mt7921Regs.WL_RX_AGG_LMT)
        regClear(Mt7921Regs.UDMA_WLCFG_1, Mt7921Regs.WL_RX_AGG_PKT_LMT)

        pollReg(Mt7921Regs.UWFDMA0_GLO_CFG, Mt7921Regs.GLO_RX_DMA_BUSY, 0, 1000)
        regClear(Mt7921Regs.UWFDMA0_GLO_CFG, Mt7921Regs.GLO_RX_DMA_EN)
        regSet(Mt7921Regs.WFDMA_HOST_CONFIG, Mt7921Regs.WFDMA_HOST_CONFIG_USB_RXEVT_EP4_EN)
        regSet(Mt7921Regs.UWFDMA0_GLO_CFG, Mt7921Regs.GLO_RX_DMA_EN)
        uhwWrite(Mt7921Regs.SSUSB_EP_RST_OPT,
            uhwRead(Mt7921Regs.SSUSB_EP_RST_OPT) and Mt7921Regs.EP_RST_OPT_CLR.inv())
        log("MT7921: dma init done")
    }

    private fun loadFirmware() {
        mcuCmd(Mt7921Regs.MCU_NIC_POWER_CTRL, byteArrayOf(1, 0, 0, 0), false)
        pollReg(Mt7921Regs.CONN_ON_MISC, Mt7921Regs.FW_STATE_MASK, Mt7921Regs.FW_PWR_ON, 1000)
        loadPatch()
        log("MT7921: rom patch loaded")
        loadRam()
        log("MT7921: ram code sent, starting firmware")
    }

    private fun loadPatch() {
        mcuCmd(Mt7921Regs.MCU_PATCH_SEM, le4(1), true)
        val nRegion = be32(patchFw, 44)
        log("MT7921: patch n_region=%d size=%d".format(nRegion, patchFw.size))
        if (nRegion < 0 || nRegion > 16) throw IllegalStateException("MT7921: bad patch n_region=$nRegion")
        for (i in 0 until nRegion) {
            val sec = 96 + i * 64
            val addr = be32(patchFw, sec + 12)
            val len = be32(patchFw, sec + 16)
            val dataOff = be32(patchFw, sec + 4)
            initDownload(addr, len, Mt7921Regs.DL_MODE_NEED_RSP)
            sendFirmware(patchFw, dataOff, len)
        }
        mcuCmd(Mt7921Regs.MCU_PATCH_FINISH, byteArrayOf(0, 0, 0, 0), true)
        mcuCmd(Mt7921Regs.MCU_PATCH_SEM, le4(0), true)
    }

    private fun loadRam() {
        val trailer = ramFw.size - 36
        val nRegion = ramFw[trailer + 2].toInt() and 0xff
        log("MT7921: ram n_region=%d size=%d".format(nRegion, ramFw.size))
        if (nRegion == 0 || nRegion > 16) throw IllegalStateException("MT7921: bad ram n_region=$nRegion")
        var offset = 0
        var override = 0
        for (i in 0 until nRegion) {
            val reg = trailer - (nRegion - i) * 40
            val addr = le32(ramFw, reg + 16)
            val len = le32(ramFw, reg + 20)
            val feature = ramFw[reg + 24].toInt() and 0xff
            if (feature and Mt7921Regs.FW_FEATURE_NON_DL != 0) {
                offset += len
                continue
            }
            if (feature and Mt7921Regs.FW_FEATURE_OVERRIDE_ADDR != 0) override = addr
            initDownload(addr, len, ramMode(feature))
            sendFirmware(ramFw, offset, len)
            offset += len
        }
        val option = if (override != 0) Mt7921Regs.FW_START_OVERRIDE else 0
        val p = ByteArray(8)
        putLe32(p, 0, option)
        putLe32(p, 4, override)
        mcuCmd(Mt7921Regs.MCU_FW_START, p, true)
    }

    private fun ramMode(feature: Int): Int {
        var m = Mt7921Regs.DL_MODE_NEED_RSP
        if (feature and Mt7921Regs.FW_FEATURE_SET_ENCRYPT != 0) {
            m = m or Mt7921Regs.DL_MODE_ENCRYPT or Mt7921Regs.DL_MODE_RESET_SEC_IV
        }
        m = m or (feature and 0x6)
        return m
    }

    private fun initDownload(addr: Int, len: Int, mode: Int) {
        val cmd = if (addr == Mt7921Regs.MCU_PATCH_ADDRESS || addr == Mt7921Regs.CONNAC2_DL_ADDR)
            Mt7921Regs.MCU_PATCH_START else Mt7921Regs.MCU_TARGET_ADDR_LEN
        val p = ByteArray(12)
        putLe32(p, 0, addr)
        putLe32(p, 4, len)
        putLe32(p, 8, mode)
        mcuCmd(cmd, p, false)
    }

    private fun sendFirmware(data: ByteArray, start: Int, len: Int) {
        val ep = epFw ?: epCmdOut
        var pos = 0
        while (pos < len) {
            val cur = minOf(Mt7921Regs.DL_CHUNK, len - pos)
            val inner = ByteArray(cur)
            System.arraycopy(data, start + pos, inner, 0, cur)
            val pkt = framePacket(inner)
            if (pos > 0) clearHalt(ep.address)
            var r = conn.bulkTransfer(ep, pkt, pkt.size, 1000)
            if (r < 0) {
                clearHalt(ep.address)
                r = conn.bulkTransfer(ep, pkt, pkt.size, 1000)
            }
            if (r < 0) throw IllegalStateException("MT7921: scatter failed +%d/%d ep=0x%02x pkt=%d".format(pos, len, ep.address, pkt.size))
            pos += cur
        }
        log("MT7921: scatter %d bytes ok via 0x%02x".format(len, ep.address))
    }

    private fun framePacket(inner: ByteArray): ByteArray {
        val len = inner.size
        val afterHdr = len + 4
        val pad = (((afterHdr + 3) and 3.inv()) + 4) - afterHdr
        val buf = ByteArray(4 + len + pad)
        putLe32(buf, 0, len and 0xffff)
        System.arraycopy(inner, 0, buf, 4, len)
        return buf
    }

    private fun mcuCmd(
        opcode: Int,
        payload: ByteArray,
        wait: Boolean,
        extCid: Int = 0,
        setQuery: Int = Mt7921Regs.MCU_Q_NA,
    ): ByteArray? {
        seq = (seq % 15) + 1
        val total = 64 + payload.size
        val inner = ByteArray(total)
        putLe32(inner, 0, (total and 0xffff) or (Mt7921Regs.TX_TYPE_CMD shl 23) or (Mt7921Regs.TX_MCU_PORT_RX_Q0 shl 25))
        putLe32(inner, 4, (1 shl 31) or (Mt7921Regs.HDR_FORMAT_CMD shl 16))
        val mcuLen = total - 32
        inner[32] = mcuLen.toByte()
        inner[33] = (mcuLen ushr 8).toByte()
        inner[34] = 0x00
        inner[35] = 0x80.toByte()
        inner[36] = opcode.toByte()
        inner[37] = Mt7921Regs.MCU_PKT_ID.toByte()
        inner[38] = setQuery.toByte()
        inner[39] = seq.toByte()
        inner[41] = extCid.toByte()
        inner[43] = if (extCid != 0) 1 else 0
        System.arraycopy(payload, 0, inner, 64, payload.size)
        val pkt = framePacket(inner)
        var out = conn.bulkTransfer(epCmdOut, pkt, pkt.size, 1000)
        if (out < 0) {
            clearHalt(epCmdOut.address)
            out = conn.bulkTransfer(epCmdOut, pkt, pkt.size, 1000)
        }
        if (wait) {
            val resp = ByteArray(1536)
            var n = -1
            val deadline = System.currentTimeMillis() + 2000
            loop@ while (System.currentTimeMillis() < deadline) {
                for (ep in inEps) {
                    val m = conn.bulkTransfer(ep, resp, resp.size, 150)
                    if (m > 0) { n = m; break@loop }
                }
            }
            val hx = if (n > 0) {
                val sb = StringBuilder()
                for (i in 0 until minOf(n, 20)) sb.append("%02x".format(resp[i].toInt() and 0xff))
                sb.toString()
            } else ""
            log("MT7921: mcu 0x%02x out=%d resp=%d %s".format(opcode, out, n, hx))
            return if (n > 0) resp.copyOf(n) else null
        }
        log("MT7921: mcu 0x%02x out=%d (no-wait)".format(opcode, out))
        return null
    }

    private fun clearHalt(epAddr: Int) =
        conn.controlTransfer(0x02, 0x01, 0x00, epAddr, null, 0, 1000)

    private fun le4(v: Int) = byteArrayOf(v.toByte(), (v ushr 8).toByte(), (v ushr 16).toByte(), (v ushr 24).toByte())

    private fun be32(b: ByteArray, i: Int): Int =
        ((b[i].toInt() and 0xff) shl 24) or ((b[i + 1].toInt() and 0xff) shl 16) or
            ((b[i + 2].toInt() and 0xff) shl 8) or (b[i + 3].toInt() and 0xff)
}

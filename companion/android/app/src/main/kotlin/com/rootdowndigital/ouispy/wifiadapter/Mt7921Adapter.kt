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
    private val CHANNELS = intArrayOf(
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
        36, 40, 44, 48, 52, 56, 60, 64,
        100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144,
        149, 153, 157, 161, 165, 169, 173, 177,
    )
    private val MAIN = setOf(1, 6, 11)
    private val MAIN_DWELL_MS = 300L
    private val SIDE_DWELL_MS = 50L
    private lateinit var epRx: UsbEndpoint
    private lateinit var epCmdOut: UsbEndpoint
    private var epCmdResp: UsbEndpoint? = null
    private var epFw: UsbEndpoint? = null
    private val rd4 = ByteArray(4)
    private var seq = 0
    private var onFrame: ((ByteArray, Int) -> Unit)? = null
    private var frameCount = 0

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
            log("MT7921: loaded — replug to re-scan")
            while (!stop) sleep(1000)
        }
    }

    private fun monitorRx(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        clearHalt(epCmdOut.address)
        val nic = mcuCmd(Mt7921Regs.MCU_CE_GET_NIC_CAPAB, ByteArray(0), true, setQuery = Mt7921Regs.MCU_Q_SET)
        setEeprom()
        log("MT7921: nic-capab resp=%d, efuse pushed".format(nic?.size ?: -1))

        setRxFilter(Mt7921Regs.FILTER_MONITOR, 0, 0)
        setRxFilter(0, Mt7921Regs.FIF_BIT_CLR, Mt7921Regs.MONITOR_DROP_CLEAR)
        setSniffer(true)

        val sights = HashMap<String, Sight>()
        onFrame = { b, m -> ingestFrame(b, m, sights) }
        var chIdx = 0
        tune(CHANNELS[0], true)
        log("MT7921: scanning %d channels (2.4 + 5 GHz)".format(CHANNELS.size))

        val buf = ByteArray(8192)
        var lastBeat = System.currentTimeMillis()
        var lastEmit = lastBeat
        var lastHop = lastBeat
        try {
            while (!stop) {
                val n = conn.bulkTransfer(epRx, buf, buf.size, 120)
                val now = System.currentTimeMillis()
                if (n > 0) ingestFrame(buf, n, sights)
                val dwell = if (CHANNELS[chIdx] in MAIN) MAIN_DWELL_MS else SIDE_DWELL_MS
                if (now - lastHop > dwell) {
                    chIdx = (chIdx + 1) % CHANNELS.size
                    tune(CHANNELS[chIdx], true)
                    lastHop = System.currentTimeMillis()
                }
                if (now - lastEmit > 2000) {
                    val batch = ArrayList<Mt7612uAdapter.ApSighting>()
                    for ((bssid, s) in sights) {
                        if (!s.emitted || Math.abs(s.rssi - s.emitRssi) >= 8) {
                            batch.add(Mt7612uAdapter.ApSighting(
                                bssid, s.ssid, s.rssi, s.channel, Mt76Regs.freqOf(s.channel), authMode = s.authMode))
                            s.emitted = true
                            s.emitRssi = s.rssi
                        }
                    }
                    sights.entries.removeAll { now - it.value.lastSeen > 180000 }
                    if (batch.isNotEmpty()) onBatch(batch)
                    lastEmit = now
                }
                if (now - lastBeat > 5000) {
                    log("MT7921: ch%d, %d frames, %d APs".format(CHANNELS[chIdx], frameCount, sights.size))
                    lastBeat = now
                }
            }
        } finally {
            onFrame = null
        }
    }

    private fun ingestFrame(b: ByteArray, n: Int, sights: HashMap<String, Sight>) {
        val rx = decodeRx(b, n) ?: return
        val f = rx.frame
        if (f.size < 22) return
        val fc = (f[0].toInt() and 0xff) or ((f[1].toInt() and 0xff) shl 8)
        val ftype = (fc ushr 2) and 0x3
        val subtype = (fc ushr 4) and 0xf
        if (ftype != 0 || (subtype != 8 && subtype != 5)) return
        frameCount++
        val bssid = macOf(f, 16)
        val ssid = if (f.size > 36) parseSsid(f, 36) else null
        val isNew = !sights.containsKey(bssid)
        val s = sights.getOrPut(bssid) { Sight() }
        if (!ssid.isNullOrEmpty()) s.ssid = ssid
        else if (s.ssid == null) s.ssid = "(hidden)"
        s.rssi = rx.rssi
        s.channel = rx.channel
        s.authMode = parseSecurity(f)
        s.lastSeen = System.currentTimeMillis()
        if (isNew) log("MT7921: +AP #%d ch%d rssi%d auth%d".format(sights.size, rx.channel, rx.rssi, s.authMode))
    }

    private fun tune(ch: Int, wait: Boolean) {
        val chanBand = if (ch <= 14) 0 else 1
        val sniffBand = if (ch <= 14) 1 else 2
        setChanInfo(ch, ch, 0, chanBand, wait)
        configSniffer(ch, sniffBand, wait)
    }

    private fun setEeprom() =
        mcuCmd(Mt7921Regs.MCU_EXT_CID, byteArrayOf(0, 1, 0, 0), true,
            extCid = Mt7921Regs.MCU_EXT_EFUSE_BUFFER_MODE, setQuery = Mt7921Regs.MCU_Q_SET)

    private fun setRxFilter(fif: Int, bitOp: Int, bitMap: Int) {
        val d = ByteArray(68)
        d[4] = if (fif != 0) 1 else 2
        putLe32(d, 8, fif)
        putLe32(d, 12, bitMap)
        d[16] = bitOp.toByte()
        mcuCmd(Mt7921Regs.MCU_CE_SET_RX_FILTER, d, false, setQuery = Mt7921Regs.MCU_Q_SET)
    }

    private fun setChanInfo(controlCh: Int, centerCh: Int, bw: Int, band: Int, wait: Boolean = true) {
        val d = ByteArray(76)
        d[0] = controlCh.toByte()
        d[1] = centerCh.toByte()
        d[2] = bw.toByte()
        d[3] = 2
        d[4] = 2
        d[10] = band.toByte()
        mcuCmd(Mt7921Regs.MCU_EXT_CID, d, wait,
            extCid = Mt7921Regs.MCU_EXT_CHANNEL_SWITCH, setQuery = Mt7921Regs.MCU_Q_SET)
    }

    private fun setSniffer(enable: Boolean) {
        val d = ByteArray(12)
        d[6] = 8
        d[8] = if (enable) 1 else 0
        mcuUni(Mt7921Regs.MCU_UNI_SNIFFER, d)
    }

    private fun configSniffer(ch: Int, band: Int, wait: Boolean = true) {
        val d = ByteArray(20)
        d[4] = 1
        d[6] = 16
        d[10] = band.toByte()
        d[12] = ch.toByte()
        d[14] = ch.toByte()
        d[16] = 1
        mcuUni(Mt7921Regs.MCU_UNI_SNIFFER, d, wait)
    }

    private class Sight(var ssid: String? = null, var rssi: Int = 0, var channel: Int = 0, var lastSeen: Long = 0, var authMode: Int = 0, var emitted: Boolean = false, var emitRssi: Int = 0)

    private class Rx(val frame: ByteArray, val channel: Int, val rssi: Int)

    private fun decodeRx(buf: ByteArray, n: Int): Rx? {
        if (n < 24) return null
        val rxd0 = le32(buf, 0)
        val rxd1 = le32(buf, 4)
        val rxd2 = le32(buf, 8)
        val rxd3 = le32(buf, 12)
        var ptype = (rxd0 ushr 27) and 0x1f
        if (ptype == 7 && ((rxd0 ushr 16) and 0xf) == 1) ptype = 17
        if (ptype != 2 && ptype != 17) return null
        if (rxd2 and ((1 shl 23) or (1 shl 24)) != 0) return null
        val dmaLen = rxd0 and 0xffff
        val channel = (rxd3 ushr 8) and 0xff
        val removePad = (rxd2 ushr 14) and 0x3
        var off = 24
        var g3v1: Int? = null
        var g5: Int? = null
        if (rxd1 and (1 shl 14) != 0) { if (off + 16 > n) return null; off += 16 }
        if (rxd1 and (1 shl 11) != 0) off += 16
        if (rxd1 and (1 shl 12) != 0) off += 8
        if (rxd1 and (1 shl 13) != 0) {
            if (off + 8 <= n) g3v1 = le32(buf, off + 4)
            off += 8
            if (rxd1 and (1 shl 15) != 0) {
                off += 24
                if (off + 4 <= n) g5 = le32(buf, off)
                off += 48
            }
        }
        var rssi = 0
        val rcpi = g5 ?: g3v1
        if (rcpi != null) {
            var best: Int? = null
            for (s in intArrayOf(0, 8, 16, 24)) {
                val v = Math.floorDiv(((rcpi ushr s) and 0xff) - 220, 2)
                if (v < 0 && (best == null || v > best)) best = v
            }
            rssi = best ?: 0
        }
        val hdrGap = off + 2 * removePad
        val end = if (dmaLen != 0) minOf(dmaLen, n) else n
        if (hdrGap >= end) return null
        return Rx(buf.copyOfRange(hdrGap, end), channel, rssi)
    }

    private fun parseSecurity(f: ByteArray): Int {
        if (f.size < 36) return 0
        val cap = (f[34].toInt() and 0xff) or ((f[35].toInt() and 0xff) shl 8)
        val privacy = (cap and 0x10) != 0
        var hasRsn = false
        var hasWpa = false
        var sae = false
        var eap = false
        var i = 36
        while (i + 2 <= f.size) {
            val eid = f[i].toInt() and 0xff
            val len = f[i + 1].toInt() and 0xff
            val p = i + 2
            if (p + len > f.size) break
            if (eid == 48 && len >= 8) {
                hasRsn = true
                var o = p + 6
                if (o + 2 <= p + len) {
                    val pw = (f[o].toInt() and 0xff) or ((f[o + 1].toInt() and 0xff) shl 8)
                    o += 2 + 4 * pw
                    if (o + 2 <= p + len) {
                        val akm = (f[o].toInt() and 0xff) or ((f[o + 1].toInt() and 0xff) shl 8)
                        o += 2
                        var k = 0
                        while (k < akm && o + 4 <= p + len) {
                            when (f[o + 3].toInt() and 0xff) {
                                8, 9 -> sae = true
                                1, 3, 5, 11, 13 -> eap = true
                            }
                            o += 4; k++
                        }
                    }
                }
            } else if (eid == 221 && len >= 4) {
                if ((f[p].toInt() and 0xff) == 0x00 && (f[p + 1].toInt() and 0xff) == 0x50 &&
                    (f[p + 2].toInt() and 0xff) == 0xf2 && (f[p + 3].toInt() and 0xff) == 0x01) hasWpa = true
            }
            i += 2 + len
        }
        return when {
            sae -> 6
            hasRsn && eap -> 5
            hasRsn && hasWpa -> 4
            hasRsn -> 3
            hasWpa -> 2
            privacy -> 1
            else -> 0
        }
    }

    private fun parseSsid(f: ByteArray, start: Int): String? {
        var i = start
        while (i + 2 <= f.size) {
            val eid = f[i].toInt() and 0xff
            val len = f[i + 1].toInt() and 0xff
            if (i + 2 + len > f.size) break
            if (eid == 0) return if (len == 0) "" else String(f, i + 2, len, Charsets.UTF_8)
            i += 2 + len
        }
        return null
    }

    private fun macOf(f: ByteArray, o: Int): String =
        (0 until 6).joinToString(":") { "%02x".format(f[o + it].toInt() and 0xff) }

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
        regWrite(Mt7921Regs.SWDEF_MODE, 0)
        regSet(Mt7921Regs.UDMA_TX_QSEL, Mt7921Regs.FW_DL_EN)
        mcuCmd(Mt7921Regs.MCU_NIC_POWER_CTRL, byteArrayOf(1, 0, 0, 0), false)
        pollReg(Mt7921Regs.CONN_ON_MISC, Mt7921Regs.FW_STATE_MASK, Mt7921Regs.FW_PWR_ON, 1000)
        loadPatch()
        log("MT7921: rom patch loaded")
        loadRam()
        regClear(Mt7921Regs.UDMA_TX_QSEL, Mt7921Regs.FW_DL_EN)
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
        mcuCmd(cmd, p, true)
    }

    private fun sendFirmware(data: ByteArray, start: Int, len: Int) {
        val ep = epFw ?: epCmdOut
        clearHalt(ep.address)
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
        return if (wait) mcuWait(seq) else null
    }

    private fun mcuWait(seq: Int, timeoutMs: Int = 4000): ByteArray? {
        val deadline = System.currentTimeMillis() + timeoutMs
        val buf = ByteArray(4096)
        var seen = 0
        var lastType = -1
        var lastSeq = -1
        while (System.currentTimeMillis() < deadline && !stop) {
            val n = conn.bulkTransfer(epRx, buf, buf.size, 250)
            if (n < 4) continue
            seen++
            val rxd0 = le32(buf, 0)
            val pktType = (rxd0 ushr 27) and 0x1f
            val pktFlag = (rxd0 ushr 16) and 0xf
            lastType = pktType
            if (n >= 30) lastSeq = buf[29].toInt() and 0xff
            val isFrame = pktType == 2 || (pktType == 7 && pktFlag == 1)
            if (isFrame) { onFrame?.invoke(buf, n); continue }
            if (pktType == 7 && n >= 36 && (buf[29].toInt() and 0xff) == seq) return buf.copyOf(n)
        }
        log("MT7921: mcuWait seq=%d TIMEOUT seen=%d type=%d seq=%d".format(seq, seen, lastType, lastSeq))
        return null
    }

    private fun mcuUni(cid: Int, payload: ByteArray, wait: Boolean = true): ByteArray? {
        seq = (seq % 15) + 1
        val total = 48 + payload.size
        val inner = ByteArray(total)
        putLe32(inner, 0, (total and 0xffff) or (Mt7921Regs.TX_TYPE_CMD shl 23) or (Mt7921Regs.TX_MCU_PORT_RX_Q0 shl 25))
        putLe32(inner, 4, (1 shl 31) or (Mt7921Regs.HDR_FORMAT_CMD shl 16))
        val uniLen = total - 32
        inner[32] = uniLen.toByte()
        inner[33] = (uniLen ushr 8).toByte()
        inner[34] = cid.toByte()
        inner[35] = (cid ushr 8).toByte()
        inner[37] = Mt7921Regs.MCU_PKT_ID.toByte()
        inner[39] = seq.toByte()
        inner[42] = 0
        inner[43] = 0x07
        System.arraycopy(payload, 0, inner, 48, payload.size)
        val pkt = framePacket(inner)
        var out = conn.bulkTransfer(epCmdOut, pkt, pkt.size, 1000)
        if (out < 0) { clearHalt(epCmdOut.address); out = conn.bulkTransfer(epCmdOut, pkt, pkt.size, 1000) }
        return if (wait) mcuWait(seq) else null
    }

    private fun clearHalt(epAddr: Int) =
        conn.controlTransfer(0x02, 0x01, 0x00, epAddr, null, 0, 1000)

    private fun le4(v: Int) = byteArrayOf(v.toByte(), (v ushr 8).toByte(), (v ushr 16).toByte(), (v ushr 24).toByte())

    private fun be32(b: ByteArray, i: Int): Int =
        ((b[i].toInt() and 0xff) shl 24) or ((b[i + 1].toInt() and 0xff) shl 16) or
            ((b[i + 2].toInt() and 0xff) shl 8) or (b[i + 3].toInt() and 0xff)
}

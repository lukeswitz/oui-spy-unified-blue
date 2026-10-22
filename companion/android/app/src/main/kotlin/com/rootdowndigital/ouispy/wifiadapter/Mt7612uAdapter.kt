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
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.putLe32
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.sleep

// Passive MT7612U monitor receiver (Alfa AWUS036ACM, Netgear A6210): receive only, never transmits.
internal class Mt7612uAdapter(
    private val conn: UsbDeviceConnection,
    private val intf: UsbInterface,
    private val fw: FirmwareStore.Blobs,
    private val log: (String) -> Unit,
    private val phoneChannels: () -> Set<Int> = { emptySet() },
) {
    data class ApSighting(
        val bssid: String,
        val ssid: String?,
        val rssi: Int,
        val channel: Int,
        val frequency: Int,
        val client: Boolean = false,
        val authMode: Int = 0,
    )

    @Volatile private var stop = false
    private val captureClients = true
    private val io = UsbIo(conn)
    private lateinit var epRx: UsbEndpoint
    private lateinit var epCmdOut: UsbEndpoint
    private var epCmdResp: UsbEndpoint? = null
    private var seq = 0
    private var mcuLogged = 0
    private var mcuGain = 0
    private var rssiOff2g = 0
    private var rssiOff5g = 0
    private var lna2g = 0
    private var lna5g = 0

    fun abort() { stop = true }

    fun run(onBatch: (List<ApSighting>) -> Unit) {
        conn.claimInterface(intf, true)
        if (!findEndpoints()) throw IllegalStateException("MT7612U: bulk endpoints not found")

        io.clearHalt(epCmdOut.address)
        io.clearHalt(epRx.address)
        resetWlan()
        powerOn()
        if (!waitForMac()) {
            throw IllegalStateException("MT7612U: MAC not ready after power-on")
        }
        uploadRomPatch()
        uploadFirmware()
        log("MT7612U: firmware running")
        io.pollReg(Mt76Regs.WPDMA_GLO_CFG, Mt76Regs.WPDMA_TX_BUSY or Mt76Regs.WPDMA_RX_BUSY, 0, 100)
        if (!waitForMac()) {
            throw IllegalStateException("MT7612U: MAC not ready after firmware load")
        }
        initDma()
        mcuCmd(Mt76Regs.CMD_FUN_SET_OP, le32words(Mt76Regs.Q_SELECT, 1), false)
        mcuCmd(Mt76Regs.CMD_POWER_SAVING_OP, le32words(Mt76Regs.RADIO_ON, 0), false)
        macReset()
        val eeprom = readEeprom()
        computeGainAndRssi(eeprom)
        fixupXtal(eeprom)
        io.regRmw(Mt76Regs.US_CYC_CFG, 0xff, 0x1e)
        io.regWrite(Mt76Regs.TXOP_CTRL_CFG, 0x583f)
        loadCr(eeprom, Mt76Regs.CHANNELS[0])
        setRxPath()
        tuneChannel(Mt76Regs.CHANNELS[0], scan = false)
        io.regWrite(Mt76Regs.RX_FILTR_CFG, Mt76Regs.FILTR_CRC_ERR or Mt76Regs.FILTR_PHY_ERR)
        macStart()
        log("MT7612U: receiver live")
        rxLoop(onBatch)
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
        val rx = bulkIn.getOrNull(0) ?: return false
        val cmd = bulkOut.getOrNull(0) ?: return false
        epRx = rx
        epCmdResp = bulkIn.getOrNull(1)
        epCmdOut = cmd
        log("MT7612U: eps IN=[${bulkIn.joinToString { "0x%02x".format(it.address) }}] OUT=[${bulkOut.joinToString { "0x%02x".format(it.address) }}] maxIn=${rx.maxPacketSize}")
        return true
    }

    private fun uploadRomPatch() {
        val patch = fw.romPatch
        io.cfgWrite(Mt76Regs.USB_U3DMA_CFG, Mt76Regs.USB_DMA_CFG_UPLOAD)
        io.devMode(Mt76Regs.DIR_OUT, 0x1, null)
        sleep(8)
        configureFce()
        fceSend(patch, Mt76Regs.PATCH_HDR_LEN, patch.size - Mt76Regs.PATCH_HDR_LEN,
            Mt76Regs.ROM_PATCH_MAX_PAYLOAD, Mt76Regs.ROM_PATCH_OFFSET)
        io.devMode(Mt76Regs.TYPE_CLASS_OUT, 0x12,
            byteArrayOf(0x6f, 0xfc.toByte(), 0x08, 0x01, 0x20, 0x04, 0x00, 0x00, 0x00, 0x09, 0x00))
        io.devMode(Mt76Regs.TYPE_CLASS_OUT, 0x12,
            byteArrayOf(0x6f, 0xfc.toByte(), 0x05, 0x01, 0x07, 0x01, 0x00, 0x04))
        sleep(20)
        val e3 = (io.regRead(Mt76Regs.ASIC_VERSION) and 0xffff) >= Mt76Regs.REV_E3
        val reg = if (e3) Mt76Regs.MCU_CLOCK_CTL else Mt76Regs.MCU_COM_REG0
        val mask = if (e3) 0x1 else 0x2
        if (!io.pollReg(reg, mask, mask, 100)) log("MT7612U: ROM patch poll failed (reg=0x${reg.toString(16)})")
    }

    private fun uploadFirmware() {
        val f = fw.firmware
        val ilmLen = le32(f, 0)
        val dlmLen = le32(f, 4)
        if (Mt76Regs.FW_HDR_LEN + ilmLen + dlmLen != f.size) {
            throw IllegalStateException("MT7612U: firmware size mismatch")
        }
        val e3 = (io.regRead(Mt76Regs.ASIC_VERSION) and 0xffff) >= Mt76Regs.REV_E3
        io.devMode(Mt76Regs.DIR_OUT, 0x1, null)
        sleep(8)
        io.cfgWrite(Mt76Regs.USB_U3DMA_CFG, Mt76Regs.USB_DMA_CFG_UPLOAD)
        configureFce()
        fceSend(f, Mt76Regs.FW_HDR_LEN, ilmLen, Mt76Regs.FW_URB_MAX_PAYLOAD, Mt76Regs.ILM_OFFSET)
        val dlmOffset = if (e3) Mt76Regs.DLM_OFFSET + 0x800 else Mt76Regs.DLM_OFFSET
        fceSend(f, Mt76Regs.FW_HDR_LEN + ilmLen, dlmLen, Mt76Regs.FW_URB_MAX_PAYLOAD, dlmOffset)
        io.devMode(Mt76Regs.DIR_OUT, 0x12, null)
        if (!io.pollReg(Mt76Regs.MCU_COM_REG0, 0x1, 0x1, 100)) log("MT7612U: firmware failed to start")
        io.regSet(Mt76Regs.MCU_COM_REG0, 0x2)
        io.regWrite(Mt76Regs.FCE_PSE_CTRL, 0x1)
    }

    private fun configureFce() {
        io.regWrite(Mt76Regs.FCE_PSE_CTRL, 0x1)
        io.regWrite(Mt76Regs.TX_CPU_FROM_FCE_BASE_PTR, 0x400230)
        io.regWrite(Mt76Regs.TX_CPU_FROM_FCE_MAX_COUNT, 0x1)
        io.regWrite(Mt76Regs.FCE_PDMA_GLOBAL_CONF, 0x44)
        io.regWrite(Mt76Regs.FCE_SKIP_FS, 0x3)
    }

    private fun fceSend(src: ByteArray, srcOff: Int, dataLen: Int, maxPayload: Int, dstAddr: Int) {
        val maxLen = maxPayload - 8
        var pos = 0
        while (pos < dataLen) {
            val len = minOf(dataLen - pos, maxLen)
            val rounded = (len + 3) and 3.inv()
            val buf = ByteArray(4 + rounded + 4)
            putLe32(buf, 0, (Mt76Regs.CPU_TX_PORT shl 27) or Mt76Regs.MCU_MSG_TYPE_CMD or (len and 0xffff))
            System.arraycopy(src, srcOff + pos, buf, 4, len)
            var n = -1
            var tries = 0
            while (tries < 4) {
                io.singleWriteFce(Mt76Regs.FCE_DMA_ADDR, dstAddr + pos)
                io.singleWriteFce(Mt76Regs.FCE_DMA_LEN, rounded shl 16)
                n = conn.bulkTransfer(epCmdOut, buf, buf.size, 1000)
                if (n == buf.size) break
                io.clearHalt(epCmdOut.address)
                tries++
                sleep(15)
            }
            if (n != buf.size) throw IllegalStateException("MT7612U: firmware chunk failed at $pos (n=$n tries=$tries)")
            io.regWrite(Mt76Regs.TX_CPU_FROM_FCE_CPU_DESC_IDX,
                io.regRead(Mt76Regs.TX_CPU_FROM_FCE_CPU_DESC_IDX) + 1)
            pos += len
            sleep(10)
        }
    }

    // -- Bring-up --

    private fun resetWlan() {
        var v = io.regRead(Mt76Regs.WLAN_FUN_CTRL) and Mt76Regs.FRC_WL_ANT_SEL.inv()
        if (v and Mt76Regs.WLAN_EN != 0) {
            io.regWrite(Mt76Regs.WLAN_FUN_CTRL, v or Mt76Regs.WLAN_RESET_RF); sleep(1)
            v = v and Mt76Regs.WLAN_RESET_RF.inv()
        }
        io.regWrite(Mt76Regs.WLAN_FUN_CTRL, v); sleep(1)
        v = v or Mt76Regs.WLAN_EN; io.regWrite(Mt76Regs.WLAN_FUN_CTRL, v); sleep(1)
        v = v or Mt76Regs.WLAN_CLK_EN; io.regWrite(Mt76Regs.WLAN_FUN_CTRL, v); sleep(1)
    }

    private fun powerOn() {
        io.cfgSet(0x148, 1 shl 0)
        val up = (1 shl 28) or (1 shl 12) or (1 shl 13)
        io.pollCfg(0x148, up, up, 1000)
        io.cfgClear(0x148, 0x7f shl 16); sleep(1)
        io.cfgClear(0x148, 0xf shl 24); sleep(1)
        io.cfgSet(0x148, 0xf shl 24); io.cfgClear(0x148, 0xfff)
        io.cfgClear(0x1204, 1 shl 3)
        io.cfgSet(0x80, 1 shl 0)
        io.cfgClear(0x64, 1 shl 18)
        powerOnRf(0); powerOnRf(1)
    }

    private fun powerOnRf(unit: Int) {
        val s = if (unit != 0) 8 else 0
        io.cfgSet(0x130, 1 shl s); sleep(1)
        io.cfgSet(0x130, ((1 shl 1) or (1 shl 3) or (1 shl 4) or (1 shl 5)) shl s); sleep(1)
        io.cfgClear(0x130, (1 shl 2) shl s); sleep(1)
        io.cfgSet(0x130, (1 shl 0) or (1 shl 16)); sleep(1)
        io.cfgClear(0x1c, 0xff); io.cfgSet(0x1c, 0x30)
        io.cfgWrite(0x14, 0x484f); sleep(1)
        io.cfgSet(0x130, 1 shl 17); sleep(1)
        io.cfgClear(0x130, 1 shl 16); sleep(1)
        io.cfgSet(0x14c, (1 shl 19) or (1 shl 20))
        io.regWrite(0x530, 0xf)
    }

    private fun initDma() {
        var v = io.cfgRead(Mt76Regs.USB_U3DMA_CFG)
        v = v or Mt76Regs.DMA_RX_DROP_OR_PAD or Mt76Regs.DMA_RX_BULK_EN or Mt76Regs.DMA_TX_BULK_EN
        v = v and Mt76Regs.DMA_RX_BULK_AGG_EN.inv()
        io.cfgWrite(Mt76Regs.USB_U3DMA_CFG, v)
    }

    private fun macReset() {
        io.regWrite(Mt76Regs.WPDMA_GLO_CFG, (1 shl 4) or (1 shl 5))
        io.regWrite(Mt76Regs.PBF_TX_MAX_PCNT, 0xefef3f1f.toInt())
        io.regWrite(Mt76Regs.PBF_RX_MAX_PCNT, 0xfebf)
        for (p in Mt76Regs.MAC_INITVALS) io.regWrite(p[0], p[1])
        io.regWrite(Mt76Regs.TX_LINK_CFG, 0x1020)
        io.regWrite(Mt76Regs.AUTO_RSP_CFG, 0x13)
        io.regWrite(Mt76Regs.MAX_LEN_CFG, 0x2f00)
        io.regWrite(Mt76Regs.WMM_AIFSN, 0x2273)
        io.regWrite(Mt76Regs.WMM_CWMIN, 0x2344)
        io.regWrite(Mt76Regs.WMM_CWMAX, 0x34aa)
        io.regClear(Mt76Regs.MAC_SYS_CTRL, Mt76Regs.SYS_CTRL_RESET_CSR or Mt76Regs.SYS_CTRL_RESET_BBP)
        io.regClear(Mt76Regs.COEXCFG0, Mt76Regs.COEX_EN)
        io.regSet(Mt76Regs.EXT_CCA_CFG, 0xf000)
        io.regClear(Mt76Regs.TX_ALC_CFG_4, 1 shl 31)
    }

    private fun macStart() {
        io.regWrite(Mt76Regs.MAC_SYS_CTRL, Mt76Regs.SYS_CTRL_ENABLE_TX)
        io.pollReg(Mt76Regs.WPDMA_GLO_CFG, Mt76Regs.WPDMA_TX_BUSY or Mt76Regs.WPDMA_RX_BUSY, 0, 1000)
        io.regWrite(Mt76Regs.RX_FILTR_CFG, Mt76Regs.FILTR_CRC_ERR or Mt76Regs.FILTR_PHY_ERR)
        io.regWrite(Mt76Regs.MAC_SYS_CTRL, Mt76Regs.SYS_CTRL_ENABLE_TX or Mt76Regs.SYS_CTRL_ENABLE_RX)
        io.pollReg(Mt76Regs.WPDMA_GLO_CFG, Mt76Regs.WPDMA_TX_BUSY or Mt76Regs.WPDMA_RX_BUSY, 0, 1000)
        io.regWrite(Mt76Regs.CH_TIME_CFG, 0x15f)
    }

    private fun setRxPath() {
        val v = io.regRead(Mt76Regs.BBP_AGC0)
        io.regWrite(Mt76Regs.BBP_AGC0, (v and (1 shl 4).inv()) or (1 shl 3))
    }

    private val calAt = HashMap<Int, Long>()

    private fun tuneChannel(ch: Int, scan: Boolean = true) {
        val is5 = ch > 14
        if (!is5) { io.regSet(Mt76Regs.TX_BAND_CFG, 1 shl 2); io.regClear(Mt76Regs.TX_BAND_CFG, 1 shl 1) }
        else { io.regClear(Mt76Regs.TX_BAND_CFG, 1 shl 2); io.regSet(Mt76Regs.TX_BAND_CFG, 1 shl 1) }
        io.regRmw(Mt76Regs.BBP_CORE1, 0x18, 0)
        io.regRmw(Mt76Regs.BBP_AGC0, 0x7000, 1 shl 12)
        switchChannel(ch, scan)
        val now = System.currentTimeMillis()
        val wait = !scan
        if (!scan || now - (calAt[ch] ?: 0L) > 30_000L) {
            mcuCmd(Mt76Regs.CMD_INIT_GAIN_OP, le32words(ch or (1 shl 31), mcuGain), wait)
            io.regSet(Mt76Regs.BBP_RXO13, 1 shl 10)
            mcuCmd(Mt76Regs.CMD_CALIBRATION_OP, le32words(Mt76Regs.MCU_CAL_RXDCOC, ch), wait)
            mcuCmd(Mt76Regs.CMD_CALIBRATION_OP, le32words(Mt76Regs.MCU_CAL_RC, 0), wait)
            io.regWrite(Mt76Regs.BBP_AGC61, 0xff64a4e2.toInt())
            io.regWrite(Mt76Regs.BBP_AGC7, 0x08081010)
            io.regWrite(Mt76Regs.BBP_AGC11, 0x00000404)
            io.regWrite(Mt76Regs.BBP_AGC2, 0x00007070)
            io.regWrite(Mt76Regs.TXOP_CTRL_CFG, 0x04101b3f)
            io.regSet(Mt76Regs.BBP_TXO4, 1 shl 25)
            io.regSet(Mt76Regs.BBP_RXO13, 1 shl 8)
            calAt[ch] = now
        }
        if (scan) return
        val b = if (is5) 1 else 0
        if (is5) mcuCmd(Mt76Regs.CMD_CALIBRATION_OP, le32words(Mt76Regs.MCU_CAL_LC, 0), true)
        mcuCmd(Mt76Regs.CMD_CALIBRATION_OP, le32words(Mt76Regs.MCU_CAL_TX_LOFT, b), true)
        mcuCmd(Mt76Regs.CMD_CALIBRATION_OP, le32words(Mt76Regs.MCU_CAL_TXIQ, b), true)
        mcuCmd(Mt76Regs.CMD_CALIBRATION_OP, le32words(Mt76Regs.MCU_CAL_RXIQC_FI, b), true)
        mcuCmd(Mt76Regs.CMD_CALIBRATION_OP, le32words(Mt76Regs.MCU_CAL_TEMP, 0), true)
        mcuCmd(Mt76Regs.CMD_CALIBRATION_OP, le32words(Mt76Regs.MCU_CAL_TX_SHAPING, 0), true)
        edccaInit()
    }

    // Enables the RX antenna/LNA path (TX_PIN_CFG) after calibration; mt76 mt76x02_edcca_init + tx_enable.
    private fun edccaInit() {
        io.regSet(Mt76Regs.TX_LINK_CFG, 1 shl 12)
        io.regClear(Mt76Regs.TXOP_CTRL_CFG, 1 shl 20)
        io.regWrite(Mt76Regs.BBP_AGC2, 0x00007070)
        io.regSet(Mt76Regs.TXOP_HLDR_ET, 1 shl 1)
        io.regSet(Mt76Regs.MAC_SYS_CTRL, Mt76Regs.SYS_CTRL_ENABLE_TX)
        io.regSet(Mt76Regs.AUTO_RSP_CFG, 1 shl 0)
        val v = io.regRead(Mt76Regs.TX_PIN_CFG) or 0xf or (0xf shl 8) or (1 shl 16) or (1 shl 18)
        io.regWrite(Mt76Regs.TX_PIN_CFG, v)
    }

    private fun waitForMac(): Boolean {
        val end = System.currentTimeMillis() + 1000
        do {
            val v = io.regRead(Mt76Regs.MAC_CSR0)
            if (v != 0 && v != -0x1) return true
            sleep(5)
        } while (System.currentTimeMillis() < end)
        return false
    }

    private fun switchChannel(ch: Int, scan: Boolean) {
        // mt76x2_mcu_set_channel (mt76x2/mcu.c, BSD): two CMD_SWITCH_CHANNEL_OP sends, idx/scan/bw/chainmask, 2nd with ext_chan 0xe0.
        // Single-threaded RX loop: on scan hops skip the MCU response wait so the RX drain is not starved.
        val waitResp = !scan
        val msg = ByteArray(8)
        msg[0] = ch.toByte()
        msg[1] = if (scan) 1 else 0
        msg[4] = 0x03
        mcuCmd(Mt76Regs.CMD_SWITCH_CHANNEL_OP, msg, waitResp)
        sleep(6)
        msg[6] = 0xe0.toByte()
        mcuCmd(Mt76Regs.CMD_SWITCH_CHANNEL_OP, msg, waitResp)
    }

    private fun loadCr(ee: ByteArray, ch: Int) {
        val nc0 = le16(ee, Mt76Regs.EE_NIC_CONF_0)
        val nc1 = le16(ee, Mt76Regs.EE_NIC_CONF_1)
        val cfg = (1 shl 31) or ((nc0 shr 8) and 0xff) or ((nc1 shl 8) and 0xff00)
        val m = ByteArray(8)
        m[0] = Mt76Regs.MT_RF_BBP_CR.toByte(); m[2] = ch.toByte(); putLe32(m, 4, cfg)
        mcuCmd(Mt76Regs.CMD_LOAD_CR, m, true)
    }

    private fun mcuCmd(cmd: Int, payload: ByteArray, waitResp: Boolean): Int {
        seq = (seq + 1) and 0xf; if (seq == 0) seq = 1
        val rounded = (payload.size + 3) and 3.inv()
        val txinfo = (rounded and 0xffff) or (Mt76Regs.CPU_TX_PORT shl 27) or (seq shl 16) or
            (cmd shl 20) or Mt76Regs.MCU_MSG_TYPE_CMD
        val buf = ByteArray(4 + rounded + 4)
        putLe32(buf, 0, txinfo); System.arraycopy(payload, 0, buf, 4, payload.size)
        conn.bulkTransfer(epCmdOut, buf, buf.size, 1000)
        if (!waitResp) return -1
        val rep = epCmdResp
        if (rep == null) { sleep(10); return -1 }
        val rb = ByteArray(512)
        val n = conn.bulkTransfer(rep, rb, rb.size, 300)
        if (mcuLogged < 6) {
            mcuLogged++
            val evt = if (n >= 4) (le32(rb, 0) ushr 20) and 0xf else -1
            log("MT7612U MCU cmd=$cmd resp=${n}B evt=$evt fce=0x${(if (n >= 4) le32(rb, 0) else 0).toString(16)}")
        }
        return n
    }

    // -- RX --

    private fun rxLoop(onBatch: (List<ApSighting>) -> Unit) {
        val nbuf = 16
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
        io.regWrite(Mt76Regs.RX_FILTR_CFG, Mt76Regs.FILTR_PHY_ERR)
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
        var phoneCh = emptySet<Int>()
        var phoneChAt = 0L
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
                            rxBytes += nbytes
                            rxBufs++
                            lastRxAt = now
                            b.rewind(); b.get(scratch, 0, nbytes)
                            runCatching { parseRx(scratch, nbytes, Mt76Regs.CHANNELS[hopIdx], table) }
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
                    }
                }
                if (now - diagAt > 3000) {
                    val busy = io.regRead(Mt76Regs.CH_BUSY)
                    val rs0 = io.regRead(Mt76Regs.RX_STAT_0)
                    log("MT7612U rx: bufs=$rxBufs bytes=$rxBytes tracked=${table.map.size} ch=${Mt76Regs.CHANNELS[hopIdx]} CH_BUSY=$busy STAT0(crc=${rs0 and 0xffff} phy=${(rs0 ushr 16) and 0xffff})")
                    diagAt = now
                    if (now - lastRxAt > 4000 && (busy > 50000 || rxBufs == 0L)) {
                        reKickRx()
                        lastRxAt = now
                    }
                }
                if (now - emitAt > 2000) { emit(table, onBatch); emitAt = now }
                if (now - hopAt > DWELL_MS) {
                    if (now - phoneChAt > 5000) { phoneCh = phoneChannels(); phoneChAt = now }
                    val active = table.map.values.mapTo(HashSet(phoneCh)) { it.channel }
                    val explore = now - exploreAt > EXPLORE_MS
                    var nx = (hopIdx + 1) % Mt76Regs.CHANNELS.size
                    if (active.isNotEmpty() && !explore) {
                        var s = 0
                        while (s < Mt76Regs.CHANNELS.size && Mt76Regs.CHANNELS[nx] !in active) {
                            nx = (nx + 1) % Mt76Regs.CHANNELS.size; s++
                        }
                    } else if (explore) {
                        exploreAt = now
                    }
                    hopIdx = nx
                    runCatching { tuneChannel(Mt76Regs.CHANNELS[hopIdx]) }
                    drainCmdResp()
                    hopAt = now
                }
            }
        } finally {
            reqs.forEach { runCatching { it.cancel() }; runCatching { it.close() } }
        }
        emit(table, onBatch)
    }

    private fun rxLoopSync(bufSz: Int, onBatch: (List<ApSighting>) -> Unit) {
        val buf = ByteArray(bufSz)
        val table = SightingTable()
        var hopIdx = 0
        var hopAt = System.currentTimeMillis()
        var emitAt = hopAt
        var diagAt = hopAt
        var rxBytes = 0L
        var rxBufs = 0L
        while (!stop) {
            val n = conn.bulkTransfer(epRx, buf, buf.size, 500)
            val now = System.currentTimeMillis()
            if (n > 0) { rxBytes += n; rxBufs++; runCatching { parseRx(buf, n, Mt76Regs.CHANNELS[hopIdx], table) } }
            if (now - diagAt > 3000) {
                val rs0 = io.regRead(Mt76Regs.RX_STAT_0)
                log("MT7612U rxsync: bufs=$rxBufs bytes=$rxBytes tracked=${table.map.size} ch=${Mt76Regs.CHANNELS[hopIdx]} STAT0(crc=${rs0 and 0xffff} phy=${(rs0 ushr 16) and 0xffff})")
                diagAt = now
            }
            if (now - emitAt > 2000) { emit(table, onBatch); emitAt = now }
            if (now - hopAt > DWELL_MS) {
                hopIdx = (hopIdx + 1) % Mt76Regs.CHANNELS.size
                runCatching { tuneChannel(Mt76Regs.CHANNELS[hopIdx]) }
                drainCmdResp()
                hopAt = now
            }
        }
        emit(table, onBatch)
    }

    // RX stalled with RF energy present: re-arm RX DMA + MAC RX (mt76 reKick, as Wardrive Go does).
    private fun reKickRx() {
        io.regClear(Mt76Regs.MAC_SYS_CTRL, Mt76Regs.SYS_CTRL_ENABLE_RX)
        val v = io.cfgRead(Mt76Regs.USB_U3DMA_CFG)
        io.cfgWrite(Mt76Regs.USB_U3DMA_CFG, v and Mt76Regs.DMA_RX_BULK_EN.inv())
        io.cfgWrite(Mt76Regs.USB_U3DMA_CFG, v or Mt76Regs.DMA_RX_BULK_EN)
        io.regSet(Mt76Regs.MAC_SYS_CTRL, Mt76Regs.SYS_CTRL_ENABLE_RX)
    }

    private fun drainCmdResp() {
        val ep = epCmdResp ?: return
        val tmp = ByteArray(512)
        repeat(6) { if (conn.bulkTransfer(ep, tmp, tmp.size, 1) <= 0) return }
    }

    // -- 802.11 parse: APs (beacon/probe-resp/data) + client stations --

    private class Entry(var ssid: String?, var rssi: Int, var channel: Int, var lastSeen: Long, var isAp: Boolean)
    private class SightingTable {
        val map = LinkedHashMap<String, Entry>()
    }

    private fun parseRx(b: ByteArray, n: Int, ch: Int, table: SightingTable) {
        fun u8(i: Int) = b[i].toInt() and 0xff
        val dmaHdr = 4
        val rxwiLen = 32
        if (n < dmaHdr + rxwiLen + 24) return
        val dmaLen = u8(0) or (u8(1) shl 8)
        if (dmaLen < rxwiLen + 24 || dmaHdr + dmaLen > n) return
        val rxwi = dmaHdr
        val rxinfo = le32(b, rxwi)
        val ctl = le32(b, rxwi + 4)
        val rssiRaw = b[rxwi + 12].toInt()
        val mpduLen = (ctl ushr 16) and 0x3fff
        val pad = if (rxinfo and (1 shl 14) != 0) 2 else 0
        val d = rxwi + rxwiLen
        val end = minOf(n, rxwi + rxwiLen + mpduLen + pad)
        if (d + 24 > end) return
        val crc = rxinfo and (1 shl 8) != 0
        val good = !crc
        val fc = u8(d)
        val flags = u8(d + 1)
        val type = (fc shr 2) and 3
        val sub = (fc shr 4) and 0xf
        val rssi = (if (ch <= 14) rssiRaw + rssiOff2g - lna2g else rssiRaw + rssiOff5g - lna5g)
            .coerceIn(-120, -20)
        fun macAt(off: Int) = (0 until 6).joinToString(":") { "%02x".format(u8(off + it)) }
        fun group(off: Int) = u8(off) and 1 != 0
        fun touch(mac: String, isAp: Boolean, ssid: String?) {
            if (mac == "ff:ff:ff:ff:ff:ff" || mac == "00:00:00:00:00:00") return
            if (mac.startsWith("01:00:5e") || mac.startsWith("33:33") || mac.startsWith("01:80:c2")) return
            val e = table.map.getOrPut(mac) { Entry(null, rssi, ch, 0, isAp) }
            e.isAp = e.isAp || isAp
            if (!ssid.isNullOrEmpty()) e.ssid = ssid
            if (rssi > e.rssi) e.rssi = rssi
            e.channel = ch
            e.lastSeen = System.currentTimeMillis()
        }
        when (type) {
            0 -> when (sub) {
                8, 5 -> {
                    val ssid = readSsid(b, d + 36 + pad, end)
                    if (good || !ssid.isNullOrEmpty()) touch(macAt(d + 16), true, ssid)
                }
                4, 0, 1, 2, 3, 10, 11, 12 -> if (good && captureClients) touch(macAt(d + 10), false, null)
            }
            2 -> {
                if (!good) return
                val toDs = flags and 1 != 0
                val fromDs = flags and 2 != 0
                when {
                    toDs && !fromDs -> { if (!group(d + 4)) touch(macAt(d + 4), true, null); if (captureClients) touch(macAt(d + 10), false, null) }
                    !toDs && fromDs -> { if (!group(d + 10)) touch(macAt(d + 10), true, null); if (captureClients) touch(macAt(d + 4), false, null) }
                    !toDs && !fromDs -> { if (!group(d + 16)) touch(macAt(d + 16), true, null); if (captureClients) touch(macAt(d + 10), false, null) }
                    else -> if (captureClients) touch(macAt(d + 10), false, null)
                }
            }
            1 -> if (good && captureClients && (sub == 11 || sub == 10)) touch(macAt(d + 10), false, null)
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

    private fun emit(table: SightingTable, onBatch: (List<ApSighting>) -> Unit) {
        val now = System.currentTimeMillis()
        val fresh = 8000L
        val batch = table.map.entries
            .filter { now - it.value.lastSeen < fresh }
            .map { (mac, e) -> ApSighting(mac, e.ssid, e.rssi, e.channel, Mt76Regs.freqOf(e.channel), client = !e.isAp) }
        table.map.entries.removeAll { now - it.value.lastSeen > 60_000L }
        if (batch.isNotEmpty()) onBatch(batch)
    }

    private fun readEeprom(): ByteArray {
        val ee = ByteArray(Mt76Regs.EE_SIZE)
        var i = 0
        while (i + 4 <= Mt76Regs.EE_SIZE) {
            putLe32(ee, i, io.eepromRead(i))
            i += 4
        }
        return ee
    }

    private fun computeGainAndRssi(ee: ByteArray) {
        fun signExt(v: Int, bits: Int): Int { val s = 1 shl (bits - 1); return if (v and s != 0) v - (1 shl bits) else v }
        fun rssiOff(v: Int): Int { val b0 = v and 0xff; return if (b0 == 0 || b0 == 0xff || b0 and 0x80 == 0) 0 else signExt(b0, 7) }
        fun lnaOf(v: Int): Int { val b0 = v and 0xff; return if (b0 == 0xff) 0 else signExt(b0, 8) }
        rssiOff2g = rssiOff(le16(ee, Mt76Regs.EE_RSSI_OFFSET_2G_0))
        rssiOff5g = rssiOff(le16(ee, Mt76Regs.EE_RSSI_OFFSET_5G_0))
        lna2g = lnaOf(le16(ee, Mt76Regs.EE_LNA_GAIN))
        lna5g = lnaOf(le16(ee, Mt76Regs.EE_LNA_GAIN) ushr 8)
        val v044 = le16(ee, Mt76Regs.EE_LNA_GAIN)
        val g2 = v044 and 0xff
        val g5 = (v044 ushr 8) and 0xff
        var g5b = (le16(ee, Mt76Regs.EE_RSSI_OFFSET_2G_1) ushr 8) and 0xff
        if (g5b == 0 || g5b == 0xff) g5b = g5
        mcuGain = g2 or (g5 shl 8) or (g5b shl 16) or (g5 shl 24)
    }

    private fun fixupXtal(ee: ByteArray) {
        var ev = le16(ee, Mt76Regs.EE_XTAL_TRIM_2)
        var offset = ev and 0x7f
        if ((ev and 0xff) == 0xff) offset = 0 else if (ev and 0x80 != 0) offset = -offset
        ev = ev shr 8
        if (ev == 0x00 || ev == 0xff) {
            ev = le16(ee, Mt76Regs.EE_XTAL_TRIM_1) and 0xff
            if (ev == 0x00 || ev == 0xff) ev = 0x14
        }
        ev = ev and 0x7f
        val c2 = (ev + offset) and 0x7f
        io.cfgWrite(0x114, (io.cfgRead(0x114) and (0x7f shl 8).inv()) or (c2 shl 8))
        io.cfgSet(0x118, 0x7f shl 8)
        io.regWrite(0x504, 0x06000000); io.regWrite(0x50c, 0x08800000); sleep(5); io.regWrite(0x504, 0)
        io.regRmw(0x1100, 0xff shl 8, 0xd shl 8)
        io.regRmw(0x1104, 0xf shl 8, 1 shl 8)
        io.regClear(0x080c, 1 shl 4)
        when ((le16(ee, Mt76Regs.EE_NIC_CONF_2) shr 9) and 0x3) {
            0 -> io.regWrite(0x011c, 0x5c1fee80)
            1 -> io.regWrite(0x011c, 0x5c1feed0.toInt())
        }
    }

    private fun le32words(vararg w: Int): ByteArray {
        val b = ByteArray(w.size * 4)
        for (i in w.indices) putLe32(b, i * 4, w[i])
        return b
    }

    companion object {
        const val DWELL_MS = 125L
        const val EXPLORE_MS = 2000L
    }
}

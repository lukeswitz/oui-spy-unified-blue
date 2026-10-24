package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbRequest
import com.rootdowndigital.ouispy.wifiadapter.Rtl88Regs as R
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.le16
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.le32
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.putLe32
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.sleep
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.TimeoutException

// Passive RTL8814AU monitor receiver (Alfa AWUS1900) ported from Linux rtw88 (SPDX GPL-2.0 OR BSD-3-Clause): receive only, never transmits.
internal class Rtl8814auAdapter(
    private val conn: UsbDeviceConnection,
    private val intf: UsbInterface,
    private val fw: RtlFirmwareStore.Blobs,
    private val log: (String) -> Unit,
) {
    @Volatile private var stop = false
    private val io = RtlIo(conn)
    private lateinit var epRx: UsbEndpoint
    private lateinit var epTx: UsbEndpoint
    private var bulkOutCount = 0
    private var superSpeed = false
    private var cut = 0
    private var rfe = 0
    private var crystalCap = 0
    private var rsvdBoundary = 0
    private var rsvdH2cqAddr = 0
    private var chParam0 = 0
    private var chParam1 = 0
    private var accessed = false

    fun abort() {
        stop = true
        io.canceled = true
    }

    fun run(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        conn.claimInterface(intf, true)
        if (!findEndpoints()) throw IllegalStateException("RTL8814AU: bulk endpoints not found")
        try {
            bringUp()
            log("RTL8814AU: receiver live")
            rxLoop(onBatch)
        } finally {
            if (accessed) powerDown()
        }
    }

    private fun findEndpoints(): Boolean {
        var rx: UsbEndpoint? = null
        var tx: UsbEndpoint? = null
        var outs = 0
        for (i in 0 until intf.endpointCount) {
            val ep = intf.getEndpoint(i)
            if (ep.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
            if (ep.direction == UsbConstants.USB_DIR_IN) {
                if (rx == null) rx = ep
            } else {
                if (tx == null) tx = ep
                outs++
            }
        }
        epRx = rx ?: return false
        epTx = tx ?: return false
        if (outs < 2) return false
        bulkOutCount = minOf(outs, 4)
        // unverified: USB speed is inferred from the bulk-in max packet size
        superSpeed = epRx.maxPacketSize >= 1024
        return true
    }

    private fun powerDown() {
        io.canceled = false
        try {
            io.w8(R.CR, 0)
            runPwrSeq(io, Rtl8814auRegs.PWR_OFF)
        } catch (e: IOException) {
            log("RTL8814AU: power-down skipped: ${e.message}")
        } catch (e: IllegalStateException) {
            log("RTL8814AU: power-down incomplete: ${e.message}")
        }
    }

    private fun bringUp() {
        accessed = true
        cut = (io.r32(R.SYS_CFG1) ushr 12) and 0xf
        log("RTL8814AU: chip cut $cut")
        macPowerOn()
        // unverified: efuse is read straight after MAC power-on with no firmware running, rtw88 reads it with the MAC powered via its own on/off cycle
        parseEfuse(RtlEfuse.dump(io, Rtl8814auRegs.PHY_EFUSE_SIZE, Rtl8814auRegs.LOG_EFUSE_SIZE))
        val tbl = RtlPhyTables(fw.tables)
        val drv = PhyDrv(if (cut == 0) 15 else cut, rfe, false)
        macInit(tbl, drv)
        phySetParam(tbl, drv)
        // unverified: firmware H2C general/phydm info, IQK/LCK calibration and TX power setup from rtw88 are not performed
        io.w32(R.RCR, R.RCR_MONITOR)
        for (reg in Rtl8814auRegs.DIG_REGS) io.m32(reg, 0x7f, DIG_MAX_COVERAGE)
        setChannel(Mt76Regs.CHANNELS[0])
    }

    private fun parseEfuse(ee: ByteArray) {
        val xtal = ee[Rtl8814auRegs.EE_XTAL_K].toInt() and 0xff
        crystalCap = if (xtal == 0xff) 0 else xtal
        val raw = ee[Rtl8814auRegs.EE_RFE_OPTION].toInt() and 0xff
        rfe = if ((raw and 0x80) != 0) 1 else raw
        // unverified: rtw88 only accepts rfe 0 and 1 for 8814A, other values are applied here against the table conditions
        if (rfe > 1) log("RTL8814AU: efuse rfe option $rfe is outside the rtw88 supported set")
    }

    private fun macPowerOn() {
        preSystemCfg()
        if (!powerSwitch(true)) {
            powerSwitch(false)
            preSystemCfg()
            powerSwitch(true)
        }
        var v = io.r32(R.CPU_DMEM_CON)
        v = v or (1 shl 16) or (1 shl 8)
        io.w32(R.CPU_DMEM_CON, v)
        io.s8(R.SYS_FUNC_EN + 1, Rtl8814auRegs.SYS_FUNC_EN_INIT)
        io.w8(R.CR_EXT + 3, (io.r8(R.CR_EXT + 3) and 0xf0) or 0x0c)
        val mcu = io.r32(R.MCUFW_CTRL)
        if ((mcu and (1 shl 20)) != 0) {
            io.w32(R.MCUFW_CTRL, mcu and (1 shl 20).inv())
            io.w32(R.GPIO_MUXCFG, io.r32(R.GPIO_MUXCFG) and (1 shl 19).inv())
        }
    }

    private fun preSystemCfg() {
        io.w8(R.RSV_CTRL, 0)
        io.s32(R.PAD_CTRL1, (1 shl 29) or (1 shl 28))
        io.c32(R.LED_CFG, (1 shl 26) or (1 shl 25))
        io.s32(R.GPIO_MUXCFG, 1 shl 2)
        io.c8(R.SYS_FUNC_EN, 0x03)
        io.c8(R.RF_CTRL, 0x07)
        io.c32(R.WLRF1, (1 shl 24) or (1 shl 25) or (1 shl 26))
    }

    private fun powerSwitch(on: Boolean): Boolean {
        var rpwm = io.r8(R.USB_HRPWM)
        if (io.r16(R.MCUFW_CTRL) == Rtl8814auRegs.FW_READY) {
            rpwm = (rpwm xor 0x80) and 0x80
            io.w8(R.USB_HRPWM, rpwm)
        }
        val curOn = io.r8(R.CR) != 0xea
        if (on == curOn) return false
        runPwrSeq(io, if (on) Rtl8814auRegs.PWR_ON else Rtl8814auRegs.PWR_OFF)
        return true
    }

    private fun cpuEnable(on: Boolean) {
        if (on) {
            io.s8(R.RSV_CTRL + 1, 1)
            io.s8(R.SYS_FUNC_EN + 1, 1 shl 2)
        } else {
            io.c8(R.SYS_FUNC_EN + 1, 1 shl 2)
            io.c8(R.RSV_CTRL + 1, 1)
        }
    }

    private fun downloadFirmware() {
        val f = fw.firmware
        val dmemSz = le32(f, 0x24)
        val imemSz = le32(f, 0x30)
        val ememSz = if ((f[0x18].toInt() and 0x10) != 0) le32(f, 0x34) else 0
        val dm = dmemSz + Rtl8814auRegs.FW_CHKSUM_SIZE
        val im = imemSz + Rtl8814auRegs.FW_CHKSUM_SIZE
        val em = if (ememSz != 0) ememSz + Rtl8814auRegs.FW_CHKSUM_SIZE else 0
        if (Rtl8814auRegs.FW_HDR_SIZE + dm + im + em != f.size) throw IllegalStateException("RTL8814AU: firmware size mismatch")

        cpuEnable(false)
        val b0 = io.r8(R.TXDMA_PQ_MAP + 1)
        io.w8(R.TXDMA_PQ_MAP + 1, R.DMA_HIGH shl 6)
        val b1 = io.r8(R.CR)
        io.w8(R.CR, 0x05)
        io.w32(R.H2CQ_CSR, 1 shl 31)
        val b3 = io.r16(R.FIFOPAGE_INFO_1)
        io.w16(R.FIFOPAGE_INFO_1, 0x200)
        val b4 = io.r32(R.RQPN_CTRL_2) or R.LD_RQPN
        io.w32(R.RQPN_CTRL_2, b4)
        val b5 = io.r8(R.BCN_CTRL)
        io.w8(R.BCN_CTRL, (b5 and BIT_EN_BCN_FUNCTION.inv()) or BIT_DIS_TSF_UDT)

        io.c8(R.CPU_DMEM_CON + 2, 1)
        io.c8(R.SYS_CLK_CTRL + 1, 1 shl 6)
        io.s8(R.CPU_DMEM_CON + 2, 1)
        io.s8(R.SYS_CLK_CTRL + 1, 1 shl 6)

        io.w16(R.MCUFW_CTRL, (io.r16(R.MCUFW_CTRL) and 0x3800) or 1)
        val mask31 = (1 shl 31).inv()
        var off = Rtl8814auRegs.FW_HDR_SIZE
        fwToMem(f, off, le32(f, 0x20) and mask31, dm)
        off += dm
        fwToMem(f, off, le32(f, 0x3c) and mask31, im)
        off += im
        if (em != 0) fwToMem(f, off, le32(f, 0x38) and mask31, em)

        io.w8(R.TXDMA_PQ_MAP + 1, b0)
        io.w8(R.CR, b1)
        io.w32(R.H2CQ_CSR, 1 shl 31)
        io.w16(R.FIFOPAGE_INFO_1, b3)
        io.w32(R.RQPN_CTRL_2, b4)
        io.w8(R.BCN_CTRL, b5)

        io.w32(R.TXDMA_STATUS, 1 shl 2)
        var ctrl = io.r16(R.MCUFW_CTRL)
        if ((ctrl and 0x50) == 0x50) {
            ctrl = (ctrl or (1 shl 14)) and 1.inv()
            io.w16(R.MCUFW_CTRL, ctrl)
        }
        cpuEnable(true)
        if (!io.waitMask(R.MCUFW_CTRL, Rtl8814auRegs.FW_READY_MASK, Rtl8814auRegs.FW_READY)) {
            throw IllegalStateException("RTL8814AU: firmware failed to start")
        }
    }

    private fun fwToMem(f: ByteArray, srcOff: Int, dst: Int, size: Int) {
        io.s32(R.DDMA_CH0CTRL, 1 shl 25)
        var done = 0
        var first = true
        while (done < size) {
            val pkt = minOf(0x1000, size - done)
            sendFwPkt(f, srcOff + done, pkt)
            iddma(R.OCPBASE_TXBUF + R.TX_DESC_SIZE, dst + done, pkt, first)
            first = false
            done += pkt
        }
        checkFwChecksum(dst)
    }

    private fun sendFwPkt(f: ByteArray, off: Int, len: Int) {
        val size = if (((len + R.TX_DESC_SIZE) and 511) == 0) len + 1 else len
        val buf = ByteArray(R.TX_DESC_SIZE + size)
        putLe32(buf, 0, size or (R.TX_DESC_SIZE shl 16) or (1 shl 26))
        putLe32(buf, 4, TX_QSEL_BEACON shl 8)
        System.arraycopy(f, off, buf, R.TX_DESC_SIZE, len)
        var x = 0
        for (i in 0 until 16) x = x xor le16(buf, i * 2)
        putLe32(buf, 28, x and 0xffff)
        writeRsvdPage(buf)
    }

    private fun writeRsvdPage(buf: ByteArray) {
        val bcn = io.r8(R.BCN_CTRL)
        io.w16(R.FIFOPAGE_CTRL_2, R.BCN_VALID_V1)
        val cr1 = io.r8(R.CR + 1)
        io.w8(R.CR + 1, cr1 or 1)
        io.w8(R.BCN_CTRL, (bcn and BIT_EN_BCN_FUNCTION.inv()) or BIT_DIS_TSF_UDT)
        // unverified: firmware pages go out the first bulk-out endpoint, and a short-packet terminator is only added by the +1 length rule
        var ok = conn.bulkTransfer(epTx, buf, buf.size, 1000) == buf.size
        if (ok) ok = io.waitMask(R.FIFOPAGE_CTRL_2, R.BCN_VALID_V1, 1)
        // unverified: rsvdBoundary is still 0 during firmware download, as in rtw88 where the fifo layout is set after it
        io.w16(R.FIFOPAGE_CTRL_2, rsvdBoundary or R.BCN_VALID_V1)
        io.w8(R.BCN_CTRL, bcn)
        io.w8(R.CR + 1, cr1)
        if (!ok) throw IllegalStateException("RTL8814AU: firmware page write failed")
    }

    private fun iddma(src: Int, dst: Int, len: Int, first: Boolean) {
        var ctrl = (1 shl 29) or (1 shl 31)
        if (!io.waitMask(R.DDMA_CH0CTRL, 1 shl 31, 0)) throw IllegalStateException("RTL8814AU: DDMA busy")
        ctrl = ctrl or (len and 0x3ffff)
        if (!first) ctrl = ctrl or (1 shl 24)
        io.w32(R.DDMA_CH0SA, src)
        io.w32(R.DDMA_CH0DA, dst)
        io.w32(R.DDMA_CH0CTRL, ctrl)
        if (!io.waitMask(R.DDMA_CH0CTRL, 1 shl 31, 0)) throw IllegalStateException("RTL8814AU: DDMA timeout")
    }

    private fun checkFwChecksum(addr: Int) {
        var ctl = io.r8(R.MCUFW_CTRL)
        val imem = addr < R.OCPBASE_DMEM
        val dwOk = if (imem) 1 shl 3 else 1 shl 5
        val sumOk = if (imem) 1 shl 4 else 1 shl 6
        if ((io.r32(R.DDMA_CH0CTRL) and (1 shl 27)) != 0) {
            io.w8(R.MCUFW_CTRL, (ctl or dwOk) and sumOk.inv())
            throw IllegalStateException("RTL8814AU: firmware checksum mismatch")
        }
        ctl = ctl or dwOk or sumOk
        io.w8(R.MCUFW_CTRL, ctl)
    }

    private fun macInit(tbl: RtlPhyTables, drv: PhyDrv) {
        val q = Rtl8814auRegs.rqpn(bulkOutCount)
        io.w16(R.TXDMA_PQ_MAP, (q[5] shl 14) or (q[4] shl 12) or (q[3] shl 10) or (q[2] shl 8) or (q[1] shl 6) or (q[0] shl 4))
        io.w8(R.CR, 0)
        io.w8(R.CR, MAC_TRX_ENABLE)
        io.w32(R.H2CQ_CSR, 1 shl 31)
        io.s8(R.TXDMA_PQ_MAP, 1)
        priorityQueueCfg()
        initH2c()

        io.w16(R.CR, MAC_TRX_ENABLE or (1 shl 9) or (1 shl 10))
        tbl.load(tbl.array(Rtl8814auRegs.TBL_MAC), drv) { a, d -> io.w8(a, d) }
        io.w8(R.AUTO_LLT_V1 + 3, Rtl8814auRegs.USB_TX_AGG_DESC_NUM shl 1)
        io.w32(R.HIMR0, 0)
        io.w32(R.HIMR1, 0)
        io.m32(R.RRSR, 0xfffff, 0xfffff)
        io.w16(R.RETRY_LIMIT, 0x3030)
        io.w16(R.RXFLTMAP0, 0xffff)
        io.w16(R.RXFLTMAP1, 0x0400)
        io.w16(R.RXFLTMAP2, 0xffff)
        io.w8(R.MAX_AGGR_NUM, 0x36)
        io.w8(R.MAX_AGGR_NUM + 1, 0x36)
        io.w16(R.SPEC_SIFS, 0x100a)
        io.w16(R.MAC_SPEC_SIFS, 0x100a)
        io.w16(R.SIFS, 0x100a)
        io.w16(R.SIFS + 2, 0x100a)
        io.w32(R.EDCA_BE_PARAM, 0x005EA42B)
        io.w32(R.EDCA_BK_PARAM, 0x0000A44F)
        io.w32(R.EDCA_VI_PARAM, 0x005EA324)
        io.w32(R.EDCA_VO_PARAM, 0x002FA226)
        io.s8(R.FWHW_TXQ_CTRL, 1 shl 7)
        io.w8(R.ACKTO, 0x80)
        io.w16(R.BCN_CTRL, BIT_DIS_TSF_UDT or (BIT_DIS_TSF_UDT shl 8))
        io.m32(R.TBTT_PROHIBIT, 0xfffff, WLAN_TBTT_TIME)
        io.w8(R.DRVERLYINT, 0x05)
        io.w8(R.BCNDMATIM, 0x02)
        io.w16(R.BCNTCFG, 0x4413)
        io.w8(R.BCN_MAX_ERR, 0xff)
        io.w32(R.FAST_EDCA_VOVI_SETTING, 0x08070807)
        io.w32(R.FAST_EDCA_BEBK_SETTING, 0x08070807)
        if (superSpeed) {
            io.c8(R.USB_MOD, (1 shl 4) or (1 shl 3))
            io.w16(R.USB_H2C_FIX, 0)
            io.c8(R.SW_AMPDU_BURST_MODE_CTRL, 1 shl 6)
        }

        io.w8(R.RX_DRVINFO_SZ, R.PHY_STATUS_SIZE)
        io.w8(R.TRXFF_BNDY + 1, (io.r8(R.TRXFF_BNDY + 1) and 0xf0) or 0x0f)
        io.s32(R.RCR, R.RCR_APP_PHYSTS)
        io.c32(R.WMAC_OPTION_FUNCTION + 4, (1 shl 8) or (1 shl 9))
        initBurstLen()
    }

    private fun priorityQueueCfg() {
        val pgPer = 32
        val rsvdPg = Rtl8814auRegs.RSVD_DRV_PG + Rtl8814auRegs.RSVD_H2C_EXTRAINFO_PG +
            Rtl8814auRegs.RSVD_H2C_STATICINFO_PG + Rtl8814auRegs.RSVD_H2CQ_PG + Rtl8814auRegs.RSVD_FW_TXBUF_PG
        val acqPg = Rtl8814auRegs.TXFF_PG_NUM - rsvdPg
        rsvdBoundary = acqPg
        rsvdH2cqAddr = Rtl8814auRegs.TXFF_PG_NUM - Rtl8814auRegs.RSVD_FW_TXBUF_PG - Rtl8814auRegs.RSVD_H2CQ_PG
        val pub = acqPg - 4 * pgPer
        io.w16(R.FIFOPAGE_INFO_1, pgPer)
        io.w16(R.FIFOPAGE_INFO_2, pgPer)
        io.w16(R.FIFOPAGE_INFO_3, pgPer)
        io.w16(R.FIFOPAGE_INFO_4, pgPer)
        io.w16(R.FIFOPAGE_INFO_5, pub)
        io.s32(R.RQPN_CTRL_2, R.LD_RQPN)
        io.w16(R.FIFOPAGE_CTRL_2, rsvdBoundary)
        io.s8(R.FWHW_TXQ_CTRL + 2, 1 shl 4)
        io.w16(R.BCNQ_BDNY_V1, rsvdBoundary)
        io.w16(R.FIFOPAGE_CTRL_2 + 2, rsvdBoundary)
        io.w16(R.BCNQ1_BDNY_V1, rsvdBoundary)
        io.w32(R.RXFF_BNDY, Rtl8814auRegs.RXFF_SIZE - R.C2H_PKT_BUF - 1)
        io.m8(R.AUTO_LLT_V1, 0xf0, Rtl8814auRegs.USB_TX_AGG_DESC_NUM)
        io.w8(R.AUTO_LLT_V1 + 3, Rtl8814auRegs.USB_TX_AGG_DESC_NUM)
        io.s8(R.TXDMA_OFFSET_CHK + 1, 1 shl 1)
        io.s8(R.AUTO_LLT_V1, 1)
        if (!io.waitMask(R.AUTO_LLT_V1, 1, 0)) throw IllegalStateException("RTL8814AU: auto LLT init timeout")
        io.w8(R.CR + 3, 0)
    }

    private fun initH2c() {
        val addr = rsvdH2cqAddr shl 7
        val size = Rtl8814auRegs.RSVD_H2CQ_PG shl 7
        val keep = 0xFFFC0000.toInt()
        io.w32(R.H2C_HEAD, (io.r32(R.H2C_HEAD) and keep) or addr)
        io.w32(R.H2C_READ_ADDR, (io.r32(R.H2C_READ_ADDR) and keep) or addr)
        io.w32(R.H2C_TAIL, (io.r32(R.H2C_TAIL) and keep) or (addr + size))
        io.w8(R.H2C_INFO, (io.r8(R.H2C_INFO) and 0xfc) or 0x01)
        io.w8(R.H2C_INFO, (io.r8(R.H2C_INFO) and 0xfb) or 0x04)
        io.w8(R.TXDMA_OFFSET_CHK + 1, (io.r8(R.TXDMA_OFFSET_CHK + 1) and 0x7f) or 0x80)
        val wp = io.r32(R.H2C_PKT_WRITEADDR) and 0x3ffff
        val rp = io.r32(R.H2C_PKT_READADDR) and 0x3ffff
        val free = if (wp >= rp) size - (wp - rp) else rp - wp
        if (free != size) log("RTL8814AU: H2C queue mismatch (free $free of $size)")
    }

    private fun initBurstLen() {
        val size = if (superSpeed) 0 else 1
        io.w8(R.RXDMA_MODE, (1 shl 1) or (3 shl 2) or (size shl 4))
        io.s16(R.TXDMA_OFFSET_CHK, 1 shl 9)
    }

    private fun phySetParam(tbl: RtlPhyTables, drv: PhyDrv) {
        io.s8(R.SYS_FUNC_EN, 1 shl 2)
        io.s8(R.SYS_CFG3_8814A + 2, 0x03)
        io.w8(R.RF_CTRL, RF_ON)
        io.w8(R.RF_CTRL1, RF_ON)
        io.w8(R.RF_CTRL2, RF_ON)
        io.w8(R.RF_CTRL3, RF_ON)
        tbl.load(tbl.array(Rtl8814auRegs.TBL_BB), drv) { a, d -> bbCfg(a, d) }
        tbl.load(tbl.array(Rtl8814auRegs.TBL_AGC), drv) { a, d -> io.w32(a, d) }
        val cap = crystalCap and 0x3f
        io.m32(R.AFE_CTRL3, 0x07ff8000, cap or (cap shl 6))

        io.c32(R.CCK0_FAREPORT, (1 shl 18) or (1 shl 22))
        io.m32(R.CCK_RX, 0xf0000000.toInt(), 0x4)
        io.m32(R.CCK_RX, 0x0f000000, 0x5)

        for (path in 0 until 4) {
            tbl.load(tbl.array(Rtl8814auRegs.TBL_RF[path]), drv) { a, d -> rfCfg(path, a, d) }
        }
        val rck = rfRead(0, R.RF_RCK1_V1, R.RFREG_MASK)
        for (path in 1 until 4) rfWrite(path, R.RF_RCK1_V1, R.RFREG_MASK, rck)

        io.s32(R.RXPSEL, RX_PSEL_RST)
        io.w8(R.HWSEQ_CTRL, 0xff)
        io.w32(R.BAR_MODE_CTRL, 0x0201ffff)
        io.w8(R.MISC_CTRL, 0x03)
        io.w8(R.NAV_CTRL + 2, 0)
        io.c8(R.GPIO_MUXCFG, 1 shl 5)

        io.m32(R.RXSB, 1 shl 15, 0)
        io.m32(R.CCA, 1 shl 7, 0)
        io.m32(R.ANTSEL, 1 shl 8, 0)
        io.m32(R.PRECTRL, 1 shl 7, 0)
        io.m32(R.CCA_MF, 0x30, 1)
        io.m32(R.CCKTX, 1 shl 28, 1)

        if (rfe == 2 || rfe == 1) {
            io.m32(R.RFESEL_1994, 0xf, 0xf)
            io.s8(R.GPIO_MUXCFG + 2, 0xf0)
        } else if (rfe == 0) {
            io.m32(R.RFESEL_1994, 0xf, 0xf)
            io.s8(R.GPIO_MUXCFG + 2, 0xc0)
        }
        io.c8(R.QUEUE_CTRL, 1 shl 3)
        io.w8(R.NAV_CTRL + 2, 235)
        io.w8(R.FWHW_TXQ_CTRL + 1, 0x1f)
        io.w8(R.SYS_SDIO_CTRL, 0)
        io.w8(R.ACLK_MON, 0)
    }

    private fun bbCfg(addr: Int, data: Int) {
        when (addr) {
            0xfe -> sleep(50)
            0xfd -> sleep(5)
            0xfc, 0xfb, 0xfa, 0xf9 -> sleep(1)
            else -> io.w32(addr, data)
        }
    }

    private fun rfCfg(path: Int, addr: Int, data: Int) {
        if (addr == 0xffe) sleep(50) else if (addr == 0xfe) sleep(1) else rfWrite(path, addr, R.RFREG_MASK, data)
    }

    private fun rfRead(path: Int, addr: Int, mask: Int): Int =
        io.rm32(Rtl8814auRegs.RF_BASE[path] + ((addr and 0xff) shl 2), mask and R.RFREG_MASK)

    private fun rfWrite(path: Int, addr: Int, mask: Int, data: Int) {
        val a = addr and 0xff
        val m = mask and R.RFREG_MASK
        var d = data
        if (m != R.RFREG_MASK) {
            val old = rfRead(path, a, R.RFREG_MASK)
            d = (old and m.inv()) or (data shl Integer.numberOfTrailingZeros(m))
        }
        io.w32(Rtl8814auRegs.LSSI_WRITE[path], ((a shl 20) or (d and 0xfffff)) and 0x0fffffff)
    }

    private fun setChannel(ch: Int) {
        val oldIs5g = (io.r8(R.CCK_CHECK) and (1 shl 7)) != 0
        val newIs5g = ch > 14
        if (oldIs5g != newIs5g) switchBand(newIs5g)
        switchChannel(ch)
        cck24gTxDfir(ch)
        setBwMode(ch)
    }

    private fun switchBand(is5g: Boolean) {
        io.c8(R.SYS_CFG3_8814A + 2, 1)
        if (!is5g) {
            io.m32(R.AGC_TABLE, 0x1f, 0)
            setRfeReg24g()
            io.m32(R.TXPSEL, 0xf0, 0x2)
            io.m32(R.CCK_RX, 0x0f000000, 0x5)
            io.m32(R.RXPSEL, RX_PSEL_RST, 0x3)
            io.w8(R.CCK_CHECK, 0)
            io.m32(R.CCK_A80, 1 shl 18, 0)
        } else {
            io.w8(R.CCK_CHECK, 1 shl 7)
            io.m32(R.CCK_A80, 1 shl 18, 1)
            setRfeReg5g()
            io.m32(R.TXPSEL, 0xf0, 0x0)
            io.m32(R.CCK_RX, 0x0f000000, 0xf)
            io.m32(R.RXPSEL, RX_PSEL_RST, 0x2)
        }
        io.m32(R.ADCCLK, 0x3, 0)
        io.m32(R.CCASEL, 0xf000, 6)
        io.s8(R.SYS_CFG3_8814A + 2, 1)
    }

    private fun setRfeReg24g() {
        when (rfe) {
            2 -> {
                io.w32(R.RFE_PINMUX_A, 0x72707270)
                io.w32(R.RFE_PINMUX_B, 0x72707270)
                io.w32(R.RFE_PINMUX_C, 0x72707270)
                io.w32(R.RFE_PINMUX_D, 0x77707770)
                io.m32(R.RFE_INVSEL_D, RFE_SELSW0_D, 0x72)
            }
            1 -> {
                io.w32(R.RFE_PINMUX_A, 0x77777777)
                io.w32(R.RFE_PINMUX_B, 0x77777777)
                io.w32(R.RFE_PINMUX_C, 0x77777777)
                io.w32(R.RFE_PINMUX_D, 0x77777777)
                io.m32(R.RFE_INVSEL_D, RFE_SELSW0_D, 0x77)
            }
            else -> {
                io.w32(R.RFE_PINMUX_A, 0x77777777)
                io.w32(R.RFE_PINMUX_B, 0x77777777)
                io.w32(R.RFE_PINMUX_C, 0x77777777)
                io.m32(R.RFE_INVSEL_D, RFE_SELSW0_D, 0x77)
            }
        }
    }

    private fun setRfeReg5g() {
        when (rfe) {
            2 -> {
                io.w32(R.RFE_PINMUX_A, 0x37173717)
                io.w32(R.RFE_PINMUX_B, 0x37173717)
                io.w32(R.RFE_PINMUX_C, 0x37173717)
                io.w32(R.RFE_PINMUX_D, 0x77177717)
                io.m32(R.RFE_INVSEL_D, RFE_SELSW0_D, 0x37)
            }
            1 -> {
                io.w32(R.RFE_PINMUX_A, 0x33173317)
                io.w32(R.RFE_PINMUX_B, 0x33173317)
                io.w32(R.RFE_PINMUX_C, 0x33173317)
                io.w32(R.RFE_PINMUX_D, 0x77177717)
                io.m32(R.RFE_INVSEL_D, RFE_SELSW0_D, 0x33)
            }
            else -> {
                io.w32(R.RFE_PINMUX_A, 0x54775477)
                io.w32(R.RFE_PINMUX_B, 0x54775477)
                io.w32(R.RFE_PINMUX_C, 0x54775477)
                io.w32(R.RFE_PINMUX_D, 0x54775477)
                io.m32(R.RFE_INVSEL_D, RFE_SELSW0_D, 0x54)
            }
        }
    }

    private fun switchChannel(ch: Int) {
        val fcArea = when {
            ch in 36..48 -> 0x494
            ch in 50..64 -> 0x453
            ch in 100..116 -> 0x452
            ch >= 118 -> 0x412
            else -> 0x96a
        }
        io.m32(R.CLKTRK, 0x1ffe0000, fcArea)
        val rfModAg = when {
            ch in 36..64 -> 0x101
            ch in 100..140 -> 0x301
            ch > 140 -> 0x501
            else -> 0x000
        }
        val mask = R.RF18_RFSI_MASK or R.RF18_BAND_MASK or R.RF18_CHANNEL_MASK
        for (path in 0 until 4) rfWrite(path, R.RF_CFGCH, mask, (rfModAg shl 8) or ch)
        when {
            ch in 36..64 -> io.m32(R.AGC_TABLE, 0x1f, 1)
            ch in 100..144 -> io.m32(R.AGC_TABLE, 0x1f, 2)
            ch >= 149 -> io.m32(R.AGC_TABLE, 0x1f, 3)
        }
    }

    private fun cck24gTxDfir(ch: Int) {
        if (ch in 1..11) {
            io.w32(R.CCK0_TX_FILTER1, 0x1a1b0030)
            io.w32(R.CCK0_TX_FILTER2, 0x090e1317)
            io.w32(R.CCK0_DEBUG_PORT, 0x00000204)
        } else if (ch in 12..13) {
            io.w32(R.CCK0_TX_FILTER1, 0x1a1b0030)
            io.w32(R.CCK0_TX_FILTER2, 0x090e1217)
            io.w32(R.CCK0_DEBUG_PORT, 0x00000305)
        } else if (ch == 14) {
            io.w32(R.CCK0_TX_FILTER1, 0x1a1b0030)
            io.w32(R.CCK0_TX_FILTER2, 0x00000E17)
            io.w32(R.CCK0_DEBUG_PORT, 0x00000000)
        }
    }

    private fun setBwMode(ch: Int) {
        io.w16(R.WMAC_TRXPTCL_CTL, io.r16(R.WMAC_TRXPTCL_CTL) and ((1 shl 7) or (1 shl 8)).inv())
        io.w8(R.DATA_SC, 0)
        io.m32(R.ADCCLK, 0x3, 0)
        io.m32(R.CCASEL, 0xf000, 6)
        for (path in 0 until 4) rfWrite(path, R.RF_CFGCH, R.RF18_BW_MASK, 3)
        adcClk()
        spurCalibration(ch)
    }

    private fun adcClk() {
        if (cut != 0) return
        val txPause = io.r8(R.TXPAUSE)
        val dbgSel = io.r32(R.DBGSEL)
        val rxpsel = io.r32(R.RXPSEL)
        io.w8(R.TXPAUSE, 0x3f)
        val rxiqc = IntArray(4)
        for (i in 0 until 4) {
            rxiqc[i] = io.r32(Rtl8814auRegs.RX_IQC_AB[i])
            io.w32(Rtl8814auRegs.RX_IQC_AB[i], 0)
            io.w32(Rtl8814auRegs.RX_IQC_CD[i], 0)
        }
        io.m32(R.PRECTRL, 0x300, 0x3)
        io.w32(R.DBGSEL, 0)
        var active = 1
        var n = 0
        while (active != 0 && n++ <= 1000) active = io.r32(R.DBGRPT) and 0x803e0008.toInt()

        io.w8(R.RXPSEL, 0x11)
        io.m32(R.DAC_RSTB, 1 shl 13, 1)
        io.m8(R.GNT_BT, 0x06, 0x3)
        io.m32(R.CCK_RPT_FORMAT, 1 shl 2, 1)
        for (p in Rtl8814auRegs.AFE_PWR1) {
            io.w32(p, 0x15800002)
            io.w32(p, 0x01808003)
        }
        io.m8(R.GNT_BT, 0x04, 0)
        io.m32(R.CCK_RPT_FORMAT, 1 shl 2, 0)
        for (p in Rtl8814auRegs.CK_MONH) io.w32(p, 0x0D080058)
        for (p in Rtl8814auRegs.CK_MONH) io.w32(p, 0x0D000058)
        for (p in Rtl8814auRegs.AFE_PWR1) io.w32(p, 0x05808032)
        io.m8(R.GNT_BT, 0x04, 1)
        io.m32(R.CCK_RPT_FORMAT, 1 shl 2, 1)
        for (p in Rtl8814auRegs.AFE_PWR1) io.w32(p, 0x05808032)
        for (p in Rtl8814auRegs.AFE_PWR1) {
            io.w32(p, 0x05800002)
            io.w32(p, 0x07808003)
        }
        io.m8(R.GNT_BT, 0x06, 0)
        io.m32(R.CCK_RPT_FORMAT, 1 shl 2, 0)
        io.m32(R.DAC_RSTB, 1 shl 13, 0)

        io.w8(R.TXPAUSE, txPause)
        io.w32(R.DBGSEL, dbgSel)
        io.w32(R.RXPSEL, rxpsel)
        for (i in 0 until 4) {
            io.w32(Rtl8814auRegs.RX_IQC_AB[i], rxiqc[i])
            io.w32(Rtl8814auRegs.RX_IQC_CD[i], 0x01000000)
        }
        io.m32(R.PRECTRL, 0x300, 0x0)
    }

    private fun spurCalibration(ch: Int) {
        var reset = true
        if (rfe == 0 || rfe == 1 || rfe == 2) {
            if (ch == 153) {
                io.m32(R.NBI_SETTING, 0x000fe000, 0x1e shr 1)
                io.m32(R.CSI_MASK_SETTING1, 1, 1)
                io.w32(R.CSI_FIX_MASK0, 0)
                io.w32(R.CSI_FIX_MASK1, 0)
                io.w32(R.CSI_FIX_MASK6, 0)
                io.m32(R.CSI_FIX_MASK7, 1 shl 16, 1)
                reset = false
            }
            if (rfe == 0) spurCh140(ch)
        }
        if (reset) {
            io.m32(R.NBI_SETTING, 0x000fe000, 0xfc shr 1)
            io.m32(R.CSI_MASK_SETTING1, 1, 0)
            io.w32(R.CSI_FIX_MASK0, 0)
            io.w32(R.CSI_FIX_MASK1, 0)
            io.w32(R.CSI_FIX_MASK6, 0)
            io.w32(R.CSI_FIX_MASK7, 0)
        }
        spurNbi(ch)
    }

    private fun spurCh140(ch: Int) {
        if (ch == 140) {
            if (chParam0 == 0) chParam0 = io.r32(R.CCASEL)
            if (chParam1 == 0) chParam1 = io.r32(R.PDMFTH)
            io.w32(R.CCASEL, 0x75438170)
            io.w32(R.PDMFTH, 0x79a18a0a)
        } else {
            if (io.r32(R.CCASEL) == 0x75438170 && chParam0 != 0) io.w32(R.CCASEL, chParam0)
            if (io.r32(R.PDMFTH) == 0x79a18a0a && chParam1 != 0) io.w32(R.PDMFTH, chParam1)
            chParam0 = io.r32(R.CCASEL)
            chParam1 = io.r32(R.PDMFTH)
        }
    }

    private fun spurNbi(ch: Int) {
        if (rfe != 0 && rfe != 1 && rfe != 6 && rfe != 7) return
        if (ch == 14) {
            nbiSetting(ch, 2480)
        } else if (ch in 4..8) {
            nbiSetting(ch, 2440)
        } else {
            io.m32(R.NBI_SETTING, 1 shl 13, 0)
        }
    }

    private fun nbiSetting(ch: Int, fIntf: Int) {
        val fc = 2412 + (ch - 1) * 5
        val toneIdx = Math.abs(fc - fIntf) shl 5
        var idx = 0
        for (i in NBI_128.indices) {
            if (toneIdx < NBI_128[i]) {
                idx = i + 1
                break
            }
        }
        io.m32(R.NBI_SETTING, 0xfc000, idx)
        io.m32(R.NBI_SETTING, 1 shl 13, 1)
    }

    private class Entry(var ssid: String?, var rssi: Int, var channel: Int, var lastSeen: Long, var isAp: Boolean, var auth: Int = 0)

    private val table = LinkedHashMap<String, Entry>()
    private var hopIdx = 0
    private var hopAt = 0L
    private var emitAt = 0L
    private var exploreAt = 0L
    private var lastRxAt = 0L
    private var rxBufs = 0L

    private fun rxLoop(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val buffers = Array(NBUF) { ByteBuffer.allocateDirect(BUF_SZ) }
        val reqs = ArrayList<UsbRequest>(NBUF)
        var ok = true
        for (i in 0 until NBUF) {
            val r = UsbRequest()
            if (!r.initialize(conn, epRx)) { ok = false; break }
            r.clientData = i
            buffers[i].clear()
            if (!r.queue(buffers[i])) { ok = false; break }
            reqs.add(r)
        }
        val start = System.currentTimeMillis()
        hopAt = start; emitAt = start; exploreAt = start; lastRxAt = start
        if (!ok) {
            reqs.forEach { runCatching { it.cancel() }; runCatching { it.close() } }
            rxLoopSync(onBatch)
            return
        }
        val scratch = ByteArray(BUF_SZ)
        try {
            while (!stop) {
                val req = try { conn.requestWait(100L) } catch (e: TimeoutException) { null }
                val now = System.currentTimeMillis()
                if (req != null) {
                    val idx = req.clientData as? Int ?: -1
                    if (idx in 0 until NBUF) {
                        val b = buffers[idx]
                        val n = b.position()
                        if (n in 1..BUF_SZ) {
                            rxBufs++
                            lastRxAt = now
                            b.rewind(); b.get(scratch, 0, n)
                            runCatching { parseRx(scratch, n, Mt76Regs.CHANNELS[hopIdx]) }
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
                rxTick(now, onBatch)
            }
        } finally {
            reqs.forEach { runCatching { it.cancel() }; runCatching { it.close() } }
        }
        emit(onBatch)
    }

    private fun rxLoopSync(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val buf = ByteArray(BUF_SZ)
        while (!stop) {
            val n = conn.bulkTransfer(epRx, buf, buf.size, 500)
            val now = System.currentTimeMillis()
            if (n > 0) {
                rxBufs++
                lastRxAt = now
                runCatching { parseRx(buf, n, Mt76Regs.CHANNELS[hopIdx]) }
            }
            rxTick(now, onBatch)
        }
        emit(onBatch)
    }

    private fun rxTick(now: Long, onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        if (now - lastRxAt > REKICK_MS) {
            runCatching { reKickRx() }
            lastRxAt = now
        }
        if (now - emitAt > EMIT_MS) { emit(onBatch); emitAt = now }
        if (now - hopAt > DWELL_MS) {
            val chs = Mt76Regs.CHANNELS
            val active = table.values.mapTo(HashSet()) { it.channel }
            val explore = now - exploreAt > Mt7612uAdapter.EXPLORE_MS
            var nx = (hopIdx + 1) % chs.size
            if (active.isNotEmpty() && !explore) {
                var s = 0
                while (s < chs.size && chs[nx] !in active) { nx = (nx + 1) % chs.size; s++ }
            } else if (explore) {
                exploreAt = now
            }
            hopIdx = nx
            runCatching { setChannel(chs[hopIdx]) }
            hopAt = now
        }
    }

    // unverified: RX re-arm toggles CR RXDMA_EN + MACRXEN (bit positions from Rtl8812auRegs) after a silent window, no reference app does this on RTL
    private fun reKickRx() {
        val cr = io.r16(R.CR)
        io.w16(R.CR, cr and (CR_RXDMA_EN or CR_MACRXEN).inv())
        io.w16(R.CR, cr or CR_RXDMA_EN or CR_MACRXEN)
    }

    private fun parseRx(b: ByteArray, n: Int, hopCh: Int) {
        val desc = R.RX_DESC_SIZE
        var p = 0
        while (p + desc <= n) {
            val w0 = le32(b, p)
            val w2 = le32(b, p + 8)
            val w3 = le32(b, p + 12)
            val pktLen = w0 and 0x3fff
            val drvRaw = (w0 ushr 16) and 0xf
            val shift = (w0 ushr 24) and 3
            val rate = w3 and 0x7f
            val c2h = ((w2 ushr 28) and 1) != 0
            if (rate >= RATE_MAX || (drvRaw != 0 && drvRaw != R.PHY_STATUS_SIZE) || pktLen > MAX_MPDU) return
            val total = desc + drvRaw * 8 + shift + pktLen
            if (p + total > n || (!c2h && pktLen <= FCS_LEN)) return
            val bad = (w0 and ((1 shl 14) or (1 shl 15))) != 0
            if (!c2h && !bad) {
                val drv = drvRaw * 8
                val physt = ((w0 ushr 26) and 1) != 0 && drv >= PHY_STATUS_BYTES
                val rssi = if (physt) phyPower(b, p + desc, rate).coerceIn(-120, -20) else -100
                frame(b, p + desc + drv + shift, pktLen - FCS_LEN, rssi, hopCh)
            }
            p += (total + 7) and 7.inv()
        }
    }

    private fun frame(b: ByteArray, d: Int, len: Int, rssi: Int, ch: Int) {
        if (len < 10) return
        val end = d + len
        fun u8(i: Int) = b[i].toInt() and 0xff
        fun macAt(off: Int) = (0 until 6).joinToString(":") { "%02x".format(u8(off + it)) }
        fun group(off: Int) = u8(off) and 1 != 0
        val fc = u8(d)
        val type = (fc shr 2) and 3
        val sub = (fc shr 4) and 0xf
        val toDs = len > 1 && u8(d + 1) and 1 != 0
        val fromDs = len > 1 && u8(d + 1) and 2 != 0
        fun touch(mac: String, isAp: Boolean, ssid: String?, chan: Int, auth: Int = 0) {
            if (mac == "ff:ff:ff:ff:ff:ff" || mac == "00:00:00:00:00:00") return
            if (mac.startsWith("01:00:5e") || mac.startsWith("33:33") || mac.startsWith("01:80:c2")) return
            val e = table.getOrPut(mac) { Entry(null, rssi, chan, 0, isAp) }
            e.isAp = e.isAp || isAp
            if (!ssid.isNullOrEmpty()) e.ssid = ssid
            if (rssi > e.rssi) e.rssi = rssi
            if (auth > e.auth) e.auth = auth
            e.channel = chan
            e.lastSeen = System.currentTimeMillis()
        }
        when (type) {
            0 -> when (sub) {
                8, 5 -> if (len >= 36) {
                    val ds = beaconChannel(b, d + 36, end)
                    val cap = u8(d + 34) or (u8(d + 35) shl 8)
                    val auth = wifiAuthMode(b, d + 36, end, cap and 0x10 != 0)
                    touch(macAt(d + 16), true, readSsid(b, d + 36, end), if (ds in 1..196) ds else ch, auth)
                }
                4, 0, 1, 2, 3, 10, 11, 12 -> if (len >= 16) touch(macAt(d + 10), false, null, ch)
            }
            2 -> if (len >= 24) when {
                toDs && !fromDs -> { if (!group(d + 4)) touch(macAt(d + 4), true, null, ch); touch(macAt(d + 10), false, null, ch) }
                !toDs && fromDs -> { if (!group(d + 10)) touch(macAt(d + 10), true, null, ch); touch(macAt(d + 4), false, null, ch) }
                !toDs && !fromDs -> { if (!group(d + 16)) touch(macAt(d + 16), true, null, ch); touch(macAt(d + 10), false, null, ch) }
                else -> touch(macAt(d + 10), false, null, ch)
            }
            1 -> if (len >= 16 && (sub == 11 || sub == 10)) touch(macAt(d + 10), false, null, ch)
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

    private fun beaconChannel(b: ByteArray, from: Int, end: Int): Int {
        var i = from
        while (i + 2 <= end) {
            val tag = b[i].toInt() and 0xff
            val tl = b[i + 1].toInt() and 0xff
            if (i + 2 + tl > end) break
            if ((tag == 3 || tag == 61) && tl >= 1) return b[i + 2].toInt() and 0xff
            i += 2 + tl
        }
        return 0
    }

    private fun emit(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val now = System.currentTimeMillis()
        val batch = table.entries
            .filter { now - it.value.lastSeen < FRESH_MS }
            .map { (mac, e) -> Mt7612uAdapter.ApSighting(mac, e.ssid, e.rssi, e.channel, Mt76Regs.freqOf(e.channel), client = !e.isAp, authMode = e.auth) }
        table.entries.removeAll { now - it.value.lastSeen > EXPIRE_MS }
        if (batch.isNotEmpty()) onBatch(batch)
    }

    private fun phyPower(b: ByteArray, o: Int, rate: Int): Int {
        val w0 = le32(b, o)
        val w1 = le32(b, o + 4)
        if (rate <= RATE_11M) return cckRxPower((w1 ushr 13) and 7, (w1 ushr 8) and 0x1f)
        val ga = w0 and 0x7f
        val gb = (w0 ushr 8) and 0x7f
        val gc = (le32(b, o + 20) ushr 24) and 0x7f
        val gd = le32(b, o + 24) and 0x7f
        val middle1 = maxOf(minOf(ga, gb), minOf(gc, gd))
        val middle2 = minOf(maxOf(ga, gb), maxOf(gc, gd))
        return minOf(middle1, middle2) - 110
    }

    private fun cckRxPower(lna: Int, vga: Int): Int {
        val base = when (lna) {
            7 -> -38
            5 -> -28
            3 -> -8
            2 -> -1
            else -> return -100
        }
        return base - 2 * vga
    }

    companion object {
        private const val MAC_TRX_ENABLE = 0xFF
        private const val RF_ON = 0x07
        private const val RX_PSEL_RST = (1 shl 28) or (1 shl 29)
        private const val RFE_SELSW0_D = 0x0ff00000
        private const val RATE_11M = 3
        private const val DWELL_MS = RtlRx.DWELL_MS
        private const val EMIT_MS = 2000L
        private const val FRESH_MS = 8000L
        private const val EXPIRE_MS = 60_000L
        private const val REKICK_MS = 4000L
        private const val NBUF = 8
        private const val BUF_SZ = 16384
        private const val RATE_MAX = 0x54
        private const val MAX_MPDU = 11454
        private const val FCS_LEN = 4
        private const val PHY_STATUS_BYTES = 28
        private const val CR_RXDMA_EN = 1 shl 3
        private const val CR_MACRXEN = 1 shl 7
        private const val DIG_MAX_COVERAGE = 0x1c
        private const val TX_QSEL_BEACON = 16
        private const val BIT_DIS_TSF_UDT = 1 shl 4
        private const val BIT_EN_BCN_FUNCTION = 1 shl 3
        private const val WLAN_TBTT_TIME = 0x04 or (0x064 shl 8)
        private val NBI_128 = intArrayOf(
            25, 55, 85, 115, 135, 155, 185, 205, 225, 245, 265, 285, 305, 335, 355,
            375, 395, 415, 435, 455, 485, 505, 525, 555, 585, 615, 635,
        )
    }
}

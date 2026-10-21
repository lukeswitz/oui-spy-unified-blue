package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import com.rootdowndigital.ouispy.wifiadapter.Rtl88Regs as R
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.le32
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.sleep
import java.io.IOException

// Passive RTL8821AU/RTL8811AU monitor receiver ported from Linux rtw88 (SPDX GPL-2.0 OR BSD-3-Clause): receive only, never transmits.
internal class Rtl8821auAdapter(
    private val conn: UsbDeviceConnection,
    private val intf: UsbInterface,
    private val fw: RtlFirmwareStore.Blobs,
    private val log: (String) -> Unit,
) {
    @Volatile private var stop = false
    private val io = RtlIo(conn)
    private lateinit var epRx: UsbEndpoint
    private var bulkOutCount = 0
    private var superSpeed = false
    private var cut = 0
    private var btcoex = false
    private var extLna2g = false
    private var extPa2g = false
    private var extLna5g = false
    private var extPa5g = false
    private var crystalCap = 0
    private var rsvdBoundary = 0
    private var accessed = false

    fun abort() {
        stop = true
        io.canceled = true
    }

    fun run(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        conn.claimInterface(intf, true)
        if (!findEndpoints()) throw IllegalStateException("RTL8821AU: bulk endpoints not found")
        try {
            bringUp()
            log("RTL8821AU: receiver live")
            RtlRx(conn, epRx, ::phyPower, ::setChannel, { stop }).run(Mt76Regs.CHANNELS, onBatch)
        } finally {
            if (accessed) powerDown()
        }
    }

    private fun findEndpoints(): Boolean {
        var rx: UsbEndpoint? = null
        var outs = 0
        for (i in 0 until intf.endpointCount) {
            val ep = intf.getEndpoint(i)
            if (ep.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
            if (ep.direction == UsbConstants.USB_DIR_IN) {
                if (rx == null) rx = ep
            } else {
                outs++
            }
        }
        val r = rx ?: return false
        if (outs < 2) return false
        epRx = r
        bulkOutCount = minOf(outs, 4)
        // unverified: USB speed is inferred from the bulk-in max packet size
        superSpeed = r.maxPacketSize >= 1024
        return true
    }

    private fun powerDown() {
        io.canceled = false
        try {
            io.w8(R.CR, 0)
            runPwrSeq(io, Rtl8821auRegs.PWR_OFF)
        } catch (e: IOException) {
            log("RTL8821AU: power-down skipped: ${e.message}")
        } catch (e: IllegalStateException) {
            log("RTL8821AU: power-down incomplete: ${e.message}")
        }
    }

    private fun bringUp() {
        accessed = true
        val ver = io.r32(R.SYS_CFG1)
        cut = (ver ushr 12) and 0xf
        btcoex = io.rm32(R.WL_BT_PWR_CTRL, 1 shl 18) != 0
        log("RTL8821AU: chip cut $cut")
        hwReset()
        preSystemCfg()
        runPwrSeq(io, Rtl8821auRegs.PWR_ON)
        io.w16(R.CR, 0)
        io.s16(R.CR, MAC_TRX_INIT)
        if ((io.r8(R.SYS_CFG1 + 3) and 1) != 0) io.s8(R.LDO_SWR_CTRL, 1 shl 6)
        // unverified: efuse is read right after the power sequence, rtw88 reads it in a separate power cycle
        parseEfuse(RtlEfuse.dump(io, Rtl8821auRegs.PHY_EFUSE_SIZE, Rtl8821auRegs.LOG_EFUSE_SIZE))

        val txffPg = Rtl8821auRegs.TXFF_SIZE / Rtl8821auRegs.PAGE_SIZE
        val acqPg = txffPg - Rtl8821auRegs.RSVD_DRV_PG
        rsvdBoundary = acqPg
        lltInit(rsvdBoundary)
        io.s32(R.TXDMA_OFFSET_CHK, 1 shl 9)
        downloadFirmware()
        log("RTL8821AU: firmware running")
        io.w8(R.HMETFR, 0xf)

        val tbl = RtlPhyTables(fw.tables)
        val drv = phyDrv()
        tbl.load(tbl.array(Rtl8821auRegs.TBL_MAC), drv) { a, d -> io.w8(a, d) }

        initQueueReservedPage(acqPg)
        initTxBufferBoundary()
        initQueuePriority()
        io.w16(R.TRXFF_BNDY + 2, Rtl8821auRegs.RXFF_SIZE - R.REPORT_BUF - 1)
        io.w8(R.RX_DRVINFO_SZ, R.PHY_STATUS_SIZE)
        io.w32(R.HIMR0, 0)
        io.w32(R.HIMR1, 0)
        io.m32(R.CR, 0x30000, 0x2)
        initWmacSetting()
        io.m32(R.RRSR, 0xfffff, 0xffff1)
        io.w16(R.RETRY_LIMIT, 0x3030)
        initEdca()
        io.s8(R.FWHW_TXQ_CTRL, 1 shl 7)
        io.w8(R.ACKTO, 0x80)
        io.m32(R.DWBCN0_CTRL, 0xf0, Rtl8821auRegs.USB_TX_AGG_DESC_NUM)
        io.w8(R.DWBCN1_CTRL, Rtl8821auRegs.USB_TX_AGG_DESC_NUM shl 1)
        initBeaconParameters()
        io.w8(R.BCN_MAX_ERR, 0xff)
        initBurstLen()
        io.w8(R.USB3_RXITV, 0x01)
        io.w16(R.RXDMA_STATUS, 0x7400)
        io.w8(R.RXDMA_STATUS + 1, 0xf5)
        io.w8(R.AMPDU_MAX_TIME, 0x5e)
        io.w32(R.AMPDU_MAX_LENGTH, -1)
        io.w8(R.USTIME_TSF, 0x50)
        io.w8(R.USTIME_EDCA, 0x50)
        if (superSpeed) io.c8(R.USB_MOD, (1 shl 4) or (1 shl 3))
        io.s8(R.SINGLE_AMPDU_CTRL, 1 shl 7)
        io.w8(R.RX_PKT_LIMIT, 0x18)
        io.w8(R.PIFS, 0x00)
        io.w16(R.MAX_AGGR_NUM, 0x1f1f)
        io.w8(R.FWHW_TXQ_CTRL, 0x80)
        io.w32(R.FAST_EDCA_CTRL, 0x03087777)
        io.s8(R.RSV_CTRL, (1 shl 5) or (1 shl 6))
        io.s8(R.CR, (1 shl 6) or (1 shl 7))

        phyBbConfig(tbl, drv)
        tbl.load(tbl.array(Rtl8821auRegs.TBL_RF_A), drv) { a, d -> rfCfg(a, d) }
        switchBand(false)

        io.w8(R.HWSEQ_CTRL, 0xff)
        io.w32(R.BAR_MODE_CTRL, 0x0201ffff)
        io.w8(R.NAV_CTRL + 2, 0)
        io.c8(R.GPIO_MUXCFG, 1 shl 5)
        io.c8(R.QUEUE_CTRL, 1 shl 3)
        io.w8(R.FWHW_TXQ_CTRL + 1, 0x0f)
        io.w8(R.EARLY_MODE_CONTROL + 3, 0x01)
        io.w16(R.TX_RPT_TIME, 0x3df0)
        io.w8(R.SYS_SDIO_CTRL, 0)
        io.w8(R.ACLK_MON, 0)
        io.w8(R.USB_HRPWM, 0)
        io.s32(R.FWHW_TXQ_CTRL, 1 shl 12)

        // unverified: security CAM clear, IQK/LCK calibration and TX power setup from rtw88 are not performed
        io.w32(R.RCR, R.RCR_MONITOR)
        io.m32(R.RXIGI_A, 0x7f, DIG_MAX_COVERAGE)
        setChannel(Mt76Regs.CHANNELS[0])
    }

    private fun phyDrv(): PhyDrv {
        var rfe = 0
        if (extLna2g) rfe = rfe or 1
        if (extPa2g) rfe = rfe or 2
        if (extLna5g) rfe = rfe or 4
        if (extPa5g) rfe = rfe or 8
        if (btcoex) rfe = rfe or 16
        return PhyDrv(if (cut == 0) 15 else cut, rfe, true)
    }

    private fun rfCfg(addr: Int, data: Int) {
        if (addr == 0xffe) sleep(50) else if (addr == 0xfe) sleep(1) else rfWrite(0, addr, R.RFREG_MASK, data)
    }

    private fun parseEfuse(ee: ByteArray) {
        fun b(i: Int) = ee[i].toInt() and 0xff
        crystalCap = if (b(Rtl8821auRegs.EE_XTAL_K) == 0xff) 0x20 else b(Rtl8821auRegs.EE_XTAL_K)
        val pa = b(Rtl8821auRegs.EE_PA_TYPE).let { if (it == 0xff) 0 else it }
        val lna2 = b(Rtl8821auRegs.EE_LNA_2G).let { if (it == 0xff) 0 else it }
        val lna5 = b(Rtl8821auRegs.EE_LNA_5G).let { if (it == 0xff) 0 else it }
        extPa2g = (pa and 0x10) != 0
        extLna2g = (lna2 and 0x08) != 0
        extPa5g = (pa and 0x01) != 0
        extLna5g = (lna5 and 0x08) != 0
    }

    private fun hwReset() {
        if ((io.r8(R.MCUFW_CTRL) and (1 shl 7)) == 0) return
        reset8051()
        io.w8(R.MCUFW_CTRL, 0x00)
        io.s32(R.FPGA0_XCD_RF_PARA, 1 shl 6)
        io.c8(R.SYS_FUNC_EN, 0x03)
        io.w8(R.RF_CTRL, 0)
        io.w16(R.CR, 0)
        io.s8(R.APS_FSMCO + 1, 1 shl 1)
        var v = io.r8(R.APS_FSMCO + 1)
        var tries = 0
        while ((v and (1 shl 1)) != 0 && tries++ < 5000) v = io.r8(R.APS_FSMCO + 1)
        io.w8(R.APS_FSMCO + 1, v or 1)
        io.c8(R.SYS_FUNC_EN + 1, (1 shl 4) or (1 shl 7))
        io.s8(R.SYS_FUNC_EN + 1, (1 shl 4) or (1 shl 7))
    }

    private fun reset8051() {
        io.c8(R.RSV_CTRL, 1 shl 1)
        io.c8(R.RSV_CTRL + 1, 1 shl 0)
        val v = io.r8(R.SYS_FUNC_EN + 1)
        io.w8(R.SYS_FUNC_EN + 1, v and (1 shl 2).inv())
        io.c8(R.RSV_CTRL, 1 shl 1)
        io.s8(R.RSV_CTRL + 1, 1 shl 0)
        io.w8(R.SYS_FUNC_EN + 1, v or (1 shl 2))
    }

    // unverified: kernel runs this only in the probe-time efuse path, not in rtw88xxa_power_on
    private fun preSystemCfg() {
        io.w8(R.RSV_CTRL, 0)
        val ldo = (io.r32(R.SYS_CFG1) and (1 shl 24)) != 0
        io.w8(R.LDO_SWR_CTRL, if (ldo) LDO_SEL else SPS_SEL)
    }

    private fun lltWrite(addr: Int, data: Int) {
        io.w32(R.LLT_INIT, (1 shl 30) or (addr shl 8) or data)
        var n = 0
        while (io.rm32(R.LLT_INIT, (1 shl 31) or (1 shl 30)) != 0) {
            if (++n > 20) throw IllegalStateException("RTL8821AU: LLT write timeout at $addr")
        }
    }

    private fun lltInit(boundary: Int) {
        for (i in 0 until boundary - 1) lltWrite(i, i + 1)
        lltWrite(boundary - 1, 0xff)
        for (i in boundary until 255) lltWrite(i, i + 1)
        lltWrite(255, boundary)
    }

    private fun downloadFirmware() {
        val f = fw.firmware
        cpuEnable(false)
        cpuEnable(true)
        io.s8(R.MCUFW_CTRL, 1)
        var tries = 0
        while ((io.r8(R.MCUFW_CTRL) and 1) == 0) {
            if (++tries >= 10) throw IllegalStateException("RTL8821AU: firmware download not ready")
            io.s8(R.MCUFW_CTRL, 1)
            sleep(20)
        }
        io.c32(R.MCUFW_CTRL, 1 shl 19)

        val start = Rtl8821auRegs.FW_HDR_LEGACY
        val size = f.size - start
        io.s8(R.MCUFW_CTRL, 1 shl 2)
        val pages = size ushr 12
        for (page in 0 until pages) writeFwPage(page, f, start + (page shl 12), 0x1000)
        val rest = size and 0xfff
        if (rest != 0) writeFwPage(pages, f, start + (pages shl 12), rest)
        if (!io.waitMask(R.MCUFW_CTRL, 1 shl 2, 1)) throw IllegalStateException("RTL8821AU: firmware checksum report failed")
        io.c8(R.MCUFW_CTRL, 1)

        var v = io.r32(R.MCUFW_CTRL)
        v = (v or (1 shl 1)) and (1 shl 6).inv()
        io.w32(R.MCUFW_CTRL, v)
        cpuEnable(false)
        cpuEnable(true)
        for (i in 0 until 10) {
            if ((io.r32(R.MCUFW_CTRL) and FW_READY_LEGACY) == FW_READY_LEGACY) return
            sleep(20)
        }
        throw IllegalStateException("RTL8821AU: firmware failed to start")
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

    private fun writeFwPage(page: Int, data: ByteArray, off: Int, size: Int) {
        io.m32(R.MCUFW_CTRL, 0x70000, page)
        var addr = R.FW_START_ADDR_LEGACY
        var o = off
        var rem = size
        while (rem > 0) {
            val n = if (rem >= Rtl8821auRegs.FW_BLOCK_USB) Rtl8821auRegs.FW_BLOCK_USB else if (rem >= 8) 8 else 1
            io.writeBlock(addr, data, o, n)
            addr += n
            o += n
            rem -= n
        }
    }

    private fun initQueueReservedPage(acqPg: Int) {
        val pg = Rtl8821auRegs.pageTable(bulkOutCount)
        val pub = acqPg - pg[0] - pg[2] - pg[1] - pg[3] - pg[4]
        io.w32(R.RQPN_NPQ, pg[1] or (pg[3] shl 16))
        io.w32(R.RQPN, R.LD_RQPN or pg[0] or (pg[2] shl 8) or (pub shl 16))
    }

    private fun initTxBufferBoundary() {
        io.w8(R.BCNQ_BDNY, rsvdBoundary)
        io.w8(R.MGQ_BDNY, rsvdBoundary)
        io.w8(R.WMAC_LBK_BF_HD, rsvdBoundary)
        io.w8(R.TRXFF_BNDY, rsvdBoundary)
        io.w8(R.DWBCN0_CTRL + 1, rsvdBoundary)
    }

    private fun initQueuePriority() {
        val q = Rtl8821auRegs.rqpn(bulkOutCount)
        var map = io.r16(R.TXDMA_PQ_MAP) and 0x7
        map = map or (q[5] shl 14) or (q[4] shl 12) or (q[3] shl 10) or (q[2] shl 8) or (q[1] shl 6) or (q[0] shl 4)
        io.w16(R.TXDMA_PQ_MAP, map)
        if (bulkOutCount == 4) io.w8(R.HIQ_NO_LMT_EN, 0xff)
    }

    private fun initWmacSetting() {
        io.w16(R.RXFLTMAP0, 0xffff)
        io.w16(R.RXFLTMAP1, 0x0400)
        io.w16(R.RXFLTMAP2, 0xffff)
        io.w32(R.MAR, -1)
        io.w32(R.MAR + 4, -1)
    }

    private fun initEdca() {
        io.w16(R.SPEC_SIFS, 0x100a)
        io.w16(R.MAC_SPEC_SIFS, 0x100a)
        io.w16(R.SIFS, 0x100a)
        io.w16(R.SIFS + 2, 0x100a)
        io.w32(R.EDCA_BE_PARAM, 0x005EA42B)
        io.w32(R.EDCA_BK_PARAM, 0x0000A44F)
        io.w32(R.EDCA_VI_PARAM, 0x005EA324)
        io.w32(R.EDCA_VO_PARAM, 0x002FA226)
        io.w8(R.USTIME_TSF, 0x50)
        io.w8(R.USTIME_EDCA, 0x50)
    }

    private fun initBeaconParameters() {
        var v = (BIT_DIS_TSF_UDT shl 8) or BIT_DIS_TSF_UDT
        if (btcoex) v = v or BIT_EN_BCN_FUNCTION
        io.w16(R.BCN_CTRL, v)
        io.m32(R.TBTT_PROHIBIT, 0xfffff, WLAN_TBTT_TIME)
        io.w8(R.DRVERLYINT, 0x05)
        io.w8(R.BCNDMATIM, 0x02)
        io.w16(R.BCNTCFG, 0x4413)
    }

    private fun initBurstLen() {
        val size = if (superSpeed) 0 else 1
        io.w8(R.RXDMA_MODE, (1 shl 1) or (3 shl 2) or (size shl 4))
        io.s16(R.TXDMA_OFFSET_CHK, 1 shl 9)
    }

    private fun phyBbConfig(tbl: RtlPhyTables, drv: PhyDrv) {
        var v = io.r8(R.SYS_FUNC_EN) or (1 shl 2)
        io.w8(R.SYS_FUNC_EN, v)
        v = v or (1 shl 0) or (1 shl 1)
        io.w8(R.SYS_FUNC_EN, v)
        io.w8(R.RF_CTRL, RF_ON)
        io.w8(R.RF_CTRL3, RF_ON)
        tbl.load(tbl.array(Rtl8821auRegs.TBL_BB), drv) { a, d -> bbCfg(a, d) }
        tbl.load(tbl.array(Rtl8821auRegs.TBL_AGC), drv) { a, d -> io.w32(a, d) }
        val cap = crystalCap and 0x3f
        io.m32(R.AFE_CTRL3, 0x00FFF000, cap or (cap shl 6))
    }

    private fun bbCfg(addr: Int, data: Int) {
        when (addr) {
            0xfe -> sleep(50)
            0xfd -> sleep(5)
            0xfc, 0xfb, 0xfa, 0xf9 -> sleep(1)
            else -> io.w32(addr, data)
        }
    }

    private fun rfRead(path: Int, addr: Int, mask: Int): Int {
        val pi = io.rm32(R.THREEWIRE_SWA, 0x4)
        io.m32(R.HSSI_READ, 0xff, addr and 0xff)
        // unverified: rtw88 waits 20 us for the RF readback, 1 ms is used here
        sleep(1)
        return io.rm32(if (pi != 0) R.PI_READ_A else R.SI_READ_A, mask)
    }

    private fun rfWrite(path: Int, addr: Int, mask: Int, data: Int) {
        val a = addr and 0xff
        val m = mask and R.RFREG_MASK
        var d = data
        if (m != R.RFREG_MASK) {
            val old = rfRead(path, a, R.RFREG_MASK)
            d = (old and m.inv()) or (data shl Integer.numberOfTrailingZeros(m))
        }
        io.w32(Rtl8821auRegs.LSSI_WRITE[path], ((a shl 20) or (d and 0xfffff)) and 0x0fffffff)
    }

    private fun setChannel(ch: Int) {
        val oldIs5g = (io.r8(R.CCK_CHECK) and (1 shl 7)) != 0
        val newIs5g = ch > 14
        if (oldIs5g != newIs5g) switchBand(newIs5g)
        switchChannel(ch)
        postSetBwMode()
        rfWrite(0, R.RF_CFGCH, R.RF18_BW_MASK, 3)
    }

    private fun switchBand(is5g: Boolean) {
        if (!btcoex) setExtBandSwitch(is5g)
        if (!is5g) {
            io.s32(R.RXPSEL, RX_PSEL_RST)
            setRfeReg24g()
            io.m32(R.TXSCALE_A, 0xf00, 0)
            io.m32(R.TXPSEL, 0xf0, 0x1)
            io.m32(R.CCK_RX, 0x0f000000, 0x1)
            io.m32(R.RRSR, 0xfffff, BASIC_RATES_2G)
            io.c8(R.CCK_CHECK, 1 shl 7)
        } else {
            setRfeReg5g()
            io.s8(R.CCK_CHECK, 1 shl 7)
            for (i in 0 until 50) {
                if ((io.r16(R.TXPKT_EMPTY) and 0x30) == 0x30) break
            }
            io.s32(R.RXPSEL, RX_PSEL_RST)
            io.m32(R.TXSCALE_A, 0xf00, 1)
            io.m32(R.TXPSEL, 0xf0, 0)
            io.m32(R.CCK_RX, 0x0f000000, 0xf)
            io.m32(R.RRSR, 0xfffff, BASIC_RATES_5G)
        }
    }

    private fun setExtBandSwitch(is5g: Boolean) {
        io.m32(R.LED_CFG, 1 shl 23, 0)
        io.m32(R.LED_CFG, 1 shl 24, 1)
        io.m32(R.RFE_INV_A, 0xf, 7)
        io.m32(R.RFE_INV_A, 0xf0, 7)
        io.m32(R.RFE_INV_A, (1 shl 29) or (1 shl 28), if (is5g) 2 else 1)
    }

    private fun setRfeReg24g() {
        io.m32(R.RFE_PINMUX_A, 0xf000, 0x7)
        io.m32(R.RFE_PINMUX_A, 0xf0, 0x7)
        if (extLna2g) {
            io.m32(R.RFE_INV_A, 1 shl 20, 1)
            io.m32(R.RFE_INV_A, 1 shl 22, 0)
            io.m32(R.RFE_PINMUX_A, 0x7, 0x2)
            io.m32(R.RFE_PINMUX_A, 0x700, 0x2)
        } else {
            io.m32(R.RFE_INV_A, 1 shl 20, 0)
            io.m32(R.RFE_INV_A, 1 shl 22, 0)
            io.m32(R.RFE_PINMUX_A, 0x7, 0x7)
            io.m32(R.RFE_PINMUX_A, 0x700, 0x7)
        }
    }

    private fun setRfeReg5g() {
        io.m32(R.RFE_PINMUX_A, 0xf000, 0x5)
        io.m32(R.RFE_PINMUX_A, 0xf0, 0x4)
        io.m32(R.RFE_INV_A, 1 shl 20, 0)
        io.m32(R.RFE_INV_A, 1 shl 22, 0)
        io.m32(R.RFE_PINMUX_A, 0x7, 0x7)
        io.m32(R.RFE_PINMUX_A, 0x700, 0x7)
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
        rfWrite(0, R.RF_CFGCH, R.RF18_RFSI_MASK or R.RF18_BAND_MASK, rfModAg)
        rfWrite(0, R.RF_CFGCH, R.RF18_CHANNEL_MASK, ch)
    }

    private fun postSetBwMode() {
        io.w16(R.WMAC_TRXPTCL_CTL, io.r16(R.WMAC_TRXPTCL_CTL) and ((1 shl 7) or (1 shl 8)).inv())
        io.w8(R.DATA_SC, 0)
        io.m32(R.ADCCLK, 0x003003C3, 0x00300200)
        io.m32(R.ADC160, 1 shl 30, 0)
        io.m32(R.L1PKTH, 0x03C00000, 8)
    }

    private fun phyPower(b: ByteArray, o: Int, rate: Int): Int {
        val w0 = le32(b, o)
        val w1 = le32(b, o + 4)
        if (rate <= RATE_11M) return cckRxPower((w1 ushr 13) and 7, (w1 ushr 8) and 0x1f)
        return (w0 and 0x7f) - 110
    }

    private fun cckRxPower(lna: Int, vga: Int): Int {
        val gain = when (lna) {
            5 -> -38
            4 -> -30
            2 -> -17
            1 -> -1
            0 -> 15
            else -> return -100
        }
        return gain - 2 * vga
    }

    companion object {
        private const val MAC_TRX_INIT = 0x63F
        private const val LDO_SEL = 0xC3
        private const val SPS_SEL = 0x83
        private const val FW_READY_LEGACY = 0xC6
        private const val RF_ON = 0x07
        private const val RX_PSEL_RST = (1 shl 28) or (1 shl 29)
        private const val BASIC_RATES_2G = 0x15f
        private const val BASIC_RATES_5G = 0x150
        private const val RATE_11M = 3
        private const val DIG_MAX_COVERAGE = 0x1c
        private const val BIT_DIS_TSF_UDT = 1 shl 4
        private const val BIT_EN_BCN_FUNCTION = 1 shl 3
        private const val WLAN_TBTT_TIME = 0x04 or (0x064 shl 8)
    }
}

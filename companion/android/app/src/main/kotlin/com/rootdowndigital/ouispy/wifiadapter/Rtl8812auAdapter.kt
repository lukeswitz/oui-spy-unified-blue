package com.rootdowndigital.ouispy.wifiadapter

import android.content.Context
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbRequest
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.concurrent.TimeoutException
import com.rootdowndigital.ouispy.wifiadapter.Rtl8812auRegs as Rg
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.le16
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.le32
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.sleep

// Passive RTL8812AU monitor receiver (Alfa AWUS036ACH): receive only, never queues a bulk-out frame.
internal class Rtl8812auAdapter(
    private val conn: UsbDeviceConnection,
    private val intf: UsbInterface,
    private val fw: ByteArray,
    private val log: (String) -> Unit,
) {
    @Volatile private var stop = false
    private lateinit var epRx: UsbEndpoint
    private var bulkOut = 0
    private var superSpeed = false
    private val rb = ByteArray(4)
    private var ioFails = 0

    private var cutVersion = 0
    private var rfPathNum = 2
    private var crystalCap = 0x20
    private var rfeOption = 0
    private var extLna2g = false
    private var btcoex = false
    private var condRfe = 0
    private var condGlna = 0
    private var condGpa = 0
    private var condAlna = 0
    private var condApa = 0
    private var malformed = 0

    fun abort() { stop = true }

    fun run(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        if (!conn.claimInterface(intf, true)) throw IllegalStateException("RTL8812AU: cannot claim interface")
        findEndpoints()
        try {
            bringUp()
            log("RTL8812AU: receiver live")
            rxLoop(onBatch)
        } finally {
            try {
                powerOff()
            } catch (e: IllegalStateException) {
                log("RTL8812AU: power-off skipped: ${e.message}")
            }
            conn.releaseInterface(intf)
        }
    }

    private fun findEndpoints() {
        var rx: UsbEndpoint? = null
        for (i in 0 until intf.endpointCount) {
            val ep = intf.getEndpoint(i)
            if (ep.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
            if (ep.direction == UsbConstants.USB_DIR_IN) {
                if (rx == null) rx = ep
            } else {
                bulkOut++
            }
        }
        epRx = rx ?: throw IllegalStateException("RTL8812AU: bulk-in endpoint not found")
        if (bulkOut !in 2..4) throw IllegalStateException("RTL8812AU: unsupported bulk-out count $bulkOut")
        superSpeed = epRx.maxPacketSize >= 1024
    }

    // -- Register I/O (vendor request 0x05, rtw_usb_read / rtw_usb_write) --

    private fun failIo() {
        ioFails++
        if (ioFails >= 32) throw IllegalStateException("RTL8812AU: USB control transfers failing")
    }

    private fun rd(addr: Int, len: Int): Int {
        val n = conn.controlTransfer(Rg.DIR_IN, Rg.VENDOR_REQ, addr and 0xffff, 0, rb, len, Rg.CTRL_TIMEOUT)
        if (n != len) { failIo(); return 0 }
        ioFails = 0
        return when (len) {
            1 -> rb[0].toInt() and 0xff
            2 -> le16(rb, 0)
            else -> le32(rb, 0)
        }
    }

    private fun wr(addr: Int, value: Int, len: Int) {
        val buf = ByteArray(len) { (value ushr (8 * it)).toByte() }
        val n = conn.controlTransfer(Rg.DIR_OUT, Rg.VENDOR_REQ, addr and 0xffff, 0, buf, len, Rg.CTRL_TIMEOUT)
        if (n != len) failIo() else ioFails = 0
    }

    private fun r8(a: Int) = rd(a, 1)
    private fun r16(a: Int) = rd(a, 2)
    private fun r32(a: Int) = rd(a, 4)
    private fun w8(a: Int, v: Int) = wr(a, v, 1)
    private fun w16(a: Int, v: Int) = wr(a, v, 2)
    private fun w32(a: Int, v: Int) = wr(a, v, 4)
    private fun set8(a: Int, bits: Int) = w8(a, r8(a) or bits)
    private fun clr8(a: Int, bits: Int) = w8(a, r8(a) and bits.inv())
    private fun set16(a: Int, bits: Int) = w16(a, r16(a) or bits)
    private fun set32(a: Int, bits: Int) = w32(a, r32(a) or bits)
    private fun clr32(a: Int, bits: Int) = w32(a, r32(a) and bits.inv())

    private fun mask32(a: Int, mask: Int, value: Int) {
        val shift = mask.countTrailingZeroBits()
        w32(a, (r32(a) and mask.inv()) or ((value shl shift) and mask))
    }

    private fun poll8(a: Int, mask: Int, want: Int, ms: Int): Boolean {
        val end = System.currentTimeMillis() + ms
        do {
            if ((r8(a) and mask) == want) return true
            sleep(1)
        } while (System.currentTimeMillis() < end)
        return false
    }

    private fun pw(a: Int, mask: Int, value: Int) = w8(a, (r8(a) and mask.inv()) or (value and mask))

    // -- RF (3-wire SIPI) --

    private fun readRf(path: Int, addr: Int, mask: Int): Int {
        val setCca = addr != 0 && cutVersion != Rg.CUT_C
        if (setCca) set32(Rg.REG_CCA2ND, 1 shl 3)
        val piMode = (r32(if (path == 0) Rg.REG_3WIRE_SWA else Rg.REG_3WIRE_SWB) and 0x4) != 0
        mask32(Rg.REG_HSSI_READ, 0xff, addr and 0xff)
        if (cutVersion == Rg.CUT_C) sleep(1)
        val ra = if (piMode) {
            if (path == 0) Rg.REG_PI_READ_A else Rg.REG_PI_READ_B
        } else {
            if (path == 0) Rg.REG_SI_READ_A else Rg.REG_SI_READ_B
        }
        val v = (r32(ra) and mask) ushr mask.countTrailingZeroBits()
        if (setCca) clr32(Rg.REG_CCA2ND, 1 shl 3)
        return v
    }

    private fun writeRf(path: Int, addr: Int, mask: Int, data: Int) {
        val a = addr and 0xff
        val m = mask and Rg.RFREG_MASK
        var d = data
        if (m != Rg.RFREG_MASK) {
            val old = readRf(path, a, Rg.RFREG_MASK)
            d = (old and m.inv()) or (data shl m.countTrailingZeroBits())
        }
        val v = ((a shl 20) or (d and Rg.RFREG_MASK)) and 0x0fffffff
        w32(if (path == 0) Rg.REG_LSSI_WRITE_A else Rg.REG_LSSI_WRITE_B, v)
    }

    // -- Conditional PHY tables (rtw_parse_tbl_phy_cond) --

    private fun checkPositive(cond: Int, cond2: Int): Boolean {
        val cut = (cond ushr 24) and 0xf
        val pkg = (cond ushr 12) and 0xf
        val intfSel = (cond ushr 8) and 0xf
        val rfe = cond and 0xff
        if (cut != 0 && cut != (if (cutVersion != 0) cutVersion else 15)) return false
        if (pkg != 0 && pkg != Rg.PKG_DEFAULT) return false
        if (intfSel != 0 && intfSel != Rg.INTF_USB) return false
        if ((rfe and 0x0f) == 0) return true
        if ((rfe and condRfe) != rfe) return false
        if ((rfe and 1) != 0 && (cond2 and 0xff) != condGlna) return false
        if ((rfe and 2) != 0 && ((cond2 ushr 8) and 0xff) != condGpa) return false
        if ((rfe and 4) != 0 && ((cond2 ushr 16) and 0xff) != condAlna) return false
        if ((rfe and 8) != 0 && ((cond2 ushr 24) and 0xff) != condApa) return false
        return true
    }

    private fun loadTable(tbl: IntArray, cfg: (Int, Int) -> Unit) {
        var matched = true
        var skipped = false
        var posCond = 0
        var posCond2 = 0
        var i = 0
        while (i + 1 < tbl.size) {
            val a = tbl[i]
            val d = tbl[i + 1]
            i += 2
            if (a < 0) {
                when ((a ushr 28) and 3) {
                    Rg.BRANCH_ENDIF -> { matched = true; skipped = false }
                    Rg.BRANCH_ELSE -> matched = !skipped
                    else -> { posCond = a; posCond2 = d }
                }
            } else if ((a and 0x40000000) != 0) {
                if (!skipped) {
                    if (checkPositive(posCond, posCond2)) { matched = true; skipped = true } else { matched = false }
                } else {
                    matched = false
                }
            } else if (matched) {
                cfg(a, d)
            }
        }
    }

    private fun cfgBb(addr: Int, data: Int) {
        when (addr) {
            0xfe -> sleep(50)
            0xfd -> sleep(5)
            0xfc, 0xfb, 0xfa, 0xf9 -> sleep(1)
            else -> w32(addr, data)
        }
    }

    // -- Power sequences (card_enable_flow_8812a / card_disable_flow_8812a, USB rows only) --

    private fun preSystemCfg() {
        w8(Rg.REG_RSV_CTRL, 0)
        w8(Rg.REG_LDO_SWR_CTRL, if ((r32(Rg.REG_SYS_CFG1) and Rg.BIT_LDO) != 0) Rg.LDO_SEL else Rg.SPS_SEL)
    }

    private fun macPowered(): Boolean {
        if (r8(Rg.REG_CR) == 0xea) return false
        if ((r8(Rg.REG_SYS_STATUS1 + 1) and 1) != 0) return false
        return true
    }

    private fun pwrSeqOn() {
        pw(0x12, 0x01, 0x01); pw(0x14, 0x80, 0); pw(0x15, 0x01, 0); pw(0x23, 0x10, 0)
        pw(0x46, 0xff, 0); pw(0x43, 0xff, 0); pw(0x05, 0x08, 0); pw(0x03, 0x04, 0x04)
        pw(0x24, 0x02, 0x02); pw(0x28, 0x08, 0x08)
        pw(0x05, 0x04, 0)
        if (!poll8(0x06, 0x02, 0x02, Rg.PWR_POLL_MS)) throw IllegalStateException("RTL8812AU: power-on poll 0x06 timed out")
        pw(0x05, 0x08, 0); pw(0x05, 0x01, 0x01)
        if (!poll8(0x05, 0x01, 0, Rg.PWR_POLL_MS)) throw IllegalStateException("RTL8812AU: power-on poll 0x05 timed out")
        pw(0x24, 0x02, 0); pw(0x28, 0x08, 0)
    }

    private fun pwrSeqOff() {
        pw(0xc00, 0xff, 0x04); pw(0xe00, 0xff, 0x04); pw(0x02, 0x01, 0)
        pw(0x07, 0xff, 0x2a); pw(0x08, 0x02, 0); pw(0x05, 0x02, 0x02)
        if (!poll8(0x05, 0x02, 0, Rg.PWR_POLL_MS)) throw IllegalStateException("RTL8812AU: power-off poll 0x05 timed out")
        pw(0x03, 0x04, 0); pw(0x80, 0xff, 0x05); pw(0x42, 0xf0, 0xcc); pw(0x43, 0xff, 0x07)
        pw(0x45, 0xff, 0); pw(0x46, 0xff, 0xff); pw(0x47, 0xff, 0); pw(0x14, 0x80, 0x80)
        pw(0x15, 0x01, 0x01); pw(0x12, 0x01, 0); pw(0x23, 0x10, 0x10); pw(0x08, 0x02, 0)
        pw(0x07, 0xff, 0x20); pw(0x1f, 0x02, 0); pw(0x76, 0x02, 0); pw(0x05, 0x08, 0x08)
    }

    private fun enterLps() {
        w8(0x522, 0x7f)
        for (a in 0x5f8..0x5fb) poll8(a, 0xff, 0, Rg.PWR_POLL_MS)
        w8(0xc00, 0x04); w8(0xe00, 0x04)
        pw(0x02, 0x01, 0); pw(0x02, 0x02, 0)
        w8(0x100, 0x03); pw(0x101, 0x02, 0); pw(0x553, 0x20, 0x20)
    }

    private fun reset8051() {
        clr8(Rg.REG_RSV_CTRL, 1 shl 1)
        clr8(Rg.REG_RSV_CTRL + 1, 1 shl 3)
        val v = r8(Rg.REG_SYS_FUNC_EN + 1)
        w8(Rg.REG_SYS_FUNC_EN + 1, v and (1 shl 2).inv())
        clr8(Rg.REG_RSV_CTRL, 1 shl 1)
        set8(Rg.REG_RSV_CTRL + 1, 1 shl 3)
        w8(Rg.REG_SYS_FUNC_EN + 1, v or (1 shl 2))
    }

    // rtw88xxa_power_off
    private fun powerOff() {
        val cr = r8(Rg.REG_CR)
        if (cr == 0 || cr == 0xea) return
        w16(Rg.REG_GPIO_MUXCFG, r16(Rg.REG_GPIO_MUXCFG) and Rg.BIT_EN_SIC.inv())
        if (superSpeed) set8(Rg.REG_USB_MOD, 0x18)
        w32(Rg.REG_HISR0, -1); w32(Rg.REG_HISR1, -1); w32(Rg.REG_HIMR0, 0); w32(Rg.REG_HIMR1, 0)
        val fsmco = r16(Rg.REG_APS_FSMCO)
        w16(Rg.REG_APS_FSMCO, fsmco and Rg.APS_FSMCO_HW_POWERDOWN.inv())
        w8(Rg.REG_CR, 0)
        enterLps()
        if ((r8(Rg.REG_MCUFW_CTRL) and Rg.BIT_RAM_DL_SEL) != 0) reset8051()
        clr8(Rg.REG_SYS_FUNC_EN + 1, 1 shl 2)
        w8(Rg.REG_MCUFW_CTRL, 0)
        pwrSeqOff()
        if ((fsmco and Rg.APS_FSMCO_HW_POWERDOWN) != 0) set16(Rg.REG_APS_FSMCO, Rg.APS_FSMCO_HW_POWERDOWN)
    }

    // -- Efuse (rtw_dump_physical_efuse_map / rtw_dump_logical_efuse_map / rtw88xxa_read_efuse) --

    private fun efuseGrant(on: Boolean) {
        if (on) {
            w8(Rg.REG_EFUSE_ACCESS, Rg.EFUSE_ACCESS_ON)
            set16(Rg.REG_SYS_FUNC_EN, Rg.BIT_FEN_ELDR)
            set16(Rg.REG_SYS_CLKR, Rg.BIT_LOADER_CLK_EN or Rg.BIT_ANA8M)
        } else {
            w8(Rg.REG_EFUSE_ACCESS, 0)
        }
    }

    private fun dumpPhysicalEfuse(): ByteArray {
        val map = ByteArray(512)
        efuseGrant(true)
        mask32(Rg.REG_LDO_EFUSE_CTRL, 0x300, 0)
        var ctl = r32(Rg.REG_EFUSE_CTRL)
        for (addr in 0 until 512) {
            ctl = (ctl and (0x3ff shl 8).inv() and 0xff.inv()) or ((addr and 0x3ff) shl 8)
            w32(Rg.REG_EFUSE_CTRL, ctl and Rg.BIT_EF_FLAG.inv())
            var tries = 0
            do {
                ctl = r32(Rg.REG_EFUSE_CTRL)
                if (++tries > 2000) throw IllegalStateException("RTL8812AU: efuse read timed out")
            } while ((ctl and Rg.BIT_EF_FLAG) == 0)
            map[addr] = ctl.toByte()
        }
        efuseGrant(false)
        return map
    }

    private fun logicalEfuse(phy: ByteArray): ByteArray {
        val out = ByteArray(512) { 0xff.toByte() }
        var p = 0
        while (p < phy.size) {
            val h1 = phy[p].toInt() and 0xff
            val h2 = if (p + 1 < phy.size) phy[p + 1].toInt() and 0xff else 0xff
            if (h1 == 0xff || ((h1 and 0x1f) == 0xf && h2 == 0xff)) break
            val blk: Int
            val wordEn: Int
            if ((h1 and 0x1f) == 0xf) {
                blk = ((h2 and 0xf0) shr 1) or ((h1 shr 5) and 7)
                wordEn = h2 and 0xf
                p += 2
            } else {
                blk = (h1 and 0xf0) shr 4
                wordEn = h1 and 0xf
                p += 1
            }
            for (i in 0 until 4) {
                if ((wordEn and (1 shl i)) != 0) continue
                val li = (blk shl 3) + (i shl 1)
                if (p + 1 >= phy.size || li + 1 >= out.size) throw IllegalStateException("RTL8812AU: efuse map corrupt")
                out[li] = phy[p]
                out[li + 1] = phy[p + 1]
                p += 2
            }
        }
        return out
    }

    private fun readEfuse8(addr: Int): Int {
        mask32(Rg.REG_EFUSE_CTRL, 0x3ff00, addr)
        clr32(Rg.REG_EFUSE_CTRL, Rg.BIT_EF_FLAG)
        val end = System.currentTimeMillis() + 100
        while ((r32(Rg.REG_EFUSE_CTRL) and Rg.BIT_EF_FLAG) == 0) {
            if (System.currentTimeMillis() > end) throw IllegalStateException("RTL8812AU: efuse byte read timed out")
            sleep(1)
        }
        return r8(Rg.REG_EFUSE_CTRL)
    }

    private class Amp(
        val extPa2g: Boolean,
        val extLna2g: Boolean,
        val extPa5g: Boolean,
        val extLna5g: Boolean,
        val gpa: Int,
        val apa: Int,
        val glna: Int,
        val alna: Int,
    )

    private fun amplifier(pa: Int, lna2: Int, lna5: Int): Amp {
        val epa2 = (pa and 0x20) != 0 && (pa and 0x10) != 0
        val elna2 = (lna2 and 0x80) != 0 && (lna2 and 0x08) != 0
        val epa5 = (pa and 0x02) != 0 && (pa and 0x01) != 0
        val elna5 = (lna5 and 0x80) != 0 && (lna5 and 0x08) != 0
        val gpa = if (epa2) (((lna2 shr 6) and 1) shl 2) or ((lna2 shr 2) and 1) else 0
        val apa = if (epa5) (((lna5 shr 6) and 1) shl 2) or ((lna5 shr 2) and 1) else 0
        val glna = if (elna2) (((lna2 shr 4) and 3) shl 2) or (lna2 and 3) else 0
        val alna = if (elna5) (((lna5 shr 4) and 3) shl 2) or (lna5 and 3) else 0
        return Amp(epa2, elna2, epa5, elna5, gpa, apa, glna, alna)
    }

    private fun applyEfuse(map: ByteArray) {
        fun u(i: Int) = map[i].toInt() and 0xff
        val xtal = u(0xb9)
        crystalCap = if (xtal == 0xff) 0x20 else xtal
        val paRaw = u(0xbc)
        val lna2Raw = u(0xbd)
        val lna5Raw = u(0xbf)
        val boardRaw = u(0xc1)
        val rfeRaw = u(0xca)

        val a1 = amplifier(paRaw, lna2Raw, lna5Raw)
        rfeOption = when {
            rfeRaw == 0xff -> 0
            (rfeRaw and 0x80) != 0 ->
                if (a1.extLna5g) {
                    if (a1.extPa5g) { if (a1.extLna2g && a1.extPa2g) 3 else 0 } else 2
                } else {
                    4
                }
            else -> {
                val r = rfeRaw and 0x3f
                if (r == 4 && (a1.extPa5g || a1.extPa2g || a1.extLna5g || a1.extLna2g)) 0 else r
            }
        }

        val pa = if (paRaw == 0xff) 0 else paRaw
        val lna2 = if (lna2Raw == 0xff) 0 else lna2Raw
        val lna5 = if (lna5Raw == 0xff) 0 else lna5Raw
        val board = if (boardRaw == 0xff) 0 else boardRaw
        btcoex = (board and 0xe0) == 0x20
        val p2 = (pa and 0x10) != 0
        val l2 = (lna2 and 0x08) != 0
        val p5 = (pa and 0x01) != 0
        val l5 = (lna5 and 0x08) != 0
        condRfe = (if (l2) 1 else 0) or (if (p2) 2 else 0) or (if (l5) 4 else 0) or (if (p5) 8 else 0) or
            (if (btcoex) 0x10 else 0)
        condGlna = a1.glna
        condGpa = a1.gpa
        condAlna = a1.alna
        condApa = a1.apa
        extLna2g = amplifier(pa, lna2, lna5).extLna2g

        var antenna = 0
        for (i in 0 until 2) {
            val v = readEfuse8(1019 - i)
            antenna = (v shr 5) and 7
            if (antenna != 0) break
            antenna = (v shr 1) and 7
            if (antenna != 0) break
        }
        rfPathNum = if (antenna == 1) 1 else 2
        log("RTL8812AU: efuse parsed, rfe=$rfeOption paths=$rfPathNum")
    }

    // -- Bring-up (rtw_mac_power_on + rtw88xxa_power_on, TX-only blocks omitted) --

    private fun bringUp() {
        cutVersion = ((r32(Rg.REG_SYS_CFG1) ushr 12) and 0xf) + 1

        preSystemCfg()
        if (macPowered()) {
            powerOff()
            preSystemCfg()
        }
        pwrSeqOn()
        w8(Rg.REG_CR, 0xff); sleep(2)
        w8(Rg.REG_HWSEQ_CTRL, 0x7f); sleep(2)
        set8(Rg.REG_SYS_CLKR, Rg.BIT_WAKEPAD_EN)
        w16(Rg.REG_GPIO_MUXCFG, r16(Rg.REG_GPIO_MUXCFG) and Rg.BIT_EN_SIC.inv())
        w16(Rg.REG_CR, 0x2ff)
        // unverified: efuse is read here, before the firmware download, after rtw_mac_power_on-equivalent steps
        applyEfuse(logicalEfuse(dumpPhysicalEfuse()))
        pwrSeqOff()

        w8(Rg.REG_RF_CTRL, 5); w8(Rg.REG_RF_CTRL, 7)
        w8(Rg.REG_RF_B_CTRL, 5); w8(Rg.REG_RF_B_CTRL, 7)

        pwrSeqOn()
        w16(Rg.REG_CR, 0)
        set16(
            Rg.REG_CR,
            Rg.BIT_HCI_TXDMA_EN or Rg.BIT_HCI_RXDMA_EN or Rg.BIT_TXDMA_EN or Rg.BIT_RXDMA_EN or
                Rg.BIT_PROTOCOL_EN or Rg.BIT_SCHEDULE_EN or Rg.BIT_MAC_SEC_EN or Rg.BIT_32K_CAL_TMR_EN,
        )

        val txffPages = Rg.TXFF_SIZE / Rg.PAGE_SIZE
        val rsvdPages = Rg.RSVD_DRV_PG_NUM
        val acqPages = txffPages - rsvdPages
        val boundary = acqPages
        initLlt(boundary)
        set32(Rg.REG_TXDMA_OFFSET_CHK, Rg.BIT_DROP_DATA_EN)

        downloadFirmware()
        w8(Rg.REG_HMETFR, 0xf)
        log("RTL8812AU: firmware running")

        loadTable(Rg.MAC_TBL) { a, d -> w8(a, d) }
        initQueues(acqPages, boundary)
        w16(Rg.REG_TRXFF_BNDY + 2, Rg.RXFF_SIZE - Rg.REPORT_BUF - 1)
        w8(Rg.REG_PBP, 0x30)
        w8(Rg.REG_RX_DRVINFO_SZ, Rg.PHY_STATUS_SIZE)
        w32(Rg.REG_HIMR0, 0); w32(Rg.REG_HIMR1, 0)
        mask32(Rg.REG_CR, 0x30000, 2)

        w16(Rg.REG_RXFLTMAP0, 0xffff); w16(Rg.REG_RXFLTMAP1, 0x0400); w16(Rg.REG_RXFLTMAP2, 0xffff)
        w32(Rg.REG_MAR, -1); w32(Rg.REG_MAR + 4, -1)
        mask32(Rg.REG_RRSR, 0xfffff, 0xffff1)
        w16(Rg.REG_RETRY_LIMIT, 0x3030)
        w8(Rg.REG_USTIME_TSF, 0x50); w8(Rg.REG_USTIME_EDCA, 0x50)

        val burst = if (superSpeed) Rg.BURST_1024 else if (epRx.maxPacketSize >= 512) Rg.BURST_512 else Rg.BURST_64
        w8(Rg.REG_RXDMA_MODE, Rg.BIT_DMA_BURST_CNT or Rg.BIT_DMA_MODE or (burst shl 4))
        set16(Rg.REG_TXDMA_OFFSET_CHK, Rg.BIT_DROP_DATA_EN)
        w8(Rg.REG_USB3_RXITV, 0x01)
        w16(Rg.REG_RXDMA_STATUS, 0x7400); w8(Rg.REG_RXDMA_STATUS + 1, 0xf5)
        if (superSpeed) clr8(Rg.REG_USB_MOD, (1 shl 4) or (1 shl 3))
        w8(Rg.REG_RX_PKT_LIMIT, 0x18)
        set8(Rg.REG_RSV_CTRL, (1 shl 5) or (1 shl 6))
        // unverified: rtw88 only calls rx-agg disable from its watchdog; here it keeps each USB transfer under 16 KiB
        w16(Rg.REG_RXDMA_AGG_PG_TH, 0x0100)
        set8(Rg.REG_TXDMA_PQ_MAP, Rg.BIT_RXDMA_AGG_EN)
        set8(Rg.REG_CR, Rg.BIT_MACTXEN or Rg.BIT_MACRXEN)

        bbConfig()
        for (path in 0 until rfPathNum) {
            loadTable(if (path == 0) Rg.RF_A_TBL else Rg.RF_B_TBL) { a, d ->
                when (a) {
                    0xffe -> sleep(50)
                    0xfe -> sleep(1)
                    else -> writeRf(path, a, Rg.RFREG_MASK, d)
                }
            }
        }
        if (rfPathNum == 1) config1t()
        switchBand(false)

        clr8(Rg.REG_GPIO_MUXCFG, 1 shl 5)
        w8(Rg.REG_SYS_SDIO_CTRL, 0); w8(Rg.REG_ACLK_MON, 0); w8(Rg.REG_USB_HRPWM, 0)

        w32(Rg.REG_RCR, Rg.RCR_MONITOR)
        setChannel(Rg.CHANNELS[0])
    }

    private fun initLlt(boundary: Int) {
        for (i in 0 until boundary - 1) lltWrite(i, i + 1)
        lltWrite(boundary - 1, 0xff)
        for (i in boundary until 255) lltWrite(i, i + 1)
        lltWrite(255, boundary)
    }

    private fun lltWrite(address: Int, data: Int) {
        w32(Rg.REG_LLT_INIT, Rg.BIT_LLT_WRITE_ACCESS or (address shl 8) or data)
        var count = 0
        while ((r32(Rg.REG_LLT_INIT) ushr 30) != 0) {
            if (++count > 20) throw IllegalStateException("RTL8812AU: LLT write timed out at $address")
        }
    }

    private fun initQueues(acqPages: Int, boundary: Int) {
        val idx = bulkOut - 2
        val pg = Rg.PAGE_TABLE[idx]
        val rq = Rg.RQPN_TABLE[idx]
        val pub = acqPages - pg[0] - pg[2] - pg[1] - pg[3] - pg[4]
        w32(Rg.REG_RQPN_NPQ, (pg[1] and 0xff) or ((pg[3] and 0xff) shl 16))
        w32(Rg.REG_RQPN, Rg.BIT_LD_RQPN or (pg[0] and 0xff) or ((pg[2] and 0xff) shl 8) or ((pub and 0xff) shl 16))
        w8(Rg.REG_BCNQ_BDNY, boundary); w8(Rg.REG_MGQ_BDNY, boundary)
        w8(Rg.REG_WMAC_LBK_BF_HD, boundary); w8(Rg.REG_TRXFF_BNDY, boundary)
        w8(Rg.REG_DWBCN0_CTRL + 1, boundary)
        val map = (r16(Rg.REG_TXDMA_PQ_MAP) and 7) or (rq[5] shl 14) or (rq[4] shl 12) or (rq[3] shl 10) or
            (rq[2] shl 8) or (rq[1] shl 6) or (rq[0] shl 4)
        w16(Rg.REG_TXDMA_PQ_MAP, map)
        if (bulkOut == 4) w8(Rg.REG_HIQ_NO_LMT_EN, 0xff)
    }

    private fun wlanCpu(enable: Boolean) {
        if (enable) {
            set8(Rg.REG_RSV_CTRL + 1, Rg.BIT_WLMCU_IOIF)
            set8(Rg.REG_SYS_FUNC_EN + 1, Rg.BIT_FEN_CPUEN)
        } else {
            clr8(Rg.REG_SYS_FUNC_EN + 1, Rg.BIT_FEN_CPUEN)
            clr8(Rg.REG_RSV_CTRL + 1, Rg.BIT_WLMCU_IOIF)
        }
    }

    private fun downloadFirmware() {
        if (fw.size <= Rg.FW_HDR_LEGACY_SIZE) throw IllegalStateException("RTL8812AU: firmware too small")
        wlanCpu(false); wlanCpu(true)
        set8(Rg.REG_MCUFW_CTRL, Rg.BIT_MCUFWDL_EN)
        for (attempt in 0 until 10) {
            if ((r8(Rg.REG_MCUFW_CTRL) and Rg.BIT_MCUFWDL_EN) != 0) break
            set8(Rg.REG_MCUFW_CTRL, Rg.BIT_MCUFWDL_EN)
            sleep(20)
        }
        clr32(Rg.REG_MCUFW_CTRL, Rg.BIT_ROM_DLEN)

        set8(Rg.REG_MCUFW_CTRL, Rg.BIT_FWDL_CHK_RPT)
        val total = fw.size - Rg.FW_HDR_LEGACY_SIZE
        var off = Rg.FW_HDR_LEGACY_SIZE
        var page = 0
        var remain = total
        while (remain > 0) {
            val n = minOf(remain, Rg.FW_PAGE_SIZE)
            writeFirmwarePage(page, off, n)
            off += n
            remain -= n
            page++
        }
        if (!poll8(Rg.REG_MCUFW_CTRL, Rg.BIT_FWDL_CHK_RPT, Rg.BIT_FWDL_CHK_RPT, Rg.PWR_POLL_MS)) {
            throw IllegalStateException("RTL8812AU: firmware download report not set")
        }
        clr8(Rg.REG_MCUFW_CTRL, Rg.BIT_MCUFWDL_EN)

        var v = r32(Rg.REG_MCUFW_CTRL)
        v = (v or Rg.BIT_MCUFWDL_RDY) and Rg.BIT_WINTINI_RDY.inv()
        w32(Rg.REG_MCUFW_CTRL, v)
        wlanCpu(false); wlanCpu(true)
        for (attempt in 0 until 10) {
            if ((r32(Rg.REG_MCUFW_CTRL) and Rg.FW_READY_LEGACY) == Rg.FW_READY_LEGACY) return
            sleep(20)
        }
        throw IllegalStateException("RTL8812AU: firmware failed to start")
    }

    private fun writeFirmwarePage(page: Int, srcOff: Int, size: Int) {
        mask32(Rg.REG_MCUFW_CTRL, Rg.BIT_ROM_PGE, page)
        var addr = Rg.FW_START_ADDR
        var pos = srcOff
        var left = size
        while (left > 0) {
            val n = if (left >= Rg.FW_USB_BLOCK) Rg.FW_USB_BLOCK else if (left >= 8) 8 else 1
            val r = conn.controlTransfer(Rg.DIR_OUT, Rg.VENDOR_REQ, addr, 0, fw, pos, n, 500)
            if (r != n) throw IllegalStateException("RTL8812AU: firmware write failed at page $page")
            addr += n
            pos += n
            left -= n
        }
    }

    private fun bbConfig() {
        var v = r8(Rg.REG_SYS_FUNC_EN) or Rg.BIT_FEN_USBA
        w8(Rg.REG_SYS_FUNC_EN, v)
        v = v or Rg.BIT_FEN_BB_RSTB or Rg.BIT_FEN_BB_GLB_RST
        w8(Rg.REG_SYS_FUNC_EN, v)
        w8(Rg.REG_RF_CTRL, Rg.BIT_RF_EN or Rg.BIT_RF_RSTB or Rg.BIT_RF_SDM_RSTB)
        w8(Rg.REG_RF_B_CTRL, Rg.BIT_RF_EN or Rg.BIT_RF_RSTB or Rg.BIT_RF_SDM_RSTB)
        loadTable(Rg.BB_TBL) { a, d -> cfgBb(a, d) }
        loadTable(Rg.AGC_TBL) { a, d -> w32(a, d) }
        val cap = crystalCap and 0x3f
        mask32(Rg.REG_AFE_CTRL3, 0x7ff80000, cap or (cap shl 6))
    }

    private fun config1t() {
        mask32(Rg.REG_RXPSEL, 0xff, 0x11)
        mask32(Rg.REG_TXPSEL, 0xffff, 0x1111)
        mask32(Rg.REG_CCK_RX, 0x0c000000, 0)
        mask32(Rg.REG_RX_MCS_LIMIT, 0xc0000060.toInt(), 0x4)
        mask32(Rg.REG_3WIRE_SWB, 0xf, 0x4)
        w32(Rg.REG_LSSI_WRITE_B, 0)
        w32(Rg.REG_AFE_PWR1_B, 0)
        w32(Rg.REG_AFE_PWR2_B, 0)
    }

    // -- Band / channel (rtw88xxa_switch_band, rtw88xxa_switch_channel, 20 MHz only) --

    private fun setRfe(is5g: Boolean) {
        val pa = Rg.REG_RFE_PINMUX_A
        val pb = Rg.REG_RFE_PINMUX_B
        val ia = Rg.REG_RFE_INV_A
        val ib = Rg.REG_RFE_INV_B
        val m = Rg.RFE_INV_MASK
        fun pin(a: Int, b: Int, inv: Int) {
            w32(pa, a); w32(pb, b)
            mask32(ia, m, inv); mask32(ib, m, inv)
        }
        if (!is5g) {
            when (rfeOption) {
                0, 2 -> pin(0x77777777, 0x77777777, 0x000)
                1 -> if (btcoex) {
                    mask32(pa, 0xffffff, 0x777777); w32(pb, 0x77777777)
                    mask32(ia, 0x33f00000, 0x000); mask32(ib, m, 0x000)
                } else {
                    pin(0x77777777, 0x77777777, 0x000)
                }
                3 -> {
                    pin(0x54337770, 0x54337770, 0x010)
                    mask32(Rg.REG_ANTSEL_SW, 0x00000303, 0x1)
                }
                4 -> pin(0x77777777, 0x77777777, 0x001)
                5 -> {
                    w8(pa + 2, 0x77); w32(pb, 0x77777777)
                    clr8(ia + 3, 1); mask32(ib, m, 0x000)
                }
                6 -> {
                    w32(pa, 0x07772770); w32(pb, 0x07772770)
                    w32(ia, 0x00000077); w32(ib, 0x00000077)
                }
            }
        } else {
            when (rfeOption) {
                0 -> pin(0x77337717, 0x77337717, 0x010)
                1 -> if (btcoex) {
                    mask32(pa, 0xffffff, 0x337717); w32(pb, 0x77337717)
                    mask32(ia, 0x33f00000, 0x000); mask32(ib, m, 0x000)
                } else {
                    pin(0x77337717, 0x77337717, 0x000)
                }
                2, 4 -> pin(0x77337777, 0x77337777, 0x010)
                3 -> {
                    pin(0x54337717, 0x54337717, 0x010)
                    mask32(Rg.REG_ANTSEL_SW, 0x00000303, 0x1)
                }
                5 -> {
                    w8(pa + 2, 0x33); w32(pb, 0x77337777)
                    set8(ia + 3, 1); mask32(ib, m, 0x010)
                }
                6 -> {
                    w32(pa, 0x07737717); w32(pb, 0x07737717)
                    w32(ia, 0x00000077); w32(ib, 0x00000077)
                }
            }
        }
    }

    private fun switchBand(is5g: Boolean) {
        if (!is5g) {
            set32(Rg.REG_RXPSEL, Rg.BIT_RX_PSEL_RST)
            mask32(Rg.REG_BWINDICATION, 0x3, 0x1)
            mask32(Rg.REG_PDMFTH, 0x3e000, 0x17)
            if (rfPathNum == 1 && !extLna2g) mask32(Rg.REG_PDMFTH, 0xe, 0x02) else mask32(Rg.REG_PDMFTH, 0xe, 0x04)
            mask32(Rg.REG_CCASEL, 0x3, 0)
            setRfe(false)
            mask32(Rg.REG_TXPSEL, 0xf0, 0x1)
            mask32(Rg.REG_CCK_RX, 0x0f000000, 0x1)
            mask32(Rg.REG_RRSR, 0xfffff, 0x15f)
            clr8(Rg.REG_CCK_CHECK, Rg.BIT_CHECK_CCK_EN)
        } else {
            set8(Rg.REG_CCK_CHECK, Rg.BIT_CHECK_CCK_EN)
            val end = System.currentTimeMillis() + 3
            while ((r16(Rg.REG_TXPKT_EMPTY) and 0x30) != 0x30 && System.currentTimeMillis() < end) sleep(1)
            set32(Rg.REG_RXPSEL, Rg.BIT_RX_PSEL_RST)
            mask32(Rg.REG_BWINDICATION, 0x3, 0x2)
            mask32(Rg.REG_PDMFTH, 0x3e000, 0x15)
            mask32(Rg.REG_PDMFTH, 0xe, 0x04)
            mask32(Rg.REG_CCASEL, 0x3, 1)
            setRfe(true)
            mask32(Rg.REG_TXPSEL, 0xf0, 0)
            mask32(Rg.REG_CCK_RX, 0x0f000000, 0xf)
            mask32(Rg.REG_RRSR, 0xfffff, 0x150)
        }
    }

    private fun fixSpur(ch: Int) {
        if (cutVersion == Rg.CUT_C) {
            mask32(Rg.REG_ADCCLK, 0xc00, 0x2)
            if (ch == 13 || ch == 14) {
                mask32(Rg.REG_ADCCLK, 0x300, 0x3)
                mask32(Rg.REG_ADC160, 1 shl 30, 1)
            } else {
                mask32(Rg.REG_ADCCLK, 0x300, 0x2)
                mask32(Rg.REG_ADC160, 1 shl 30, 0)
            }
        } else {
            if (ch == 13 || ch == 14) mask32(Rg.REG_ADCCLK, 0x300, 0x3)
            else if (ch <= 14) mask32(Rg.REG_ADCCLK, 0x300, 0x2)
        }
    }

    private fun setChannel(ch: Int) {
        val oldIs5g = (r8(Rg.REG_CCK_CHECK) and Rg.BIT_CHECK_CCK_EN) != 0
        val newIs5g = ch > 14
        if (newIs5g != oldIs5g) switchBand(newIs5g)

        val fcArea = when {
            ch in 36..48 -> 0x494
            ch in 50..64 -> 0x453
            ch in 100..116 -> 0x452
            ch >= 118 -> 0x412
            else -> 0x96a
        }
        mask32(Rg.REG_CLKTRK, 0x1ffe0000, fcArea)
        val rfModAg = when {
            ch in 36..64 -> 0x101
            ch in 100..140 -> 0x301
            ch > 140 -> 0x501
            else -> 0x000
        }
        for (path in 0 until rfPathNum) {
            writeRf(path, Rg.RF_CFGCH, Rg.RF18_RFSI_MASK or Rg.RF18_BAND_MASK, rfModAg)
            fixSpur(ch)
            writeRf(path, Rg.RF_CFGCH, Rg.RF18_CHANNEL_MASK, ch)
        }

        w16(Rg.REG_WMAC_TRXPTCL_CTL, r16(Rg.REG_WMAC_TRXPTCL_CTL) and Rg.BIT_RFMOD.inv())
        w8(Rg.REG_DATA_SC, 0)
        mask32(Rg.REG_ADCCLK, 0x003003c3, 0x00300200)
        mask32(Rg.REG_ADC160, 1 shl 30, 0)
        mask32(Rg.REG_L1PKTH, 0x03c00000, if (rfPathNum == 2) 7 else 8)
        fixSpur(ch)
        for (path in 0 until rfPathNum) writeRf(path, Rg.RF_CFGCH, Rg.RF18_BW_MASK, 3)
    }

    // -- RX --

    private fun rxLoop(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val nbuf = 8
        val bufSz = 16384
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
                            b.rewind(); b.get(scratch, 0, nbytes)
                            parseRx(scratch, nbytes, Rg.CHANNELS[hopIdx], table)
                        }
                        b.clear()
                        if (!runCatching { req.queue(b) }.getOrDefault(false)) {
                            runCatching { req.close() }
                        }
                    }
                }
                if (now - emitAt > 2000) { emit(table, onBatch); emitAt = now }
                if (now - hopAt > DWELL_MS) {
                    hopIdx = (hopIdx + 1) % Rg.CHANNELS.size
                    setChannel(Rg.CHANNELS[hopIdx])
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
        while (!stop) {
            val n = conn.bulkTransfer(epRx, buf, buf.size, 500)
            val now = System.currentTimeMillis()
            if (n > 0) parseRx(buf, n, Rg.CHANNELS[hopIdx], table)
            if (now - emitAt > 2000) { emit(table, onBatch); emitAt = now }
            if (now - hopAt > DWELL_MS) {
                hopIdx = (hopIdx + 1) % Rg.CHANNELS.size
                setChannel(Rg.CHANNELS[hopIdx])
                hopAt = now
            }
        }
        emit(table, onBatch)
    }

    // -- 802.11 parse: beacons and probe responses only --

    private class Entry(var ssid: String?, var rssi: Int, var channel: Int, var lastSeen: Long)
    private class SightingTable {
        val map = LinkedHashMap<String, Entry>()
    }
    private class IeInfo(val ssid: String?, val channel: Int)

    private fun cckRxPwr(lna: Int, vga: Int): Int = when (lna) {
        7 -> if (vga <= 27) -94 + 2 * (27 - vga) else -94
        6 -> -42 + 2 * (2 - vga)
        5 -> -36 + 2 * (7 - vga)
        4 -> -30 + 2 * (7 - vga)
        3 -> -18 + 2 * (7 - vga)
        2 -> 2 * (5 - vga)
        1 -> 14 - 2 * vga
        0 -> 20 - 2 * vga
        else -> 0
    }

    private fun parseRx(b: ByteArray, n: Int, hopCh: Int, table: SightingTable) {
        try {
            var off = 0
            while (off + Rg.RX_DESC_SIZE < n) {
                val w0 = le32(b, off)
                val w2 = le32(b, off + 8)
                val w3 = le32(b, off + 12)
                val pktLen = w0 and 0x3fff
                val crcErr = (w0 and (1 shl 14)) != 0
                val drvInfo = (w0 ushr 16) and 0xf
                val shift = (w0 ushr 24) and 3
                val physt = (w0 and (1 shl 26)) != 0
                val isC2h = (w2 and (1 shl 28)) != 0
                val rate = w3 and 0x7f
                if (drvInfo != 0 && drvInfo != Rg.PHY_STATUS_SIZE) break
                if (physt && drvInfo == 0) break
                if (pktLen > Rg.MAX_MPDU_LEN) break
                val phyOff = off + Rg.RX_DESC_SIZE + shift
                val hdr = phyOff + drvInfo * 8
                val total = hdr + pktLen - off
                if (off + total > n) break
                if (!isC2h && !crcErr && pktLen > 4) {
                    // Deliver even without PHY status (rtw88 rx.c parses phy only when present); fall back to -100.
                    val rssi = if (!physt) {
                        -100
                    } else if (rate <= 3) {
                        val w1 = le32(b, phyOff + 4)
                        cckRxPwr((w1 ushr 13) and 7, (w1 ushr 8) and 0x1f)
                    } else {
                        val pw0 = le32(b, phyOff)
                        val pa = (pw0 and 0x7f) - 110
                        val pb = if (rfPathNum == 1) pa else ((pw0 ushr 8) and 0x7f) - 110
                        maxOf(pa, pb, -120)
                    }
                    handleFrame(b, hdr, pktLen, rssi.coerceIn(-120, -10), hopCh, table)
                }
                off += (total + 7) and 7.inv()
            }
        } catch (e: IndexOutOfBoundsException) {
            malformed++ // truncated or corrupt USB transfer; counted, next transfer continues
        }
    }

    private fun handleFrame(b: ByteArray, hdr: Int, frameLen: Int, rssi: Int, hopCh: Int, table: SightingTable) {
        if (frameLen < 36 + 4) return
        val fc = b[hdr].toInt() and 0xff
        if (((fc shr 2) and 3) != 0) return
        val sub = (fc shr 4) and 0xf
        if (sub != 8 && sub != 5) return
        val bssid = (0 until 6).joinToString(":") { "%02x".format(b[hdr + 16 + it].toInt() and 0xff) }
        if (bssid == "ff:ff:ff:ff:ff:ff" || bssid == "00:00:00:00:00:00") return
        val ie = parseIes(b, hdr + 36, hdr + frameLen - 4)
        val ch = if (Rg.CHANNELS.contains(ie.channel)) ie.channel else hopCh
        val e = table.map.getOrPut(bssid) { Entry(null, rssi, ch, 0) }
        if (!ie.ssid.isNullOrEmpty()) e.ssid = ie.ssid
        if (rssi > e.rssi) e.rssi = rssi
        e.channel = ch
        e.lastSeen = System.currentTimeMillis()
    }

    private fun parseIes(b: ByteArray, from: Int, end: Int): IeInfo {
        var ssid: String? = null
        var channel = 0
        var i = from
        while (i + 2 <= end) {
            val tag = b[i].toInt() and 0xff
            val tl = b[i + 1].toInt() and 0xff
            if (i + 2 + tl > end) break
            if (tag == 0) {
                if (tl == 0) {
                    ssid = ""
                } else {
                    val s = String(b, i + 2, tl, Charsets.UTF_8)
                    ssid = if (s.length <= 32 && s.none { it.code == 0xFFFD || it.isISOControl() }) s else null
                }
            } else if (tag == 3 && tl >= 1) {
                channel = b[i + 2].toInt() and 0xff
            } else if (tag == 61 && tl >= 1 && channel == 0) {
                channel = b[i + 2].toInt() and 0xff
            }
            i += 2 + tl
        }
        return IeInfo(ssid, channel)
    }

    private fun emit(table: SightingTable, onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val now = System.currentTimeMillis()
        val fresh = 8000L
        val batch = table.map.entries
            .filter { now - it.value.lastSeen < fresh }
            .map { (mac, e) -> Mt7612uAdapter.ApSighting(mac, e.ssid, e.rssi, e.channel, Rg.freqOf(e.channel)) }
        table.map.entries.removeAll { now - it.value.lastSeen > 60_000L }
        if (batch.isNotEmpty()) onBatch(batch)
    }

    companion object {
        const val DWELL_MS = 150L

        fun loadFirmware(ctx: Context): ByteArray {
            val dir = File(ctx.cacheDir, "wifi_fw").apply { mkdirs() }
            val f = File(dir, Rg.FIRMWARE_FILE)
            if (f.exists()) {
                val have = f.readBytes()
                if (sha256(have) == Rg.FIRMWARE_SHA256) return have
                f.delete()
            }
            val bytes = download(Rg.FW_URL)
            val got = sha256(bytes)
            if (got != Rg.FIRMWARE_SHA256) {
                throw IllegalStateException("${Rg.FIRMWARE_FILE} sha256 $got != expected ${Rg.FIRMWARE_SHA256}")
            }
            f.writeBytes(bytes)
            return bytes
        }

        private fun download(url: String): ByteArray {
            val c = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000
                readTimeout = 30000
                requestMethod = "GET"
                setRequestProperty("User-Agent", "oui-spy-companion/1.0")
            }
            try {
                val code = c.responseCode
                if (code != 200) throw IllegalStateException("download $url HTTP $code")
                return c.inputStream.use { it.readBytes() }
            } finally {
                c.disconnect()
            }
        }

        private fun sha256(b: ByteArray): String =
            MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }
    }
}

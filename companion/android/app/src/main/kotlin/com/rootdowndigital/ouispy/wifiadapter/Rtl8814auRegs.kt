package com.rootdowndigital.ouispy.wifiadapter

// RTL8814AU constants transcribed from Linux rtw88 rtw8814a.c and rtw8814a_table.c, SPDX-License-Identifier: GPL-2.0 OR BSD-3-Clause (USB entries only).
internal object Rtl8814auRegs {
    const val TXFF_PG_NUM = 2038
    const val RXFF_SIZE = 23552
    const val RSVD_DRV_PG = 8
    const val RSVD_H2C_EXTRAINFO_PG = 24
    const val RSVD_H2C_STATICINFO_PG = 8
    const val RSVD_H2CQ_PG = 8
    const val RSVD_FW_TXBUF_PG = 4
    const val PHY_EFUSE_SIZE = 1024
    const val LOG_EFUSE_SIZE = 512
    const val USB_TX_AGG_DESC_NUM = 3
    const val SYS_FUNC_EN_INIT = 0xDC
    const val FW_HDR_SIZE = 64
    const val FW_CHKSUM_SIZE = 8
    const val FW_READY = 0xC078
    const val FW_READY_MASK = 0xCFFF

    const val EE_XTAL_K = 0xB9
    const val EE_RFE_OPTION = 0xCA

    const val TBL_MAC = "rtw8814a_mac"
    const val TBL_AGC = "rtw8814a_agc"
    const val TBL_BB = "rtw8814a_bb"
    val TBL_RF = arrayOf("rtw8814a_rf_a", "rtw8814a_rf_b", "rtw8814a_rf_c", "rtw8814a_rf_d")

    val RF_BASE = intArrayOf(0x2800, 0x2C00, 0x3800, 0x3C00)
    val LSSI_WRITE = intArrayOf(Rtl88Regs.LSSI_WRITE_A, Rtl88Regs.LSSI_WRITE_B, Rtl88Regs.LSSI_WRITE_C, Rtl88Regs.LSSI_WRITE_D)
    val DIG_REGS = intArrayOf(Rtl88Regs.RXIGI_A, Rtl88Regs.RXIGI_B, Rtl88Regs.RXIGI_C, Rtl88Regs.RXIGI_D)
    val RX_IQC_AB = intArrayOf(0x0C10, 0x0E10, 0x1810, 0x1A10)
    val RX_IQC_CD = intArrayOf(0x0C14, 0x0E14, 0x1814, 0x1A14)
    val AFE_PWR1 = intArrayOf(0x0C60, 0x0E60, 0x1860, 0x1A60)
    val CK_MONH = intArrayOf(0x0C5C, 0x0E5C, 0x185C, 0x1A5C)

    val PWR_ON: Array<PwrCmd> = arrayOf(
        pwrW(0x10C2, 0x02, 0x02),
        pwrW(0x0012, 0x40, 0x40),
        pwrW(0x0015, 0x20, 0x00),
        pwrW(0x0015, 0x40, 0x00),
        pwrW(0x0023, 0x10, 0x00),
        pwrW(0x0046, 0xFF, 0x00),
        pwrW(0x0062, 0xFF, 0x00),
        pwrW(0x0005, 0x08, 0x00),
        pwrW(0x0005, 0x04, 0x00),
        pwrPoll(0x0006, 0x02, 0x02),
        pwrW(0x0005, 0x08, 0x00),
        pwrW(0x00F0, 0x80, 0x00),
        pwrW(0x0081, 0x30, 0x20),
        pwrW(0x0005, 0x01, 0x01),
        pwrPoll(0x0005, 0x01, 0x00),
    )

    val PWR_OFF: Array<PwrCmd> = arrayOf(
        pwrW(0x0C00, 0xFF, 0x04),
        pwrW(0x0E00, 0xFF, 0x04),
        pwrW(0x1002, 0x01, 0x00),
        pwrDelayUs(1),
        pwrW(0x001F, 0xFF, 0x00),
        pwrW(0x0007, 0xFF, 0x28),
        pwrW(0x0008, 0x02, 0x00),
        pwrW(0x0066, 0x80, 0x00),
        pwrW(0x0041, 0x10, 0x00),
        pwrW(0x0042, 0x02, 0x00),
        pwrW(0x004E, 0x20, 0x20),
        pwrW(0x0041, 0x01, 0x00),
        pwrW(0x0005, 0x02, 0x02),
        pwrPoll(0x0005, 0x02, 0x00),
        pwrW(0x0003, 0x04, 0x00),
        pwrW(0x0080, 0xFF, 0x01),
        pwrW(0x0081, 0xFF, 0x30),
        pwrW(0x0045, 0xFF, 0x00),
        pwrW(0x0046, 0xFF, 0xFF),
        pwrW(0x0047, 0xFF, 0x00),
        pwrW(0x0015, 0x40, 0x40),
        pwrW(0x0015, 0x20, 0x20),
        pwrW(0x0012, 0x40, 0x00),
        pwrW(0x0023, 0x10, 0x10),
        pwrW(0x0008, 0x02, 0x00),
        pwrW(0x0007, 0xFF, 0x20),
        pwrW(0x001F, 0x02, 0x00),
        pwrW(0x0020, 0x02, 0x00),
        pwrW(0x0021, 0x02, 0x00),
        pwrW(0x0076, 0x02, 0x00),
        pwrW(0x0091, 0xA0, 0xA0),
        pwrW(0x0070, 0x08, 0x08),
        pwrW(0x0005, 0x08, 0x08),
    )

    fun rqpn(bulkOut: Int): IntArray = when (bulkOut) {
        2 -> intArrayOf(Rtl88Regs.DMA_HIGH, Rtl88Regs.DMA_HIGH, Rtl88Regs.DMA_NORMAL, Rtl88Regs.DMA_NORMAL, Rtl88Regs.DMA_HIGH, Rtl88Regs.DMA_HIGH)
        else -> intArrayOf(Rtl88Regs.DMA_HIGH, Rtl88Regs.DMA_NORMAL, Rtl88Regs.DMA_LOW, Rtl88Regs.DMA_LOW, Rtl88Regs.DMA_HIGH, Rtl88Regs.DMA_HIGH)
    }
}

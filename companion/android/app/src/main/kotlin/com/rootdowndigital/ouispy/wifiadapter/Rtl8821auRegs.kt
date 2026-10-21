package com.rootdowndigital.ouispy.wifiadapter

// RTL8821AU/8811AU constants transcribed from Linux rtw88 rtw8821a.c and rtw8821a_table.c, SPDX-License-Identifier: GPL-2.0 OR BSD-3-Clause (USB entries only).
internal object Rtl8821auRegs {
    const val TXFF_SIZE = 65536
    const val RXFF_SIZE = 16128
    const val PAGE_SIZE = 256
    const val RSVD_DRV_PG = 8
    const val PHY_EFUSE_SIZE = 512
    const val LOG_EFUSE_SIZE = 512
    const val USB_TX_AGG_DESC_NUM = 6
    const val FW_HDR_LEGACY = 32
    const val FW_BLOCK_USB = 196

    const val EE_XTAL_K = 0xB9
    const val EE_PA_TYPE = 0xBC
    const val EE_LNA_2G = 0xBD
    const val EE_LNA_5G = 0xBF

    const val TBL_MAC = "rtw8821a_mac"
    const val TBL_AGC = "rtw8821a_agc"
    const val TBL_BB = "rtw8821a_bb"
    const val TBL_RF_A = "rtw8821a_rf_a"

    val LSSI_WRITE = intArrayOf(Rtl88Regs.LSSI_WRITE_A)

    val PWR_ON: Array<PwrCmd> = arrayOf(
        pwrW(0x0005, 0x88, 0x00),
        pwrW(0x004A, 0x01, 0x00),
        pwrW(0x0005, 0x18, 0x00),
        pwrW(0x0020, 0x01, 0x01),
        pwrW(0x0067, 0x10, 0x00),
        pwrDelayMs(1),
        pwrW(0x0000, 0x20, 0x00),
        pwrW(0x0005, 0x1C, 0x00),
        pwrPoll(0x0006, 0x02, 0x02),
        pwrW(0x0006, 0x01, 0x01),
        pwrW(0x0005, 0x80, 0x00),
        pwrW(0x0005, 0x18, 0x00),
        pwrW(0x0005, 0x01, 0x01),
        pwrPoll(0x0005, 0x01, 0x00),
        pwrW(0x004F, 0x01, 0x01),
        pwrW(0x0067, 0x30, 0x30),
        pwrW(0x0025, 0x40, 0x00),
        pwrW(0x0049, 0x02, 0x02),
        pwrW(0x0063, 0x02, 0x02),
        pwrW(0x0062, 0x02, 0x00),
        pwrW(0x0058, 0x01, 0x01),
        pwrW(0x005A, 0x02, 0x02),
        pwrW(0x002E, 0xFF, 0x82),
        pwrW(0x0010, 0x40, 0x40),
    )

    val PWR_OFF: Array<PwrCmd> = arrayOf(
        pwrW(0x001F, 0xFF, 0x00),
        pwrW(0x004F, 0x01, 0x00),
        pwrW(0x0049, 0x02, 0x00),
        pwrW(0x0006, 0x01, 0x01),
        pwrW(0x0005, 0x02, 0x02),
        pwrPoll(0x0005, 0x02, 0x00),
        pwrW(0x0000, 0x20, 0x20),
        pwrW(0x0020, 0x01, 0x00),
        pwrW(0x0005, 0x18, 0x08),
        pwrW(0x004A, 0x01, 0x01),
    )

    fun pageTable(bulkOut: Int): IntArray = when (bulkOut) {
        2 -> intArrayOf(8, 0, 0, 0, 1)
        3 -> intArrayOf(8, 0, 8, 0, 1)
        else -> intArrayOf(8, 0, 8, 4, 1)
    }

    fun rqpn(bulkOut: Int): IntArray = when (bulkOut) {
        2 -> intArrayOf(Rtl88Regs.DMA_HIGH, Rtl88Regs.DMA_HIGH, Rtl88Regs.DMA_NORMAL, Rtl88Regs.DMA_NORMAL, Rtl88Regs.DMA_HIGH, Rtl88Regs.DMA_HIGH)
        3 -> intArrayOf(Rtl88Regs.DMA_HIGH, Rtl88Regs.DMA_NORMAL, Rtl88Regs.DMA_LOW, Rtl88Regs.DMA_LOW, Rtl88Regs.DMA_HIGH, Rtl88Regs.DMA_HIGH)
        else -> intArrayOf(Rtl88Regs.DMA_NORMAL, Rtl88Regs.DMA_NORMAL, Rtl88Regs.DMA_LOW, Rtl88Regs.DMA_LOW, Rtl88Regs.DMA_EXTRA, Rtl88Regs.DMA_HIGH)
    }
}

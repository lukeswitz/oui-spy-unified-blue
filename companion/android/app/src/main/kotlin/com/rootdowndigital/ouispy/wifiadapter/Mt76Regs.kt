package com.rootdowndigital.ouispy.wifiadapter

// Register addresses and values transcribed from the Linux mt76 driver
// (drivers/net/wireless/mediatek/mt76), SPDX-License-Identifier: BSD-3-Clause-Clear,
// Copyright (C) 2016 Felix Fietkau, Copyright (C) 2018 Lorenzo Bianconi.
// These are hardware constants for the MT7612U, not copied driver code.
internal object Mt76Regs {
    const val VENDOR_WRITE = 0x06
    const val VENDOR_READ = 0x07
    const val VENDOR_WRITE_CFG = 0x46
    const val VENDOR_READ_CFG = 0x47
    const val VENDOR_READ_EEPROM = 0x09
    const val VENDOR_WRITE_FCE = 0x42
    const val VENDOR_DEV_MODE = 0x01

    const val DIR_OUT = 0x40
    const val DIR_IN = 0xC0
    const val TYPE_CLASS_OUT = 0x20

    // MAC / system
    const val ASIC_VERSION = 0x0000
    const val WLAN_FUN_CTRL = 0x0080
    const val MAC_CSR0 = 0x1000
    const val MAC_SYS_CTRL = 0x1004
    const val MAC_STATUS = 0x1200
    const val WPDMA_GLO_CFG = 0x0208
    const val RX_FILTR_CFG = 0x1400
    const val PBF_TX_MAX_PCNT = 0x0408
    const val PBF_RX_MAX_PCNT = 0x040c
    const val TX_LINK_CFG = 0x1350
    const val AUTO_RSP_CFG = 0x1404
    const val MAX_LEN_CFG = 0x1018
    const val WMM_AIFSN = 0x0214
    const val WMM_CWMIN = 0x0218
    const val WMM_CWMAX = 0x021c
    const val COEXCFG0 = 0x0040
    const val EXT_CCA_CFG = 0x141c
    const val TX_ALC_CFG_4 = 0x13c0
    const val US_CYC_CFG = 0x02a4
    const val TXOP_CTRL_CFG = 0x1340
    const val CH_IDLE = 0x1130
    const val CH_BUSY = 0x1134
    const val CH_TIME_CFG = 0x110c

    // WLAN_FUN_CTRL bits
    const val WLAN_EN = 1 shl 0
    const val WLAN_CLK_EN = 1 shl 1
    const val WLAN_RESET_RF = 1 shl 2
    const val FRC_WL_ANT_SEL = 1 shl 5

    // MAC_SYS_CTRL bits
    const val SYS_CTRL_RESET_CSR = 1 shl 0
    const val SYS_CTRL_RESET_BBP = 1 shl 1
    const val SYS_CTRL_ENABLE_TX = 1 shl 2
    const val SYS_CTRL_ENABLE_RX = 1 shl 3

    const val STATUS_TX = 1 shl 0
    const val STATUS_RX = 1 shl 1
    const val WPDMA_TX_BUSY = 1 shl 1
    const val WPDMA_RX_BUSY = 1 shl 3
    const val COEX_EN = 1 shl 0
    const val FILTR_CRC_ERR = 1 shl 0
    const val FILTR_PHY_ERR = 1 shl 1

    // USB DMA (CFG space)
    const val USB_U3DMA_CFG = 0x9018
    const val DMA_RX_DROP_OR_PAD = 1 shl 18
    const val DMA_RX_BULK_AGG_EN = 1 shl 21
    const val DMA_RX_BULK_EN = 1 shl 22
    const val DMA_TX_BULK_EN = 1 shl 23

    // FCE / firmware upload
    const val FCE_PSE_CTRL = 0x0800
    const val FCE_DMA_ADDR = 0x0230
    const val FCE_DMA_LEN = 0x0234
    const val TX_CPU_FROM_FCE_BASE_PTR = 0x09a0
    const val TX_CPU_FROM_FCE_MAX_COUNT = 0x09a4
    const val TX_CPU_FROM_FCE_CPU_DESC_IDX = 0x09a8
    const val FCE_PDMA_GLOBAL_CONF = 0x09c4
    const val FCE_SKIP_FS = 0x0a6c
    const val MCU_CLOCK_CTL = 0x0708
    const val MCU_COM_REG0 = 0x0730

    const val ILM_OFFSET = 0x80000
    const val DLM_OFFSET = 0x110000
    const val ROM_PATCH_OFFSET = 0x90000
    const val FW_URB_MAX_PAYLOAD = 0x3900
    const val ROM_PATCH_MAX_PAYLOAD = 2048
    const val FW_HDR_LEN = 32
    const val PATCH_HDR_LEN = 30
    const val REV_E3 = 0x22
    const val USB_DMA_CFG_UPLOAD = (1 shl 22) or (1 shl 23) or 0x20

    // MCU command framing (mt76x02 FCE in-band)
    const val CPU_TX_PORT = 2
    const val MCU_MSG_TYPE_CMD = 1 shl 30
    const val EVT_CMD_DONE = 0

    const val CMD_FUN_SET_OP = 1
    const val CMD_LOAD_CR = 2
    const val CMD_INIT_GAIN_OP = 3
    const val CMD_POWER_SAVING_OP = 20
    const val CMD_SWITCH_CHANNEL_OP = 30
    const val CMD_CALIBRATION_OP = 31

    const val Q_SELECT = 1
    const val RADIO_ON = 0x31
    const val MT_RF_BBP_CR = 2

    const val MCU_CAL_TEMP = 2
    const val MCU_CAL_RXDCOC = 3
    const val MCU_CAL_RC = 4
    const val MCU_CAL_LC = 6
    const val MCU_CAL_TX_LOFT = 7
    const val MCU_CAL_TXIQ = 8
    const val MCU_CAL_RXIQC_FI = 12
    const val MCU_CAL_TX_SHAPING = 15
    const val TX_PIN_CFG = 0x1328
    const val TXOP_HLDR_ET = 0x1608

    // BBP (via MAC addr space)
    const val BBP_AGC0 = 0x2300
    const val BBP_AGC2 = 0x2308
    const val BBP_AGC7 = 0x231c
    const val BBP_AGC11 = 0x232c
    const val BBP_AGC61 = 0x23f4
    const val BBP_TXO4 = 0x2610
    const val BBP_RXO13 = 0x2934
    const val BBP_CORE1 = 0x2004
    const val TX_BAND_CFG = 0x132c

    // EEPROM offsets
    const val EE_SIZE = 512
    const val EE_MAC_ADDR = 0x004
    const val EE_NIC_CONF_0 = 0x034
    const val EE_NIC_CONF_1 = 0x036
    const val EE_LNA_GAIN = 0x044
    const val EE_RSSI_OFFSET_2G_0 = 0x046
    const val EE_RSSI_OFFSET_2G_1 = 0x048
    const val EE_RSSI_OFFSET_5G_0 = 0x04a
    const val EE_XTAL_TRIM_1 = 0x03a
    const val EE_XTAL_TRIM_2 = 0x09e
    const val EE_NIC_CONF_2 = 0x042

    // Firmware blobs from linux-firmware, redistributable under MediaTek's own terms.
    const val ROM_PATCH_FILE = "mt7662_rom_patch.bin"
    const val FIRMWARE_FILE = "mt7662.bin"
    const val ROM_PATCH_SHA256 = "6f0e871268f6e4d99196d90d89bcc09fe493d010366260a2cfcaa5dd66095f8c"
    const val FIRMWARE_SHA256 = "f7e52492f58088cae50e51a54cca68e4abc5b74f7d0b6b731dbb4c04465a94b6"
    const val FW_BASE_URL =
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/"

    // MAC init table (mt76x2/init.c mt76_write_mac_initvals), addr to value.
    val MAC_INITVALS: Array<IntArray> = arrayOf(
        intArrayOf(0x0400, 0x00080c00), intArrayOf(0x0404, 0x1efebcff), intArrayOf(0x0800, 0x00000001),
        intArrayOf(0x1004, 0x00000000), intArrayOf(0x1018, 0x003e3f00), intArrayOf(0x1030, 0xaaa99887.toInt()),
        intArrayOf(0x1034, 0x000000aa), intArrayOf(0x1100, 0x33a40d0a), intArrayOf(0x1104, 0x00000209),
        intArrayOf(0x1118, 0x00422010), intArrayOf(0x1204, 0x00000000), intArrayOf(0x1238, 0x001700c8),
        intArrayOf(0x1330, 0x00101001), intArrayOf(0x1334, 0x00010000), intArrayOf(0x1338, 0x00000000),
        intArrayOf(0x1340, 0x0400583f), intArrayOf(0x1344, 0x00ffff20), intArrayOf(0x1348, 0x000a2290),
        intArrayOf(0x134c, 0x47f01f0f), intArrayOf(0x1380, 0x002c00dc), intArrayOf(0x13e0, 0xe3f42004.toInt()),
        intArrayOf(0x13e4, 0xe3f42084.toInt()), intArrayOf(0x13e8, 0xe3f42104.toInt()), intArrayOf(0x13ec, 0x00060fff),
        intArrayOf(0x1400, 0x00015f97), intArrayOf(0x1408, 0x0000017f), intArrayOf(0x140c, 0x00004003),
        intArrayOf(0x150c, 0x00000003), intArrayOf(0x1608, 0x00000002), intArrayOf(0x0a44, 0x00000000),
        intArrayOf(0x0260, 0x00000000), intArrayOf(0x0250, 0x00000000), intArrayOf(0x120c, 0x00000000),
        intArrayOf(0x1264, 0x00000000), intArrayOf(0x13c0, 0x00000000), intArrayOf(0x13c8, 0x00000000),
        intArrayOf(0x1314, 0x3a3a3a3a), intArrayOf(0x1318, 0x3a3a3a3a), intArrayOf(0x131c, 0x3a3a3a3a),
        intArrayOf(0x1320, 0x3a3a3a3a), intArrayOf(0x1324, 0x3a3a3a3a), intArrayOf(0x13d4, 0x3a3a3a3a),
        intArrayOf(0x13d8, 0x0000003a), intArrayOf(0x13dc, 0x0000003a), intArrayOf(0x0024, 0x0000d000),
        intArrayOf(0x0a38, 0x0000000a), intArrayOf(0x0824, 0x60401c18), intArrayOf(0x0210, 0x94ff0000.toInt()),
        intArrayOf(0x1478, 0x00000004), intArrayOf(0x1384, 0x00001818), intArrayOf(0x1358, 0xedcba980.toInt()),
        intArrayOf(0x1648, 0x00830083), intArrayOf(0x1410, 0x000001ff), intArrayOf(0x1350, 0x00001020),
    )

    // Channel plan: 2.4 GHz 1-13, then 5 GHz UNII bands.
    val CHANNELS: IntArray = intArrayOf(
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
        36, 40, 44, 48, 52, 56, 60, 64,
        100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144,
        149, 153, 157, 161, 165,
    )

    fun freqOf(ch: Int): Int = if (ch <= 14) 2407 + ch * 5 else 5000 + ch * 5
}

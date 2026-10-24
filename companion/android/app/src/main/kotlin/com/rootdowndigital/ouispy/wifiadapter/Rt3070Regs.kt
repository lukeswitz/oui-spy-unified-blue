package com.rootdowndigital.ouispy.wifiadapter

// Register addresses and values for the Ralink RT3070/RT5370/RT5372 family, the hardware constants used by the
// Linux rt2800usb/rt2x00 driver (drivers/net/wireless/ralink/rt2x00, Copyright Ralink/rt2x00 project contributors).
// Hardware constants only, not copied driver code. unverified: every value below was transcribed from the
// Wardrive Go RT3070 bring-up reference (register-by-register); none was cross-checked against the upstream headers
// or run on hardware.
internal object Rt3070Regs {
    const val OUT_VENDOR = 0x40
    const val IN_VENDOR = 0xC0
    const val DEVICE_MODE = 0x01
    const val MULTI_WRITE = 0x06
    const val MULTI_READ = 0x07
    const val EEPROM_READ = 0x09

    const val USB_MODE_RESET = 1
    const val USB_MODE_FIRMWARE = 8
    const val USB_MODE_AUTORUN = 17

    const val FIRMWARE_IMAGE_BASE = 0x3000
    const val FW_BLOCK = 4096
    const val CSR_CACHE_SIZE = 64

    const val FIRMWARE_FILE = "rt2870.bin"
    const val FW_BASE_URL = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/"
    const val FIRMWARE_SHA256 = "251b8918391eac6415d60dca239e415aad0177e885376f2a17782e64fcbbe317"

    const val WPDMA_GLO_CFG = 0x0208
    const val USB_DMA_CFG = 0x02a0
    const val US_CYC_CNT = 0x02a4
    const val PBF_SYS_CTRL = 0x0400
    const val HOST_CMD_CSR = 0x0404
    const val PBF_CFG = 0x0408
    const val PBF_MAX_PCNT = 0x040c
    const val RF_CSR_CFG = 0x0500
    const val EFUSE_CTRL = 0x0580
    const val LDO_CFG0 = 0x05d4
    const val MAC_CSR0 = 0x1000
    const val MAC_SYS_CTRL = 0x1004
    const val MAX_LEN_CFG = 0x1018
    const val BBP_CSR_CFG = 0x101c
    const val LED_CFG = 0x102c
    const val XIFS_TIME_CFG = 0x1100
    const val BKOFF_SLOT_CFG = 0x1104
    const val CH_TIME_CFG = 0x110c
    const val BCN_TIME_CFG = 0x1114
    const val CH_IDLE_STA = 0x1130
    const val CH_BUSY_STA = 0x1134
    const val CH_BUSY_STA_SEC = 0x1138
    const val MAC_STATUS_CFG = 0x1200
    const val PWR_PIN_CFG = 0x1204
    const val AUTOWAKEUP_CFG = 0x1208
    const val TX_PIN_CFG = 0x1328
    const val TX_BAND_CFG = 0x132c
    const val TX_SW_CFG0 = 0x1330
    const val TX_SW_CFG1 = 0x1334
    const val TX_SW_CFG2 = 0x1338
    const val TXOP_CTRL_CFG = 0x1340
    const val TX_RTS_CFG = 0x1344
    const val TX_TIMEOUT_CFG = 0x1348
    const val TX_RTY_CFG = 0x134c
    const val TX_LINK_CFG = 0x1350
    const val HT_FBK_CFG0 = 0x1354
    const val HT_FBK_CFG1 = 0x1358
    const val LG_FBK_CFG0 = 0x135c
    const val LG_FBK_CFG1 = 0x1360
    const val CCK_PROT_CFG = 0x1364
    const val OFDM_PROT_CFG = 0x1368
    const val MM20_PROT_CFG = 0x136c
    const val MM40_PROT_CFG = 0x1370
    const val GF20_PROT_CFG = 0x1374
    const val GF40_PROT_CFG = 0x1378
    const val EXP_ACK_TIME = 0x1380
    const val RX_FILTR_CFG = 0x1400
    const val AUTO_RSP_CFG = 0x1404
    const val LEGACY_BASIC_RATE = 0x1408
    const val HT_BASIC_RATE = 0x140c
    const val TXOP_HLDR_ET = 0x1608
    const val H2M_MAILBOX_CSR = 0x7010
    const val H2M_MAILBOX_CID = 0x7014
    const val H2M_MAILBOX_STATUS = 0x701c
    const val H2M_INT_SRC = 0x7024
    const val H2M_BBP_AGENT = 0x7028

    val EFUSE_DATA = intArrayOf(0x059c, 0x0598, 0x0594, 0x0590)

    const val PBF_SYS_CTRL_READY = 0x80
    const val WPDMA_ENABLE_TX_DMA = 1 shl 0
    const val WPDMA_ENABLE_RX_DMA = 1 shl 2
    const val WPDMA_TX_BUSY = 1 shl 1
    const val WPDMA_RX_BUSY = 1 shl 3
    const val WPDMA_RX_WRITEBACK = 1 shl 6
    const val H2M_OWNER = 0xff000000.toInt()
    const val MCU_BOOT_SIGNAL = 0x72

    const val MAC_SYS_CTRL_ENABLE_TX = 0x04
    const val MAC_SYS_CTRL_ENABLE_RX = 0x08
    const val USB_DMA_CFG_RX_BULK_EN = 0x00400000
    const val USB_DMA_CFG_TX_BULK_EN = 0x00800000
    const val USB_DMA_CFG_RX_AGG_TIMEOUT = 0x80
    const val RX_FILTR_PROMISC = 0x00000003
    const val RX_FILTR_INIT = 0x00017f97

    const val BBP_CSR_READ = 0x10000
    const val BBP_CSR_BUSY = 0x20000
    const val BBP_CSR_MODE = 0x80000
    const val RF_CSR_WRITE = 0x10000
    const val RF_CSR_BUSY = 0x20000

    const val EFUSE_SEL = 0x80000000.toInt()
    const val EFUSE_KICK = 0x40000000
    const val EFUSE_ADDR_MASK = 0x03ff0000
    const val EFUSE_MODE_MASK = 0xc0000000.toInt()

    const val REV_RT3070F = 0x0201

    const val EE_FREQ_OFFSET_WORD = 0x1d
    const val EE_LNA_GAIN_WORD = 0x22
    const val EE_RSSI_OFFSET0_WORD = 0x23
    const val EE_MAC_BYTE = 4

    val HOP = intArrayOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13)
    val RF_N = intArrayOf(241, 241, 242, 242, 243, 243, 244, 244, 245, 245, 246, 246, 247)
    val RF_K = intArrayOf(2, 7, 2, 7, 2, 7, 2, 7, 2, 7, 2, 7, 2)
    fun freqOf(ch: Int) = 2407 + ch * 5

    val BBP_EARLY = arrayOf(
        65 to 0x2C, 66 to 0x38, 68 to 0x0B, 69 to 0x12, 70 to 0x0a, 73 to 0x10, 81 to 0x37, 82 to 0x62,
        83 to 0x6A, 84 to 0x99, 86 to 0x00, 91 to 0x04, 92 to 0x00, 103 to 0x00, 105 to 0x05, 106 to 0x35,
    )

    val BBP_TABLE = arrayOf(
        65 to 0x2c, 66 to 0x38, 69 to 0x12, 73 to 0x10, 70 to 0x0a, 79 to 0x13, 80 to 0x05, 81 to 0x33,
        82 to 0x62, 83 to 0x6a, 84 to 0x99, 86 to 0x00, 91 to 0x04, 92 to 0x00, 105 to 0x05, 106 to 0x35,
    )
    const val BBP103_REV_LT_F = 0x00
    const val BBP103_REV_GE_F = 0xc0

    val RFCSR_TABLE = arrayOf(
        4 to 0x40, 5 to 0x03, 6 to 0x02, 7 to 0x60, 9 to 0x0f, 10 to 0x41, 11 to 0x21, 12 to 0x7b,
        14 to 0x90, 15 to 0x58, 16 to 0xb3, 17 to 0x92, 18 to 0x2c, 19 to 0x02, 20 to 0xba, 21 to 0xdb,
        24 to 0x16, 25 to 0x03, 29 to 0x1f,
    )
}

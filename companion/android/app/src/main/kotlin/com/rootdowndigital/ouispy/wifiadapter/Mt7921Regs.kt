package com.rootdowndigital.ouispy.wifiadapter

internal object Mt7921Regs {
    const val DIR_IN = 0xDF
    const val DIR_OUT = 0x5F
    const val UHW_DIR_IN = 0xDE
    const val UHW_DIR_OUT = 0x5E
    const val VEND_READ_EXT = 0x63
    const val VEND_WRITE_EXT = 0x66
    const val VEND_POWER_ON = 0x04
    const val VEND_DEV_MODE = 0x01
    const val VEND_WRITE = 0x02

    const val HW_CHIPID = 0x70010200
    const val CONN_ON_MISC = 0x7c0600f0
    const val FW_PWR_ON = 0x1
    const val FW_STATE_MASK = 0x7
    const val FW_N9_RDY = 0x3

    const val SWDEF_MODE = 0x41f23c
    const val UDMA_TX_QSEL = 0x74000008
    val FW_DL_EN = 1 shl 3

    const val CBTOP_WF_SUBSYS_RST = 0x70002600
    const val WF_WHOLE_PATH = 0x1
    const val SSUSB_EP_RST_OPT = 0x74011890
    const val EP_RST_OPT_CLR = 0x7003F0
    const val UDMA_CONN_INFRA_STATUS = 0x74000a20
    val WFSYS_INIT_DONE = 1 shl 22
    const val UDMA_CONN_INFRA_STATUS_SEL = 0x74000a24

    const val UDMA_WLCFG_0 = 0x74000018
    const val UDMA_WLCFG_1 = 0x7400000c
    val WL_RX_FLUSH = 1 shl 19
    val WL_RX_EN = 1 shl 22
    val WL_TX_EN = 1 shl 23
    val WL_RX_MPSZ_PAD0 = 1 shl 18
    val TICK_1US_EN = 1 shl 20
    val WL_TX_TMOUT_FUNC_EN = 1 shl 16
    val WL_RX_BUSY = 1 shl 30
    val WL_TX_BUSY = 1 shl 31
    const val WL_RX_AGG_TO = 0xff
    const val WL_RX_AGG_LMT = 0xff00
    const val WL_RX_AGG_PKT_LMT = 0xff
    const val WL_TX_TMOUT_LMT = 0x0fffff00

    const val UWFDMA0_GLO_CFG = 0x7c024208
    const val UWFDMA0_TX_RING_EXT_CTRL_BASE = 0x7c024600
    const val GLO_TX_DMA_EN = 0x1
    val GLO_RX_DMA_EN = 1 shl 2
    val GLO_RX_DMA_BUSY = 1 shl 3
    val GLO_FW_DWLD_BYPASS_DMASHDL = 1 shl 9
    val GLO_OMIT_RX_INFO_PFET2 = 1 shl 21
    val GLO_OMIT_RX_INFO = 1 shl 27
    val GLO_OMIT_TX_INFO = 1 shl 28
    const val WPDMA0_MAX_CNT_MASK = 0xff
    val WPDMA0_BASE_PTR_MASK = 0xffff shl 16

    const val DMASHDL_PAGE = 0x7c02600c
    val DMASHDL_GROUP_SEQ_ORDER = 1 shl 16
    const val DMASHDL_REFILL = 0x7c026010
    val DMASHDL_REFILL_MASK = 0xffff shl 16
    const val DMASHDL_PKT_MAX_SIZE = 0x7c02601c
    const val DMASHDL_PKT_MAX_SIZE_MASK = 0x0fff0fff
    const val DMASHDL_GROUP_QUOTA_BASE = 0x7c026020
    const val DMASHDL_Q_MAP_BASE = 0x7c026060
    const val DMASHDL_SCHED_SET_BASE = 0x7c026070

    const val WFDMA_DUMMY_CR = 0x54000120
    val WFDMA_NEED_REINIT = 1 shl 1
    const val WFDMA_HOST_CONFIG = 0x7c027030
    val WFDMA_HOST_CONFIG_USB_RXEVT_EP4_EN = 1 shl 6

    const val MCU_TARGET_ADDR_LEN = 0x01
    const val MCU_FW_START = 0x02
    const val MCU_NIC_POWER_CTRL = 0x04
    const val MCU_PATCH_START = 0x05
    const val MCU_PATCH_FINISH = 0x07
    const val MCU_PATCH_SEM = 0x10
    const val MCU_FW_SCATTER = 0xee
    const val MCU_PATCH_ADDRESS = 0x200000
    const val CONNAC2_DL_ADDR = 0x900000

    const val MCU_PKT_ID = 0xa0
    const val MCU_Q_NA = 3
    const val MCU_Q_SET = 1
    const val MCU_EXT_CID = 0xed
    const val MCU_CE_SET_RX_FILTER = 0x0a
    const val MCU_CE_GET_NIC_CAPAB = 0x8a
    const val MCU_EXT_CHANNEL_SWITCH = 0x08
    const val MCU_EXT_EFUSE_BUFFER_MODE = 0x21
    const val MCU_UNI_SNIFFER = 0x24
    val FILTER_MONITOR = (1 shl 31) or (1 shl 6) or (1 shl 5) or (1 shl 2)
    val FIF_BIT_CLR = 1 shl 1
    val MONITOR_DROP_CLEAR = (1 shl 0) or (1 shl 3) or (1 shl 4) or (1 shl 5) or
        (1 shl 6) or (1 shl 7) or (1 shl 8) or (1 shl 9) or (1 shl 10) or (1 shl 11) or
        (1 shl 13) or (1 shl 16) or (1 shl 17) or (1 shl 18) or (1 shl 19) or (1 shl 21)
    const val TX_TYPE_CMD = 2
    const val HDR_FORMAT_CMD = 1
    const val TX_MCU_PORT_RX_Q0 = 0x20

    val DL_MODE_NEED_RSP = 1 shl 31
    const val DL_MODE_ENCRYPT = 0x1
    val DL_MODE_RESET_SEC_IV = 1 shl 3
    const val FW_FEATURE_SET_ENCRYPT = 0x1
    val FW_FEATURE_OVERRIDE_ADDR = 1 shl 5
    val FW_FEATURE_NON_DL = 1 shl 6
    const val FW_START_OVERRIDE = 0x1

    const val DL_CHUNK = 4088

    const val FW_BASE_URL =
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/"
    const val PATCH_FILE = "WIFI_MT7961_patch_mcu_1_2_hdr.bin"
    const val PATCH_SHA256 = "a276c06c2b772adb50b86639d33c82824ff4c21d617feb78caea74c040b873f6"
    const val RAM_FILE = "WIFI_RAM_CODE_MT7961_1.bin"
    const val RAM_SHA256 = "b94217a951518a9c14095765f367bc5dd7698f2dc033941d6f18fc2ebd6a2ab9"

    const val BT_FW_FILE = "BT_RAM_CODE_MT7961_1_2_hdr.bin"
    const val BT_FW_SHA256 = "7a440a0f7404c73a2f03d8cc0475ac9f7fdc931b494dce37705e7d578153dbae"

    const val BT_REG_READ_TYPE = 0xC0
    const val BT_REG_READ_REQ = 0x63
    const val BT_UHW_WRITE_TYPE = 0x5E
    const val BT_UHW_WRITE_REQ = 0x02
    const val BT_HCI_CMD_TYPE = 0x20
    const val BT_HCI_CMD_REQ = 0x00
    const val BT_WMT_EVT_TYPE = 0xC0
    const val BT_WMT_EVT_REQ = 0x01
    const val BT_WMT_EVT_VALUE = 48

    const val WMT_OPCODE = 0xfc6f
    const val HCI_EV_WMT = 0xe4
    const val WMT_PATCH_DWNLD = 0x1
    const val WMT_FUNC_CTRL = 0x6
    const val WMT_PATCH_UNDONE = 1
    const val WMT_PATCH_PROGRESS = 2
    const val WMT_PATCH_DONE = 3

    const val BT_DEV_ID_REG = 0x70010200
    const val BT_EP_RST_OPT_REG = 0x74011890
    const val BT_EP_RST_IN_OUT = 0x00010001

    const val FW_ROM_PATCH_HEADER_SIZE = 32
    const val FW_ROM_PATCH_GD_SIZE = 64
    const val FW_ROM_PATCH_SEC_MAP_SIZE = 64
    const val SEC_MAP_COMMON_SIZE = 12
    const val SEC_MAP_NEED_SEND_SIZE = 52
    const val WMT_DL_CHUNK = 250
}

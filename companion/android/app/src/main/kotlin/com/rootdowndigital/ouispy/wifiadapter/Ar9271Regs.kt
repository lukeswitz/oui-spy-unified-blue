package com.rootdowndigital.ouispy.wifiadapter

// Hardware constants transcribed from the Linux ath9k driver (Atheros Communications, ISC license); not copied driver code.
internal object Ar9271Regs {
    const val FIRMWARE_FILE = "htc_9271-1.4.0.fw"
    const val FIRMWARE_SHA256 = "78f7d592a95b419a02fde7440f30c606fc31a871cf0ce150ced40d4857173eb0"
    const val FW_BASE_URL =
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath9k_htc/"

    const val DIR_OUT = 0x40
    const val EP_RX = 2
    const val EP_REG_IN = 3
    const val EP_REG_OUT = 4
    const val FW_DOWNLOAD = 0x30
    const val FW_DOWNLOAD_COMP = 0x31
    const val FW_LOAD_ADDR = 0x501000
    const val FW_TEXT_ADDR = 0x903000
    const val FW_CHUNK = 4096
    const val FW_MAJOR = 1
    const val FW_MINOR_MIN = 3

    const val CTL_TIMEOUT = 1000
    const val REG_TIMEOUT = 1000
    const val WMI_TIMEOUT = 2000
    const val READY_TIMEOUT = 2000
    const val MAX_WRITES = 62
    const val MAX_MULTI_READ = 8
    const val RX_BUF_SIZE = 16384
    const val RX_MAX_PKT = 32768
    const val RX_STREAM_TAG = 0x4e00
    const val RX_STATUS_LEN = 40
    const val RX_ERR_IGNORED = 0x08 or 0x10 or 0x20
    const val RSSI_BAD = -128
    const val NOISE_FLOOR = -95

    const val HTC_HDR_LEN = 8
    const val HTC_FLAG_TRAILER = 0x02
    const val HTC_WATCHDOG_PATTERN = 0x00C60000
    const val HTC_PANIC_EPID = 0x99
    const val HTC_MSG_READY = 1
    const val HTC_MSG_CONNECT_SERVICE = 2
    const val HTC_MSG_CONNECT_RESPONSE = 3
    const val HTC_MSG_SETUP_COMPLETE = 4
    const val HTC_MSG_CONFIG_PIPE = 5
    const val HTC_MSG_CONFIG_PIPE_RESPONSE = 6
    const val HTC_CREDITS = 33
    const val HTC_TX_PIPE = 1
    const val HTC_WMI_EPID_PROBE = 1

    const val SVC_WMI_CONTROL = 0x100
    const val SVC_WMI_BEACON = 0x101
    const val SVC_WMI_CAB = 0x102
    const val SVC_WMI_UAPSD = 0x103
    const val SVC_WMI_MGMT = 0x104
    const val SVC_WMI_DATA_VO = 0x105
    const val SVC_WMI_DATA_VI = 0x106
    const val SVC_WMI_DATA_BE = 0x107
    const val SVC_WMI_DATA_BK = 0x108
    val SERVICES: IntArray = intArrayOf(
        SVC_WMI_CONTROL, SVC_WMI_BEACON, SVC_WMI_CAB, SVC_WMI_UAPSD, SVC_WMI_MGMT,
        SVC_WMI_DATA_BE, SVC_WMI_DATA_BK, SVC_WMI_DATA_VI, SVC_WMI_DATA_VO,
    )
    const val PIPE_WMI_UL = 4
    const val PIPE_WMI_DL = 3
    const val PIPE_DATA_UL = 1
    const val PIPE_DATA_DL = 2

    const val WMI_GET_FW_VERSION = 0x03
    const val WMI_DISABLE_INTR = 0x04
    const val WMI_ENABLE_INTR = 0x05
    const val WMI_ATH_INIT = 0x06
    const val WMI_DRAIN_TXQ_ALL = 0x0b
    const val WMI_START_RECV = 0x0c
    const val WMI_STOP_RECV = 0x0d
    const val WMI_FLUSH_RECV = 0x0e
    const val WMI_SET_MODE = 0x0f
    const val WMI_NODE_CREATE = 0x10
    const val WMI_NODE_REMOVE = 0x11
    const val WMI_VAP_REMOVE = 0x12
    const val WMI_VAP_CREATE = 0x13
    const val WMI_REG_READ = 0x14
    const val WMI_REG_WRITE = 0x15
    const val WMI_TARGET_IC_UPDATE = 0x18
    const val WMI_EVENT_FLAG = 0x1000
    const val HTC_MODE_11NG = 1
    const val HTC_M_MONITOR = 8

    const val AR_CR = 0x0008
    const val CR_RXE = 0x00000004
    const val AR_RIMT = 0x002c
    const val RIMT_LAST = 0x0000ffff
    const val RIMT_FIRST = 0xffff0000.toInt()
    const val AR_CFG = 0x0014
    const val CFG_SWTB = 0x00000002
    const val CFG_SWRB = 0x00000008
    const val AR_CFG_LED = 0x1f04
    const val CFG_SCLK_32KHZ = 0x00000003
    const val LED_BLINK_SLOW = 0x00000008
    const val LED_BLINK_THRESH_SEL = 0x00000070
    const val LED_MODE_SEL = 0x00000380
    const val LED_ASSOC_CTL = 0x00000c00
    const val AR_TXCFG = 0x0030
    const val DMASZ_MASK = 0x00000007
    const val DMASZ_128B = 5
    const val AR_RXCFG = 0x0034
    const val RXCFG_ZLFDMA = 0x00000010
    const val AR_Q_TXE = 0x0840
    const val AR_ISR = 0x0080
    const val AR_IMR = 0x00a0
    const val AR_IMR_S2 = 0x00ac
    const val IMR_RXERR = 0x00000004
    const val IMR_RXORN = 0x00000020
    const val IMR_TXOK = 0x00000040
    const val IMR_TXERR = 0x00000100
    const val IMR_TXURN = 0x00000800
    const val IMR_BCNMISC = 0x00800000
    const val IMR_RXMINTR = 0x01000000
    const val IMR_RXINTM = 0x80000000.toInt()
    const val IMR_S2_GTT = 0x00800000
    const val AR_GTXTO = 0x0064
    const val AR_CST = 0x006c
    const val TIMEOUT_LIMIT_SHIFT = 16
    const val AR_EEPROM_STATUS_DATA = 0x407c
    const val EEPROM_STATUS_BUSY = 0x00010000
    const val EEPROM_STATUS_PROT_ACCESS = 0x00040000
    const val EEPROM_STATUS_VAL = 0x0000ffff
    const val AR_EEPROM_BASE = 0x2000
    const val EEPROM_WORD_SHIFT = 2

    const val AR_RC = 0x4000
    const val RC_AHB = 0x00000001
    const val RC_HOSTIF = 0x00000100
    const val AR_SREV = 0x4020
    const val SREV_VERSION2 = 0xfffc0000.toInt()
    const val SREV_VERSION2_SHIFT = 18
    const val SREV_REVISION2 = 0x00000f00
    const val SREV_REVISION2_SHIFT = 8
    const val SREV_ID_MASK = 0xff
    const val SREV_VERSION_9271 = 0x140
    const val AR_AHB_MODE = 0x4024
    const val AHB_PREFETCH_RD_EN = 0x00000004
    const val AR_INTR_SYNC_CAUSE = 0x4028
    const val AR_INTR_SYNC_ENABLE = 0x402c
    const val AR_INTR_SYNC_MASK = 0x4034
    const val SYNC_RADM_CPL_TIMEOUT = 0x00001000
    const val SYNC_LOCAL_TIMEOUT = 0x00002000
    const val SYNC_DEFAULT = 0x00023f60
    const val AR_GPIO_INPUT_EN_VAL = 0x4054
    const val GPIO_JTAG_DISABLE = 0x00020000
    const val AR_OBS = 0x4080

    const val AR_RTC_RC = 0x7000
    const val RTC_RC_M = 0x00000003
    const val RTC_RC_MAC_WARM = 0x00000001
    const val RTC_RC_MAC_COLD = 0x00000002
    const val AR_RTC_PLL_CONTROL = 0x7014
    const val PLL_CONTROL_2G = (5 shl 10) or 0x2c
    const val AR_RTC_RESET = 0x7040
    const val AR_RTC_STATUS = 0x7044
    const val RTC_STATUS_M = 0x0000000f
    const val RTC_STATUS_SHUTDOWN = 0x00000001
    const val RTC_STATUS_ON = 0x00000002
    const val AR_RTC_SLEEP_CLK = 0x7048
    const val RTC_FORCE_DERIVED_CLK = 0x2
    const val AR_RTC_FORCE_WAKE = 0x704c
    const val RTC_FORCE_WAKE_EN = 0x00000001
    const val RTC_FORCE_WAKE_ON_INT = 0x00000002

    const val AR_STA_ID0 = 0x8000
    const val AR_STA_ID1 = 0x8004
    const val STA_ID1_SADH_MASK = 0x0000ffff
    const val STA_ID1_STA_AP = 0x00010000
    const val STA_ID1_ADHOC = 0x00020000
    const val STA_ID1_PWR_SAV = 0x00040000
    const val STA_ID1_RTS_USE_DEF = 0x00800000
    const val STA_ID1_BASE_RATE_11B = 0x02000000
    const val STA_ID1_CRPT_MIC_ENABLE = 0x08000000
    const val STA_ID1_KSRCH_MODE = 0x10000000
    const val STA_ID1_PRESERVE_SEQNUM = 0x20000000
    const val STA_ID1_MCAST_KSRCH = 0x80000000.toInt()
    const val AR_BSS_ID0 = 0x8008
    const val AR_BSS_ID1 = 0x800c
    const val AR_RSSI_THR = 0x8018
    const val INIT_RSSI_THR = 0x00000700
    const val AR_USEC = 0x801c
    const val USEC_MASK = 0x0000007f
    const val AR_RX_FILTER = 0x803c
    const val AR_MCAST_FIL0 = 0x8040
    const val AR_MCAST_FIL1 = 0x8044
    const val AR_DIAG_SW = 0x8048
    const val DIAG_ACK_DIS = 0x00000002
    const val DIAG_CTS_DIS = 0x00000004
    const val DIAG_RX_DIS = 0x00000020
    const val DIAG_RX_ABORT = 0x02000000
    const val AR_DEF_ANTENNA = 0x8058
    const val AR_AES_MUTE_MASK1 = 0x8060
    const val AES_MUTE_FC_MGMT_MASK = 0xffff0000.toInt()
    const val AES_MUTE_FC_MGMT_SHIFT = 16
    const val AR_BSSMSKL = 0x80e0
    const val AR_BSSMSKU = 0x80e4
    const val AR_PHY_ERR = 0x810c
    const val AR_RXFIFO_CFG = 0x8114
    const val AR_PCU_MISC = 0x8120
    const val PCU_MIC_NEW_LOC_ENA = 0x00000004
    const val AR_SELFGEN_MASK = 0x832c
    const val AR_2040_MODE = 0x8318
    const val AR_PCU_MISC_MODE2 = 0x8344
    const val MODE2_ADHOC_MCAST_KEYID_ENABLE = 0x00000040
    const val MODE2_CFP_IGNORE = 0x00000080

    const val FILTER_UCAST = 0x00000001
    const val FILTER_MCAST = 0x00000002
    const val FILTER_BCAST = 0x00000004
    const val FILTER_BEACON = 0x00000010
    const val FILTER_PROM = 0x00000020
    const val RX_FILTER_MONITOR = FILTER_UCAST or FILTER_MCAST or FILTER_BCAST or FILTER_BEACON or FILTER_PROM
    const val RX_FILTER_PRE_MONITOR = FILTER_UCAST or FILTER_MCAST or FILTER_BCAST or FILTER_BEACON

    const val AR_PHY_BASE = 0x9800
    const val AR_PHY_TURBO = 0x9804
    const val PHY_FC_DYN2040_EN = 0x00000004
    const val PHY_FC_HT_EN = 0x00000040
    const val PHY_FC_SHORT_GI_40 = 0x00000080
    const val PHY_FC_WALSH = 0x00000100
    const val PHY_FC_SINGLE_HT_LTF1 = 0x00000200
    const val PHY_FC_ENABLE_DAC_FIFO = 0x00000800
    const val AR_PHY_TIMING3 = 0x9814
    const val TIMING3_DSC_MAN = 0xfffe0000.toInt()
    const val TIMING3_DSC_MAN_SHIFT = 17
    const val TIMING3_DSC_EXP = 0x0001e000
    const val TIMING3_DSC_EXP_SHIFT = 13
    const val AR_PHY_ACTIVE = 0x981c
    const val PHY_ACTIVE_EN = 1
    const val PHY_ACTIVE_DIS = 0
    const val AR_PHY_RF_CTL2 = 0x9824
    const val RF_CTL2_TX_END_DATA_START = 0x000000ff
    const val RF_CTL2_TX_END_DATA_START_SHIFT = 0
    const val RF_CTL2_TX_END_PA_ON = 0x0000ff00
    const val RF_CTL2_TX_END_PA_ON_SHIFT = 8
    const val AR_PHY_RF_CTL3 = 0x9828
    const val RF_CTL3_TX_END_TO_A2_RX_ON = 0x00ff0000
    const val RF_CTL3_TX_END_TO_A2_RX_ON_SHIFT = 16
    const val RF_CTL3_TX_END_TO_ADC_ON = 0xff000000.toInt()
    const val RF_CTL3_TX_END_TO_ADC_ON_SHIFT = 24
    const val AR_PHY_ADC_CTL = 0x982c
    const val ADC_CTL_OFF_PWDADC = 0x00008000
    const val AR_PHY_ADC_SERIAL_CTL = 0x9830
    const val SEL_INTERNAL_ADDAC = 0
    const val SEL_EXTERNAL_RADIO = 1
    const val AR_PHY_RF_CTL4 = 0x9834
    const val RF_CTL4_FRAME_XPAA_ON = 0x000000ff
    const val RF_CTL4_FRAME_XPAA_ON_SHIFT = 0
    const val RF_CTL4_FRAME_XPAB_ON = 0x0000ff00
    const val RF_CTL4_FRAME_XPAB_ON_SHIFT = 8
    const val RF_CTL4_TX_END_XPAA_OFF = 0x00ff0000
    const val RF_CTL4_TX_END_XPAA_OFF_SHIFT = 16
    const val RF_CTL4_TX_END_XPAB_OFF = 0xff000000.toInt()
    const val RF_CTL4_TX_END_XPAB_OFF_SHIFT = 24
    const val AR_PHY_SETTLING = 0x9844
    const val SETTLING_SWITCH = 0x00003f80
    const val SETTLING_SWITCH_SHIFT = 7
    const val AR_PHY_RXGAIN = 0x9848
    const val RXGAIN_TXRX_ATTEN = 0x00003f80
    const val RXGAIN_TXRX_ATTEN_SHIFT = 7
    const val RXGAIN_TXRX_MARGIN = 0x001fc000
    const val RXGAIN_TXRX_MARGIN_SHIFT = 14
    const val AR_PHY_DESIRED_SZ = 0x9850
    const val DESIRED_SZ_ADC = 0x000000ff
    const val DESIRED_SZ_ADC_SHIFT = 0
    const val AR_PHY_AGC_CONTROL = 0x9860
    const val AGC_CONTROL_CAL = 0x00000001
    const val AGC_CONTROL_NF = 0x00000002
    const val AGC_CONTROL_ENABLE_NF = 0x00008000
    const val AGC_CONTROL_FLTR_CAL = 0x00010000
    const val AGC_CONTROL_NO_UPDATE_NF = 0x00020000
    const val AR_PHY_CCA = 0x9864
    const val CCA_THRESH62 = 0x000ff000
    const val CCA_THRESH62_SHIFT = 12
    const val AR_PHY_SYNTH_CONTROL = 0x9874
    const val AR_AN_RF2G3 = 0x7828
    const val AR_AN_RF2G4 = 0x782c
    const val AR_PHY_RX_DELAY = 0x9914
    const val RX_DELAY_MASK = 0x00003fff
    const val AR_PHY_SPECTRAL_SCAN = 0x9910
    const val SPECTRAL_SCAN_ENA = 0x00000001
    const val AR_PHY_TIMING_CTRL4 = 0x9920
    const val TIMING_CTRL4_IQCORR_Q_Q_COFF = 0x0000001f
    const val TIMING_CTRL4_IQCORR_Q_Q_COFF_SHIFT = 0
    const val TIMING_CTRL4_IQCORR_Q_I_COFF = 0x000007e0
    const val TIMING_CTRL4_IQCORR_Q_I_COFF_SHIFT = 5
    const val AR_PHY_SWITCH_CHAIN_0 = 0x9960
    const val AR_PHY_SWITCH_COM = 0x9964
    const val AR_PHY_RFBUS_REQ = 0x997c
    const val RFBUS_REQ_EN = 0x00000001
    const val AR_PHY_RX_CHAINMASK = 0x99a4
    const val AR_PHY_MULTICHAIN_GAIN_CTL = 0x99ac
    const val ANT_DIV_CTL_ALL = 0x7f000000
    const val ANT_DIV_CTL = 0x01000000
    const val ANT_DIV_CTL_SHIFT = 24
    const val ANT_DIV_ALT_LNACONF = 0x06000000
    const val ANT_DIV_ALT_LNACONF_SHIFT = 25
    const val ANT_DIV_MAIN_LNACONF = 0x18000000
    const val ANT_DIV_MAIN_LNACONF_SHIFT = 27
    const val ANT_DIV_ALT_GAINTB = 0x20000000
    const val ANT_DIV_ALT_GAINTB_SHIFT = 29
    const val ANT_DIV_MAIN_GAINTB = 0x40000000
    const val ANT_DIV_MAIN_GAINTB_SHIFT = 30
    const val AR_PHY_EXT_CCA0 = 0x99b8
    const val EXT_CCA0_THRESH62 = 0x000000ff
    const val EXT_CCA0_THRESH62_SHIFT = 0
    const val AR_PHY_HALFGI = 0x99d0
    const val HALFGI_DSC_MAN = 0x0007fff0
    const val HALFGI_DSC_MAN_SHIFT = 4
    const val HALFGI_DSC_EXP = 0x0000000f
    const val HALFGI_DSC_EXP_SHIFT = 0
    const val AR_PHY_MODE = 0xa200
    const val PHY_MODE_DYNAMIC = 0x00000004
    const val AR_PHY_CCK_DETECT = 0xa208
    const val CCK_DETECT_WEAK_SIG_THR_CCK = 0x0000003f
    const val CCK_DETECT_BB_ENABLE_ANT_FAST_DIV = 0x00002000
    const val CCK_DETECT_BB_ENABLE_ANT_FAST_DIV_SHIFT = 13
    const val AR_PHY_GAIN_2GHZ = 0xa20c
    const val GAIN_2GHZ_XATTEN1_DB = 0x0000003f
    const val GAIN_2GHZ_XATTEN1_DB_SHIFT = 0
    const val GAIN_2GHZ_XATTEN2_DB = 0x00000fc0
    const val GAIN_2GHZ_XATTEN2_DB_SHIFT = 6
    const val GAIN_2GHZ_XATTEN1_MARGIN = 0x0001f000
    const val GAIN_2GHZ_XATTEN1_MARGIN_SHIFT = 12
    const val GAIN_2GHZ_XATTEN2_MARGIN = 0x003e0000
    const val GAIN_2GHZ_XATTEN2_MARGIN_SHIFT = 17
    const val AR_PHY_CCK_TX_CTRL = 0xa204
    const val CCK_TX_CTRL_JAPAN = 0x00000010
    const val AR_PHY_TPCRG1 = 0xa258
    const val TPCRG1_PD_CAL_ENABLE = 0x00400000
    const val AR_PHY_CL_CAL_CTL = 0xa358
    const val CL_CAL_PARALLEL_ENABLE = 0x00000001
    const val CL_CAL_ENABLE = 0x00000002
    const val AR_PHY_CAL_CHAINMASK = 0xa39c
    const val AR_PHY_RFBUS_GRANT = 0x9c20
    const val RFBUS_GRANT_EN = 0x00000001
    const val AR_PHY_FORCE_CLKEN_CCK = 0xa22c
    const val FORCE_CLKEN_CCK_MRC_MUX = 0x00000040

    const val AR9271_RESET_POWER_DOWN_CONTROL = 0x50044
    const val AR9271_RADIO_RF_RST = 0x20
    const val AR9271_GATE_MAC_CTL = 0x4000
    const val AR9271_CORE_CLOCK = 0x50040
    const val AR9271_CORE_CLOCK_117MHZ = 0x304
    const val AN_RF2G3_OB_CCK = 0x001c0000
    const val AN_RF2G3_OB_CCK_SHIFT = 18
    const val AN_RF2G3_OB_PSK = 0x00038000
    const val AN_RF2G3_OB_PSK_SHIFT = 15
    const val AN_RF2G3_OB_QAM = 0x00007000
    const val AN_RF2G3_OB_QAM_SHIFT = 12
    const val AN_RF2G3_DB_1 = 0x00e00000
    const val AN_RF2G3_DB_1_SHIFT = 21
    const val AN_RF2G4_DB_2 = 0xe0000000.toInt()
    const val AN_RF2G4_DB_2_SHIFT = 29

    const val NF_NOMINAL_9271_2G = -118
    const val NF_LOAD_RESTORE = -50
    const val NF_MASK = 0x1ff
    const val NF_LOAD_TIMEOUT_MS = 23
    const val CAL_TIMEOUT_MS = 100
    const val WAIT_TIMEOUT_MS = 100
    const val RIMT_LAST_VALUE = 250
    const val RIMT_FIRST_VALUE = 700
    const val USEC_2G_OFDM = 44
    const val FTRIG_MASK = 0x000003f0
    const val FTRIG_SHIFT = 4
    const val FTRIG_256B_LEVEL = 4
    const val RXFIFO_CFG_VALUE = 0x200
    const val OBS_VALUE = 8
    const val SPUR_NONE = 0x8000
    const val SPUR_BASE_FREQ_2G = 2300
    const val SPUR_BOUND_HT20 = 10
    const val BASE_ACTIVATE_DELAY_US = 100
    const val DELTA_SLOPE_CLOCK_SCALED = 0x64000000
    const val COEF_SCALE_S = 24

    const val EEP_WORDS = 188
    const val EEP_START_WORD = 64
    const val EEP_MAGIC = 0xa55a
    const val EEP_VER_MAJOR = 0xe
    const val EEP_MIN_REV = 1
    const val EEP_BASE_LENGTH = 0
    const val EEP_BASE_VERSION = 4
    const val EEP_BASE_MAC = 12
    const val EEP_BASE_RX_MASK = 18
    const val EEP_BASE_TX_MASK = 19
    const val EEP_BASE_TXGAIN_TYPE = 31
    const val EEP_TXGAIN_HIGH_POWER = 1
    const val EEP_MODAL = 52
    const val M_ANT_CTRL_CHAIN0 = 0
    const val M_ANT_CTRL_COMMON = 4
    const val M_SWITCH_SETTLING = 9
    const val M_TXRX_ATTEN = 10
    const val M_RXTX_MARGIN = 11
    const val M_ADC_DESIRED = 12
    const val M_TX_END_XPA_OFF = 15
    const val M_TX_END_RX_ON = 16
    const val M_TX_FRAME_XPA_ON = 17
    const val M_THRESH62 = 18
    const val M_IQCAL_I = 22
    const val M_IQCAL_Q = 23
    const val M_OB_0_1 = 25
    const val M_DB1_0_1 = 26
    const val M_TX_FRAME_DATA_START = 28
    const val M_TX_FRAME_PA_ON = 29
    const val M_BSW_ATTEN = 31
    const val M_BSW_MARGIN = 32
    const val M_XATTEN2_DB = 34
    const val M_XATTEN2_MARGIN = 35
    const val M_DB2_0_1 = 36
    const val M_VERSION = 37
    const val M_OB_2_3 = 38
    const val M_OB_4_ANTDIV1 = 39
    const val M_DB1_4_ANTDIV2 = 41
    const val M_SPUR = 48
    const val M_SPUR_COUNT = 5
    const val EEP_REV_ATTEN = 3
    const val EEP_REV_RF_CTL2 = 2
    const val TXRX_ATTEN_DEFAULT = 23
    const val MODAL_VER_ANTDIV = 3
    const val MODAL_VER_OB_DB = 2

    val CHANNELS: IntArray = intArrayOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13)

    fun freqOf(ch: Int): Int = 2407 + ch * 5

    val INI_MODES_2G_HT20: LongArray = longArrayOf(
        0x00001030, 0x00000160, 0x00001070, 0x0000018c,
        0x000010b0, 0x00003e38, 0x000010f0, 0x00000000,
        0x00008014, 0x08400b00, 0x0000801c, 0x12e0002b,
        0x00008318, 0x00003440, 0x00009804, 0x00000300,
        0x00009820, 0x02020200, 0x00009824, 0x01000e0e,
        0x00009828, 0x3a020001, 0x00009834, 0x00000e0e,
        0x00009838, 0x00000007, 0x00009840, 0x206a012e,
        0x00009844, 0x03721620, 0x00009848, 0x00001053,
        0x0000a848, 0x00001053, 0x00009850, 0x6d4000e2,
        0x00009858, 0x7ec84d2e, 0x0000985c, 0x3137605e,
        0x00009860, 0x00058d18, 0x00009864, 0x0001ce00,
        0x00009868, 0x5ac640d0, 0x0000986c, 0x06903881,
        0x00009910, 0x30002310, 0x00009914, 0x00000898,
        0x00009918, 0x0000000b, 0x00009924, 0xd00a800d,
        0x00009944, 0xffbc1020, 0x00009960, 0x00000000,
        0x00009964, 0x00000000, 0x000099b8, 0x0000421c,
        0x000099bc, 0x00000c00, 0x000099c0, 0x05eea6d4,
        0x000099c4, 0x06336f77, 0x000099c8, 0x6af6532f,
        0x000099cc, 0x08f186c8, 0x000099d0, 0x00046384,
        0x000099d4, 0x00000000, 0x000099d8, 0x00000000,
        0x00009a00, 0x00058084, 0x00009a04, 0x00058088,
        0x00009a08, 0x0005808c, 0x00009a0c, 0x00058100,
        0x00009a10, 0x00058104, 0x00009a14, 0x00058108,
        0x00009a18, 0x0005810c, 0x00009a1c, 0x00058110,
        0x00009a20, 0x00058114, 0x00009a24, 0x00058180,
        0x00009a28, 0x00058184, 0x00009a2c, 0x00058188,
        0x00009a30, 0x0005818c, 0x00009a34, 0x00058190,
        0x00009a38, 0x00058194, 0x00009a3c, 0x000581a0,
        0x00009a40, 0x0005820c, 0x00009a44, 0x000581a8,
        0x00009a48, 0x00058284, 0x00009a4c, 0x00058288,
        0x00009a50, 0x00058224, 0x00009a54, 0x00058290,
        0x00009a58, 0x00058300, 0x00009a5c, 0x00058304,
        0x00009a60, 0x00058308, 0x00009a64, 0x0005830c,
        0x00009a68, 0x00058380, 0x00009a6c, 0x00058384,
        0x00009a70, 0x00068700, 0x00009a74, 0x00068704,
        0x00009a78, 0x00068708, 0x00009a7c, 0x0006870c,
        0x00009a80, 0x00068780, 0x00009a84, 0x00068784,
        0x00009a88, 0x00078b00, 0x00009a8c, 0x00078b04,
        0x00009a90, 0x00078b08, 0x00009a94, 0x00078b0c,
        0x00009a98, 0x00078b80, 0x00009a9c, 0x00078b84,
        0x00009aa0, 0x00078b88, 0x00009aa4, 0x00078b8c,
        0x00009aa8, 0x00078b90, 0x00009aac, 0x000caf80,
        0x00009ab0, 0x000caf84, 0x00009ab4, 0x000caf88,
        0x00009ab8, 0x000caf8c, 0x00009abc, 0x000caf90,
        0x00009ac0, 0x000db30c, 0x00009ac4, 0x000db310,
        0x00009ac8, 0x000db384, 0x00009acc, 0x000db388,
        0x00009ad0, 0x000db324, 0x00009ad4, 0x000eb704,
        0x00009ad8, 0x000eb6a4, 0x00009adc, 0x000eb6a8,
        0x00009ae0, 0x000eb710, 0x00009ae4, 0x000eb714,
        0x00009ae8, 0x000eb720, 0x00009aec, 0x000eb724,
        0x00009af0, 0x000eb728, 0x00009af4, 0x000eb72c,
        0x00009af8, 0x000eb7a0, 0x00009afc, 0x000eb7a4,
        0x00009b00, 0x000eb7a8, 0x00009b04, 0x000eb7b0,
        0x00009b08, 0x000eb7b4, 0x00009b0c, 0x000eb7b8,
        0x00009b10, 0x000eb7a5, 0x00009b14, 0x000eb7a9,
        0x00009b18, 0x000eb7ad, 0x00009b1c, 0x000eb7b1,
        0x00009b20, 0x000eb7b5, 0x00009b24, 0x000eb7b9,
        0x00009b28, 0x000eb7c5, 0x00009b2c, 0x000eb7c9,
        0x00009b30, 0x000eb7d1, 0x00009b34, 0x000eb7d5,
        0x00009b38, 0x000eb7d9, 0x00009b3c, 0x000eb7c6,
        0x00009b40, 0x000eb7ca, 0x00009b44, 0x000eb7ce,
        0x00009b48, 0x000eb7d2, 0x00009b4c, 0x000eb7d6,
        0x00009b50, 0x000eb7c3, 0x00009b54, 0x000eb7c7,
        0x00009b58, 0x000eb7cb, 0x00009b5c, 0x000eb7cf,
        0x00009b60, 0x000eb7d7, 0x00009b64, 0x000eb7db,
        0x00009b68, 0x000eb7db, 0x00009b6c, 0x000eb7db,
        0x00009b70, 0x000eb7db, 0x00009b74, 0x000eb7db,
        0x00009b78, 0x000eb7db, 0x00009b7c, 0x000eb7db,
        0x00009b80, 0x000eb7db, 0x00009b84, 0x000eb7db,
        0x00009b88, 0x000eb7db, 0x00009b8c, 0x000eb7db,
        0x00009b90, 0x000eb7db, 0x00009b94, 0x000eb7db,
        0x00009b98, 0x000eb7db, 0x00009b9c, 0x000eb7db,
        0x00009ba0, 0x000eb7db, 0x00009ba4, 0x000eb7db,
        0x00009ba8, 0x000eb7db, 0x00009bac, 0x000eb7db,
        0x00009bb0, 0x000eb7db, 0x00009bb4, 0x000eb7db,
        0x00009bb8, 0x000eb7db, 0x00009bbc, 0x000eb7db,
        0x00009bc0, 0x000eb7db, 0x00009bc4, 0x000eb7db,
        0x00009bc8, 0x000eb7db, 0x00009bcc, 0x000eb7db,
        0x00009bd0, 0x000eb7db, 0x00009bd4, 0x000eb7db,
        0x00009bd8, 0x000eb7db, 0x00009bdc, 0x000eb7db,
        0x00009be0, 0x000eb7db, 0x00009be4, 0x000eb7db,
        0x00009be8, 0x000eb7db, 0x00009bec, 0x000eb7db,
        0x00009bf0, 0x000eb7db, 0x00009bf4, 0x000eb7db,
        0x00009bf8, 0x000eb7db, 0x00009bfc, 0x000eb7db,
        0x0000aa00, 0x00058084, 0x0000aa04, 0x00058088,
        0x0000aa08, 0x0005808c, 0x0000aa0c, 0x00058100,
        0x0000aa10, 0x00058104, 0x0000aa14, 0x00058108,
        0x0000aa18, 0x0005810c, 0x0000aa1c, 0x00058110,
        0x0000aa20, 0x00058114, 0x0000aa24, 0x00058180,
        0x0000aa28, 0x00058184, 0x0000aa2c, 0x00058188,
        0x0000aa30, 0x0005818c, 0x0000aa34, 0x00058190,
        0x0000aa38, 0x00058194, 0x0000aa3c, 0x000581a0,
        0x0000aa40, 0x0005820c, 0x0000aa44, 0x000581a8,
        0x0000aa48, 0x00058284, 0x0000aa4c, 0x00058288,
        0x0000aa50, 0x00058224, 0x0000aa54, 0x00058290,
        0x0000aa58, 0x00058300, 0x0000aa5c, 0x00058304,
        0x0000aa60, 0x00058308, 0x0000aa64, 0x0005830c,
        0x0000aa68, 0x00058380, 0x0000aa6c, 0x00058384,
        0x0000aa70, 0x00068700, 0x0000aa74, 0x00068704,
        0x0000aa78, 0x00068708, 0x0000aa7c, 0x0006870c,
        0x0000aa80, 0x00068780, 0x0000aa84, 0x00068784,
        0x0000aa88, 0x00078b00, 0x0000aa8c, 0x00078b04,
        0x0000aa90, 0x00078b08, 0x0000aa94, 0x00078b0c,
        0x0000aa98, 0x00078b80, 0x0000aa9c, 0x00078b84,
        0x0000aaa0, 0x00078b88, 0x0000aaa4, 0x00078b8c,
        0x0000aaa8, 0x00078b90, 0x0000aaac, 0x000caf80,
        0x0000aab0, 0x000caf84, 0x0000aab4, 0x000caf88,
        0x0000aab8, 0x000caf8c, 0x0000aabc, 0x000caf90,
        0x0000aac0, 0x000db30c, 0x0000aac4, 0x000db310,
        0x0000aac8, 0x000db384, 0x0000aacc, 0x000db388,
        0x0000aad0, 0x000db324, 0x0000aad4, 0x000eb704,
        0x0000aad8, 0x000eb6a4, 0x0000aadc, 0x000eb6a8,
        0x0000aae0, 0x000eb710, 0x0000aae4, 0x000eb714,
        0x0000aae8, 0x000eb720, 0x0000aaec, 0x000eb724,
        0x0000aaf0, 0x000eb728, 0x0000aaf4, 0x000eb72c,
        0x0000aaf8, 0x000eb7a0, 0x0000aafc, 0x000eb7a4,
        0x0000ab00, 0x000eb7a8, 0x0000ab04, 0x000eb7b0,
        0x0000ab08, 0x000eb7b4, 0x0000ab0c, 0x000eb7b8,
        0x0000ab10, 0x000eb7a5, 0x0000ab14, 0x000eb7a9,
        0x0000ab18, 0x000eb7ad, 0x0000ab1c, 0x000eb7b1,
        0x0000ab20, 0x000eb7b5, 0x0000ab24, 0x000eb7b9,
        0x0000ab28, 0x000eb7c5, 0x0000ab2c, 0x000eb7c9,
        0x0000ab30, 0x000eb7d1, 0x0000ab34, 0x000eb7d5,
        0x0000ab38, 0x000eb7d9, 0x0000ab3c, 0x000eb7c6,
        0x0000ab40, 0x000eb7ca, 0x0000ab44, 0x000eb7ce,
        0x0000ab48, 0x000eb7d2, 0x0000ab4c, 0x000eb7d6,
        0x0000ab50, 0x000eb7c3, 0x0000ab54, 0x000eb7c7,
        0x0000ab58, 0x000eb7cb, 0x0000ab5c, 0x000eb7cf,
        0x0000ab60, 0x000eb7d7, 0x0000ab64, 0x000eb7db,
        0x0000ab68, 0x000eb7db, 0x0000ab6c, 0x000eb7db,
        0x0000ab70, 0x000eb7db, 0x0000ab74, 0x000eb7db,
        0x0000ab78, 0x000eb7db, 0x0000ab7c, 0x000eb7db,
        0x0000ab80, 0x000eb7db, 0x0000ab84, 0x000eb7db,
        0x0000ab88, 0x000eb7db, 0x0000ab8c, 0x000eb7db,
        0x0000ab90, 0x000eb7db, 0x0000ab94, 0x000eb7db,
        0x0000ab98, 0x000eb7db, 0x0000ab9c, 0x000eb7db,
        0x0000aba0, 0x000eb7db, 0x0000aba4, 0x000eb7db,
        0x0000aba8, 0x000eb7db, 0x0000abac, 0x000eb7db,
        0x0000abb0, 0x000eb7db, 0x0000abb4, 0x000eb7db,
        0x0000abb8, 0x000eb7db, 0x0000abbc, 0x000eb7db,
        0x0000abc0, 0x000eb7db, 0x0000abc4, 0x000eb7db,
        0x0000abc8, 0x000eb7db, 0x0000abcc, 0x000eb7db,
        0x0000abd0, 0x000eb7db, 0x0000abd4, 0x000eb7db,
        0x0000abd8, 0x000eb7db, 0x0000abdc, 0x000eb7db,
        0x0000abe0, 0x000eb7db, 0x0000abe4, 0x000eb7db,
        0x0000abe8, 0x000eb7db, 0x0000abec, 0x000eb7db,
        0x0000abf0, 0x000eb7db, 0x0000abf4, 0x000eb7db,
        0x0000abf8, 0x000eb7db, 0x0000abfc, 0x000eb7db,
        0x0000a204, 0x00000004, 0x0000a20c, 0x0001f000,
        0x0000b20c, 0x0001f000, 0x0000a21c, 0x1883800a,
        0x0000a230, 0x00000108, 0x0000a250, 0x0004a000,
        0x0000a358, 0x7999aa0e,
    )

    val INI_COMMON: LongArray = longArrayOf(
        0x0000000c, 0x00000000, 0x00000030, 0x00020045,
        0x00000034, 0x00000005, 0x00000040, 0x00000000,
        0x00000044, 0x00000008, 0x00000048, 0x00000008,
        0x0000004c, 0x00000010, 0x00000050, 0x00000000,
        0x00000054, 0x0000001f, 0x00000800, 0x00000000,
        0x00000804, 0x00000000, 0x00000808, 0x00000000,
        0x0000080c, 0x00000000, 0x00000810, 0x00000000,
        0x00000814, 0x00000000, 0x00000818, 0x00000000,
        0x0000081c, 0x00000000, 0x00000820, 0x00000000,
        0x00000824, 0x00000000, 0x00001040, 0x002ffc0f,
        0x00001044, 0x002ffc0f, 0x00001048, 0x002ffc0f,
        0x0000104c, 0x002ffc0f, 0x00001050, 0x002ffc0f,
        0x00001054, 0x002ffc0f, 0x00001058, 0x002ffc0f,
        0x0000105c, 0x002ffc0f, 0x00001060, 0x002ffc0f,
        0x00001064, 0x002ffc0f, 0x00001230, 0x00000000,
        0x00001270, 0x00000000, 0x00001038, 0x00000000,
        0x00001078, 0x00000000, 0x000010b8, 0x00000000,
        0x000010f8, 0x00000000, 0x00001138, 0x00000000,
        0x00001178, 0x00000000, 0x000011b8, 0x00000000,
        0x000011f8, 0x00000000, 0x00001238, 0x00000000,
        0x00001278, 0x00000000, 0x000012b8, 0x00000000,
        0x000012f8, 0x00000000, 0x00001338, 0x00000000,
        0x00001378, 0x00000000, 0x000013b8, 0x00000000,
        0x000013f8, 0x00000000, 0x00001438, 0x00000000,
        0x00001478, 0x00000000, 0x000014b8, 0x00000000,
        0x000014f8, 0x00000000, 0x00001538, 0x00000000,
        0x00001578, 0x00000000, 0x000015b8, 0x00000000,
        0x000015f8, 0x00000000, 0x00001638, 0x00000000,
        0x00001678, 0x00000000, 0x000016b8, 0x00000000,
        0x000016f8, 0x00000000, 0x00001738, 0x00000000,
        0x00001778, 0x00000000, 0x000017b8, 0x00000000,
        0x000017f8, 0x00000000, 0x0000103c, 0x00000000,
        0x0000107c, 0x00000000, 0x000010bc, 0x00000000,
        0x000010fc, 0x00000000, 0x0000113c, 0x00000000,
        0x0000117c, 0x00000000, 0x000011bc, 0x00000000,
        0x000011fc, 0x00000000, 0x0000123c, 0x00000000,
        0x0000127c, 0x00000000, 0x000012bc, 0x00000000,
        0x000012fc, 0x00000000, 0x0000133c, 0x00000000,
        0x0000137c, 0x00000000, 0x000013bc, 0x00000000,
        0x000013fc, 0x00000000, 0x0000143c, 0x00000000,
        0x0000147c, 0x00000000, 0x00004030, 0x00000002,
        0x0000403c, 0x00000002, 0x00004024, 0x0000001f,
        0x00004060, 0x00000000, 0x00004064, 0x00000000,
        0x00008004, 0x00000000, 0x00008008, 0x00000000,
        0x0000800c, 0x00000000, 0x00008018, 0x00000700,
        0x00008020, 0x00000000, 0x00008038, 0x00000000,
        0x0000803c, 0x00000000, 0x00008048, 0x00000000,
        0x00008054, 0x00000000, 0x00008058, 0x00000000,
        0x0000805c, 0x000fc78f, 0x00008060, 0x0000000f,
        0x00008064, 0x00000000, 0x00008070, 0x00000000,
        0x000080b0, 0x00000000, 0x000080b4, 0x00000000,
        0x000080b8, 0x00000000, 0x000080bc, 0x00000000,
        0x000080c0, 0x2a80001a, 0x000080c4, 0x05dc01e0,
        0x000080c8, 0x1f402710, 0x000080cc, 0x01f40000,
        0x000080d0, 0x00001e00, 0x000080d4, 0x00000000,
        0x000080d8, 0x00400000, 0x000080e0, 0xffffffff,
        0x000080e4, 0x0000ffff, 0x000080e8, 0x003f3f3f,
        0x000080ec, 0x00000000, 0x000080f0, 0x00000000,
        0x000080f4, 0x00000000, 0x000080f8, 0x00000000,
        0x000080fc, 0x00020000, 0x00008100, 0x00020000,
        0x00008104, 0x00000001, 0x00008108, 0x00000052,
        0x0000810c, 0x00000000, 0x00008110, 0x00000168,
        0x00008118, 0x000100aa, 0x0000811c, 0x00003210,
        0x00008120, 0x08f04810, 0x00008124, 0x00000000,
        0x00008128, 0x00000000, 0x0000812c, 0x00000000,
        0x00008130, 0x00000000, 0x00008134, 0x00000000,
        0x00008138, 0x00000000, 0x0000813c, 0x00000000,
        0x00008144, 0xffffffff, 0x00008168, 0x00000000,
        0x0000816c, 0x00000000, 0x00008170, 0x32143320,
        0x00008174, 0xfaa4fa50, 0x00008178, 0x00000100,
        0x0000817c, 0x00000000, 0x000081c0, 0x00000000,
        0x000081d0, 0x0000320a, 0x000081ec, 0x00000000,
        0x000081f0, 0x00000000, 0x000081f4, 0x00000000,
        0x000081f8, 0x00000000, 0x000081fc, 0x00000000,
        0x00008200, 0x00000000, 0x00008204, 0x00000000,
        0x00008208, 0x00000000, 0x0000820c, 0x00000000,
        0x00008210, 0x00000000, 0x00008214, 0x00000000,
        0x00008218, 0x00000000, 0x0000821c, 0x00000000,
        0x00008220, 0x00000000, 0x00008224, 0x00000000,
        0x00008228, 0x00000000, 0x0000822c, 0x00000000,
        0x00008230, 0x00000000, 0x00008234, 0x00000000,
        0x00008238, 0x00000000, 0x0000823c, 0x00000000,
        0x00008240, 0x00100000, 0x00008244, 0x0010f400,
        0x00008248, 0x00000100, 0x0000824c, 0x0001e800,
        0x00008250, 0x00000000, 0x00008254, 0x00000000,
        0x00008258, 0x00000000, 0x0000825c, 0x400000ff,
        0x00008260, 0x00080922, 0x00008264, 0x88a00010,
        0x00008270, 0x00000000, 0x00008274, 0x40000000,
        0x00008278, 0x003e4180, 0x0000827c, 0x00000000,
        0x00008284, 0x0000002c, 0x00008288, 0x0000002c,
        0x0000828c, 0x00000000, 0x00008294, 0x00000000,
        0x00008298, 0x00000000, 0x0000829c, 0x00000000,
        0x00008300, 0x00000040, 0x00008314, 0x00000000,
        0x00008328, 0x00000000, 0x0000832c, 0x00000001,
        0x00008330, 0x00000302, 0x00008334, 0x00000e00,
        0x00008338, 0x00ff0000, 0x0000833c, 0x00000000,
        0x00008340, 0x00010380, 0x00008344, 0x00581043,
        0x00007010, 0x00000030, 0x00007034, 0x00000002,
        0x00007038, 0x000004c2, 0x00007800, 0x00140000,
        0x00007804, 0x0e4548d8, 0x00007808, 0x54214514,
        0x0000780c, 0x02025820, 0x00007810, 0x71c0d388,
        0x00007814, 0x924934a8, 0x0000781c, 0x00000000,
        0x00007828, 0x66964300, 0x0000782c, 0x8db6d961,
        0x00007830, 0x8db6d96c, 0x00007834, 0x6140008b,
        0x0000783c, 0x72ee0a72, 0x00007840, 0xbbfffffc,
        0x00007844, 0x000c0db6, 0x00007848, 0x6db6246f,
        0x0000784c, 0x6d9b66db, 0x00007850, 0x6d8c6dba,
        0x00007854, 0x00040000, 0x00007858, 0xdb003012,
        0x0000785c, 0x04924914, 0x00007860, 0x21084210,
        0x00007864, 0xf7d7ffde, 0x00007868, 0xc2034080,
        0x00007870, 0x10142c00, 0x00009808, 0x00000000,
        0x0000980c, 0xafe68e30, 0x00009810, 0xfd14e000,
        0x00009814, 0x9c0a9f6b, 0x0000981c, 0x00000000,
        0x0000982c, 0x0000a000, 0x00009830, 0x00000000,
        0x0000983c, 0x00200400, 0x0000984c, 0x0040233c,
        0x00009854, 0x00000044, 0x00009900, 0x00000000,
        0x00009904, 0x00000000, 0x00009908, 0x00000000,
        0x0000990c, 0x00000000, 0x0000991c, 0x10000fff,
        0x00009920, 0x04900000, 0x00009928, 0x00000001,
        0x0000992c, 0x00000004, 0x00009934, 0x1e1f2022,
        0x00009938, 0x0a0b0c0d, 0x0000993c, 0x00000000,
        0x00009940, 0x14750604, 0x00009948, 0x9280c00a,
        0x0000994c, 0x00020028, 0x00009954, 0x5f3ca3de,
        0x00009958, 0x0108ecff, 0x00009968, 0x000003ce,
        0x00009970, 0x192bb514, 0x00009974, 0x00000000,
        0x00009978, 0x00000001, 0x0000997c, 0x00000000,
        0x00009980, 0x00000000, 0x00009984, 0x00000000,
        0x00009988, 0x00000000, 0x0000998c, 0x00000000,
        0x00009990, 0x00000000, 0x00009994, 0x00000000,
        0x00009998, 0x00000000, 0x0000999c, 0x00000000,
        0x000099a0, 0x00000000, 0x000099a4, 0x00000001,
        0x000099a8, 0x201fff00, 0x000099ac, 0x2def0400,
        0x000099b0, 0x03051000, 0x000099b4, 0x00000820,
        0x000099dc, 0x00000000, 0x000099e0, 0x00000000,
        0x000099e4, 0xaaaaaaaa, 0x000099e8, 0x3c466478,
        0x000099ec, 0x0cc80caa, 0x000099f0, 0x00000000,
        0x0000a208, 0x803e68c8, 0x0000a210, 0x4080a333,
        0x0000a214, 0x00206c10, 0x0000a218, 0x009c4060,
        0x0000a220, 0x01834061, 0x0000a224, 0x00000400,
        0x0000a228, 0x000003b5, 0x0000a22c, 0x00000000,
        0x0000a234, 0x20202020, 0x0000a238, 0x20202020,
        0x0000a244, 0x00000000, 0x0000a248, 0xfffffffc,
        0x0000a24c, 0x00000000, 0x0000a254, 0x00000000,
        0x0000a258, 0x0ccb5380, 0x0000a25c, 0x15151501,
        0x0000a260, 0xdfa90f01, 0x0000a268, 0x00000000,
        0x0000a26c, 0x0ebae9e6, 0x0000a388, 0x0c000000,
        0x0000a38c, 0x20202020, 0x0000a390, 0x20202020,
        0x0000a39c, 0x00000001, 0x0000a3a0, 0x00000000,
        0x0000a3a4, 0x00000000, 0x0000a3a8, 0x00000000,
        0x0000a3ac, 0x00000000, 0x0000a3b0, 0x00000000,
        0x0000a3b4, 0x00000000, 0x0000a3b8, 0x00000000,
        0x0000a3bc, 0x00000000, 0x0000a3c0, 0x00000000,
        0x0000a3c4, 0x00000000, 0x0000a3cc, 0x20202020,
        0x0000a3d0, 0x20202020, 0x0000a3d4, 0x20202020,
        0x0000a3e4, 0x00000000, 0x0000a3e8, 0x18c43433,
        0x0000a3ec, 0x00f70081, 0x0000a3f0, 0x01036a2f,
        0x0000a3f4, 0x00000000, 0x0000d270, 0x0d820820,
        0x0000d35c, 0x07ffffef, 0x0000d360, 0x0fffffe7,
        0x0000d364, 0x17ffffe5, 0x0000d368, 0x1fffffe4,
        0x0000d36c, 0x37ffffe3, 0x0000d370, 0x3fffffe3,
        0x0000d374, 0x57ffffe3, 0x0000d378, 0x5fffffe2,
        0x0000d37c, 0x7fffffe2, 0x0000d380, 0x7f3c7bba,
        0x0000d384, 0xf3307ff0,
    )

    val INI_ANI_2G_HT20: LongArray = longArrayOf(
        0x00009850, 0x6d4000e2, 0x0000985c, 0x3137605e,
        0x00009858, 0x7ec84d2e, 0x0000986c, 0x06903881,
        0x00009868, 0x5ac640d0, 0x0000a208, 0x803e68c8,
        0x00009924, 0xd00a800d, 0x000099c0, 0x05eea6d4,
    )

    val INI_TXGAIN_NORMAL: LongArray = longArrayOf(
        0x0000a300, 0x00000000, 0x0000a304, 0x00009200,
        0x0000a308, 0x00010208, 0x0000a30c, 0x00019608,
        0x0000a310, 0x0001e610, 0x0000a314, 0x00024650,
        0x0000a318, 0x0002d6d0, 0x0000a31c, 0x000316d2,
        0x0000a320, 0x00039758, 0x0000a324, 0x0003b759,
        0x0000a328, 0x0003d75a, 0x0000a32c, 0x0004175c,
        0x0000a330, 0x0004575e, 0x0000a334, 0x0004979f,
        0x0000a338, 0x0004d7df, 0x0000a33c, 0x0003a95e,
        0x0000a340, 0x0003e9df, 0x0000a344, 0x0003e9df,
        0x0000a348, 0x0003e9df, 0x0000a34c, 0x0003e9df,
        0x0000a350, 0x0003e9df, 0x0000a354, 0x0003e9df,
        0x00007838, 0x00000029, 0x00007824, 0x00d8abff,
        0x0000786c, 0x48609eb4, 0x00007820, 0x00000c04,
        0x0000a274, 0x0a21c652, 0x0000a278, 0x3bdef7bd,
        0x0000a27c, 0x050e83bd, 0x0000a394, 0x3bdef7bd,
        0x0000a398, 0x000003bd, 0x0000a3dc, 0x3bdef7bd,
        0x0000a3e0, 0x000003bd,
    )

    val INI_TXGAIN_HIGH: LongArray = longArrayOf(
        0x0000a300, 0x00010000, 0x0000a304, 0x00016200,
        0x0000a308, 0x00018201, 0x0000a30c, 0x0001b240,
        0x0000a310, 0x0001d241, 0x0000a314, 0x0001f600,
        0x0000a318, 0x00022800, 0x0000a31c, 0x00026802,
        0x0000a320, 0x0002b805, 0x0000a324, 0x0002ea41,
        0x0000a328, 0x00038b00, 0x0000a32c, 0x0003ab40,
        0x0000a330, 0x0003cd80, 0x0000a334, 0x000368de,
        0x0000a338, 0x0003891e, 0x0000a33c, 0x0003a95e,
        0x0000a340, 0x0003e9df, 0x0000a344, 0x0003e9df,
        0x0000a348, 0x0003e9df, 0x0000a34c, 0x0003e9df,
        0x0000a350, 0x0003e9df, 0x0000a354, 0x0003e9df,
        0x00007838, 0x0000002b, 0x00007824, 0x00d8a7ff,
        0x0000786c, 0x08609eba, 0x00007820, 0x00000c00,
        0x0000a274, 0x0a214652, 0x0000a278, 0x0e739ce7,
        0x0000a27c, 0x05018063, 0x0000a394, 0x06318c63,
        0x0000a398, 0x00000063, 0x0000a3dc, 0x06318c63,
        0x0000a3e0, 0x00000063,
    )
}

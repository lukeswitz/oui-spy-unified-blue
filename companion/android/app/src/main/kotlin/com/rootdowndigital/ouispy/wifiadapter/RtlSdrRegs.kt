package com.rootdowndigital.ouispy.wifiadapter

// Register addresses and values transcribed from the osmocom rtl-sdr and rtl-sdr-blog drivers
// (src/librtlsdr.c, src/tuner_r82xx.c, include/tuner_r82xx.h), GPL-2.0-or-later,
// Copyright (C) 2012-2014 Steve Markgraf, Copyright (C) 2012 Dimitri Stolnikov, Copyright (C) 2013 Mauro Carvalho Chehab.
// These are hardware constants for the RTL2832U and R820T/R828D, not copied driver code.
internal object RtlSdrRegs {
    const val CTRL_OUT = 0x40
    const val CTRL_IN = 0xC0
    const val CTRL_TIMEOUT = 300
    const val STD_DIR_IN = 0x80
    const val STD_REQ_GET_DESCRIPTOR = 0x06
    const val STD_DT_STRING = 0x0300
    const val DEV_DESC_I_MANUFACTURER = 14
    const val DEV_DESC_I_PRODUCT = 15

    const val BLOCK_USB = 1
    const val BLOCK_SYS = 2
    const val BLOCK_IIC = 6

    const val USB_SYSCTL = 0x2000
    const val USB_EPA_CTL = 0x2148
    const val USB_EPA_MAXPKT = 0x2158

    const val GPO = 0x3001
    const val GPOE = 0x3003
    const val GPD = 0x3004
    const val DEMOD_CTL = 0x3000
    const val DEMOD_CTL_1 = 0x300b

    const val EP_IQ_IN = 0x81

    const val XTAL_HZ = 28_800_000
    const val R828D_XTAL_HZ = 16_000_000
    const val IF_HZ = 3_570_000
    const val MIN_RATE = 225_000
    const val MAX_RATE = 3_200_000
    const val RATE_GAP_LO = 300_000
    const val RATE_GAP_HI = 900_000

    const val V4_GPIO_UPCONVERTER = 5
    const val V4_UPCONVERT_HZ = 28_800_000

    const val USB_STR_MANUFACT = "RTLSDRBlog"
    const val USB_STR_V4 = "Blog V4"
    const val USB_STR_V4L = "Blog V4L"

    val FIR_DEFAULT = intArrayOf(
        -54, -36, -41, -40, -32, -14, 14, 53,
        101, 156, 215, 273, 327, 372, 404, 421
    )
    const val FIR_DEMOD_REG = 0x1c
    const val FIR_BYTES = 20

    const val R820T_I2C = 0x34
    const val R828D_I2C = 0x74
    const val R82XX_CHECK_ADDR = 0x00
    const val R82XX_CHECK_VAL = 0x69
    const val R82XX_SHADOW_START = 5
    const val R82XX_NUM_REGS = 30
    const val R82XX_MAX_I2C_MSG = 8
    const val R82XX_VER_NUM = 49
    const val R82XX_FILT_CAL_LO_KHZ = 56000

    const val BAND_HF = 1
    const val BAND_VHF = 2
    const val BAND_UHF = 3

    val R82XX_INIT_ARRAY = intArrayOf(
        0x83, 0x30, 0x75,
        0xc0, 0x40, 0xd6, 0x6c,
        0xf5, 0x63, 0x75, 0x68,
        0x6c, 0x83, 0x80, 0x00,
        0x0f, 0x00, 0xc0, 0x30,
        0x48, 0xcc, 0x60, 0x00,
        0x54, 0xae, 0x4a, 0xc0,
        0x00, 0x00, 0x00
    )

    val R82XX_FREQ_RANGES = arrayOf(
        intArrayOf(0, 0x08, 0x02, 0xdf, 0x00),
        intArrayOf(50, 0x08, 0x02, 0xbe, 0x00),
        intArrayOf(55, 0x08, 0x02, 0x8b, 0x00),
        intArrayOf(60, 0x08, 0x02, 0x7b, 0x00),
        intArrayOf(65, 0x08, 0x02, 0x69, 0x00),
        intArrayOf(70, 0x08, 0x02, 0x58, 0x00),
        intArrayOf(75, 0x00, 0x02, 0x44, 0x00),
        intArrayOf(80, 0x00, 0x02, 0x44, 0x00),
        intArrayOf(90, 0x00, 0x02, 0x34, 0x00),
        intArrayOf(100, 0x00, 0x02, 0x34, 0x00),
        intArrayOf(110, 0x00, 0x02, 0x24, 0x00),
        intArrayOf(120, 0x00, 0x02, 0x24, 0x00),
        intArrayOf(140, 0x00, 0x02, 0x14, 0x00),
        intArrayOf(180, 0x00, 0x02, 0x13, 0x00),
        intArrayOf(220, 0x00, 0x02, 0x13, 0x00),
        intArrayOf(250, 0x00, 0x02, 0x11, 0x00),
        intArrayOf(280, 0x00, 0x02, 0x00, 0x00),
        intArrayOf(310, 0x00, 0x41, 0x00, 0x00),
        intArrayOf(450, 0x00, 0x41, 0x00, 0x00),
        intArrayOf(588, 0x00, 0x40, 0x00, 0x00),
        intArrayOf(650, 0x00, 0x40, 0x00, 0x00)
    )

    val R82XX_LNA_GAIN_STEPS = intArrayOf(0, 9, 13, 40, 38, 13, 31, 22, 26, 31, 26, 14, 19, 5, 35, 13)
    val R82XX_MIXER_GAIN_STEPS = intArrayOf(0, 5, 10, 10, 19, 9, 10, 25, 17, 10, 8, 16, 13, 6, 3, -8)

    val R82XX_IF_LPF_BW = intArrayOf(1_700_000, 1_600_000, 1_550_000, 1_450_000, 1_200_000, 900_000, 700_000, 550_000, 450_000, 350_000)
    const val R82XX_FILT_HP_BW1 = 350_000
    const val R82XX_FILT_HP_BW2 = 380_000
}

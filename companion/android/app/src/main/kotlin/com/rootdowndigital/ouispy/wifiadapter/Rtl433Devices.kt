package com.rootdowndigital.ouispy.wifiadapter

internal object Rtl433Devices {
    val ALL: List<Rtl433Decoder> =
        BATCH_00 + BATCH_01 + BATCH_02 + BATCH_03 + BATCH_04 +
            BATCH_05 + BATCH_06 + BATCH_07 + BATCH_08 + BATCH_09

    val DISABLED: Set<Rtl433Decoder> = setOf(
        Auriol4ld5661, BrennenstuhlRcs2044, Ced7000, Chuango, DickertPwm,
        DishRemote63, Hondaremote, LightwaveRf, MBusModeF, MBusModeR,
        Megacode, NeptuneR900bcd, NiceFlorS, TpmsJansite,
    )

    @Volatile private var lastCategories: Set<String>? = null

    fun registerAll(categories: Set<String> = Rtl433Categories.ALL_CATEGORIES.toSet()) {
        if (lastCategories == categories) return
        lastCategories = categories
        val active = Rtl433Categories.forCategories(categories)
        Rtl433Registry.decoders.clear()
        Rtl433Registry.decoders.addAll(ALL.filter { it !in DISABLED && it in active })
    }
}

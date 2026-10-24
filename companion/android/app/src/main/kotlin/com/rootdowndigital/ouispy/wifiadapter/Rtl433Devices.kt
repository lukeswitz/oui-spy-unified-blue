package com.rootdowndigital.ouispy.wifiadapter

internal object Rtl433Devices {
    val ALL: List<Rtl433Decoder> =
        BATCH_00 + BATCH_01 + BATCH_02 + BATCH_03 + BATCH_04 +
            BATCH_05 + BATCH_06 + BATCH_07 + BATCH_08 + BATCH_09

    @Volatile private var registered = false

    fun registerAll() {
        if (registered) return
        registered = true
        Rtl433Registry.decoders.addAll(ALL)
    }
}

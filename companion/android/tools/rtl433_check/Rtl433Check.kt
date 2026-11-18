package com.rootdowndigital.ouispy.wifiadapter

import java.io.File
import kotlin.system.exitProcess

private val rateRe = Regex("""_(\d+)k""")
private val freqRe = Regex("""_(\d+(?:\.\d+)?)M""")
private val modelRe = Regex(""""model"\s*:\s*"([^"]+)"""")

fun main(args: Array<String>) {
    Rtl433Devices.registerAll()
    var checked = 0
    var missed = 0
    for (root in args) {
        File(root).walkTopDown().filter { it.extension == "cu8" }.sortedBy { it.path }.forEach { f ->
            val expected = File(f.path.removeSuffix(".cu8") + ".json").takeIf { it.exists() }
                ?.readLines()?.mapNotNull { modelRe.find(it)?.groupValues?.get(1) }?.toSet().orEmpty()
            if (expected.isEmpty()) return@forEach
            val rate = rateRe.find(f.name)?.groupValues?.get(1)?.toInt()?.times(1000) ?: 250_000
            val mhz = freqRe.find(f.name)?.groupValues?.get(1)?.toDouble() ?: 433.92
            Rtl433Registry.centerFreqHz = (mhz * 1e6).toLong()
            Rtl433Registry.reset()
            val got = linkedSetOf<String>()
            val bytes = f.readBytes()
            var off = 0
            while (off < bytes.size) {
                val n = minOf(131072, bytes.size - off)
                Rtl433Registry.run(bytes.copyOfRange(off, off + n), n / 2, rate) { got.add(it.model) }
                off += n
            }
            Rtl433Registry.flush { got.add(it.model) }
            checked++
            if (got.none { it in expected }) {
                missed++
                println("MISS ${f.path} expected=$expected got=$got")
            }
        }
    }
    println("decoded ${checked - missed}/$checked")
    if (checked == 0 || missed > 0) exitProcess(1)
}

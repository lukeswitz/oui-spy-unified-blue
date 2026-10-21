package com.rootdowndigital.ouispy.wifiadapter

// Reads rtw88 u32 PHY init arrays from the downloaded table source and walks its if/else/endif conditions (Linux rtw88 phy.c, GPL-2.0 OR BSD-3-Clause).
internal class PhyDrv(val cut: Int, val rfe: Int, val rfeMask: Boolean, val cond2: Int = 0)

internal class RtlPhyTables(private val text: String) {

    fun array(name: String): IntArray {
        val start = text.indexOf("static const u32 $name[] = {")
        if (start < 0) throw IllegalStateException("RTL: table $name not found")
        val body = text.indexOf('{', start) + 1
        val end = text.indexOf("};", body)
        if (end < 0) throw IllegalStateException("RTL: table $name unterminated")
        val out = ArrayList<Int>()
        for (m in HEX.findAll(text.substring(body, end))) out.add(m.groupValues[1].toLong(16).toInt())
        if (out.size % 2 != 0) throw IllegalStateException("RTL: table $name odd length")
        return out.toIntArray()
    }

    fun load(tbl: IntArray, drv: PhyDrv, cfg: (Int, Int) -> Unit) {
        var posCond = 0
        var posCond2 = 0
        var matched = true
        var skipped = false
        var i = 0
        while (i + 1 < tbl.size) {
            val w = tbl[i]
            val w2 = tbl[i + 1]
            i += 2
            if (((w ushr 31) and 1) != 0) {
                when ((w ushr 28) and 3) {
                    3 -> {
                        matched = true
                        skipped = false
                    }
                    2 -> matched = !skipped
                    else -> {
                        posCond = w
                        posCond2 = w2
                    }
                }
            } else if (((w ushr 30) and 1) != 0) {
                if (!skipped) {
                    if (positive(posCond, posCond2, drv)) {
                        matched = true
                        skipped = true
                    } else {
                        matched = false
                        skipped = false
                    }
                } else {
                    matched = false
                }
            } else if (matched) {
                cfg(w, w2)
            }
        }
    }

    private fun positive(c: Int, c2: Int, d: PhyDrv): Boolean {
        val rfe = c and 0xff
        val intf = (c ushr 8) and 0xf
        val pkg = (c ushr 12) and 0xf
        val cut = (c ushr 24) and 0xf
        if (cut != 0 && cut != d.cut) return false
        if (pkg != 0 && pkg != PKG_ANY) return false
        if (intf != 0 && intf != INTF_USB) return false
        if (!d.rfeMask) return rfe == d.rfe
        if ((rfe and 0x0f) == 0) return true
        if ((rfe and d.rfe) != rfe) return false
        for (b in 0 until 4) {
            val sh = 8 * b
            if ((rfe and (1 shl b)) != 0 && ((c2 ushr sh) and 0xff) != ((d.cond2 ushr sh) and 0xff)) return false
        }
        return true
    }

    companion object {
        private val HEX = Regex("0[xX]([0-9a-fA-F]+)")
        private const val PKG_ANY = 15
        private const val INTF_USB = 2
    }
}

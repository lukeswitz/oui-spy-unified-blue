package com.rootdowndigital.ouispy.wifiadapter

internal fun wifiAuthMode(b: ByteArray, from: Int, end: Int, privacy: Boolean): Int {
    fun u(i: Int) = b[i].toInt() and 0xff
    var rsn = false
    var sae = false
    var ent = false
    var wpa = false
    var i = from
    while (i + 2 <= end) {
        val tag = u(i)
        val tl = u(i + 1)
        val p = i + 2
        if (p + tl > end) break
        if (tag == 48 && tl >= 8) {
            rsn = true
            var o = p + 6
            if (o + 2 <= p + tl) {
                val pw = u(o) or (u(o + 1) shl 8)
                o += 2 + 4 * pw
                if (o + 2 <= p + tl) {
                    val akm = u(o) or (u(o + 1) shl 8)
                    o += 2
                    var k = 0
                    while (k < akm && o + 4 <= p + tl) {
                        if (u(o) == 0x00 && u(o + 1) == 0x0f && u(o + 2) == 0xac) {
                            when (u(o + 3)) {
                                8, 18 -> sae = true
                                1, 3, 5, 6, 11, 12, 13 -> ent = true
                            }
                        }
                        o += 4
                        k++
                    }
                }
            }
        } else if (tag == 221 && tl >= 4 &&
            u(p) == 0x00 && u(p + 1) == 0x50 && u(p + 2) == 0xf2 && u(p + 3) == 0x01) {
            wpa = true
        }
        i += 2 + tl
    }
    return when {
        sae -> 6
        ent -> 5
        rsn && wpa -> 4
        rsn -> 3
        wpa -> 2
        privacy -> 1
        else -> 0
    }
}

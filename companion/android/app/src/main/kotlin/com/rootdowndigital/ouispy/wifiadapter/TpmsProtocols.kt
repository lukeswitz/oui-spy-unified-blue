package com.rootdowndigital.ouispy.wifiadapter

internal object TpmsProtocols {
    data class Reading(val model: String, val id: String, val pressureKpa: Double?, val tempC: Double?, val flags: String?)

    private const val PSI_KPA = 6.894757
    private const val PROTOCOLS = 30

    fun decode(bytes: ByteArray, nbits: Int): Reading? {
        val n = minOf(nbits, bytes.size * 8)
        val w = ByteArray(16)
        for (p in 0 until PROTOCOLS) {
            for (inv in 0..1) {
                for (off in 0..7) {
                    w.fill(0)
                    val r = when (p) {
                        0 -> bmwG3(bytes, n, off, inv, w)
                        1 -> porsche(bytes, n, off, inv, w)
                        2 -> jansiteSolar(bytes, n, off, inv, w)
                        3 -> sefisM3(bytes, n, off, inv, w)
                        4 -> abarthQ85(bytes, n, off, inv, w)
                        5 -> toyota(bytes, n, off, inv, w)
                        6 -> pmv107j(bytes, n, off, inv, w)
                        7 -> tyreguard400(bytes, n, off, inv, w)
                        8 -> trw(bytes, n, off, inv, w)
                        9 -> mercedes(bytes, n, off, inv, w)
                        10 -> airpuxem(bytes, n, off, inv, w)
                        11 -> bmw(bytes, n, off, inv, w)
                        12 -> ave(bytes, n, off, inv, w)
                        13 -> vdoTg1c(bytes, n, off, inv, w)
                        14 -> kia(bytes, n, off, inv, w)
                        15 -> schrader(bytes, n, off, inv, w)
                        16 -> renault(bytes, n, off, inv, w)
                        17 -> schraderMoto(bytes, n, off, inv, w)
                        18 -> elantra(bytes, n, off, inv, w)
                        19 -> gm(bytes, n, off, inv, w)
                        20 -> eeztire(bytes, n, off, inv, w)
                        21 -> gearHive(bytes, n, off, inv, w)
                        22 -> ford(bytes, n, off, inv, w)
                        23 -> smartire(bytes, n, off, inv, w)
                        24 -> renault0435r(bytes, n, off, inv, w)
                        25 -> abarthTg1c(bytes, n, off, inv, w)
                        26 -> truck(bytes, n, off, inv, w)
                        27 -> citroen(bytes, n, off, inv, w)
                        28 -> jansiteTy588(bytes, n, off, inv, w)
                        else -> jansiteTy468(bytes, n, off, inv, w)
                    }
                    if (r != null) return r
                }
            }
        }
        return null
    }

    fun crc8(d: ByteArray, len: Int, poly: Int, init: Int): Int {
        var r = init and 0xff
        for (i in 0 until len) {
            r = r xor (d[i].toInt() and 0xff)
            for (b in 0 until 8) r = if (r and 0x80 != 0) ((r shl 1) xor poly) and 0xff else (r shl 1) and 0xff
        }
        return r
    }

    // rtl_433 bit_util.c:334 crc16 (MSB-first, no reflect, no xorout)
    fun crc16(d: ByteArray, start: Int, len: Int, poly: Int, init: Int): Int {
        var r = init and 0xffff
        for (i in start until start + len) {
            r = r xor ((d[i].toInt() and 0xff) shl 8)
            for (b in 0 until 8) r = if (r and 0x8000 != 0) ((r shl 1) xor poly) and 0xffff else (r shl 1) and 0xffff
        }
        return r
    }

    // rtl_433 bit_util.c:259 crc7 (init and poly shifted left one, result is bits 7..1)
    private fun crc7(d: ByteArray, len: Int, poly: Int, init: Int): Int {
        var r = (init shl 1) and 0xff
        val p = (poly shl 1) and 0xff
        for (i in 0 until len) {
            r = r xor (d[i].toInt() and 0xff)
            for (b in 0 until 8) r = if (r and 0x80 != 0) ((r shl 1) xor p) and 0xff else (r shl 1) and 0xff
        }
        return (r ushr 1) and 0x7f
    }

    private fun grab(src: ByteArray, n: Int, start: Int, count: Int, inv: Int, dst: ByteArray, dstBit: Int): Boolean {
        if (start + count > n) return false
        for (i in 0 until count) {
            val s = start + i
            val bit = ((src[s ushr 3].toInt() ushr (7 - (s and 7))) and 1) xor inv
            if (bit != 0) {
                val d = dstBit + i
                dst[d ushr 3] = (dst[d ushr 3].toInt() or (0x80 ushr (d and 7))).toByte()
            }
        }
        return true
    }

    private fun field(src: ByteArray, n: Int, start: Int, count: Int, inv: Int): Int {
        if (start + count > n) return -1
        var v = 0
        for (i in 0 until count) {
            val s = start + i
            v = (v shl 1) or (((src[s ushr 3].toInt() ushr (7 - (s and 7))) and 1) xor inv)
        }
        return v
    }

    private fun u(w: ByteArray, i: Int) = w[i].toInt() and 0xff

    private fun allZero(w: ByteArray, len: Int): Boolean {
        for (i in 0 until len) if (w[i].toInt() != 0) return false
        return true
    }

    private fun xorAll(w: ByteArray, len: Int): Int {
        var x = 0
        for (i in 0 until len) x = x xor u(w, i)
        return x
    }

    private fun id4(w: ByteArray, i: Int) = (u(w, i) shl 24) or (u(w, i + 1) shl 16) or (u(w, i + 2) shl 8) or u(w, i + 3)

    // unverified: rtl_433 tpms_toyota.c:48 crc8(poly 0x07, init 0x80) over b[0..7] == b[8]; 52-57 fields; pressure complement b[7]
    private fun toyota(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 72, inv, w, 0) || allZero(w, 9)) return null
        if (crc8(w, 8, 0x07, 0x80) != u(w, 8)) return null
        val p1 = ((u(w, 4) and 0x7f) shl 1) or (u(w, 5) ushr 7)
        if (p1 != (u(w, 7) xor 0xff)) return null
        val t = ((u(w, 5) and 0x7f) shl 1) or (u(w, 6) ushr 7)
        val status = (u(w, 4) and 0x80) or (u(w, 6) and 0x7f)
        val id = (u(w, 0) shl 24) or (u(w, 1) shl 16) or (u(w, 2) shl 8) or u(w, 3)
        return Reading("Toyota", "%08x".format(id), (p1 * 0.25 - 7.0) * PSI_KPA, t - 40.0, "status=%02x".format(status))
    }

    // unverified: rtl_433 tpms_pmv107j.c:53 crc8(poly 0x13, init 0x00) over 6 zero bits + 66 data bits, b[8]; 57-68 fields; complement b[6]
    private fun pmv107j(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 66, inv, w, 6) || allZero(w, 9)) return null
        if (crc8(w, 8, 0x13, 0x00) != u(w, 8)) return null
        val p1 = u(w, 5)
        if (p1 != (u(w, 6) xor 0xff)) return null
        val id = (u(w, 0) shl 26) or (u(w, 1) shl 18) or (u(w, 2) shl 10) or (u(w, 3) shl 2) or (u(w, 4) ushr 6)
        val st = u(w, 4)
        val flags = "batLow=%d cnt=%d rapid=%d fail=%d".format((st shr 5) and 1, (st shr 3) and 3, (st shr 1) and 1, st and 1)
        return Reading("PMV-107J", "%08x".format(id), (p1 - 40.0) * 2.48, u(w, 7) - 40.0, flags)
    }

    // unverified: rtl_433 schraeder.c:51 crc8(poly 0x07, init 0xf0) over b[0..6] == b[7], bits after 4-bit sync nibble; 56-59 fields
    private fun schrader(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off + 4, 64, inv, w, 0) || allZero(w, 8)) return null
        if (crc8(w, 7, 0x07, 0xf0) != u(w, 7)) return null
        val id = ((u(w, 1) and 0x0f) shl 24) or (u(w, 2) shl 16) or (u(w, 3) shl 8) or u(w, 4)
        val flags = ((u(w, 0) and 0x0f) shl 4) or (u(w, 1) ushr 4)
        return Reading("Schrader", "%07X".format(id), u(w, 5) * 2.5, u(w, 6) - 50.0, "%02x".format(flags))
    }

    // unverified: rtl_433 tpms_renault.c:47 crc8(poly 0x07, init 0x00) over b[0..7] == b[8]; 49-54 fields
    private fun renault(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 72, inv, w, 0) || allZero(w, 9)) return null
        if (crc8(w, 8, 0x07, 0x00) != u(w, 8)) return null
        val id = (u(w, 5) shl 16) or (u(w, 4) shl 8) or u(w, 3)
        val praw = ((u(w, 0) and 0x03) shl 8) or u(w, 1)
        return Reading("Renault", "%06x".format(id), praw * 0.75, u(w, 2) - 30.0, "%02x".format(u(w, 0) shr 2))
    }

    // unverified: rtl_433 tpms_schrader_motorcycle.c:87 crc8(poly 0x07, init 0xe0) over b[0..6] == 0, 56 bits after preamble; 92-95 fields
    private fun schraderMoto(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 56, inv, w, 0) || allZero(w, 7)) return null
        if (crc8(w, 7, 0x07, 0xe0) != 0) return null
        val id = ((u(w, 0) and 0x03) shl 22) or (u(w, 1) shl 14) or (u(w, 2) shl 6) or (u(w, 3) ushr 2)
        val praw = ((u(w, 3) and 0x03) shl 8) or u(w, 4)
        return Reading("Schrader-Motorcycle", id.toString(), praw * 0.5, u(w, 5) - 50.0, null)
    }

    // unverified: rtl_433 tpms_ford.c:67 sum8 of b[0..6] == b[7]; flag filter 98-125; psi 84 (0.25 PSI/bit, bit 8 = b[6]&0x20); temp 89 (-56, valid when b[5]&0x80==0)
    private fun ford(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 64, inv, w, 0) || allZero(w, 8)) return null
        var sum = 0
        for (i in 0 until 7) sum += u(w, i)
        if ((sum and 0xff) != u(w, 7)) return null
        val f = u(w, 6)
        val state = when (f and 0x4c) {
            0x08 -> "learn"
            0x04 -> "rest"
            0x44 -> "moving"
            else -> return null
        }
        if (f and 0x90 != 0) return null
        val id = (u(w, 0) shl 24) or (u(w, 1) shl 16) or (u(w, 2) shl 8) or u(w, 3)
        val psi = (((f and 0x20) shl 3) or u(w, 4)) * 0.25
        val t = if (u(w, 5) and 0x80 == 0) (u(w, 5) and 0x7f) - 56.0 else null
        return Reading("Ford", "%08x".format(id), psi * PSI_KPA, t, state)
    }

    // unverified: rtl_433 tpms_citroen.c:58 xor of b[1..9] == 0, b[6]/b[7] != 0; 64-68 fields (kPa = raw*1.364, temp = raw-50)
    private fun citroen(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 80, inv, w, 0)) return null
        if (u(w, 6) == 0 || u(w, 7) == 0) return null
        var x = 0
        for (i in 1..9) x = x xor u(w, i)
        if (x != 0) return null
        val id = (u(w, 1) shl 24) or (u(w, 2) shl 16) or (u(w, 3) shl 8) or u(w, 4)
        val flags = "state=%02x flags=%x repeat=%d".format(u(w, 0), u(w, 5) shr 4, u(w, 5) and 0x0f)
        return Reading("Citroen", "%08x".format(id), u(w, 6) * 1.364, u(w, 7) - 50.0, flags)
    }

    // unverified: rtl_433 tpms_bmw_g3.c:91 crc16(poly 0x1021, init 0) over 11 (Gen3) or 10 (Gen2) bytes == 0; 102-108 kPa=(b4-43)*2.5, C=b5-40, id=b0..b3 u32
    private fun bmwG3(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        for (k in 0..1) {
            val len = 11 - k
            w.fill(0)
            if (!grab(s, n, off, len * 8, inv, w, 0) || allZero(w, len)) continue
            if (crc16(w, 0, len, 0x1021, 0) != 0) continue
            val id = id4(w, 0).toLong() and 0xffffffffL
            val flags = if (k == 0) "f1=%02x f2=%02x f3=%02x".format(u(w, 6), u(w, 7), u(w, 8)) else "f1=%02x f2=%02x".format(u(w, 6), u(w, 7))
            return Reading(if (k == 0) "BMW-GEN3" else "BMW-GEN2", id.toString(), (u(w, 4) - 43) * 2.5, u(w, 5) - 40.0, flags)
        }
        return null
    }

    // unverified: rtl_433 tpms_porsche.c:54 crc16(poly 0x1021, init 0xffff) over 10 bytes == 0; 59-65 id=b0..b3, kPa=b4*5/2-100 (integer), C=b5-40, flags=b6b7
    private fun porsche(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 80, inv, w, 0) || allZero(w, 10)) return null
        if (crc16(w, 0, 10, 0x1021, 0xffff) != 0) return null
        val kpa = u(w, 4) * 5 / 2 - 100
        return Reading("Porsche", "%08x".format(id4(w, 0)), kpa.toDouble(), u(w, 5) - 40.0, "%04x".format((u(w, 6) shl 8) or u(w, 7)))
    }

    // unverified: rtl_433 tpms_jansite_solar.c:62 sync 0xdd33 in b[0..1], :67 crc16(poly 0x8005, init 0) over b[2..8] == b[9..10]; 73-76 id=b2..b4, 89 kPa=b7*1.6, 90 C=b6-55
    private fun jansiteSolar(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 88, inv, w, 0)) return null
        if (((u(w, 0) shl 8) or u(w, 1)) != 0xdd33) return null
        if (crc16(w, 2, 7, 0x8005, 0) != ((u(w, 9) shl 8) or u(w, 10))) return null
        val id = (u(w, 2) shl 16) or (u(w, 3) shl 8) or u(w, 4)
        return Reading("Jansite-Solar", "%06x".format(id), u(w, 7) * 1.6, u(w, 6) - 55.0, "flags=%02x".format(u(w, 5)))
    }

    // unverified: rtl_433 tpms_sefis_m3.c:93-94 crc16(poly 0x1021, init 0) over b[0..6] == b[7..8]; 100-118 kPa=(page<<13|(b4&0x1f)<<8|b5 - 0x0e00)/102.4, C=14+((b2+b5)&0x0f); no sensor id in source, id=b0..b6 hex
    private fun sefisM3(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 72, inv, w, 0) || allZero(w, 9)) return null
        if (crc16(w, 0, 7, 0x1021, 0) != ((u(w, 7) shl 8) or u(w, 8))) return null
        val page = when (u(w, 4) ushr 5) {
            7 -> 0
            4 -> 1
            5 -> 2
            2 -> 3
            else -> -1
        }
        val kpa = if (page >= 0) maxOf(0.0, (((page shl 13) or ((u(w, 4) and 0x1f) shl 8) or u(w, 5)) - 0x0e00) / 102.4) else null
        val t = 14.0 + (((u(w, 2) + u(w, 5)) and 0xff) and 0x0f)
        val code = "%02x%02x%02x%02x%02x%02x%02x".format(u(w, 0), u(w, 1), u(w, 2), u(w, 3), u(w, 4), u(w, 5), u(w, 6))
        return Reading("Sefis-M3", code, kpa, t, null)
    }

    // unverified: rtl_433 tpms_abarth124.c:100 xor of b[0..8] == 0, :118-121 C=b6-55 within -20..80, :129 crc16(poly 0x1021, init 0xffff) over b[0..9] == b[11]<<8|b[10]; 143-146 kPa=b5*3
    private fun abarthQ85(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 96, inv, w, 0) || allZero(w, 9)) return null
        if (xorAll(w, 9) != 0) return null
        val t = u(w, 6) - 55.0
        if (t < -20.0 || t > 80.0) return null
        if (crc16(w, 0, 10, 0x1021, 0xffff) != ((u(w, 11) shl 8) or u(w, 10))) return null
        return Reading("Shenzhen-EGQQ85", "%08x".format(id4(w, 0)), u(w, 5) * 3.0, t, "flags=%02x status=%02x".format(u(w, 4), u(w, 7)))
    }

    // unverified: rtl_433 tpms_abarth124.c:100 xor of b[0..8] == 0, :118-121 C=b6-50 within -50..125; 143-146 kPa=b5*1.38
    private fun abarthTg1c(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 72, inv, w, 0) || allZero(w, 9)) return null
        if (xorAll(w, 9) != 0) return null
        val t = u(w, 6) - 50.0
        if (t < -50.0 || t > 125.0) return null
        return Reading("Abarth-124Spider", "%08x".format(id4(w, 0)), u(w, 5) * 1.38, t, "flags=%02x status=%02x".format(u(w, 4), u(w, 7)))
    }

    // unverified: rtl_433 tpms_tyreguard400.c:133 sync 0xfd5fd5f (28 bits), :80 crc8(poly 0x31, init 0xdd) over 11 bytes == 0; 98 id 28 bit, 103 kPa=b7|((b9&0x70)<<4), 104 C=b8-40
    private fun tyreguard400(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (field(s, n, off, 28, inv) != 0xfd5fd5f) return null
        if (!grab(s, n, off, 88, inv, w, 0)) return null
        if (crc8(w, 11, 0x31, 0xdd) != 0) return null
        val id = ((u(w, 3) and 0x0f) shl 24) or (u(w, 4) shl 16) or (u(w, 5) shl 8) or u(w, 6)
        val flags = u(w, 9)
        return Reading("TyreGuard400", "%07x".format(id), (u(w, 7) or ((flags and 0x70) shl 4)).toDouble(), u(w, 8) - 40.0, "%02x".format(flags))
    }

    // unverified: rtl_433 tpms_trw.c:47-48 preamble 0x0001 (OOK) or 0x7fff (FSK), :92 crc8(poly 0x07, init 0) over b[0..9] == 0; 99-106 id=b1..b4, psi=b6*0.4, C=b7-50
    private fun trw(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        val pre = field(s, n, off, 16, inv)
        if (pre != 0x0001 && pre != 0x7fff) return null
        if (!grab(s, n, off + 16, 80, inv, w, 0) || allZero(w, 10)) return null
        if (crc8(w, 10, 0x07, 0x00) != 0) return null
        val flags = "mode=%02x flags=%x seq=%d motion=%02x".format(u(w, 0), u(w, 5) shr 4, u(w, 5) and 0x0f, u(w, 8))
        return Reading("TRW", "%08x".format(id4(w, 1)), u(w, 6) * 0.4 * PSI_KPA, u(w, 7) - 50.0, flags)
    }

    // unverified: rtl_433 tpms_mercedes_benz.c:39 preamble 0x002 (12 bits), :63 crc8(poly 0x2f, init 0xaa) over b[0..9] == 0, :68 b0 in {0x83,0xa3}; 75-79 psi=b5/2.75, C=b6-51
    private fun mercedes(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (field(s, n, off, 12, inv) != 0x002) return null
        if (!grab(s, n, off + 12, 80, inv, w, 0)) return null
        if (crc8(w, 10, 0x2f, 0xaa) != 0) return null
        if (u(w, 0) != 0x83 && u(w, 0) != 0xa3) return null
        val flags = "counter=%d flags1=%x flags2=%02x".format(u(w, 7) and 0x1f, u(w, 7) shr 5, u(w, 8))
        return Reading("MercedesBenz-Sprinter", "%08x".format(id4(w, 1)), u(w, 5) / 2.75 * PSI_KPA, u(w, 6) - 51.0, flags)
    }

    // unverified: rtl_433 tpms_airpuxem.c:53 header nibble 0x5, :60 crc8(poly 0x2f, init 0xaa) over the next 64 bits == following byte (:65); 73-82 id=b0..b3, kPa=(b5|b4.7<<8|b4.3<<9)-100, C=signed b6
    private fun airpuxem(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (field(s, n, off, 4, inv) != 0x5) return null
        if (!grab(s, n, off + 4, 64, inv, w, 0) || !grab(s, n, off + 68, 8, inv, w, 64) || allZero(w, 8)) return null
        if (crc8(w, 8, 0x2f, 0xaa) != u(w, 8)) return null
        val b4 = u(w, 4)
        val kpa = (u(w, 5) or (((b4 shr 7) and 1) shl 8) or (((b4 shr 3) and 1) shl 9)) - 100
        val flags = "flags=%d pos=%d bat=%d".format((b4 shr 4) and 0x07, b4 and 0x07, u(w, 7))
        return Reading("Airpuxem-TYH11EU6ZQ", "%08x".format(id4(w, 0)), kpa.toDouble(), w[6].toDouble(), flags)
    }

    // unverified: rtl_433 tpms_bmw.c:126 crc8(poly 0x2f, init 0xaa) over 11 (BMW Gen5) or 8 (Audi alert) bytes == 0; 132-133 kPa=b5*2.45, C=b6-52, id=b1..b4
    private fun bmw(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        for (k in 0..1) {
            val len = if (k == 0) 11 else 8
            w.fill(0)
            if (!grab(s, n, off, len * 8, inv, w, 0)) continue
            if (crc8(w, len, 0x2f, 0xaa) != 0) continue
            val flags = if (k == 0) "brand=%02x f1=%02x f2=%02x f3=%02x".format(u(w, 0), u(w, 7), u(w, 8), u(w, 9)) else "brand=%02x alert".format(u(w, 0))
            return Reading(if (k == 0) "BMW-GEN5" else "Audi-PressureAlert", "%08x".format(id4(w, 1)), u(w, 5) * 2.45, u(w, 6) - 52.0, flags)
        }
        return null
    }

    // unverified: rtl_433 tpms_ave.c:46 crc8(poly 0x31, init 0xff) over b[0..7] == 0; 68-87 kPa=(b4-offset)*ratio by mode=b6>>6, 99 C=b5-50
    private fun ave(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 64, inv, w, 0)) return null
        if (crc8(w, 8, 0x31, 0xff) != 0) return null
        val b6 = u(w, 6)
        val mode = (b6 shr 6) and 3
        val ratio = if (mode >= 2) 5.491 else 2.352
        val offset = when (mode) {
            0 -> 47.0
            2 -> 18.2
            else -> 0.0
        }
        val flags = "mode=%d bat=%d flags=%x".format(mode, (b6 shr 3) and 7, b6 and 7)
        return Reading("AVE", "%08x".format(id4(w, 0)), (u(w, 4) - offset) * ratio, u(w, 5) - 50.0, flags)
    }

    // unverified: hydrasdr_433 tpms_vdo_tg1c.c:143 b6/b7 nonzero, :147-148 crc8(poly 0x07, init 0xaa) over b[0..8] == b[9]; 159-164 id=b1..b4, 179 kPa=b6*1.364, 180 C=b7-50, 181 battery_ok=b8>5. Supersedes mainline tpms_hyundai_vdo.c:69 (same CRC, kPa=b6*1.375); its XOR fallback (:152) equals the Citroen decoder
    private fun vdoTg1c(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 80, inv, w, 0)) return null
        if (u(w, 6) == 0 || u(w, 7) == 0) return null
        if (crc8(w, 9, 0x07, 0xaa) != u(w, 9)) return null
        val flags = "state=%02x flags=%x repeat=%d batOk=%d".format(u(w, 0), u(w, 5) shr 4, u(w, 5) and 0x0f, if (u(w, 8) > 5) 1 else 0)
        return Reading("VDO-TG1C", "%08x".format(id4(w, 1)), u(w, 6) * 1.364, u(w, 7) - 50.0, flags)
    }

    // unverified: rtl_433 tpms_kia.c:73-74 crc8(poly 0x07, init 0x76) over b[0..7] == b[8]&0xf8 (69 bits); 66-68 id/psi/temp (8-bit truncated), 87-88 psi=raw/5, C=raw-50
    private fun kia(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 69, inv, w, 0) || allZero(w, 9)) return null
        if (crc8(w, 8, 0x07, 0x76) != (u(w, 8) and 0xf8)) return null
        val praw = ((u(w, 0) shl 4) or (u(w, 1) ushr 4)) and 0xff
        val traw = ((u(w, 1) shl 4) or (u(w, 2) ushr 4)) and 0xff
        val id = ((u(w, 2) and 0x0f) shl 28) or (u(w, 3) shl 20) or (u(w, 4) shl 12) or (u(w, 5) shl 4) or (u(w, 6) ushr 4)
        return Reading("Kia", "%08x".format(id), praw / 5.0 * PSI_KPA, traw - 50.0, null)
    }

    // unverified: rtl_433 tpms_elantra2012.c:63 crc8(poly 0x07, init 0) over b[0..7] == 0; 67-73 id=b2..b5, 69 kPa=b0+60, 70 C=b1-50, flags=b6
    private fun elantra(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 64, inv, w, 0) || allZero(w, 8)) return null
        if (crc8(w, 8, 0x07, 0x00) != 0) return null
        return Reading("Elantra2012", "%08x".format(id4(w, 2)), u(w, 0) + 60.0, u(w, 1) - 50.0, "%x".format(u(w, 6)))
    }

    // unverified: rtl_433 tpms_gm.c:66-67 six zero preamble bytes, :74-78 sum8 of b[6..14] == b[15], nonzero payload; 88-98 id=b8..b12, kPa=b13*2.75, C=b14-60, flags=b6b7
    private fun gm(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 128, inv, w, 0)) return null
        for (i in 0 until 6) if (w[i].toInt() != 0) return null
        var sum = 0
        var nz = false
        for (i in 6 until 15) {
            sum += u(w, i)
            if (w[i].toInt() != 0) nz = true
        }
        if (!nz || (sum and 0xff) != u(w, 15)) return null
        val id = (u(w, 8).toLong() shl 32) or (u(w, 9).toLong() shl 24) or (u(w, 10).toLong() shl 16) or (u(w, 11).toLong() shl 8) or u(w, 12).toLong()
        return Reading("GM-Aftermarket", "%010x".format(id), u(w, 13) * 2.75, u(w, 14) - 60.0, "%04x".format((u(w, 6) shl 8) or u(w, 7)))
    }

    // unverified: rtl_433 tpms_eezrv.c:75 preamble 0xffff, :106-111 sum8 of b[0..6] (carry sets 0x80) == check byte; 116-123 id=b0..b2, kPa=((b6&1)<<8|b3)*2.5, C=b4-50
    private fun eeztire(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (field(s, n, off, 16, inv) != 0xffff) return null
        if (!grab(s, n, off + 16, 64, inv, w, 0) || allZero(w, 8)) return null
        var sum = 0
        for (i in 1..7) sum += u(w, i)
        if (sum > 0xff) sum = sum or 0x80
        if ((sum and 0xff) != u(w, 0)) return null
        val kpa = (((u(w, 7) and 0x01) shl 8) + u(w, 4)) * 2.5
        val id = (u(w, 1) shl 16) or (u(w, 2) shl 8) or u(w, 3)
        return Reading("EezTire-E618", "%06x".format(id), kpa, u(w, 5) - 50.0, "%02x%02x".format(u(w, 6), u(w, 7)))
    }

    private fun gp(w: ByteArray, i: Int) = if (i == 0) u(w, 0) xor 0x94 else u(w, i) xor u(w, i - 1)

    // unverified: rtl_433 tpms_gear_hive.c:122 sync 0x2594, :73-76 differential xor decode, :79-83 sanity (p6&0x3c==0x20, p7&0x3f==0x35; no checksum in source); 86-95 kPa=((p5-base)&0xff)*6.25, C=21+temp_bits
    private fun gearHive(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (field(s, n, off, 16, inv) != 0x2594) return null
        if (!grab(s, n, off + 16, 72, inv, w, 0)) return null
        if ((gp(w, 6) and 0x3c) != 0x20 || (gp(w, 7) and 0x3f) != 0x35) return null
        val cls = gp(w, 1) and 0x0f
        val base = (80 + cls * 64) and 0xff
        val kpa = ((gp(w, 5) - base + 256) and 0xff) * 6.25
        val tbits = (gp(w, 7) shr 6) or ((gp(w, 6) and 0x03) shl 2)
        val id = (gp(w, 2) shl 16) or (gp(w, 3) shl 8) or gp(w, 4)
        return Reading("Gear-Hive", "%06x".format(id), kpa, tbits + 21.0, "class=%d".format(cls))
    }

    // unverified: rtl_433 tpms_smartire.c:91 crc7(poly 0x45, init 0x6f) over 6 bytes == 0 (47 bits, last bit absent); 96-107 id 22 bit, msg_type=b1>>6 (0 pressure kPa=(b0-40)*2.5, 1 temp C=b0-40)
    private fun smartire(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 47, inv, w, 0) || allZero(w, 6)) return null
        if (crc7(w, 6, 0x45, 0x6f) != 0) return null
        val type = (u(w, 1) and 0xc0) shr 6
        val v = u(w, 0) - 40
        if (type > 1) return null
        val id = ((u(w, 1) and 0x3f) shl 16) or (u(w, 2) shl 8) or u(w, 3)
        val flags = "inflate=%d flags=%02x".format((u(w, 4) and 0x80) shr 7, u(w, 4) and 0x7f)
        return Reading("SmarTire-AM", id.toString(), if (type == 0) v * 2.5 else null, if (type == 1) v.toDouble() else null, flags)
    }

    // unverified: rtl_433 tpms_renault_0435r.c:85 xor of b[0..8] == 0, :97 tick sanity; 105-111 id=b0..b2, kPa=b4/0.75, C=b5-50, flags=b3
    private fun renault0435r(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 72, inv, w, 0) || allZero(w, 9)) return null
        if (xorAll(w, 9) != 0) return null
        val b8 = u(w, 8)
        if (b8 != 0 && ((b8 shr 7) == 0 || (b8 and 0x7f) > 30)) return null
        val id = (u(w, 0) shl 16) or (u(w, 1) shl 8) or u(w, 2)
        return Reading("Renault-0435R", "%06x".format(id), u(w, 4) / 0.75, u(w, 5) - 50.0, "%02x".format(u(w, 3)))
    }

    // unverified: rtl_433 tpms_truck.c:62-69 b[] starts 4 bits in, zero id rejected, xor of 9 bytes == 0; 74-78 id=b0..b3, kPa=(b5&0xf)<<8|b6, C=b7 (no offset in source)
    private fun truck(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off + 4, 72, inv, w, 0)) return null
        if (w[0].toInt() == 0 && w[1].toInt() == 0 && w[2].toInt() == 0 && w[3].toInt() == 0) return null
        if (xorAll(w, 9) != 0) return null
        val flags = "wheel=%d flags=%x".format(u(w, 4), u(w, 5) shr 4)
        return Reading("Truck", "%08x".format(id4(w, 0)), (((u(w, 5) and 0x0f) shl 8) or u(w, 6)).toDouble(), u(w, 7).toDouble(), flags)
    }

    // unverified: rtl_433 tpms_jansite_ty588.c:72-78 b7 == b0, (b3+b4)&0xff == 0x30, b0/b1 low nibbles equal (no CRC); 80-85 C=(b2+b5)&0xff-139 within -40..120, kPa=((b5+b6)&0xff-90)*2.5; no id in source, id=b0..b6 hex
    private fun jansiteTy588(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 64, inv, w, 0)) return null
        if (u(w, 7) != u(w, 0) || ((u(w, 3) + u(w, 4)) and 0xff) != 0x30 || (u(w, 0) and 0x0f) != (u(w, 1) and 0x0f)) return null
        val t = ((u(w, 2) + u(w, 5)) and 0xff) - 139
        val praw = ((u(w, 5) + u(w, 6)) and 0xff) - 90
        if (praw < 0 || t < -40 || t > 120) return null
        val code = "%02x%02x%02x%02x%02x%02x%02x".format(u(w, 0), u(w, 1), u(w, 2), u(w, 3), u(w, 4), u(w, 5), u(w, 6))
        return Reading("Jansite-TY588", code, praw * 2.5, t.toDouble(), null)
    }

    // unverified: rtl_433 tpms_jansite_ty468.c:86-105 b7 == b0, low nibbles equal, (b3+b4)&0xff in {0xfb,0x64} (no CRC); 107-108 C=toff-((b2+b5)&0xff), kPa=(poff-((b5+b6)&0xff))*2.5; no id in source, id=b0..b6 hex
    private fun jansiteTy468(s: ByteArray, n: Int, off: Int, inv: Int, w: ByteArray): Reading? {
        if (!grab(s, n, off, 64, inv, w, 0)) return null
        if (u(w, 7) != u(w, 0) || (u(w, 0) and 0x0f) != (u(w, 1) and 0x0f)) return null
        val chk = (u(w, 3) + u(w, 4)) and 0xff
        val toff: Int
        val poff: Int
        if (chk == 0xfb) {
            toff = 224
            poff = 273
        } else if (chk == 0x64) {
            toff = 153
            poff = 201
        } else return null
        val code = "%02x%02x%02x%02x%02x%02x%02x".format(u(w, 0), u(w, 1), u(w, 2), u(w, 3), u(w, 4), u(w, 5), u(w, 6))
        return Reading("Jansite-TY468", code, (poff - ((u(w, 5) + u(w, 6)) and 0xff)) * 2.5, (toff - ((u(w, 2) + u(w, 5)) and 0xff)).toDouble(), null)
    }

    private fun hex(s: String): ByteArray = ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    private fun pack(d: ByteArray, nbits: Int, shift: Int, invert: Boolean): ByteArray {
        val out = ByteArray((shift + nbits + 7) / 8)
        for (i in 0 until nbits) {
            if ((d[i ushr 3].toInt() ushr (7 - (i and 7))) and 1 != 0) {
                val p = shift + i
                out[p ushr 3] = (out[p ushr 3].toInt() or (0x80 ushr (p and 7))).toByte()
            }
        }
        if (invert) for (i in out.indices) out[i] = (out[i].toInt() xor 0xff).toByte()
        return out
    }

    private fun expect(frame: ByteArray, nbits: Int, model: String, id: String, kpa: Double?, tempC: Double?) {
        for (shift in 0..7) for (invert in listOf(false, true)) {
            val r = decode(pack(frame, nbits, shift, invert), shift + nbits)
            check(r != null && r.model == model && r.id == id) { "$model shift=$shift inv=$invert got=$r" }
            check(kpa == null || Math.abs(r.pressureKpa!! - kpa) < 0.01) { "$model kpa ${r.pressureKpa}" }
            check(tempC == null || Math.abs(r.tempC!! - tempC) < 0.01) { "$model temp ${r.tempC}" }
        }
    }

    fun demo() {
        expect(hex("fd420b3ddc5352"), 56, "Schrader-Motorcycle", ((1 shl 22) or (0x42 shl 14) or (0x0b shl 6) or 0x0f).toString(), 238.0, 33.0)
        expect(hex("7f6703a38b2004949" + "0"), 68, "Schrader", "03A38B2", 0.0, 23.0)

        val t = ByteArray(9)
        t[0] = 0x12; t[1] = 0x34; t[2] = 0x56; t[3] = 0x78
        val tp = 121
        val tt = 101
        t[4] = ((tp shr 1) and 0x7f).toByte()
        t[5] = (((tp and 1) shl 7) or (tt shr 1)).toByte()
        t[6] = ((tt and 1) shl 7).toByte()
        t[7] = (tp xor 0xff).toByte()
        t[8] = crc8(t, 8, 0x07, 0x80).toByte()
        expect(t, 72, "Toyota", "12345678", (tp * 0.25 - 7.0) * PSI_KPA, 61.0)

        val r = ByteArray(9)
        r[0] = (400 shr 8).toByte(); r[1] = (400 and 0xff).toByte(); r[2] = 55
        r[3] = 0xef.toByte(); r[4] = 0xcd.toByte(); r[5] = 0xab.toByte(); r[6] = 0xff.toByte(); r[7] = 0xff.toByte()
        r[8] = crc8(r, 8, 0x07, 0x00).toByte()
        expect(r, 72, "Renault", "abcdef", 300.0, 25.0)

        val f = ByteArray(8)
        f[0] = 0xde.toByte(); f[1] = 0xad.toByte(); f[2] = 0xbe.toByte(); f[3] = 0xef.toByte()
        f[4] = 124; f[5] = 71; f[6] = 0x44
        f[7] = (f.take(7).sumOf { it.toInt() and 0xff } and 0xff).toByte()
        expect(f, 64, "Ford", "deadbeef", 31.0 * PSI_KPA, 15.0)

        val c = ByteArray(10)
        c[0] = 0x5a; c[1] = 0x0b; c[2] = 0xad.toByte(); c[3] = 0xf0.toByte(); c[4] = 0x0d; c[5] = 0x01
        c[6] = 100; c[7] = 75; c[8] = 0x30
        var x = 0
        for (i in 1..8) x = x xor (c[i].toInt() and 0xff)
        c[9] = x.toByte()
        expect(c, 80, "Citroen", "0badf00d", 136.4, 25.0)

        val po = ByteArray(10)
        po[0] = 0x0a; po[1] = 0x1b; po[2] = 0x2c; po[3] = 0x3d; po[4] = 100; po[5] = 65; po[6] = 0x12; po[7] = 0x34
        val pc = crc16(po, 0, 8, 0x1021, 0xffff)
        po[8] = (pc shr 8).toByte(); po[9] = pc.toByte()
        expect(po, 80, "Porsche", "0a1b2c3d", 150.0, 25.0)

        val h = ByteArray(10)
        h[0] = 0x01; h[1] = 0xca.toByte(); h[2] = 0xfe.toByte(); h[3] = 0xba.toByte(); h[4] = 0xbe.toByte(); h[5] = 0x32
        h[6] = 80; h[7] = 75; h[8] = 0x11
        h[9] = crc8(h, 9, 0x07, 0xaa).toByte()
        expect(h, 80, "VDO-TG1C", "cafebabe", 80 * 1.364, 25.0)

        val a = ByteArray(8)
        a[0] = 0x0b; a[1] = 0x0c; a[2] = 0x0d; a[3] = 0x0e; a[4] = 100; a[5] = 70; a[6] = 0x40
        a[7] = crc8(a, 7, 0x31, 0xff).toByte()
        expect(a, 64, "AVE", "0b0c0d0e", 235.2, 20.0)
    }
}

// 1090 MHz Mode-S / ADS-B decoder for 2 MS/s u8 IQ, reimplemented from antirez dump1090 (BSD-3-Clause).
package com.rootdowndigital.ouispy.wifiadapter

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.floor
import kotlin.math.round
import kotlin.math.sqrt

data class AdsbMsg(
    val icao: String,
    val df: Int,
    val callsign: String?,
    val lat: Double?,
    val lon: Double?,
    val altitudeFt: Int?,
    val velocityKt: Int?,
    val headingDeg: Int?
)

// unverified: not hardware-tested; no phase-correction retry and no CRC bit-error repair (dump1090 default fix_errors=off path).
class AdsbDecoder {
    private class Track {
        var evenLat = 0; var evenLon = 0; var oddLat = 0; var oddLon = 0
        var evenT = 0L; var oddT = 0L
        var seen = 0L
    }

    private var mag = IntArray(1 shl 16)
    private var carry = 0
    private val bits = IntArray(LONG_BITS)
    private val msg = IntArray(LONG_BITS / 8)
    private val tracks = HashMap<Int, Track>()

    fun process(iq: ByteArray, n: Int, onMsg: (AdsbMsg) -> Unit) {
        val ns = n / 2
        val len = carry + ns
        if (mag.size < len) mag = mag.copyOf(len + (len shr 1))
        val m = mag
        var o = carry
        var p = 0
        while (p + 1 < n) {
            val i = abs((iq[p].toInt() and 255) - 127)
            val q = abs((iq[p + 1].toInt() and 255) - 127)
            m[o++] = MAGLUT[i * 129 + q]
            p += 2
        }
        val end = len - FULL_LEN * 2
        var j = 0
        while (j < end) {
            if (!preamble(m, j)) { j++; continue }
            j += demod(m, j, onMsg) + 1
        }
        val start = if (j > len) len else if (j < 0) 0 else j
        carry = len - start
        if (carry > 0) System.arraycopy(m, start, m, 0, carry)
    }

    private fun preamble(m: IntArray, j: Int): Boolean {
        if (!(m[j] > m[j + 1] && m[j + 1] < m[j + 2] && m[j + 2] > m[j + 3] && m[j + 3] < m[j] &&
                m[j + 4] < m[j] && m[j + 5] < m[j] && m[j + 6] < m[j] && m[j + 7] > m[j + 8] &&
                m[j + 8] < m[j + 9] && m[j + 9] > m[j + 6])) return false
        val high = (m[j] + m[j + 2] + m[j + 7] + m[j + 9]) / 6
        if (m[j + 4] >= high || m[j + 5] >= high) return false
        if (m[j + 11] >= high || m[j + 12] >= high || m[j + 13] >= high || m[j + 14] >= high) return false
        return true
    }

    private fun demod(m: IntArray, j: Int, onMsg: (AdsbMsg) -> Unit): Int {
        val base = j + PREAMBLE_US * 2
        var errors = 0
        var i = 0
        while (i < LONG_BITS * 2) {
            val low = m[base + i]
            val high = m[base + i + 1]
            var d = low - high
            if (d < 0) d = -d
            val b = i shr 1
            if (i > 0 && d < 256) bits[b] = bits[b - 1]
            else if (low == high) { bits[b] = 2; if (i < SHORT_BITS * 2) errors++ }
            else bits[b] = if (low > high) 1 else 0
            i += 2
        }
        i = 0
        while (i < LONG_BITS) {
            msg[i shr 3] = ((bits[i] shl 7) or (bits[i + 1] shl 6) or (bits[i + 2] shl 5) or (bits[i + 3] shl 4) or
                    (bits[i + 4] shl 3) or (bits[i + 5] shl 2) or (bits[i + 6] shl 1) or bits[i + 7]) and 255
            i += 8
        }
        val df = msg[0] shr 3
        val msgBits = if (df in 16..21) LONG_BITS else SHORT_BITS
        val msgLen = msgBits / 8
        var delta = 0
        i = 0
        while (i < msgLen * 16) {
            delta += abs(m[base + i] - m[base + i + 1])
            i += 2
        }
        delta /= msgLen * 4
        if (delta < 10 * 255) return 0
        if (errors != 0) return 0
        if (checksum(msgBits) != 0) return 0
        if (df == 17) decode17(onMsg) else if (df == 11) onMsg(AdsbMsg(icaoStr(), 11, null, null, null, null, null, null))
        return (PREAMBLE_US + msgLen * 8) * 2
    }

    private fun checksum(msgBits: Int): Int {
        val off = if (msgBits == LONG_BITS) 0 else LONG_BITS - SHORT_BITS
        var crc = 0
        for (k in 0 until msgBits - 24) {
            if (msg[k shr 3] and (1 shl (7 - (k and 7))) != 0) crc = crc xor CRC_TABLE[k + off]
        }
        val nb = msgBits / 8
        val rem = (msg[nb - 3] shl 16) or (msg[nb - 2] shl 8) or msg[nb - 1]
        return (crc xor rem) and 0xFFFFFF
    }

    private fun icaoKey() = (msg[1] shl 16) or (msg[2] shl 8) or msg[3]

    private fun icaoStr() = String.format("%06X", icaoKey())

    private fun decode17(onMsg: (AdsbMsg) -> Unit) {
        val tc = msg[4] shr 3
        val sub = msg[4] and 7
        var callsign: String? = null
        var lat: Double? = null
        var lon: Double? = null
        var alt: Int? = null
        var vel: Int? = null
        var hdg: Int? = null
        if (tc in 1..4) {
            val c = CharArray(8)
            c[0] = AIS[msg[5] shr 2]
            c[1] = AIS[((msg[5] and 3) shl 4) or (msg[6] shr 4)]
            c[2] = AIS[((msg[6] and 15) shl 2) or (msg[7] shr 6)]
            c[3] = AIS[msg[7] and 63]
            c[4] = AIS[msg[8] shr 2]
            c[5] = AIS[((msg[8] and 3) shl 4) or (msg[9] shr 4)]
            c[6] = AIS[((msg[9] and 15) shl 2) or (msg[10] shr 6)]
            c[7] = AIS[msg[10] and 63]
            val s = String(c).trim()
            callsign = if (s.isEmpty()) null else s
        } else if (tc in 9..18) {
            if (msg[5] and 1 != 0) alt = (((msg[5] shr 1) shl 4) or ((msg[6] and 0xF0) shr 4)) * 25 - 1000
            val odd = msg[6] and 4 != 0
            val rawLat = ((msg[6] and 3) shl 15) or (msg[7] shl 7) or (msg[8] shr 1)
            val rawLon = ((msg[8] and 1) shl 16) or (msg[9] shl 8) or msg[10]
            val now = System.currentTimeMillis()
            val t = tracks.getOrPut(icaoKey()) { Track() }
            t.seen = now
            if (odd) { t.oddLat = rawLat; t.oddLon = rawLon; t.oddT = now }
            else { t.evenLat = rawLat; t.evenLon = rawLon; t.evenT = now }
            if (t.evenT != 0L && t.oddT != 0L && abs(t.evenT - t.oddT) <= 10000L) {
                val r = cpr(t)
                if (r != null) { lat = r[0]; lon = r[1] }
            }
            if (tracks.size > 1024) tracks.entries.removeIf { now - it.value.seen > 60000L }
        } else if (tc == 19 && sub in 1..2) {
            val ewDir = (msg[5] and 4) shr 2
            val ew = ((msg[5] and 3) shl 8) or msg[6]
            val nsDir = (msg[7] and 0x80) shr 7
            val ns = ((msg[7] and 0x7f) shl 3) or ((msg[8] and 0xe0) shr 5)
            val v = sqrt((ns * ns + ew * ew).toDouble())
            vel = v.toInt()
            if (vel > 0) {
                val h = atan2((if (ewDir != 0) -ew else ew).toDouble(), (if (nsDir != 0) -ns else ns).toDouble()) * 360.0 / (2 * Math.PI)
                hdg = (if (h < 0) h + 360 else h).toInt()
            } else hdg = 0
        } else if (tc == 19 && sub in 3..4) {
            if (msg[5] and 4 != 0) hdg = (360.0 / 128 * (((msg[5] and 3) shl 5) or (msg[6] shr 3))).toInt()
        } else return
        onMsg(AdsbMsg(icaoStr(), 17, callsign, lat, lon, alt, vel, hdg))
    }

    private fun nl(latIn: Double): Int {
        val lat = abs(latIn)
        for (k in NL_THRESH.indices) if (lat < NL_THRESH[k]) return 59 - k
        return 1
    }

    private fun cpr(t: Track): DoubleArray? {
        val lat0 = t.evenLat.toDouble()
        val lat1 = t.oddLat.toDouble()
        val lon0 = t.evenLon.toDouble()
        val lon1 = t.oddLon.toDouble()
        val j = floor((59 * lat0 - 60 * lat1) / 131072 + 0.5).toInt()
        var rlat0 = (360.0 / 60) * (Math.floorMod(j, 60) + lat0 / 131072)
        var rlat1 = (360.0 / 59) * (Math.floorMod(j, 59) + lat1 / 131072)
        if (rlat0 >= 270) rlat0 -= 360
        if (rlat1 >= 270) rlat1 -= 360
        if (nl(rlat0) != nl(rlat1)) return null
        val lat: Double
        var lon: Double
        if (t.evenT > t.oddT) {
            val nlv = nl(rlat0)
            val ni = maxOf(nlv, 1)
            val m = floor((lon0 * (nlv - 1) - lon1 * nlv) / 131072 + 0.5).toInt()
            lon = (360.0 / ni) * (Math.floorMod(m, ni) + lon0 / 131072)
            lat = rlat0
        } else {
            val nlv = nl(rlat1)
            val ni = maxOf(nlv - 1, 1)
            val m = floor((lon0 * (nlv - 1) - lon1 * nlv) / 131072 + 0.5).toInt()
            lon = (360.0 / ni) * (Math.floorMod(m, ni) + lon1 / 131072)
            lat = rlat1
        }
        if (lon > 180) lon -= 360
        return doubleArrayOf(lat, lon)
    }

    companion object {
        private const val PREAMBLE_US = 8
        private const val SHORT_BITS = 56
        private const val LONG_BITS = 112
        private const val FULL_LEN = PREAMBLE_US + LONG_BITS
        private const val AIS = "?ABCDEFGHIJKLMNOPQRSTUVWXYZ????? ???????????????0123456789??????"

        private val MAGLUT = IntArray(129 * 129).also {
            for (i in 0 until 129) for (q in 0 until 129) it[i * 129 + q] = round(sqrt((i * i + q * q).toDouble()) * 360).toInt()
        }

        private val CRC_TABLE = intArrayOf(
            0x3935ea, 0x1c9af5, 0xf1b77e, 0x78dbbf, 0xc397db, 0x9e31e9, 0xb0e2f0, 0x587178,
            0x2c38bc, 0x161c5e, 0x0b0e2f, 0xfa7d13, 0x82c48d, 0xbe9842, 0x5f4c21, 0xd05c14,
            0x682e0a, 0x341705, 0xe5f186, 0x72f8c3, 0xc68665, 0x9cb936, 0x4e5c9b, 0xd8d449,
            0x939020, 0x49c810, 0x24e408, 0x127204, 0x093902, 0x049c81, 0xfdb444, 0x7eda22,
            0x3f6d11, 0xe04c8c, 0x702646, 0x381323, 0xe3f395, 0x8e03ce, 0x4701e7, 0xdc7af7,
            0x91c77f, 0xb719bb, 0xa476d9, 0xadc168, 0x56e0b4, 0x2b705a, 0x15b82d, 0xf52612,
            0x7a9309, 0xc2b380, 0x6159c0, 0x30ace0, 0x185670, 0x0c2b38, 0x06159c, 0x030ace,
            0x018567, 0xff38b7, 0x80665f, 0xbfc92b, 0xa01e91, 0xaff54c, 0x57faa6, 0x2bfd53,
            0xea04ad, 0x8af852, 0x457c29, 0xdd4410, 0x6ea208, 0x375104, 0x1ba882, 0x0dd441,
            0xf91024, 0x7c8812, 0x3e4409, 0xe0d800, 0x706c00, 0x383600, 0x1c1b00, 0x0e0d80,
            0x0706c0, 0x038360, 0x01c1b0, 0x00e0d8, 0x00706c, 0x003836, 0x001c1b, 0xfff409,
            0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000,
            0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000,
            0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000
        )

        private val NL_THRESH = doubleArrayOf(
            10.47047130, 14.82817437, 18.18626357, 21.02939493, 23.54504487, 25.82924707, 27.93898710,
            29.91135686, 31.77209708, 33.53993436, 35.22899598, 36.85025108, 38.41241892, 39.92256684,
            41.38651832, 42.80914012, 44.19454951, 45.54626723, 46.86733252, 48.16039128, 49.42776439,
            50.67150166, 51.89342469, 53.09516153, 54.27817472, 55.44378444, 56.59318756, 57.72747354,
            58.84763776, 59.95459277, 61.04917774, 62.13216659, 63.20427479, 64.26616523, 65.31845310,
            66.36171008, 67.39646774, 68.42322022, 69.44242631, 70.45451075, 71.45986473, 72.45884545,
            73.45177442, 74.43893416, 75.42056257, 76.39684391, 77.36789461, 78.33374083, 79.29428225,
            80.24923213, 81.19801349, 82.13956981, 83.07199445, 83.99173563, 84.89166191, 85.75541621,
            86.53536998, 87.00000000
        )
    }
}

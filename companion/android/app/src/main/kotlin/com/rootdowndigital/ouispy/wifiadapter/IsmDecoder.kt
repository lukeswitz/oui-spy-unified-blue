package com.rootdowndigital.ouispy.wifiadapter

import kotlin.math.atan2
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

// OOK/ASK + 2-FSK ISM burst demodulator for u8 IQ; emits raw bitstrings only, no vendor/ID decode.
// unverified: Manchester polarity (high->low = 1), differential convention (start transition = 0), FSK polarity (high = 1) are conventions, not checked against captures.

data class IsmBurst(val modulation: String, val bitHex: String, val bitCount: Int, val centerHz: Long, val rssiDb: Float)

class IsmDecoder(
    private val sampleRate: Int,
    private val centerHz: Long = 433_920_000L,
    private val minBits: Int = 24,
    maxGapUs: Int = 3000,
    private val listener: (IsmBurst) -> Unit,
) {
    var onPulses: ((IntArray) -> Unit)? = null

    private val aEnv = minOf(1f, 1f / (sampleRate * 8e-6f))
    private val aF = minOf(1f, 1f / (sampleRate * 6e-6f))
    private val dHi = 1f / (sampleRate * 0.05f)
    private val dLo = 1f / (sampleRate * 0.2f)
    private val maxGap = (sampleRate.toLong() * maxGapUs / 1_000_000L).toInt()
    private val minRun = max(2, (sampleRate * 20e-6f).toInt())
    private val guard = max(4, (sampleRate * 20e-6f).toInt())
    private val minFsk = sampleRate / 1000
    private val minSpread = 2f * Math.PI.toFloat() * 10000f / sampleRate

    private val pulses = IntArray(MAXP)
    private val runsF = IntArray(MAXP)
    private val hb = ByteArray(2 * MAXP)
    private val bitsBuf = ByteArray(MAXP)
    private val fbuf = FloatArray(max(1024, sampleRate / 20))

    private var primed = false
    private var pi = 0f
    private var pq = 0f
    private var env = 0f
    private var fsm = 0f
    private var hi = 0f
    private var lo = 0f
    private var inMark = false
    private var inBurst = false
    private var run = 0
    private var np = 0
    private var fn = 0
    private var markSum = 0f
    private var sumMag = 0f
    private var nMag = 0

    fun feed(buf: ByteArray, len: Int) {
        var k = 0
        while (k + 1 < len) {
            step((buf[k].toInt() and 0xFF) - 127.5f, (buf[k + 1].toInt() and 0xFF) - 127.5f)
            k += 2
        }
    }

    private fun step(i: Float, q: Float) {
        val mag = sqrt(i * i + q * q)
        val f = atan2(q * pi - i * pq, i * pi + q * pq)
        pi = i
        pq = q
        if (!primed) {
            env = mag; hi = mag; lo = mag; fsm = 0f; primed = true
            return
        }
        env += aEnv * (mag - env)
        fsm += aF * (f - fsm)
        if (env > hi) hi = env else hi += (env - hi) * dHi
        if (env < lo) lo = env else if (!inMark) lo += (env - lo) * dLo
        val span = hi - lo
        if (!inMark) {
            if (span >= MIN_SPAN && hi >= 2f * lo && env > lo + 0.6f * span) startMark()
        } else if (env < lo + 0.4f * span) {
            endMark()
        }
        if (inMark) {
            run++
            markSum += env
            sumMag += env
            nMag++
            if (fn < fbuf.size) fbuf[fn++] = fsm
        } else if (inBurst) {
            run++
            if (run > maxGap) finishBurst()
        }
    }

    private fun push(r: Int) {
        if (np < MAXP) pulses[np++] = r
    }

    private fun startMark() {
        if (inBurst) {
            push(run)
        } else {
            inBurst = true
            np = 0
            sumMag = 0f
            nMag = 0
        }
        inMark = true
        run = 0
        fn = 0
        markSum = 0f
    }

    private fun endMark() {
        push(run)
        val mk = run
        inMark = false
        run = 0
        if (fn >= minFsk && mk > 0) decodeFsk(markSum / mk)
        if (np >= MAXP) finishBurst()
    }

    private fun finishBurst() {
        val n = np
        inBurst = false
        np = 0
        run = 0
        if (n >= minBits / 2) decodeOok(n)
    }

    private fun dbfs(x: Float): Float = 20f * log10(max(x, 1e-3f) / 180.3f)

    private fun mergeGlitches(a: IntArray, n: Int): Int {
        var w = 0
        var i = 0
        while (i < n) {
            if (a[i] < minRun && w > 0 && i + 1 < n) {
                a[w - 1] += a[i] + a[i + 1]
                i += 2
            } else {
                a[w++] = a[i]
                i++
            }
        }
        return w
    }

    private fun unitOf(a: IntArray, n: Int): Float {
        var m = Int.MAX_VALUE
        for (i in 0 until n) if (a[i] >= minRun && a[i] < m) m = a[i]
        if (m == Int.MAX_VALUE) return 0f
        var s = 0f
        var c = 0
        for (i in 0 until n) if (a[i] >= minRun && a[i] * 2 <= m * 3) { s += a[i]; c++ }
        return s / c
    }

    private fun decodeOok(n0: Int) {
        val n = mergeGlitches(pulses, n0)
        if (n < minBits / 2) return
        onPulses?.let { cb ->
            val us = IntArray(n)
            for (i in 0 until n) us[i] = (pulses[i] * 1_000_000L / sampleRate).toInt()
            cb(us)
        }
        val u = unitOf(pulses, n)
        if (u < 3f) return
        var hn = 0
        var broke = false
        for (i in 0 until n) {
            val k = (pulses[i] / u + 0.5f).toInt()
            if (k < 1) continue
            if (k > 2 || hn + k > hb.size) {
                if (hn >= 2 * minBits) { broke = true; break }
                hn = 0
                continue
            }
            val lvl: Byte = if (i % 2 == 0) 1 else 0
            for (j in 0 until k) hb[hn++] = lvl
        }
        if (!broke && n % 2 == 1 && hn < hb.size) hb[hn++] = 0
        var best = 0
        var bestStart = 0
        for (off in 0..1) {
            var j = off
            var cur = -1
            while (j + 1 < hn) {
                if (hb[j] != hb[j + 1]) {
                    if (cur < 0) cur = j
                    val len = (j - cur) / 2 + 1
                    if (len > best) { best = len; bestStart = cur }
                } else {
                    cur = -1
                }
                j += 2
            }
        }
        val rssi = dbfs(if (nMag > 0) sumMag / nMag else 0f)
        if (best >= minBits) {
            for (q in 0 until best) bitsBuf[q] = hb[bestStart + 2 * q]
            emit("OOK-MANCHESTER", best, rssi)
        }
        if (best - 1 >= minBits) {
            var prevSecond = hb[bestStart + 1]
            for (q in 1 until best) {
                bitsBuf[q - 1] = if (hb[bestStart + 2 * q] == prevSecond) 1 else 0
                prevSecond = hb[bestStart + 2 * q + 1]
            }
            emit("OOK-DMANCHESTER", best - 1, rssi)
        }
    }

    private fun decodeFsk(markMag: Float) {
        val a = guard
        val b = fn - guard
        if (b - a < minFsk / 2) return
        var mn = Float.MAX_VALUE
        var mx = -Float.MAX_VALUE
        for (i in a until b) {
            val v = fbuf[i]
            if (v < mn) mn = v
            if (v > mx) mx = v
        }
        if (mx - mn < minSpread) return
        val mid = (mx + mn) / 2f
        val h = (mx - mn) * 0.1f
        var level = if (fbuf[a] > mid) 1 else 0
        val lv0 = level
        var r = 0
        var nr = 0
        for (i in a until b) {
            val v = fbuf[i]
            val nl = if (v > mid + h) 1 else if (v < mid - h) 0 else level
            if (nl == level) {
                r++
            } else {
                if (nr < MAXP) runsF[nr++] = r
                r = 1
                level = nl
            }
        }
        if (nr < MAXP) runsF[nr++] = r
        nr = mergeGlitches(runsF, nr)
        val u = unitOf(runsF, nr)
        if (u < 3f) return
        var nb = 0
        for (i in 0 until nr) {
            val k = (runsF[i] / u + 0.5f).toInt()
            if (k < 1) continue
            if (k > 16 || nb + k > bitsBuf.size) break
            val lvl: Byte = if ((i % 2 == 0) == (lv0 == 1)) 1 else 0
            for (j in 0 until k) bitsBuf[nb++] = lvl
        }
        if (nb >= minBits) emit("FSK", nb, dbfs(markMag))
    }

    private fun emit(mod: String, nb: Int, rssi: Float) {
        val sb = StringBuilder((nb + 3) / 4)
        var v = 0
        var c = 0
        for (i in 0 until nb) {
            v = (v shl 1) or bitsBuf[i].toInt()
            if (++c == 4) { sb.append(HEX[v]); v = 0; c = 0 }
        }
        if (c > 0) sb.append(HEX[v shl (4 - c)])
        listener(IsmBurst(mod, sb.toString(), nb, centerHz, rssi))
    }

    companion object {
        private const val MAXP = 1024
        private const val MIN_SPAN = 8f
        private const val HEX = "0123456789ABCDEF"

        fun demo() {
            val fs = 250000
            val half = 25
            val bits = 0xA5C3F00DL
            val out = ArrayList<IsmBurst>()
            val d = IsmDecoder(fs) { out.add(it) }
            val total = 3000 + 32 * 2 * half + 4000
            val buf = ByteArray(2 * total)
            var rng = 1
            var p = 0
            fun put(on: Boolean) {
                rng = rng * 1103515245 + 12345
                buf[p++] = ((if (on) 207 else 127) + ((rng ushr 16) and 1)).toByte()
                buf[p++] = (127 + ((rng ushr 17) and 1)).toByte()
            }
            repeat(3000) { put(false) }
            for (b in 31 downTo 0) {
                val first = ((bits shr b) and 1L) == 1L
                repeat(half) { put(first) }
                repeat(half) { put(!first) }
            }
            repeat(4000) { put(false) }
            d.feed(buf, p)
            val m = out.firstOrNull { it.modulation == "OOK-MANCHESTER" }
            check(m != null && m.bitCount == 32 && m.bitHex == "A5C3F00D") { "ism demo failed: $out" }
        }
    }
}

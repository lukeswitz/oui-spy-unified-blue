package com.rootdowndigital.ouispy.wifiadapter // Pure DSP for RTL-SDR u8 IQ: FFT, Hann, power spectrum, peak picking.

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.sin

internal object SdrDsp {
    private val windows = HashMap<Int, FloatArray>()

    fun fft(re: FloatArray, im: FloatArray) {
        val n = re.size
        require(n > 0 && n and (n - 1) == 0 && im.size == n) { "size must be a power of two" }
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) {
                j = j xor bit
                bit = bit shr 1
            }
            j = j xor bit
            if (i < j) {
                val tr = re[i]; re[i] = re[j]; re[j] = tr
                val ti = im[i]; im[i] = im[j]; im[j] = ti
            }
        }
        var len = 2
        while (len <= n) {
            val half = len shr 1
            val step = -2.0 * PI / len
            for (k in 0 until half) {
                val wr = cos(step * k).toFloat()
                val wi = sin(step * k).toFloat()
                var a = k
                while (a < n) {
                    val b = a + half
                    val xr = re[b] * wr - im[b] * wi
                    val xi = re[b] * wi + im[b] * wr
                    re[b] = re[a] - xr
                    im[b] = im[a] - xi
                    re[a] += xr
                    im[a] += xi
                    a += len
                }
            }
            len = len shl 1
        }
    }

    @Synchronized
    fun hann(n: Int): FloatArray = windows.getOrPut(n) {
        if (n == 1) floatArrayOf(1f)
        else FloatArray(n) { (0.5 * (1.0 - cos(2.0 * PI * it / (n - 1)))).toFloat() }
    }

    class Spectrum(val fftSize: Int) {
        private val re = FloatArray(fftSize)
        private val im = FloatArray(fftSize)
        private val window = hann(fftSize)
        private val power = FloatArray(fftSize)
        private val norm = fftSize.toFloat() * fftSize

        fun process(iq: ByteArray, n: Int): FloatArray {
            val avail = minOf(n / 2, fftSize)
            for (k in 0 until avail) {
                val w = window[k]
                re[k] = ((iq[2 * k].toInt() and 0xFF) - 127.4f) * w
                im[k] = ((iq[2 * k + 1].toInt() and 0xFF) - 127.4f) * w
            }
            for (k in avail until fftSize) {
                re[k] = 0f
                im[k] = 0f
            }
            fft(re, im)
            val half = fftSize / 2
            for (k in 0 until fftSize) {
                power[(k + half) % fftSize] = 10f * log10((re[k] * re[k] + im[k] * im[k]) / norm + 1e-12f)
            }
            return power
        }
    }

    fun peaks(power: FloatArray, centerHz: Long, sampleRate: Int, floorDb: Float, minSepBins: Int): List<Pair<Long, Float>> {
        val size = power.size
        if (size < 3) return emptyList()
        val sorted = power.copyOf().also { it.sort() }
        val thresh = sorted[size / 2] + floorDb
        val bins = ArrayList<Int>()
        for (i in 1 until size - 1) {
            val p = power[i]
            if (p < thresh || p <= power[i - 1] || p < power[i + 1]) continue
            if (bins.isNotEmpty() && i - bins.last() < minSepBins) {
                if (p > power[bins.last()]) bins[bins.size - 1] = i
            } else {
                bins.add(i)
            }
        }
        return bins.map { centerHz + (it - size / 2).toLong() * sampleRate / size to power[it] }
    }

    fun demo() {
        val n = 1024
        val bin = 100
        val sr = 1_024_000
        val iq = ByteArray(2 * n)
        for (k in 0 until n) {
            val a = 2.0 * PI * bin * k / n
            iq[2 * k] = (127.4 + 100.0 * cos(a)).toInt().toByte()
            iq[2 * k + 1] = (127.4 + 100.0 * sin(a)).toInt().toByte()
        }
        val p = Spectrum(n).process(iq, iq.size)
        var best = 0
        for (i in p.indices) if (p[i] > p[best]) best = i
        check(best == n / 2 + bin) { "tone at bin $best" }
        val found = peaks(p, 100_000_000L, sr, 30f, 4)
        check(found.size == 1 && found[0].first == 100_000_000L + bin * 1000L) { "peaks $found" }
        val re = FloatArray(n) { cos(2.0 * PI * bin * it / n).toFloat() }
        val im = FloatArray(n)
        fft(re, im)
        check(re[bin] > n / 2 - 1 && re[n - bin] > n / 2 - 1 && kotlin.math.abs(re[bin + 5]) < 1f) { "fft real tone" }
    }
}

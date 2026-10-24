// Kotlin reimplementation of rtl_433 pulse slicers (src/pulse_slicer.c; GPL-3 reference, algorithm transcribed as facts).
package com.rootdowndigital.ouispy.wifiadapter

import kotlin.math.abs

class SliceParams(
    val short: Float,
    val long: Float,
    val reset: Float,
    val gap: Float,
    val sync: Float,
    val tolerance: Float,
)

private class SliceCtx(p: PulseData, t: SliceParams) {
    val spu = p.sampleRate / 1.0e6f
    val sShort = (t.short * spu).toInt()
    val sLong = (t.long * spu).toInt()
    val sReset = (t.reset * spu).toInt()
    val sGap = (t.gap * spu).toInt()
    val sSync = (t.sync * spu).toInt()
    val sTol = (t.tolerance * spu).toInt()
    val ok = !((t.short > 0 && sShort <= 0)
        || (t.long > 0 && sLong <= 0)
        || (t.reset > 0 && sReset <= 0)
        || (t.gap > 0 && sGap <= 0)
        || (t.sync > 0 && sSync <= 0)
        || (t.tolerance > 0 && sTol <= 0))
}

object Slicer {
    private fun sym(p: PulseData, n: Int): Int = if (n % 2 == 0) p.pulse[n / 2] else p.gap[n / 2]

    fun pulsePcm(p: PulseData, t: SliceParams): List<BitBuffer> {
        val c = SliceCtx(p, t)
        if (!c.ok) return emptyList()
        // unverified: guard against divide by zero where pulse_slicer.c would be undefined behavior
        if (c.sLong <= 0) return emptyList()
        val out = ArrayList<BitBuffer>()
        var bits = BitBuffer()
        val np = p.numPulses
        var fShort = if (t.short > 0.0f) 1.0f / (t.short * c.spu) else 0f
        var fLong = if (t.long > 0.0f) 1.0f / (t.long * c.spu) else 0f
        val gapLimit = if (c.sGap != 0) c.sGap else c.sReset
        val maxZeros = gapLimit / c.sLong
        var sTol = c.sTol
        if (sTol <= 0) sTol = c.sLong / 4
        var minCount = if (c.sShort == c.sLong) 12 else 4
        var preambleLen = 0
        var n = 0
        while (c.sShort != c.sLong && n < np) {
            var swidth = 0
            var lwidth = 0
            var count = 0
            while (n < np
                && p.pulse[n] >= c.sShort - sTol
                && p.pulse[n] <= c.sShort + sTol
                && p.pulse[n] + p.gap[n] >= c.sLong - sTol
                && p.pulse[n] + p.gap[n] <= c.sLong + sTol
            ) {
                swidth += p.pulse[n]
                lwidth += p.pulse[n] + p.gap[n]
                count += 1
                n++
            }
            if (count >= minCount) {
                fLong = count.toFloat() / lwidth
                fShort = count.toFloat() / swidth
                minCount = count
                preambleLen = count
            }
            n++
        }
        var rzsWidth = 0
        var rzlWidth = 0
        var rzCount = 0
        n = 0
        while (preambleLen == 0 && c.sShort != c.sLong && n < np) {
            if (p.pulse[n] >= c.sShort - sTol
                && p.pulse[n] <= c.sShort + sTol
                && p.pulse[n] + p.gap[n] >= c.sLong - sTol
                && p.pulse[n] + p.gap[n] <= c.sLong + sTol
            ) {
                rzsWidth += p.pulse[n]
                rzlWidth += p.pulse[n] + p.gap[n]
                rzCount += 1
            }
            n++
        }
        if (rzCount > 8) {
            fLong = rzCount.toFloat() / rzlWidth
            fShort = rzCount.toFloat() / rzsWidth
        }
        n = 0
        while (c.sShort == c.sLong && n < np) {
            var width = 0
            var count = 0
            while (n < np
                && (p.pulse[n] * fShort + 0.5).toInt() == 1
                && (p.gap[n] * fLong + 0.5).toInt() == 1
            ) {
                width += p.pulse[n] + p.gap[n]
                count += 2
                n++
            }
            if (count >= minCount) {
                fShort = count.toFloat() / width
                fLong = fShort
                minCount = count
                preambleLen = count
            }
            n++
        }
        var nrzWidth = 0
        var nrzCount = 0
        n = 0
        while (preambleLen == 0 && c.sShort == c.sLong && n < np) {
            if (p.pulse[n] >= c.sShort - sTol && p.pulse[n] <= c.sShort + sTol) {
                nrzWidth += p.pulse[n]
                nrzCount += 1
            }
            if (p.pulse[n] >= 2 * c.sShort - sTol && p.pulse[n] <= 2 * c.sShort + sTol) {
                nrzWidth += p.pulse[n]
                nrzCount += 2
            }
            if (p.gap[n] >= c.sLong - sTol && p.gap[n] <= c.sLong + sTol) {
                nrzWidth += p.gap[n]
                nrzCount += 1
            }
            if (p.gap[n] >= 2 * c.sLong - sTol && p.gap[n] <= 2 * c.sLong + sTol) {
                nrzWidth += p.gap[n]
                nrzCount += 2
            }
            n++
        }
        if (nrzCount > 20) {
            fShort = nrzCount.toFloat() / nrzWidth
            fLong = fShort
        }
        for (i in 0 until np) {
            val highs = (p.pulse[i] * fShort + 0.5f).toInt()
            var lows = ((p.gap[i] + c.sShort - c.sLong) * fLong + 0.5f).toInt()
            repeat(highs) { bits.addBit(1) }
            lows = minOf(lows, maxZeros)
            repeat(lows) { bits.addBit(0) }
            if (c.sShort != c.sLong && abs(p.pulse[i] - c.sShort) > sTol) {
                bits = BitBuffer()
            } else if (p.gap[i] > gapLimit && p.gap[i] <= c.sReset) {
                bits.addRow()
            }
            if ((i == np - 1 || p.gap[i] > c.sReset) && (bits.bitsPerRow[0] > 0 || bits.numRows > 1)) {
                out.add(bits)
                bits = BitBuffer()
            }
        }
        return out
    }

    fun pulsePpm(p: PulseData, t: SliceParams): List<BitBuffer> {
        val c = SliceCtx(p, t)
        if (!c.ok) return emptyList()
        val out = ArrayList<BitBuffer>()
        var bits = BitBuffer()
        val np = p.numPulses
        val zeroL: Int
        val zeroU: Int
        val oneL: Int
        val oneU: Int
        var syncL = 0
        var syncU = 0
        if (c.sTol > 0) {
            zeroL = c.sShort - c.sTol
            zeroU = c.sShort + c.sTol
            oneL = c.sLong - c.sTol
            oneU = c.sLong + c.sTol
            if (c.sSync > 0) {
                syncL = c.sSync - c.sTol
                syncU = c.sSync + c.sTol
            }
        } else {
            zeroL = 0
            zeroU = (c.sShort + c.sLong) / 2 + 1
            oneL = zeroU - 1
            oneU = if (c.sGap != 0) c.sGap else c.sReset
        }
        for (n in 0 until np) {
            val g = p.gap[n]
            if (g > zeroL && g < zeroU) {
                bits.addBit(0)
            } else if (g > oneL && g < oneU) {
                bits.addBit(1)
            } else if (g > syncL && g < syncU) {
                bits.addSync()
            } else if (g < c.sReset) {
                bits.addRow()
            }
            if ((n == np - 1 || g >= c.sReset) && (bits.bitsPerRow[0] > 0 || bits.numRows > 1)) {
                out.add(bits)
                bits = BitBuffer()
            }
        }
        return out
    }

    fun pulsePwm(p: PulseData, t: SliceParams): List<BitBuffer> {
        val c = SliceCtx(p, t)
        if (!c.ok) return emptyList()
        val out = ArrayList<BitBuffer>()
        var bits = BitBuffer()
        val np = p.numPulses
        val oneL: Int
        val oneU: Int
        val zeroL: Int
        val zeroU: Int
        var syncL = 0
        var syncU = 0
        if (c.sTol > 0) {
            oneL = c.sShort - c.sTol
            oneU = c.sShort + c.sTol
            zeroL = c.sLong - c.sTol
            zeroU = c.sLong + c.sTol
            if (c.sSync > 0) {
                syncL = c.sSync - c.sTol
                syncU = c.sSync + c.sTol
            }
        } else if (c.sSync <= 0) {
            oneL = 0
            oneU = (c.sShort + c.sLong) / 2 + 1
            zeroL = oneU - 1
            zeroU = Int.MAX_VALUE
        } else if (c.sSync < c.sShort) {
            syncL = 0
            syncU = (c.sSync + c.sShort) / 2 + 1
            oneL = syncU - 1
            oneU = (c.sShort + c.sLong) / 2 + 1
            zeroL = oneU - 1
            zeroU = Int.MAX_VALUE
        } else if (c.sSync < c.sLong) {
            oneL = 0
            oneU = (c.sShort + c.sSync) / 2 + 1
            syncL = oneU - 1
            syncU = (c.sSync + c.sLong) / 2 + 1
            zeroL = syncU - 1
            zeroU = Int.MAX_VALUE
        } else {
            oneL = 0
            oneU = (c.sShort + c.sLong) / 2 + 1
            zeroL = oneU - 1
            zeroU = (c.sLong + c.sSync) / 2 + 1
            syncL = zeroU - 1
            syncU = Int.MAX_VALUE
        }
        for (n in 0 until np) {
            val pw = p.pulse[n]
            if (pw > oneL && pw < oneU) {
                bits.addBit(1)
            } else if (pw > zeroL && pw < zeroU) {
                bits.addBit(0)
            } else if (pw > syncL && pw < syncU) {
                bits.addSync()
            } else if (pw > oneL) {
                bits.addRow()
            }
            if ((n == np - 1 || p.gap[n] > c.sReset) && bits.numRows > 0) {
                out.add(bits)
                bits = BitBuffer()
            } else if (c.sGap > 0 && p.gap[n] > c.sGap && bits.numRows > 0 && bits.bitsPerRow[bits.numRows - 1] > 0) {
                bits.addRow()
            }
        }
        return out
    }

    fun pulseManchesterZerobit(p: PulseData, t: SliceParams): List<BitBuffer> {
        val c = SliceCtx(p, t)
        if (!c.ok) return emptyList()
        val out = ArrayList<BitBuffer>()
        var bits = BitBuffer()
        val np = p.numPulses
        var timeSinceLast = 0
        bits.addBit(0)
        for (n in 0 until np) {
            if (c.sTol > 0
                && (p.pulse[n] < c.sShort - c.sTol
                    || p.pulse[n] > c.sShort * 2 + c.sTol
                    || p.gap[n] < c.sShort - c.sTol
                    || p.gap[n] > c.sShort * 2 + c.sTol)
            ) {
                if (p.pulse[n] > c.sShort * 1.5 && p.pulse[n] <= c.sShort * 2 + c.sTol) {
                    bits.addBit(1)
                }
                bits.addRow()
                bits.addBit(0)
                timeSinceLast = 0
            } else if (p.pulse[n] + timeSinceLast > c.sShort * 1.5) {
                bits.addBit(1)
                timeSinceLast = 0
            } else {
                timeSinceLast += p.pulse[n]
            }
            if ((n == np - 1 || p.gap[n] > c.sReset) && bits.numRows > 0) {
                out.add(bits)
                bits = BitBuffer()
                bits.addBit(0)
                timeSinceLast = 0
            } else if (p.gap[n] + timeSinceLast > c.sShort * 1.5) {
                bits.addBit(0)
                timeSinceLast = 0
            } else {
                timeSinceLast += p.gap[n]
            }
        }
        return out
    }

    fun pulseDmc(p: PulseData, t: SliceParams): List<BitBuffer> {
        val c = SliceCtx(p, t)
        if (!c.ok) return emptyList()
        val out = ArrayList<BitBuffer>()
        var bits = BitBuffer()
        val total = p.numPulses * 2
        var n = 0
        while (n < total) {
            var symbol = sym(p, n)
            if (abs(symbol - c.sShort) < c.sTol) {
                bits.addBit(1)
                if (n + 1 < total) {
                    n++
                    symbol = sym(p, n)
                } else {
                    symbol = 0
                }
                if (abs(symbol - c.sShort) > c.sTol) {
                    if (symbol >= c.sReset - c.sTol) {
                        n--
                    } else if (bits.numRows > 0 && bits.bitsPerRow[bits.numRows - 1] > 0) {
                        bits.addRow()
                    }
                }
            } else if (abs(symbol - c.sLong) < c.sTol) {
                bits.addBit(0)
            } else if (symbol >= c.sReset - c.sTol && bits.numRows > 0) {
                out.add(bits)
                bits = BitBuffer()
            }
            n++
        }
        return out
    }

    fun pulsePiwmRaw(p: PulseData, t: SliceParams): List<BitBuffer> {
        val c = SliceCtx(p, t)
        if (!c.ok) return emptyList()
        val out = ArrayList<BitBuffer>()
        var bits = BitBuffer()
        val total = p.numPulses * 2
        val fShort = if (t.short > 0.0f) 1.0f / (t.short * c.spu) else 0f
        for (n in 0 until total) {
            val symbol = sym(p, n)
            var w = (symbol * fShort + 0.5).toInt()
            if (symbol > c.sLong) {
                bits.addRow()
            } else if (abs(symbol - w * c.sShort) < c.sTol) {
                while (w > 0) {
                    bits.addBit(1 - n % 2)
                    w--
                }
            } else if (symbol < c.sReset && bits.numRows > 0 && bits.bitsPerRow[bits.numRows - 1] > 0) {
                bits.addRow()
            }
            if ((n == total - 1 || symbol > c.sReset) && bits.numRows > 0) {
                out.add(bits)
                bits = BitBuffer()
            }
        }
        return out
    }

    fun pulsePiwmDc(p: PulseData, t: SliceParams): List<BitBuffer> {
        val c = SliceCtx(p, t)
        if (!c.ok) return emptyList()
        val out = ArrayList<BitBuffer>()
        var bits = BitBuffer()
        val total = p.numPulses * 2
        for (n in 0 until total) {
            val symbol = sym(p, n)
            if (abs(symbol - c.sShort) < c.sTol) {
                bits.addBit(1)
            } else if (abs(symbol - c.sLong) < c.sTol) {
                bits.addBit(0)
            } else if (symbol < c.sReset && bits.numRows > 0 && bits.bitsPerRow[bits.numRows - 1] > 0) {
                bits.addRow()
            }
            if ((n == total - 1 || symbol > c.sReset) && bits.numRows > 0) {
                out.add(bits)
                bits = BitBuffer()
            }
        }
        return out
    }

    fun pulseNrzs(p: PulseData, t: SliceParams): List<BitBuffer> {
        val c = SliceCtx(p, t)
        if (!c.ok) return emptyList()
        // unverified: guard against divide by zero where pulse_slicer.c would be undefined behavior
        if (c.sShort <= 0) return emptyList()
        val out = ArrayList<BitBuffer>()
        var bits = BitBuffer()
        val np = p.numPulses
        val limit = c.sShort
        for (n in 0 until np) {
            if (p.pulse[n] > limit) {
                repeat(p.pulse[n] / limit) { bits.addBit(1) }
                bits.addBit(0)
            } else if (p.pulse[n] < limit) {
                bits.addBit(0)
            }
            if (n == np - 1 || p.gap[n] >= c.sReset) {
                out.add(bits)
                bits = BitBuffer()
            }
        }
        return out
    }

    fun pulseOsv1(p: PulseData, t: SliceParams): List<BitBuffer> {
        val c = SliceCtx(p, t)
        if (!c.ok) return emptyList()
        val out = ArrayList<BitBuffer>()
        val bits = BitBuffer()
        val np = p.numPulses
        var preamble = 0
        var manbit = 0
        val halfbitMin = c.sShort / 2
        val halfbitMax = c.sShort * 3 / 2
        val syncMin = 2 * halfbitMax
        var n = 0
        while (n < np) {
            if (p.pulse[n] > halfbitMin && p.gap[n] > halfbitMin) {
                preamble++
                if (p.gap[n] > halfbitMax) break
            } else {
                return out
            }
            n++
        }
        if (preamble != 12) return out
        n++
        // unverified: bounds guard where pulse_slicer.c reads past the last pulse (zeroed storage)
        if (n >= np) return out
        if (p.pulse[n] < syncMin || p.gap[n] < syncMin) return out
        if (p.gap[n] > p.pulse[n]) {
            manbit = manbit xor 1
            if (manbit != 0) bits.addBit(0)
        }
        n++
        while (n < np) {
            manbit = manbit xor 1
            if (manbit != 0) bits.addBit(1)
            if (p.pulse[n] > halfbitMax) {
                manbit = manbit xor 1
                if (manbit != 0) bits.addBit(1)
            }
            if ((n == np - 1 || p.gap[n] > c.sReset) && bits.numRows > 0) {
                out.add(bits)
                return out
            }
            manbit = manbit xor 1
            if (manbit != 0) bits.addBit(0)
            if (p.gap[n] > halfbitMax) {
                manbit = manbit xor 1
                if (manbit != 0) bits.addBit(0)
            }
            n++
        }
        return out
    }

    fun pulseRzi(p: PulseData, t: SliceParams): List<BitBuffer> {
        val spu = p.sampleRate / 1.0e6f
        val sShort = (t.short * spu).toInt()
        val sLong = (t.long * spu).toInt()
        val sReset = (t.reset * spu).toInt()
        if ((t.short > 0 && sShort <= 0) || (t.long > 0 && sLong <= 0) || (t.reset > 0 && sReset <= 0)) return emptyList()
        // unverified: guard against divide by zero where pulse_slicer.c would be undefined behavior
        if (sLong <= 0) return emptyList()
        val sBase = sLong - sShort
        val out = ArrayList<BitBuffer>()
        var bits = BitBuffer()
        val np = p.numPulses
        var atStart = true
        for (n in 0 until np) {
            val high = p.pulse[n]
            var ones = if (atStart) (high + sLong / 2) / sLong else (high - sBase + sLong / 2) / sLong
            atStart = false
            if (ones < 0) ones = 0
            repeat(ones) { bits.addBit(1) }
            if (p.gap[n] > sReset || n == np - 1) {
                if (bits.bitsPerRow[0] > 0) out.add(bits)
                bits = BitBuffer()
                atStart = true
                continue
            }
            bits.addBit(0)
        }
        return out
    }
}

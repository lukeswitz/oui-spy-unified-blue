// Kotlin reimplementation of rtl_433 pulse detection (pulse_data.h, pulse_detect.c, pulse_detect_fsk.c, baseband.c; GPL-3 reference, algorithm transcribed as facts).
package com.rootdowndigital.ouispy.wifiadapter

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.tan

const val PD_MAX_PULSES = 1200
const val PD_MIN_PULSES = 16
const val PD_MIN_PULSE_SAMPLES = 10
const val PD_MIN_GAP_MS = 10
const val PD_MAX_GAP_MS = 100
const val PD_MAX_GAP_RATIO = 10
const val PULSE_DATA_OOK = 1
const val PULSE_DATA_FSK = 2
const val FSK_PULSE_DETECT_OLD = 0
const val FSK_PULSE_DETECT_NEW = 1
const val FSK_PULSE_DETECT_AUTO = 2
const val FSK_PULSE_DETECTOR_LIMIT = 800_000_000L

private const val OOK_MAX_HIGH_LEVEL = 16383
private const val OOK_EST_HIGH_RATIO = 64
private const val OOK_EST_LOW_RATIO = 1024
private const val OOK_MIN_HIGH_LEVEL = 1000
private const val OOK_HIGH_LOW_RATIO = 8
private const val FSK_DEFAULT_FM_DELTA = 6000
private const val FSK_EST_SLOW = 64
private const val FSK_EST_FAST = 16

class PulseData {
    var sampleRate = 0
    var numPulses = 0
    val pulse = IntArray(PD_MAX_PULSES)
    val gap = IntArray(PD_MAX_PULSES)
    var ookLowEstimate = 0
    var ookHighEstimate = 0
    var fskF1Est = 0
    var fskF2Est = 0

    fun clear() {
        sampleRate = 0
        numPulses = 0
        pulse.fill(0)
        gap.fill(0)
        ookLowEstimate = 0
        ookHighEstimate = 0
        fskF1Est = 0
        fskF2Est = 0
    }

    fun shift() {
        val offs = PD_MAX_PULSES / 2
        System.arraycopy(pulse, offs, pulse, 0, PD_MAX_PULSES - offs)
        System.arraycopy(gap, offs, gap, 0, PD_MAX_PULSES - offs)
        numPulses -= offs
    }

    fun copy(): PulseData {
        val c = PulseData()
        c.sampleRate = sampleRate
        c.numPulses = numPulses
        System.arraycopy(pulse, 0, c.pulse, 0, PD_MAX_PULSES)
        System.arraycopy(gap, 0, c.gap, 0, PD_MAX_PULSES)
        c.ookLowEstimate = ookLowEstimate
        c.ookHighEstimate = ookHighEstimate
        c.fskF1Est = fskF1Est
        c.fskF2Est = fskF2Est
        return c
    }
}

class PulsePackage(val type: Int, val data: PulseData)

private fun toI16(v: Int): Int = v.toShort().toInt()

object Baseband {
    fun envelopeDetectNolut(iq: ByteArray, y: IntArray, len: Int) {
        for (i in 0 until len) {
            val x = 127 - (iq[2 * i].toInt() and 0xFF)
            val q = 127 - (iq[2 * i + 1].toInt() and 0xFF)
            y[i] = (x * x + q * q) and 0xFFFF
        }
    }

    private const val F_SCALE = 15
    private const val S_CONST = 1 shl F_SCALE
    private val lpA1 = (0.85408 * S_CONST).toInt() shr 1
    private val lpB0 = (0.07296 * S_CONST).toInt() shr 1

    class LowPassState {
        var x0 = 0
        var y0 = 0
    }

    fun lowPassFilter(state: LowPassState, x: IntArray, y: IntArray, len: Int) {
        if (len < 1) return
        y[0] = toI16((lpA1 * state.y0 + lpB0 * (x[0] + state.x0)) shr (F_SCALE - 1))
        for (i in 1 until len) {
            y[i] = toI16((lpA1 * y[i - 1] + lpB0 * (x[i] + x[i - 1])) shr (F_SCALE - 1))
        }
        state.x0 = toI16(x[len - 1])
        state.y0 = y[len - 1]
    }

    private fun atan2Int16(y: Int, x: Int): Int {
        val iPi4 = Short.MAX_VALUE / 4
        val i3Pi4 = 3 * Short.MAX_VALUE / 4
        val absY = abs(y)
        if (x == 0 && y == 0) return 0
        var angle: Int
        if (x >= 0) {
            var denom = absY + x
            if (denom == 0) denom = 1
            angle = iPi4 - iPi4 * (x - absY) / denom
        } else {
            var denom = absY - x
            if (denom == 0) denom = 1
            angle = i3Pi4 - iPi4 * (x + absY) / denom
        }
        if (y < 0) angle = -angle
        return toI16(angle)
    }

    class FmState {
        var xr = 0
        var xi = 0
        var xf = 0
        var yf = 0
        var rate = 0
        var alp1 = 0
        var blp0 = 0
        var blp1 = 0
    }

    fun demodFm(state: FmState, iq: ByteArray, y: IntArray, numSamples: Int, sampRate: Int, lowPassIn: Float) {
        if (state.rate != sampRate) {
            var lowPass = lowPassIn
            if (lowPass > 1e4f) {
                lowPass /= sampRate
            } else if (lowPass >= 1.0f) {
                lowPass = 1e6f / lowPass / sampRate
            }
            val ita = 1.0 / tan(PI / 2 * lowPass.toDouble())
            val gain = 1.0 / (1.0 + ita) / 2
            state.alp1 = ((ita - 1.0) * gain * S_CONST).toInt()
            state.blp0 = (gain * S_CONST).toInt()
            state.blp1 = (gain * S_CONST).toInt()
            state.rate = sampRate
        }
        var x0r = state.xr
        var x0i = state.xi
        var x0f = state.xf
        var y0f = state.yf
        for (n in 0 until numSamples) {
            val x1r = x0r
            val x1i = x0i
            val y1f = y0f
            val x1f = x0f
            x0r = (iq[2 * n].toInt() and 0xFF) - 128
            x0i = (iq[2 * n + 1].toInt() and 0xFF) - 128
            val pr = x0r * x1r + x0i * x1i
            val pi = x0i * x1r - x0r * x1i
            x0f = atan2Int16(pi, pr)
            y0f = toI16((state.alp1 * y1f + state.blp0 * (x0f + x1f)) shr (F_SCALE - 1))
            y[n] = y0f
        }
        state.xr = x0r
        state.xi = x0i
        state.xf = x0f
        state.yf = y0f
    }
}

private const val FSK_INIT = 0
private const val FSK_FH = 1
private const val FSK_FL = 2
private const val FSK_ERROR = 3

private class FskState {
    var fskPulseLength = 0
    var fskState = FSK_INIT
    var fmF1Est = 0
    var fmF2Est = 0
    var varTestMax = Short.MIN_VALUE.toInt()
    var varTestMin = Short.MAX_VALUE.toInt()
    var skipSamples = 40

    fun classic(fmN: Int, fsk: PulseData) {
        val f1Delta = abs(fmN - fmF1Est)
        val f2Delta = abs(fmN - fmF2Est)
        fskPulseLength += 1
        when (fskState) {
            FSK_INIT -> {
                if (fskPulseLength < PD_MIN_PULSE_SAMPLES) {
                    fmF1Est = fmF1Est / 2 + fmN / 2
                } else if (f1Delta > FSK_DEFAULT_FM_DELTA / 2) {
                    if (fmN > fmF1Est) {
                        fskState = FSK_FH
                        fmF2Est = fmF1Est
                        fmF1Est = fmN
                        fsk.pulse[0] = 0
                        fsk.gap[0] = fskPulseLength
                        fsk.numPulses += 1
                        fskPulseLength = 0
                    } else {
                        fskState = FSK_FL
                        fmF2Est = fmN
                        fsk.pulse[0] = fskPulseLength
                        fskPulseLength = 0
                    }
                } else {
                    fmF1Est += fmN / FSK_EST_FAST - fmF1Est / FSK_EST_FAST
                }
            }
            FSK_FH -> {
                if (f1Delta > f2Delta) {
                    fskState = FSK_FL
                    if (fskPulseLength >= PD_MIN_PULSE_SAMPLES) {
                        fsk.pulse[fsk.numPulses] = fskPulseLength
                        fskPulseLength = 0
                    } else {
                        fskPulseLength += fsk.gap[fsk.numPulses - 1]
                        fsk.numPulses -= 1
                        if (fsk.numPulses == 0 && fsk.pulse[0] == 0) {
                            fmF1Est = fmF2Est
                            fskState = FSK_INIT
                        }
                    }
                } else {
                    if (fmN > fmF1Est) {
                        fmF1Est += fmN / FSK_EST_FAST - fmF1Est / FSK_EST_FAST
                    } else {
                        fmF1Est += fmN / FSK_EST_SLOW - fmF1Est / FSK_EST_SLOW
                    }
                }
            }
            FSK_FL -> {
                if (f2Delta > f1Delta) {
                    fskState = FSK_FH
                    if (fskPulseLength >= PD_MIN_PULSE_SAMPLES) {
                        fsk.gap[fsk.numPulses] = fskPulseLength
                        fsk.numPulses += 1
                        fskPulseLength = 0
                        if (fsk.numPulses >= PD_MAX_PULSES) fsk.shift()
                    } else {
                        fskPulseLength += fsk.pulse[fsk.numPulses]
                        if (fsk.numPulses == 0) fskState = FSK_INIT
                    }
                } else {
                    if (fmN < fmF2Est) {
                        fmF2Est += fmN / FSK_EST_FAST - fmF2Est / FSK_EST_FAST
                    } else {
                        fmF2Est += fmN / FSK_EST_SLOW - fmF2Est / FSK_EST_SLOW
                    }
                }
            }
            FSK_ERROR -> {}
            else -> fskState = FSK_ERROR
        }
    }

    fun wrapUp(fsk: PulseData) {
        if (fsk.numPulses < PD_MAX_PULSES) {
            fskPulseLength += 1
            if (fskState == FSK_FH) {
                fsk.pulse[fsk.numPulses] = fskPulseLength
                fsk.gap[fsk.numPulses] = 0
            } else {
                fsk.gap[fsk.numPulses] = fskPulseLength
            }
            fsk.numPulses += 1
        }
    }

    fun minmax(fmN: Int, fsk: PulseData) {
        var mid = 0
        if (skipSamples == 0) {
            varTestMax = maxOf(fmN, varTestMax)
            varTestMin = minOf(fmN, varTestMin)
            mid = (varTestMax + varTestMin) / 2
            if (fmN > mid) varTestMax -= 10
            if (fmN < mid) varTestMin += 10
            fskPulseLength += 1
            when (fskState) {
                FSK_INIT -> {
                    if (fmN > mid) fskState = FSK_FH
                    if (fmN <= mid) fskState = FSK_FL
                }
                FSK_FH -> {
                    if (fmN < mid) {
                        fskState = FSK_FL
                        fsk.pulse[fsk.numPulses] = fskPulseLength
                        fskPulseLength = 0
                    }
                    fmF2Est += fmN / FSK_EST_SLOW - fmF2Est / FSK_EST_SLOW
                }
                FSK_FL -> {
                    if (fmN > mid) {
                        fskState = FSK_FH
                        fsk.gap[fsk.numPulses] = fskPulseLength
                        fsk.numPulses += 1
                        fskPulseLength = 0
                        if (fsk.numPulses >= PD_MAX_PULSES) fsk.shift()
                    }
                    fmF1Est += fmN / FSK_EST_SLOW - fmF1Est / FSK_EST_SLOW
                }
                FSK_ERROR -> {}
                else -> fskState = FSK_ERROR
            }
        }
        if (skipSamples > 0) skipSamples -= 1
    }
}

private const val OOK_IDLE = 0
private const val OOK_PULSE = 1
private const val OOK_GAP_START = 2
private const val OOK_GAP = 3

class PulseDetector {
    private var ookState = OOK_IDLE
    private var pulseLength = 0
    private var maxPulse = 0
    private var dataCounter = 0
    private var leadInCounter = 0
    private var ookLowEstimate = 0
    private var ookHighEstimate = 0
    private var fsk = FskState()
    private val pulses = PulseData()
    private val fskPulses = PulseData()

    fun reset() {
        ookState = OOK_IDLE
        pulseLength = 0
        maxPulse = 0
        dataCounter = 0
        leadInCounter = 0
        ookLowEstimate = 0
        ookHighEstimate = 0
        fsk = FskState()
    }

    private fun fskStep(fm: Int, fpdm: Int) {
        if (pulses.numPulses == 0) {
            if (fpdm == FSK_PULSE_DETECT_OLD) fsk.classic(fm, fskPulses) else fsk.minmax(fm, fskPulses)
        }
    }

    private fun fskPackage(fpdm: Int): PulsePackage {
        if (fpdm == FSK_PULSE_DETECT_OLD) fsk.wrapUp(fskPulses)
        fskPulses.fskF1Est = fsk.fmF1Est
        fskPulses.fskF2Est = fsk.fmF2Est
        fskPulses.ookLowEstimate = ookLowEstimate
        fskPulses.ookHighEstimate = ookHighEstimate
        ookState = OOK_IDLE
        return PulsePackage(PULSE_DATA_FSK, fskPulses.copy())
    }

    private fun ookPackage(): PulsePackage {
        pulses.ookLowEstimate = ookLowEstimate
        pulses.ookHighEstimate = ookHighEstimate
        return PulsePackage(PULSE_DATA_OOK, pulses.copy())
    }

    fun flush(fpdm: Int): PulsePackage? {
        var gapStart = true
        when (ookState) {
            OOK_IDLE -> return null
            OOK_PULSE -> {
                if (pulseLength < PD_MIN_PULSE_SAMPLES) {
                    if (pulses.numPulses <= 1) {
                        ookState = OOK_IDLE
                        return null
                    }
                    ookState = OOK_GAP
                } else {
                    pulses.pulse[pulses.numPulses] = pulseLength
                    maxPulse = maxOf(pulseLength, maxPulse)
                    pulseLength = 0
                    ookState = OOK_GAP_START
                }
            }
            OOK_GAP_START -> {}
            OOK_GAP -> gapStart = false
            else -> {
                ookState = OOK_IDLE
                return null
            }
        }
        if (gapStart) {
            ookState = OOK_GAP
            if (fskPulses.numPulses > PD_MIN_PULSES) return fskPackage(fpdm)
        }
        pulses.gap[pulses.numPulses] = pulseLength
        pulses.numPulses += 1
        ookState = OOK_IDLE
        return ookPackage()
    }

    fun detectPackage(am: IntArray, fm: IntArray, len: Int, sampRate: Int, fpdm: Int): PulsePackage? {
        val samplesPerMs = sampRate / 1000
        ookHighEstimate = maxOf(ookHighEstimate, OOK_MIN_HIGH_LEVEL)
        var eopOnSpurious = false
        while (dataCounter < len) {
            val amN = am[dataCounter]
            val ookThreshold = toI16((ookLowEstimate + minOf(ookHighEstimate, OOK_MAX_HIGH_LEVEL)) / 2)
            val ookHysteresis = toI16(ookThreshold / 8)
            when (ookState) {
                OOK_IDLE -> {
                    if (amN > ookThreshold + ookHysteresis && leadInCounter > OOK_EST_LOW_RATIO) {
                        pulses.clear()
                        fskPulses.clear()
                        pulses.sampleRate = sampRate
                        fskPulses.sampleRate = sampRate
                        pulseLength = 0
                        maxPulse = 0
                        fsk = FskState()
                        ookState = OOK_PULSE
                    } else {
                        val delta = amN - ookLowEstimate
                        ookLowEstimate += delta / OOK_EST_LOW_RATIO
                        ookLowEstimate += if (delta > 0) 1 else -1
                        ookHighEstimate = OOK_HIGH_LOW_RATIO * ookLowEstimate
                        ookHighEstimate = maxOf(ookHighEstimate, OOK_MIN_HIGH_LEVEL)
                        if (leadInCounter <= OOK_EST_LOW_RATIO) leadInCounter += 1
                    }
                }
                OOK_PULSE -> {
                    pulseLength += 1
                    if (amN < ookThreshold - ookHysteresis) {
                        if (pulseLength < PD_MIN_PULSE_SAMPLES) {
                            if (pulses.numPulses <= 1) {
                                ookState = OOK_IDLE
                            } else {
                                eopOnSpurious = true
                                ookState = OOK_GAP
                            }
                        } else {
                            pulses.pulse[pulses.numPulses] = pulseLength
                            maxPulse = maxOf(pulseLength, maxPulse)
                            pulseLength = 0
                            ookState = OOK_GAP_START
                        }
                    } else {
                        ookHighEstimate += amN / OOK_EST_HIGH_RATIO - ookHighEstimate / OOK_EST_HIGH_RATIO
                        ookHighEstimate = maxOf(ookHighEstimate, OOK_MIN_HIGH_LEVEL)
                        pulses.fskF1Est += fm[dataCounter] / OOK_EST_HIGH_RATIO - pulses.fskF1Est / OOK_EST_HIGH_RATIO
                    }
                    fskStep(fm[dataCounter], fpdm)
                }
                OOK_GAP_START -> {
                    pulseLength += 1
                    if (amN > ookThreshold + ookHysteresis) {
                        pulseLength += pulses.pulse[pulses.numPulses]
                        ookState = OOK_PULSE
                    } else if (pulseLength >= PD_MIN_PULSE_SAMPLES) {
                        ookState = OOK_GAP
                        if (fskPulses.numPulses > PD_MIN_PULSES) return fskPackage(fpdm)
                    }
                    fskStep(fm[dataCounter], fpdm)
                }
                OOK_GAP -> {
                    pulseLength += 1
                    if (amN > ookThreshold + ookHysteresis) {
                        pulses.gap[pulses.numPulses] = pulseLength
                        pulses.numPulses += 1
                        if (pulses.numPulses >= PD_MAX_PULSES) {
                            ookState = OOK_IDLE
                            return ookPackage()
                        }
                        pulseLength = 0
                        ookState = OOK_PULSE
                    }
                    if (eopOnSpurious
                        || (pulseLength > PD_MAX_GAP_RATIO * maxPulse && pulseLength > PD_MIN_GAP_MS * samplesPerMs)
                        || pulseLength > PD_MAX_GAP_MS * samplesPerMs
                    ) {
                        pulses.gap[pulses.numPulses] = pulseLength
                        pulses.numPulses += 1
                        ookState = OOK_IDLE
                        return ookPackage()
                    }
                }
            }
            dataCounter += 1
        }
        dataCounter = 0
        return null
    }
}

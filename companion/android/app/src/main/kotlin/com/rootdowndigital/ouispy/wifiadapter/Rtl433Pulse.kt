// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

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

const val PULSE_DETECT_END = 0
const val PULSE_DETECT_OOK = 1
const val PULSE_DETECT_START = 2
const val PULSE_DETECT_PULSE = 3
const val PULSE_DETECT_RESTART = 4
const val PULSE_DETECT_RETRY = 5

const val FSK_PULSE_DETECTOR_CLASSIC = 0
const val FSK_PULSE_DETECTOR_MINMAX = 1
const val FSK_PULSE_DETECTOR_HYSTERESIS = 2
const val FSK_PULSE_DETECTOR_MEDIAN = 3
const val FSK_PULSE_DETECTOR_COUNT = 4

private const val OOK_MAX_HIGH_LEVEL = 16383
private const val OOK_EST_HIGH_RATIO = 64
private const val OOK_EST_LOW_RATIO = 1024
private const val OOK_MIN_HIGH_LEVEL = 1000
private const val OOK_HIGH_LOW_RATIO = 8
private const val PD_FSK_MAX_LEADIN_US = 200
private const val PD_FSK_MIN_LEADIN_GAP_US = 200
private const val FSK_DEFAULT_FM_DELTA = 6000
private const val FSK_EST_SLOW = 64
private const val FSK_EST_FAST = 16
private const val FSK_MINMAX_DECAY = 10
private const val FSK_MINMAX_HYSTERESIS_DIVISOR = 3
private const val FSK_MIN_RESTART_BURST_US = 7500

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

class PulseSpan {
    var start = 0
    var len = 0
}

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

class FskState {
    private var fskPulseLength = 0
    private var fskState = FSK_INIT
    private var fmF1Est = 0
    private var fmF2Est = 0
    private var varTestMax = Short.MIN_VALUE.toInt()
    private var varTestMin = Short.MAX_VALUE.toInt()
    private var skipSamples = 40
    private var restarted = false
    private var firstPulse = 0
    private val medianSamples = IntArray(3)
    private var medianCount = 0

    fun init() {
        fskPulseLength = 0
        fskState = FSK_INIT
        fmF1Est = 0
        fmF2Est = 0
        varTestMax = Short.MIN_VALUE.toInt()
        varTestMin = Short.MAX_VALUE.toInt()
        skipSamples = 40
        restarted = false
        firstPulse = 0
        medianSamples.fill(0)
        medianCount = 0
    }

    fun pkg(fm: IntArray, span: PulseSpan, event: Int, pulses: PulseData, fsk: PulseData, detector: Int): Boolean {
        if (event == PULSE_DETECT_START || event == PULSE_DETECT_RESTART || event == PULSE_DETECT_RETRY) {
            val first = if (event == PULSE_DETECT_START) 0 else pulses.numPulses
            init()
            restarted = event == PULSE_DETECT_RESTART
            firstPulse = first
            fsk.clear()
            fsk.sampleRate = pulses.sampleRate
            return false
        }
        if (span.len > 0) {
            when (detector) {
                FSK_PULSE_DETECTOR_CLASSIC -> classic(fm, span.start, span.len, fsk)
                FSK_PULSE_DETECTOR_MINMAX -> minmax(fm, span.start, span.len, fsk, false, FSK_MINMAX_DECAY, false)
                FSK_PULSE_DETECTOR_HYSTERESIS -> minmax(fm, span.start, span.len, fsk, true, FSK_MINMAX_DECAY, false)
                FSK_PULSE_DETECTOR_MEDIAN -> minmax(fm, span.start, span.len, fsk, false, 0, true)
            }
        }
        if (event != PULSE_DETECT_PULSE || fsk.numPulses <= PD_MIN_PULSES) return false
        if (restarted && pulses.pulse[firstPulse] < FSK_MIN_RESTART_BURST_US * (pulses.sampleRate / 1000) / 1000) return false
        return true
    }

    fun finalize(pulses: PulseData, fsk: PulseData, detector: Int) {
        if (detector == FSK_PULSE_DETECTOR_CLASSIC) wrapUp(fsk) else minmaxWrapUp(fsk)
        fsk.fskF1Est = fmF1Est
        fsk.fskF2Est = fmF2Est
        fsk.ookLowEstimate = pulses.ookLowEstimate
        fsk.ookHighEstimate = pulses.ookHighEstimate
    }

    private fun classic(fm: IntArray, start: Int, len: Int, fsk: PulseData) {
        for (i in start until start + len) {
            val fmN = fm[i]
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
    }

    private fun wrapUp(fsk: PulseData) {
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

    private fun minmaxWrapUp(fsk: PulseData) {
        if (fskState == FSK_FH && fskPulseLength + 1 < PD_MIN_PULSE_SAMPLES) return
        wrapUp(fsk)
    }

    private fun median3(sample: Int): Int {
        if (medianCount < 3) {
            medianSamples[medianCount++] = sample
            return sample
        }
        medianSamples[0] = medianSamples[1]
        medianSamples[1] = medianSamples[2]
        medianSamples[2] = sample
        val a = medianSamples[0]
        val b = medianSamples[1]
        val c = medianSamples[2]
        return a + b + c - minOf(a, b, c) - maxOf(a, b, c)
    }

    private fun minmax(fm: IntArray, start: Int, len: Int, fsk: PulseData, useHysteresis: Boolean, decay: Int, useMedian: Boolean) {
        for (i in start until start + len) {
            var fmN = fm[i]
            if (useMedian) fmN = median3(fmN)
            if (skipSamples == 0) {
                varTestMax = maxOf(fmN, varTestMax)
                varTestMin = minOf(fmN, varTestMin)
                val mid = toI16((varTestMax + varTestMin) / 2)
                if (fmN > mid) varTestMax = toI16(varTestMax - decay)
                if (fmN < mid) varTestMin = toI16(varTestMin + decay)
                val span = varTestMax - varTestMin
                val hyst = if (useHysteresis && span > 0) span / FSK_MINMAX_HYSTERESIS_DIVISOR else 0
                fskPulseLength += 1
                when (fskState) {
                    FSK_INIT -> {
                        if (fmN > mid) fskState = FSK_FH
                        if (fmN <= mid) fskState = FSK_FL
                    }
                    FSK_FH -> {
                        if (fmN < mid - hyst) {
                            fskState = FSK_FL
                            fsk.pulse[fsk.numPulses] = fskPulseLength
                            fskPulseLength = 0
                        }
                        fmF2Est += fmN / FSK_EST_SLOW - fmF2Est / FSK_EST_SLOW
                    }
                    FSK_FL -> {
                        if (fmN > mid + hyst) {
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
}

private const val OOK_IDLE = 0
private const val OOK_PULSE = 1
private const val OOK_GAP_START = 2
private const val OOK_GAP = 3

class PulseDetector {
    private var ookState = OOK_IDLE
    private var pulseLength = 0
    private var maxPulse = 0
    private var fskPulseNum = 0
    private var fskRetry = 0
    private var dataCounter = 0
    private var leadInCounter = 0
    private var ookLowEstimate = 0
    private var ookHighEstimate = 0
    private var eopOnSpurious = false
    private var pendingGap = false

    fun reset() {
        ookState = OOK_IDLE
        pulseLength = 0
        maxPulse = 0
        dataCounter = 0
        leadInCounter = 0
        ookLowEstimate = 0
        ookHighEstimate = 0
        pendingGap = false
        fskPulseNum = 0
        fskRetry = 0
        eopOnSpurious = false
    }

    fun retryFsk() {
        if (fskRetry == 0) fskRetry = 1
    }

    fun skipPackage() {
        ookState = OOK_IDLE
        pendingGap = false
        eopOnSpurious = false
        fskRetry = 0
    }

    private fun endPackage(pulses: PulseData): Int {
        ookState = OOK_IDLE
        eopOnSpurious = false
        fskRetry = 0
        pulses.ookLowEstimate = ookLowEstimate
        pulses.ookHighEstimate = ookHighEstimate
        return PULSE_DETECT_OOK
    }

    private fun fskStep(pulses: PulseData, span: PulseSpan) {
        if (pulses.numPulses == fskPulseNum) {
            if (span.len == 0) span.start = dataCounter
            span.len += 1
        }
    }

    fun detectPackage(am: IntArray, fm: IntArray, len: Int, sampRate: Int, pulses: PulseData, span: PulseSpan): Int {
        span.start = dataCounter
        span.len = 0
        if (pendingGap) {
            if (pulses.numPulses == fskPulseNum) span.len = 1
            dataCounter += 1
            pendingGap = false
        }
        if (len == 0) {
            var state = ookState
            if (state == OOK_PULSE) {
                if (pulseLength < PD_MIN_PULSE_SAMPLES) {
                    if (pulses.numPulses <= 1) ookState = OOK_IDLE
                    state = if (pulses.numPulses <= 1) OOK_IDLE else OOK_GAP_START
                } else {
                    pulses.pulse[pulses.numPulses] = pulseLength
                    maxPulse = maxOf(pulseLength, maxPulse)
                    pulseLength = 0
                    state = OOK_GAP_START
                }
            }
            when (state) {
                OOK_GAP_START -> {
                    ookState = OOK_GAP
                    pulses.ookLowEstimate = ookLowEstimate
                    pulses.ookHighEstimate = ookHighEstimate
                    return PULSE_DETECT_PULSE
                }
                OOK_GAP -> {
                    pulses.gap[pulses.numPulses] = pulseLength
                    pulses.numPulses += 1
                    ookState = OOK_IDLE
                    pulses.ookLowEstimate = ookLowEstimate
                    pulses.ookHighEstimate = ookHighEstimate
                    return PULSE_DETECT_OOK
                }
            }
        }
        val samplesPerMs = sampRate / 1000
        ookHighEstimate = maxOf(ookHighEstimate, OOK_MIN_HIGH_LEVEL)
        while (dataCounter < len) {
            val amN = am[dataCounter]
            val ookThreshold = toI16((ookLowEstimate + minOf(ookHighEstimate, OOK_MAX_HIGH_LEVEL)) / 2)
            val ookHysteresis = toI16(ookThreshold / 8)
            when (ookState) {
                OOK_IDLE -> {
                    if (amN > ookThreshold + ookHysteresis && leadInCounter > OOK_EST_LOW_RATIO) {
                        pulses.clear()
                        pulses.sampleRate = sampRate
                        pulseLength = 0
                        maxPulse = 0
                        eopOnSpurious = false
                        fskPulseNum = 0
                        fskRetry = 0
                        ookState = OOK_PULSE
                        dataCounter += 1
                        span.len = 0
                        return PULSE_DETECT_START
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
                    fskStep(pulses, span)
                }
                OOK_GAP_START -> {
                    pulseLength += 1
                    if (amN > ookThreshold + ookHysteresis) {
                        pulseLength += pulses.pulse[pulses.numPulses]
                        ookState = OOK_PULSE
                    } else if (pulseLength >= PD_MIN_PULSE_SAMPLES) {
                        ookState = OOK_GAP
                        pulses.ookLowEstimate = ookLowEstimate
                        pulses.ookHighEstimate = ookHighEstimate
                        pendingGap = true
                        return PULSE_DETECT_PULSE
                    }
                    fskStep(pulses, span)
                }
                OOK_GAP -> {
                    pulseLength += 1
                    if (amN > ookThreshold + ookHysteresis) {
                        pulses.gap[pulses.numPulses] = pulseLength
                        pulses.numPulses += 1
                        if (pulses.numPulses >= PD_MAX_PULSES) return endPackage(pulses)
                        pulseLength = 0
                        ookState = OOK_PULSE
                        if (pulses.numPulses == 1
                            && pulses.pulse[0] < PD_FSK_MAX_LEADIN_US * samplesPerMs / 1000
                            && pulses.gap[0] >= PD_FSK_MIN_LEADIN_GAP_US * samplesPerMs / 1000
                        ) {
                            fskPulseNum = 1
                            dataCounter += 1
                            span.len = 0
                            return PULSE_DETECT_RESTART
                        }
                        if (fskRetry == 1) {
                            fskRetry = 2
                            fskPulseNum = pulses.numPulses
                            dataCounter += 1
                            span.len = 0
                            return PULSE_DETECT_RETRY
                        }
                    }
                    if (eopOnSpurious
                        || (pulseLength > PD_MAX_GAP_RATIO * maxPulse && pulseLength > PD_MIN_GAP_MS * samplesPerMs)
                        || pulseLength > PD_MAX_GAP_MS * samplesPerMs
                    ) {
                        pulses.gap[pulses.numPulses] = pulseLength
                        pulses.numPulses += 1
                        return endPackage(pulses)
                    }
                }
            }
            dataCounter += 1
        }
        dataCounter = 0
        return PULSE_DETECT_END
    }
}

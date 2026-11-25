// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

// Kotlin reimplementation of rtl_433's device row and dispatch (include/r_device.h, src/r_api.c run_ook_demods/run_fsk_demods, src/r_flow.c; GPL-3 reference, algorithm transcribed as facts).
package com.rootdowndigital.ouispy.wifiadapter

import kotlin.math.log10
import kotlin.math.max

data class Reading(val model: String, val id: String?, val fields: Map<String, Any?>) {
    val key: String get() = "$model::${id ?: ""}"
}

enum class Mod(val fsk: Boolean) {
    OOK_PWM(false),
    OOK_PPM(false),
    OOK_PCM(false),
    OOK_MC_ZEROBIT(false),
    OOK_DMC(false),
    OOK_NRZS(false),
    OOK_PIWM_RAW(false),
    OOK_PIWM_DC(false),
    OOK_PWM_OSV1(false),
    OOK_RZI(false),
    FSK_PCM(true),
    FSK_PWM(true),
    FSK_MC_ZEROBIT(true),
}

abstract class Rtl433Decoder {
    abstract val name: String
    abstract val mod: Mod
    open val short: Int get() = 0
    open val long: Int get() = 0
    open val reset: Int get() = 0
    open val gap: Int get() = 0
    open val sync: Int get() = 0
    open val tolerance: Int get() = 0
    open val priority: Int get() = 0

    abstract fun decode(bb: BitBuffer): List<Reading>

    fun sliceParams(): SliceParams =
        SliceParams(short.toFloat(), long.toFloat(), reset.toFloat(), gap.toFloat(), sync.toFloat(), tolerance.toFloat())
}

class GenericRemoteDecoder : Rtl433Decoder() {
    override val name = "Generic Remote SC226x EV1527"
    override val mod = Mod.OOK_PWM
    override val short = 464
    override val long = 1404
    override val reset = 1800
    override val sync = 0
    override val tolerance = 200

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows == 0) return emptyList()
        val b = bb.bb[0]
        b[0] = b[0].inv() and 0xFF
        b[1] = b[1].inv() and 0xFF
        b[2] = b[2].inv() and 0xFF
        val bits = bb.bitsPerRow[0]
        if (bits != 25 || (b[3] and 0x80) == 0 || (b[0] == 0 && b[1] == 0) || b[2] == 0) return emptyList()
        val id16 = (b[0] shl 8) or b[1]
        val cmd8 = b[2]
        val full = (b[0] shl 16) or (b[1] shl 8) or b[2]
        val sb = StringBuilder()
        var i = 22
        while (i >= 0) {
            sb.append(
                when ((full shr i) and 0x03) {
                    0x00 -> '0'
                    0x01 -> 'Z'
                    0x02 -> 'X'
                    else -> '1'
                }
            )
            i -= 2
        }
        return listOf(
            Reading(
                "Generic-Remote", id16.toString(),
                mapOf("id" to id16, "cmd" to cmd8, "tristate" to sb.toString()),
            )
        )
    }
}

object Rtl433Registry {
    val decoders = mutableListOf<Rtl433Decoder>()

    var onPackage: ((Int, Int, Int) -> Unit)? = null

    private val lowPass = Baseband.LowPassState()
    private val fmState = Baseband.FmState()
    private val detector = PulseDetector()
    private val pulses = PulseData()
    private val span = PulseSpan()
    private val fskStates = Array(FSK_PULSE_DETECTOR_COUNT) { FskState() }
    private val fskPulses = Array(FSK_PULSE_DETECTOR_COUNT) { PulseData() }
    private var fskRejected = false
    private var fskReady = 0

    fun reset() {
        lowPass.x0 = 0
        lowPass.y0 = 0
        fmState.xr = 0
        fmState.xi = 0
        fmState.xf = 0
        fmState.yf = 0
        fmState.rate = 0
        detector.reset()
        pulses.clear()
        for (s in fskStates) s.init()
        for (p in fskPulses) p.clear()
        fskRejected = false
        fskReady = 0
    }

    private fun slice(d: Rtl433Decoder, p: PulseData): List<BitBuffer> {
        val t = d.sliceParams()
        return when (d.mod) {
            Mod.OOK_PWM, Mod.FSK_PWM -> Slicer.pulsePwm(p, t)
            Mod.OOK_PPM -> Slicer.pulsePpm(p, t)
            Mod.OOK_PCM, Mod.FSK_PCM -> Slicer.pulsePcm(p, t)
            Mod.OOK_MC_ZEROBIT, Mod.FSK_MC_ZEROBIT -> Slicer.pulseManchesterZerobit(p, t)
            Mod.OOK_DMC -> Slicer.pulseDmc(p, t)
            Mod.OOK_NRZS -> Slicer.pulseNrzs(p, t)
            Mod.OOK_PIWM_RAW -> Slicer.pulsePiwmRaw(p, t)
            Mod.OOK_PIWM_DC -> Slicer.pulsePiwmDc(p, t)
            Mod.OOK_PWM_OSV1 -> Slicer.pulseOsv1(p, t)
            Mod.OOK_RZI -> Slicer.pulseRzi(p, t)
        }
    }

    fun dispatch(pkg: PulsePackage, onReading: (Reading) -> Unit): Int {
        val fsk = pkg.type == PULSE_DATA_FSK
        var events = 0
        var priority = 0
        while (events == 0 && priority < Int.MAX_VALUE) {
            var nextPriority = Int.MAX_VALUE
            for (d in decoders) {
                if (d.mod.fsk != fsk) continue
                if (d.priority > priority && d.priority < nextPriority) nextPriority = d.priority
                if (d.priority != priority) continue
                for (bb in slice(d, pkg.data)) {
                    val readings = try {
                        d.decode(bb)
                    } catch (e: IndexOutOfBoundsException) {
                        emptyList<Reading>()
                    }
                    for (r in readings) onReading(r)
                    events += readings.size
                }
            }
            priority = nextPriority
        }
        return events
    }

    private fun detectPackage(am: IntArray, fm: IntArray, n: Int, sampleRate: Int): Int {
        while (true) {
            val event = detector.detectPackage(am, fm, n, sampleRate, pulses, span)
            if (event == PULSE_DETECT_START || event == PULSE_DETECT_RESTART || event == PULSE_DETECT_RETRY) fskRejected = false
            var ready = 0
            for (d in 0 until FSK_PULSE_DETECTOR_COUNT) {
                if (fskStates[d].pkg(fm, span, event, pulses, fskPulses[d], d)) ready = ready or (1 shl d)
            }
            if (ready != 0 && !fskRejected) {
                for (d in 0 until FSK_PULSE_DETECTOR_COUNT) {
                    if ((ready and (1 shl d)) != 0) fskStates[d].finalize(pulses, fskPulses[d], d)
                }
                fskReady = ready
                return PULSE_DATA_FSK
            }
            if (event == PULSE_DETECT_OOK) return PULSE_DATA_OOK
            if (event == PULSE_DETECT_END) return 0
        }
    }

    private fun report(type: Int, p: PulseData) {
        val rssiDb = (10.0 * log10(max(1, p.ookHighEstimate) / 32258.0)).toInt()
        onPackage?.invoke(type, p.numPulses, rssiDb)
    }

    private fun process(am: IntArray, fm: IntArray, n: Int, sampleRate: Int, onReading: (Reading) -> Unit): Int {
        var packages = 0
        while (true) {
            val type = detectPackage(am, fm, n, sampleRate)
            if (type == 0) break
            if (type == PULSE_DATA_OOK) {
                report(type, pulses)
                dispatch(PulsePackage(PULSE_DATA_OOK, pulses.copy()), onReading)
                packages++
                continue
            }
            var events = 0
            var tried = -1
            for (d in 0 until FSK_PULSE_DETECTOR_COUNT) {
                if (events != 0) break
                if ((fskReady and (1 shl d)) == 0) continue
                if (tried < 0) tried = d
                events += dispatch(PulsePackage(PULSE_DATA_FSK, fskPulses[d].copy()), onReading)
                if (events != 0) tried = d
            }
            if (events == 0 && (fskReady and (1 shl FSK_PULSE_DETECTOR_CLASSIC)) == 0) {
                fskRejected = true
                detector.retryFsk()
                continue
            }
            detector.skipPackage()
            report(type, fskPulses[tried])
            packages++
        }
        return packages
    }

    fun run(iq: ByteArray, n: Int, sampleRate: Int, onReading: (Reading) -> Unit): Int {
        val env = IntArray(n)
        val am = IntArray(n)
        val fm = IntArray(n)
        Baseband.envelopeDetectNolut(iq, env, n)
        Baseband.lowPassFilter(lowPass, env, am, n)
        Baseband.demodFm(fmState, iq, fm, n, sampleRate, 0.1f)
        return process(am, fm, n, sampleRate, onReading)
    }

    fun flush(onReading: (Reading) -> Unit) {
        process(IntArray(0), IntArray(0), 0, pulses.sampleRate, onReading)
    }

    private fun pwmTrain(bytes: IntArray, bits: Int, sampleRate: Int, shortUs: Int, longUs: Int, gapUs: Int, endGapUs: Int): PulseData {
        val p = PulseData()
        p.sampleRate = sampleRate
        val spus = sampleRate / 1_000_000f
        for (i in 0 until bits) {
            val bit = (bytes[i / 8] shr (7 - i % 8)) and 1
            p.pulse[i] = ((if (bit == 1) shortUs else longUs) * spus).toInt()
            p.gap[i] = ((if (i == bits - 1) endGapUs else gapUs) * spus).toInt()
        }
        p.numPulses = bits
        return p
    }

    fun demo() {
        decoders.clear()
        decoders.add(GenericRemoteDecoder())
        val rate = 250_000

        val remote = intArrayOf(0xED, 0xCB, 0xFE, 0x80)
        val remoteTrain = pwmTrain(remote, 25, rate, 464, 1404, 464, 20_000)
        val got = ArrayList<Reading>()
        dispatch(PulsePackage(PULSE_DATA_OOK, remoteTrain)) { got.add(it) }
        check(got.size == 1) { "generic remote readings=${got.size}" }
        check(got[0].model == "Generic-Remote" && got[0].id == "4660") { "generic remote ${got[0]}" }
        check(got[0].fields["cmd"] == 1 && got[0].fields["tristate"] == "0Z0X01Z0000Z") { "generic remote ${got[0].fields}" }

        val honda = IntArray(49)
        honda[0] = 0xFF
        honda[38] = 0xFF
        honda[44] = 0x12
        honda[45] = 0x34
        honda[46] = 0xAB
        val hondaTrain = pwmTrain(honda, 392, rate, 250, 500, 250, 4000)
        val fskGot = ArrayList<Reading>()
        dispatch(PulsePackage(PULSE_DATA_FSK, hondaTrain)) { fskGot.add(it) }
        check(fskGot.isEmpty()) { "honda is disabled upstream; must not decode by default: $fskGot" }

        val ookBb = Slicer.pulsePwm(remoteTrain, GenericRemoteDecoder().sliceParams())
        check(ookBb.size == 1 && ookBb[0].bitsPerRow[0] == 25) { "slicer rows" }
        check(ookBb[0].bb[0][0] == 0xED && ookBb[0].bb[0][1] == 0xCB && ookBb[0].bb[0][2] == 0xFE && ookBb[0].bb[0][3] == 0x80) { "slicer bits ${ookBb[0].printHex()}" }

        reset()
        val lead = 3000
        val tail = 8000
        val sig = ArrayList<IntArray>()
        for (i in 0 until 25) {
            val bit = (remote[i / 8] shr (7 - i % 8)) and 1
            val hi = ((if (bit == 1) 464 else 1404) * rate / 1_000_000)
            sig.add(intArrayOf(hi, 464 * rate / 1_000_000))
        }
        var total = lead + tail
        for (s in sig) total += s[0] + s[1]
        val iq = ByteArray(2 * total)
        var k = 0
        fun put(high: Boolean) {
            val noise = (k * 5) % 3 - 1
            iq[2 * k] = (if (high) 255 else 127 + noise).toByte()
            iq[2 * k + 1] = (127 + (if (high) 0 else (k * 7) % 3 - 1)).toByte()
            k++
        }
        repeat(lead) { put(false) }
        for (s in sig) {
            repeat(s[0]) { put(true) }
            repeat(s[1]) { put(false) }
        }
        repeat(tail) { put(false) }
        val e2e = ArrayList<Reading>()
        run(iq, total, rate) { e2e.add(it) }
        check(e2e.size == 1 && e2e[0].model == "Generic-Remote" && e2e[0].id == "4660") { "iq pipeline readings=$e2e" }
        reset()
    }
}

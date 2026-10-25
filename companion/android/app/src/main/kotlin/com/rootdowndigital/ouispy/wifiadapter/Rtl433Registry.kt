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

    var centerFreqHz = 433_920_000L

    var onPackage: ((Int, Int, Int) -> Unit)? = null

    private val lowPass = Baseband.LowPassState()
    private val fmState = Baseband.FmState()
    private val detector = PulseDetector()

    fun reset() {
        lowPass.x0 = 0
        lowPass.y0 = 0
        fmState.xr = 0
        fmState.xi = 0
        fmState.xf = 0
        fmState.yf = 0
        fmState.rate = 0
        detector.reset()
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

    fun dispatch(pkg: PulsePackage, onReading: (Reading) -> Unit) {
        val fsk = pkg.type == PULSE_DATA_FSK
        for (d in decoders) {
            if (d.mod.fsk != fsk) continue
            for (bb in slice(d, pkg.data)) {
                val readings = try {
                    d.decode(bb)
                } catch (e: IndexOutOfBoundsException) {
                    emptyList<Reading>()
                }
                for (r in readings) onReading(r)
            }
        }
    }

    private fun fpdm(): Int =
        if (centerFreqHz > FSK_PULSE_DETECTOR_LIMIT) FSK_PULSE_DETECT_NEW else FSK_PULSE_DETECT_OLD

    fun run(iq: ByteArray, n: Int, sampleRate: Int, onReading: (Reading) -> Unit): Int {
        val env = IntArray(n)
        val am = IntArray(n)
        val fm = IntArray(n)
        Baseband.envelopeDetectNolut(iq, env, n)
        Baseband.lowPassFilter(lowPass, env, am, n)
        val mode = fpdm()
        Baseband.demodFm(fmState, iq, fm, n, sampleRate, if (mode == FSK_PULSE_DETECT_OLD) 0.1f else 0.2f)
        var packages = 0
        while (true) {
            val pkg = detector.detectPackage(am, fm, n, sampleRate, mode) ?: break
            val rssiDb = (10.0 * log10(max(1, pkg.data.ookHighEstimate) / 32258.0)).toInt()
            onPackage?.invoke(pkg.type, pkg.data.numPulses, rssiDb)
            dispatch(pkg, onReading)
            packages++
        }
        return packages
    }

    fun flush(onReading: (Reading) -> Unit) {
        val pkg = detector.flush(fpdm()) ?: return
        dispatch(pkg, onReading)
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

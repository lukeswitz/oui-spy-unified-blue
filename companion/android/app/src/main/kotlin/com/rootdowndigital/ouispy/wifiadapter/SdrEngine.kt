package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbInterface

internal class SdrEngine(
    conn: UsbDeviceConnection,
    intf: UsbInterface,
    private val log: (String) -> Unit,
    private val onSpectrum: (FloatArray, Long, Int) -> Unit,
    private val onDetection: (Map<String, Any?>) -> Unit,
) {
    enum class Mode { SPECTRUM, ADSB, TPMS, RTL433 }

    private val dev = RtlSdrDevice(conn, intf, log)
    @Volatile private var stop = false

    fun abort() {
        stop = true
        dev.abort()
    }

    fun run(mode: Mode, centerHz: Long, rate: Int, hopHz: List<Long> = emptyList()) {
        if (!dev.open()) {
            log("RTL-SDR: tuner not found")
            return
        }
        val bands = if (hopHz.isNotEmpty()) hopHz else listOf(centerHz)
        dev.setSampleRate(rate)
        dev.setCenterFreq(bands.first())
        dev.setAgc(true)
        val bandList = bands.joinToString(" / ") { "${it / 1_000_000.0}" }
        log("RTL-SDR: $mode live at $bandList MHz, ${rate / 1_000_000.0} MS/s")
        when (mode) {
            Mode.SPECTRUM -> runSpectrum(centerHz, rate)
            Mode.ADSB -> runAdsb(rate)
            Mode.TPMS -> runTpms(bands, rate)
            Mode.RTL433 -> runRtl433(bands, rate)
        }
    }

    private var rtl433ErrLogged = false

    private fun runRtl433(bands: List<Long>, rate: Int) {
        Rtl433Devices.registerAll()
        Rtl433Registry.reset()
        Rtl433Registry.centerFreqHz = bands.first()
        val isms = bands.associateWith { c ->
            IsmDecoder(rate, c) { b ->
                onDetection(
                    mapOf(
                        "kind" to "ism",
                        "modulation" to b.modulation,
                        "bits" to b.bitHex,
                        "bitCount" to b.bitCount,
                        "frequency" to b.centerHz,
                        "rssi" to b.rssiDb.toInt(),
                    ),
                )
            }
        }
        var idx = 0
        var hopAt = System.currentTimeMillis()
        var settleUntil = 0L
        var pkgs = 0
        var decs = 0
        var statAt = System.currentTimeMillis()
        dev.readIq { buf, n ->
            if (stop) return@readIq
            val now = System.currentTimeMillis()
            if (bands.size > 1 && now - hopAt >= DWELL_MS) {
                idx = (idx + 1) % bands.size
                dev.setCenterFreq(bands[idx])
                Rtl433Registry.centerFreqHz = bands[idx]
                Rtl433Registry.reset()
                hopAt = now
                settleUntil = now + SETTLE_MS
                return@readIq
            }
            if (now < settleUntil) return@readIq
            val c = bands[idx]
            try {
                pkgs += Rtl433Registry.run(buf, n / 2, rate) { r ->
                    decs++
                    val m = HashMap<String, Any?>()
                    m["kind"] = "rtl433"
                    m["model"] = r.model
                    m["id"] = r.id
                    m["frequency"] = c
                    for ((k, v) in r.fields) if (k !in m) m[k] = v
                    onDetection(m)
                }
            } catch (e: Exception) {
                if (!rtl433ErrLogged) { rtl433ErrLogged = true; log("RTL433 decoder threw (continuing): ${e.message}") }
            }
            isms[c]!!.feed(buf, n)
            if (now - statAt >= 2000) {
                statAt = now
                log("SCAN ${c / 1_000_000}MHz pkts=$pkgs decoded=$decs")
            }
        }
    }

    private fun runSpectrum(centerHz: Long, rate: Int) {
        val spec = SdrDsp.Spectrum(FFT_SIZE)
        var frameAt = 0L
        var detAt = 0L
        dev.readIq { buf, n ->
            if (stop) return@readIq
            val now = System.currentTimeMillis()
            if (now - frameAt < FRAME_MS) return@readIq
            frameAt = now
            val power = spec.process(buf, n)
            onSpectrum(power, centerHz, rate)
            if (now - detAt >= DET_MS) {
                detAt = now
                for ((hz, db) in SdrDsp.peaks(power, centerHz, rate, PEAK_FLOOR_DB, PEAK_MIN_SEP)) {
                    onDetection(
                        mapOf(
                            "kind" to "rf",
                            "frequency" to hz,
                            "rssi" to db.toInt(),
                        ),
                    )
                }
            }
        }
    }

    private fun runAdsb(rate: Int) {
        if (rate != ADSB_RATE) {
            dev.setSampleRate(ADSB_RATE)
            dev.setCenterFreq(ADSB_HZ)
        }
        val dec = AdsbDecoder()
        dev.readIq { buf, n ->
            if (stop) return@readIq
            dec.process(buf, n) { m ->
                onDetection(
                    mapOf(
                        "kind" to "adsb",
                        "icao" to m.icao,
                        "callsign" to m.callsign,
                        "lat" to m.lat,
                        "lon" to m.lon,
                        "altitude" to m.altitudeFt,
                        "velocity" to m.velocityKt,
                        "heading" to m.headingDeg,
                    ),
                )
            }
        }
    }

    private fun runTpms(bands: List<Long>, rate: Int) {
        val decs = bands.associateWith { c ->
            IsmDecoder(rate, c) { b ->
                onDetection(
                    mapOf(
                        "kind" to "ism",
                        "modulation" to b.modulation,
                        "bits" to b.bitHex,
                        "bitCount" to b.bitCount,
                        "frequency" to b.centerHz,
                        "rssi" to b.rssiDb.toInt(),
                    ),
                )
                val r = try { TpmsProtocols.decode(hexToBytes(b.bitHex), b.bitCount) } catch (e: Exception) { null }
                if (r != null && plausibleTpms(r)) {
                    onDetection(
                        mapOf(
                            "kind" to "tpms",
                            "model" to r.model,
                            "id" to r.id,
                            "pressureKpa" to r.pressureKpa,
                            "tempC" to r.tempC,
                            "flags" to r.flags,
                            "frequency" to b.centerHz,
                        ),
                    )
                }
            }
        }
        var idx = 0
        var hopAt = System.currentTimeMillis()
        var settleUntil = 0L
        dev.readIq { buf, n ->
            if (stop) return@readIq
            val now = System.currentTimeMillis()
            if (bands.size > 1 && now - hopAt >= DWELL_MS) {
                idx = (idx + 1) % bands.size
                dev.setCenterFreq(bands[idx])
                hopAt = now
                settleUntil = now + SETTLE_MS
                return@readIq
            }
            if (now < settleUntil) return@readIq
            decs[bands[idx]]!!.feed(buf, n)
        }
    }

    private fun plausibleTpms(r: TpmsProtocols.Reading): Boolean {
        val t = r.tempC
        if (t != null && (t < -50.0 || t > 90.0)) return false
        val p = r.pressureKpa
        if (p != null && (p < 0.0 || p > 900.0)) return false
        return true
    }

    private fun hexToBytes(h: String): ByteArray {
        val clean = if (h.length % 2 == 0) h else h.dropLast(1)
        return ByteArray(clean.length / 2) {
            val hi = clean[it * 2].digitToIntOrNull(16) ?: 0
            val lo = clean[it * 2 + 1].digitToIntOrNull(16) ?: 0
            ((hi shl 4) or lo).toByte()
        }
    }

    companion object {
        const val FFT_SIZE = 1024
        const val FRAME_MS = 80L
        const val DET_MS = 1000L
        const val PEAK_FLOOR_DB = 12f
        const val PEAK_MIN_SEP = 6
        const val ADSB_RATE = 2_000_000
        const val ADSB_HZ = 1_090_000_000L
        const val DWELL_MS = 2_000L
        const val SETTLE_MS = 60L
    }
}

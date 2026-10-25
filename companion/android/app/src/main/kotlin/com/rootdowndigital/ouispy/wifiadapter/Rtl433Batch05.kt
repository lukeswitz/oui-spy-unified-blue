// Kotlin transcription of rtl_433 device decoders (batch 05). GPL-3 reference; constants, bit offsets and CRC parameters transcribed as facts.
package com.rootdowndigital.ouispy.wifiadapter

// unverified: lacrosse_tx31u.c:78, struct lacrosse_tx31u.c:207
internal object LacrosseTx31u : Rtl433Decoder() {
    override val name = "LaCrosse TX31U-IT, The Weather Channel WS-1910TWC-IT"
    override val mod = Mod.FSK_PCM
    override val short = 116
    override val long = 116
    override val reset = 20000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows > 1) return emptyList()
        val start = bb.search(0, 0, intArrayOf(0xaa, 0xaa, 0x2d, 0xd4), 32)
        if (start >= bb.bitsPerRow[0]) return emptyList()
        val msgBytes = (bb.bitsPerRow[0] - start) / 8
        if (msgBytes < 9 || msgBytes > 20) return emptyList()
        val msg = IntArray(20)
        bb.extractBytes(0, start, msg, msgBytes * 8)
        val sensorId = ((msg[4] and 0xf) shl 2) or ((msg[5] shr 6) and 0x3)
        val noExtSensor = (msg[5] shr 4) and 1
        val batteryLow = (msg[5] shr 3) and 1
        val measurements = msg[5] and 0x7
        val expectedBytes = 6 + measurements * 2 + 1
        if (msgBytes < expectedBytes) return emptyList()
        val rCrc = msg[expectedBytes - 1]
        val cCrc = Rtl433BitUtil.crc8(msg.copyOfRange(4, msg.size), 2 + measurements * 2, 0x31, 0x00)
        if (rCrc != cCrc) return emptyList()
        val fields = linkedMapOf<String, Any?>(
            "battery_ok" to (if (batteryLow != 0) 0 else 1),
        )
        for (m in 0 until measurements) {
            val type = (msg[6 + m * 2] shr 4) and 0xf
            val nib1 = msg[6 + m * 2] and 0xf
            val nib2 = (msg[7 + m * 2] shr 4) and 0xf
            val nib3 = msg[7 + m * 2] and 0xf
            when (type) {
                0 -> {
                    val tempC = 10 * nib1 + nib2 + 0.1f * nib3 - 40.0f
                    fields["temperature_C"] = tempC.toDouble()
                }
                1 -> {
                    val humidity = 100 * nib1 + 10 * nib2 + nib3
                    fields["humidity"] = humidity
                }
                2 -> {
                    val rawRain = (nib1 shl 8) + (nib2 shl 4) + nib3
                    if (noExtSensor == 0 && rawRain > 0) fields["rain"] = rawRain
                }
                3 -> {
                    if (noExtSensor == 0) {
                        val windDir = nib1 * 22.5f
                        val windAvg = ((nib2 shl 4) + nib3) * 0.1f * 3.6f
                        fields["wind_dir_deg"] = windDir.toDouble()
                        fields["wind_avg_km_h"] = windAvg.toDouble()
                    }
                }
                4 -> {
                    val windInputLost = nib1 and 1
                    if (noExtSensor == 0 && windInputLost == 0) {
                        val windMax = ((nib2 shl 4) + nib3) * 0.1f * 3.6f
                        fields["wind_max_km_h"] = windMax.toDouble()
                    }
                }
                else -> {}
            }
        }
        fields["mic"] = "CRC"
        return listOf(Reading("LaCrosse-TX31UIT", sensorId.toString(), fields))
    }
}

// unverified: lacrosse_tx34.c:50, struct lacrosse_tx34.c:121
internal object LacrosseTx34 : Rtl433Decoder() {
    override val name = "LaCrosse TX34-IT rain gauge"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            val start = bb.search(row, 0, intArrayOf(0xa2, 0xdd, 0x40), 20) + 20
            if (start + 40 > bb.bitsPerRow[row]) continue
            val b = IntArray(5)
            bb.extractBytes(row, start, b, 40)
            val rCrc = b[4]
            val cCrc = Rtl433BitUtil.crc8(b, 4, 0x31, 0x00)
            if (rCrc != cCrc) continue
            if (((b[0] and 0xF0) shr 4) != 5) continue
            val sensorId = ((b[0] and 0x0F) shl 2) or (b[1] shr 6)
            val newBatt = (b[1] and 0x20) shr 5
            val lowBatt = (b[1] and 0x10) shr 4
            val rainTick = (b[2] shl 8) or b[3]
            val rainMm = rainTick * 0.222f
            out.add(
                Reading(
                    "LaCrosse-TX34IT",
                    sensorId.toString(),
                    mapOf(
                        "battery_ok" to (if (lowBatt != 0) 0 else 1),
                        "newbattery" to newBatt,
                        "rain_mm" to rainMm.toDouble(),
                        "rain_raw" to rainTick,
                        "mic" to "CRC",
                    ),
                ),
            )
        }
        return out
    }
}

// unverified: lacrosse_tx35.c:85-158 (lacrosse_it, device 35 path), struct lacrosse_tx35.c:197
internal object LacrosseTx35 : Rtl433Decoder() {
    override val name = "LaCrosse TX35DTH-IT, TFA Dostmann 30.3155 Temperature/Humidity sensor"
    override val mod = Mod.FSK_PCM
    override val short = 105
    override val long = 105
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            val startPos = bb.search(row, 0, intArrayOf(0xa2, 0xdd, 0x49), 24)
            if (startPos >= bb.bitsPerRow[row]) continue
            val b = IntArray(5)
            bb.extractBytes(row, startPos + 20, b, 40)
            val rCrc = b[4]
            val cCrc = Rtl433BitUtil.crc8(b, 4, 0x31, 0x00)
            if (rCrc != cCrc) continue
            var sensorId = ((b[0] and 0x0f) shl 2) or (b[1] shr 6)
            val tempC = 10 * (b[1] and 0x0f) + 1 * ((b[2] shr 4) and 0x0f) + 0.1f * (b[2] and 0x0f) - 40.0f
            val newBatt = (b[1] shr 5) and 1
            val batteryLow = b[3] shr 7
            val humidity = b[3] and 0x7f
            val fields = linkedMapOf<String, Any?>(
                "battery_ok" to (if (batteryLow != 0) 0 else 1),
                "newbattery" to newBatt,
                "temperature_C" to tempC.toDouble(),
            )
            if (humidity == 0x6a || humidity == 0x7d) {
                if (humidity == 0x7d) sensorId += 0x40
            } else {
                fields["humidity"] = humidity
            }
            fields["mic"] = "CRC"
            out.add(Reading("LaCrosse-TX35DTHIT", sensorId.toString(), fields))
        }
        return out
    }
}

// unverified: lacrosse_wr1.c:53, struct lacrosse_wr1.c:139
internal object LacrosseWr1 : Rtl433Decoder() {
    override val name = "LaCrosse Technology View LTV-WR1 Multi Sensor"
    override val mod = Mod.FSK_PCM
    override val short = 104
    override val long = 104
    override val reset = 9600

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 120 || bb.bitsPerRow[0] > 156) return emptyList()
        val offset0 = bb.search(0, 0, intArrayOf(0xd2, 0xaa, 0x2d, 0xd4), 32)
        if (offset0 >= bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(11)
        bb.extractBytes(0, offset0 + 32, b, 88)
        if (Rtl433BitUtil.crc8(b, 11, 0x31, 0x00) != 0) return emptyList()
        val id = (b[0] shl 16) or (b[1] shl 8) or b[2]
        val flags = b[3] and 0xf1
        val seq = (b[3] and 0x0e) shr 1
        val rawWind = (b[4] shl 4) or ((b[5] and 0xf0) shr 4)
        val direction = ((b[5] and 0x0f) shl 8) or b[6]
        val rawRain1 = (b[7] shl 4) or ((b[8] and 0xf0) shr 4)
        val rawRain2 = ((b[8] and 0x0f) shl 8) or b[9]
        val speedKmh = rawWind * 0.1f
        if (speedKmh < 0 || speedKmh > 200 || direction < 0 || direction > 360) return emptyList()
        return listOf(
            Reading(
                "LaCrosse-WR1",
                String.format("%06x", id),
                mapOf(
                    "seq" to seq,
                    "flags" to flags,
                    "wind_avg_km_h" to speedKmh.toDouble(),
                    "wind_dir_deg" to direction,
                    "rain1" to rawRain1,
                    "rain2" to rawRain2,
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

private val WS6868_PREAMBLE = intArrayOf(0xd2, 0xaa, 0x2d, 0xd4)

private fun s16(x: Int): Int = x.toShort().toInt()

private class Ws6868Header(val id: Int, val batteryLow: Int, val test: Int, val channel: Int, val counter: Int)

private fun ws6868ParseHeader(b: IntArray): Ws6868Header =
    Ws6868Header(
        id = (b[0] shl 16) or (b[1] shl 8) or b[2],
        batteryLow = (b[3] shr 7) and 1,
        test = (b[3] shr 6) and 1,
        channel = (b[3] shr 4) and 3,
        counter = (b[3] shr 1) and 7,
    )

// unverified: lacrosse_ws6868.c:68-130, struct lacrosse_ws6868.c:132
internal object LacrosseWs6868Tx232th : Rtl433Decoder() {
    override val name = "LaCrosse WS6868 TX232TH-LCD temperature/humidity sensor"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val pos0 = bb.search(0, 0, WS6868_PREAMBLE, 32)
        if (pos0 >= bb.bitsPerRow[0]) return emptyList()
        val pos = pos0 + 32
        if (bb.bitsPerRow[0] - pos < 64) return emptyList()
        val b = IntArray(8)
        bb.extractBytes(0, pos, b, 64)
        val crc = Rtl433BitUtil.crc8(b, 7, 0x31, 0x00)
        if (crc != b[7]) return emptyList()
        val h = ws6868ParseHeader(b)
        val tempRaw = (b[4] shl 4) or (b[5] shr 4)
        val humidity = ((b[5] and 0x0f) shl 8) or b[6]
        val tempC = (tempRaw - 500) * 0.1f
        return listOf(
            Reading(
                "LaCrosse-TX232TH",
                String.format("%06x", h.id),
                mapOf(
                    "channel" to h.channel + 1,
                    "battery_ok" to (if (h.batteryLow != 0) 0 else 1),
                    "test" to h.test,
                    "counter" to h.counter,
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: lacrosse_ws6868.c:155-218, struct lacrosse_ws6868.c:220
internal object LacrosseWs6868Tx231rw : Rtl433Decoder() {
    override val name = "LaCrosse WS6868 TX231RW wind/rain sensor"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val pos0 = bb.search(0, 0, WS6868_PREAMBLE, 32)
        if (pos0 >= bb.bitsPerRow[0]) return emptyList()
        val pos = pos0 + 32
        if (bb.bitsPerRow[0] - pos < 96) return emptyList()
        val b = IntArray(12)
        bb.extractBytes(0, pos, b, 96)
        val crc = Rtl433BitUtil.crc8(b, 10, 0x31, 0x00)
        val checksum = Rtl433BitUtil.addBytes(b, 11) and 0xff
        if (crc != b[10] || checksum != b[11]) return emptyList()
        val h = ws6868ParseHeader(b)
        val dataRaw = (4 until 10).joinToString("") { String.format("%02x", b[it]) }
        return listOf(
            Reading(
                "LaCrosse-TX231RW",
                String.format("%06x", h.id),
                mapOf(
                    "channel" to h.channel + 1,
                    "battery_ok" to (if (h.batteryLow != 0) 0 else 1),
                    "test" to h.test,
                    "counter" to h.counter,
                    "data_raw" to dataRaw,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

private fun reflect4(x0: Int): Int {
    var x = ((x0 and 0xCC) shr 2) or ((x0 and 0x33) shl 2)
    x = ((x and 0xAA) shr 1) or ((x and 0x55) shl 1)
    return x and 0xFF
}

private fun ws7000ExtractNibbles(msg: IntArray, offsetIn: Int, numIn: Int, dst: IntArray): Int {
    var offset = offsetIn
    var num = numIn
    var n = 0
    while (num >= 5) {
        var bits = (msg[offset / 8] shl 8) or msg[offset / 8 + 1]
        bits = bits shr (11 - (offset % 8))
        if ((bits and 1) != 1) break
        dst[n++] = (bits shr 1) and 0xf
        offset += 5
        num -= 5
    }
    return n
}

// unverified: lacrosse_ws7000.c:46-231 (decode), struct lacrosse_ws7000.c:233; reflect4/extract_nibbles_4b1s transcribed from bit_util.c:41-66
internal object LacrosseWs7000 : Rtl433Decoder() {
    override val name = "LaCrosse/ELV/Conrad WS7000/WS2500 weather sensors"
    override val mod = Mod.OOK_PWM
    override val short = 400
    override val long = 800
    override val reset = 1100

    override fun decode(bb: BitBuffer): List<Reading> {
        val dataSize = intArrayOf(3, 6, 3, 6, 10, 7)
        val start = bb.search(0, 0, intArrayOf(0x01), 8) + 8
        if (start >= bb.bitsPerRow[0]) return emptyList()
        val maxBits = minOf(14 * 5, bb.bitsPerRow[0] - start)
        val b = IntArray(14)
        val len = ws7000ExtractNibbles(bb.bb[0], start, maxBits, b)
        if (len < 7) return emptyList()
        for (i in 0 until len) b[i] = reflect4(b[i])
        val type = b[0]
        val addr = b[1] and 0x7
        val id = (type shl 4) or addr
        if (type > 5) return emptyList()
        if (len < dataSize[type]) return emptyList()
        if (Rtl433BitUtil.xorBytes(b, len - 1) != 0) return emptyList()
        if (((Rtl433BitUtil.addBytes(b, len - 1) + 5) and 0xf) != b[len - 1]) return emptyList()
        val idStr = id.toString()
        val sign = if ((b[1] and 0x8) != 0) -1 else 1
        return when (type) {
            0 -> {
                val temperature = ((b[4] * 10) + (b[3] * 1) + (b[2] * 0.1f)) * sign
                listOf(
                    Reading(
                        "LaCrosse-WS700027",
                        idStr,
                        mapOf("channel" to addr, "temperature_C" to temperature.toDouble(), "mic" to "CHECKSUM"),
                    ),
                )
            }
            1 -> {
                val temperature = ((b[4] * 10) + (b[3] * 1) + (b[2] * 0.1f)) * sign
                val humidity = ((b[7] * 10) + (b[6] * 1) + (b[5] * 0.1f)).toInt()
                listOf(
                    Reading(
                        "LaCrosse-WS700022",
                        idStr,
                        mapOf(
                            "channel" to addr,
                            "temperature_C" to temperature.toDouble(),
                            "humidity" to humidity,
                            "mic" to "CHECKSUM",
                        ),
                    ),
                )
            }
            2 -> {
                val rain = (b[4] shl 8) or (b[3] shl 4) or b[2]
                listOf(
                    Reading(
                        "LaCrosse-WS700016",
                        idStr,
                        mapOf("channel" to addr, "rain_mm" to rain * 0.3, "mic" to "CHECKSUM"),
                    ),
                )
            }
            3 -> {
                val speed = (b[4] * 10) + (b[3] * 1) + (b[2] * 0.1f)
                val direction = ((b[7] shr 2) * 100) + (b[6] * 10) + (b[5] * 1)
                val deviation = (b[7] and 0x3) * 22.5f
                listOf(
                    Reading(
                        "LaCrosse-WS700015",
                        idStr,
                        mapOf(
                            "channel" to addr,
                            "wind_avg_km_h" to speed.toDouble(),
                            "wind_dir_deg" to direction.toDouble(),
                            "wind_dev_deg" to deviation.toDouble(),
                            "mic" to "CHECKSUM",
                        ),
                    ),
                )
            }
            4 -> {
                val temperature = ((b[4] * 10) + (b[3] * 1) + (b[2] * 0.1f)) * sign
                val humidity = ((b[7] * 10) + (b[6] * 1) + (b[5] * 0.1f)).toInt()
                val pressure = (b[10] * 100) + (b[9] * 10) + (b[8] * 1) + 200
                listOf(
                    Reading(
                        "LaCrosse-WS700020",
                        idStr,
                        mapOf(
                            "channel" to addr,
                            "temperature_C" to temperature.toDouble(),
                            "humidity" to humidity,
                            "pressure_hPa" to pressure,
                            "mic" to "CHECKSUM",
                        ),
                    ),
                )
            }
            else -> {
                var brightness = ((b[4] * 100) + (b[3] * 10) + (b[2] * 1)).toLong()
                val bExponent = b[5]
                val exposition = (b[8] * 100) + (b[7] * 10) + (b[6] * 1)
                for (i in bExponent downTo 1) brightness *= 10
                brightness = brightness and 0xFFFFFFFFL
                listOf(
                    Reading(
                        "LaCrosse-WS250019",
                        idStr,
                        mapOf(
                            "channel" to addr,
                            "light_lux" to brightness,
                            "exposure_mins" to exposition,
                            "mic" to "CHECKSUM",
                        ),
                    ),
                )
            }
        }
    }
}

// unverified: lacrosse.c:56-186 (lacrossetx_decode), struct lacrosse.c:208
internal object Lacrossetx : Rtl433Decoder() {
    override val name = "LaCrosse TX Temperature / Humidity Sensor, TX5U rain gauge"
    override val mod = Mod.OOK_PWM
    override val short = 550
    override val long = 1400
    override val gap = 3000
    override val reset = 8000

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            val pRow = bb.bb[row]
            if (bb.bitsPerRow[row] != 44) continue
            if (pRow[0] != 0x0a) continue
            val nyb = IntArray(11)
            var parity = 0
            for (i in 0 until 44) {
                val rbyte = i / 8
                val rbit = 7 - (i % 8)
                val mnybble = i / 4
                val mbit = 3 - (i % 4)
                val bit = (pRow[rbyte] shr rbit) and 1
                nyb[mnybble] = nyb[mnybble] or (bit shl mbit)
                if (mnybble > 4 && mnybble < 8) parity += bit
            }
            parity += nyb[4] and 0x01
            var checksum = 0
            for (i in 0 until 10) checksum = (checksum + nyb[i]) and 0x0F
            if (checksum != nyb[10] || parity % 2 != 0) continue
            val msgType = nyb[2]
            val sensorId = (nyb[3] shl 3) + (nyb[4] shr 1)
            val msgValueRaw = (nyb[5] shl 8) or (nyb[6] shl 4) or nyb[7]
            val msgValue = nyb[5] * 10 + nyb[6] + nyb[7] * 0.1f
            if (nyb[5] != nyb[8] || nyb[6] != nyb[9]) continue
            when (msgType) {
                0x00 -> {
                    val tempC = msgValue - 50.0f
                    out.add(
                        Reading(
                            "LaCrosse-TX",
                            sensorId.toString(),
                            mapOf("temperature_C" to tempC.toDouble(), "mic" to "PARITY"),
                        ),
                    )
                }
                0x0E -> {
                    val fields = linkedMapOf<String, Any?>("mic" to "PARITY")
                    if (msgValueRaw != 0xff) fields["humidity"] = msgValue.toDouble()
                    out.add(Reading("LaCrosse-TX", sensorId.toString(), fields))
                }
                0x0A -> {
                    val rainIn = msgValueRaw * 0.0105f
                    out.add(
                        Reading(
                            "LaCrosse-TX5U",
                            sensorId.toString(),
                            mapOf("rain_in" to rainIn.toDouble(), "rain_raw" to msgValueRaw, "mic" to "PARITY"),
                        ),
                    )
                }
                else -> {}
            }
        }
        return out
    }
}

// unverified: lacrossews.c:40-87 (detect), lacrossews.c:89-219 (callback), struct lacrossews.c:221
internal object Lacrossews : Rtl433Decoder() {
    override val name = "LaCrosse WS-2310 / WS-3600 Weather Station"
    override val mod = Mod.OOK_PWM
    override val short = 368
    override val long = 1464
    override val reset = 8000

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            val pRow = bb.bb[row]
            if (bb.bitsPerRow[row] != 52) continue
            if (pRow[0] != 0x09 && pRow[0] != 0x06) continue
            val nyb = IntArray(13)
            var parity = 0
            for (i in 0 until 52) {
                val rbyte = i / 8
                val rbit = 7 - (i % 8)
                val mnybble = i / 4
                val mbit = 3 - (i % 4)
                val bit = (pRow[rbyte] shr rbit) and 1
                nyb[mnybble] = nyb[mnybble] or (bit shl mbit)
                if (i == 9 || (i >= 27 && i <= 39)) parity += bit
            }
            var checksum = 0
            for (i in 0 until 12) checksum += nyb[i]
            checksum = checksum and 0x0F
            val checksumOk = nyb[7] == (nyb[10] xor 0xF) &&
                nyb[8] == (nyb[11] xor 0xF) &&
                (parity and 0x1) == 0x1 &&
                checksum == nyb[12]
            if (!checksumOk) continue
            val wsId = (nyb[0] shl 4) + nyb[1]
            val msgType = ((nyb[2] shr 1) and 0x4) + (nyb[2] and 0x3)
            val sensorId = (nyb[3] shl 4) + nyb[4]
            val bcd = nyb[7] * 100 + nyb[8] * 10 + nyb[9]
            val bcd2 = nyb[7] * 10 + nyb[8]
            val bin = nyb[7] * 256 + nyb[8] * 16 + nyb[9]
            val model = if (wsId == 0x6) "LaCrosse-WS3600" else "LaCrosse-WS2310"
            val id = sensorId.toString()
            when (msgType) {
                0 -> {
                    val tempC = if (wsId == 0x6) (bcd - 400) * 0.1f else (bcd - 300) * 0.1f
                    out.add(Reading(model, id, mapOf("temperature_C" to tempC.toDouble())))
                }
                1 -> {
                    if (nyb[7] == 0xA && nyb[8] == 0xA) continue
                    out.add(Reading(model, id, mapOf("humidity" to bcd2)))
                }
                2 -> {
                    val rainMm = 0.5180f * bin
                    out.add(Reading(model, id, mapOf("rain_mm" to rainMm.toDouble())))
                }
                3, 7 -> {
                    if (nyb[7] == 0xF && nyb[8] == 0xE) continue
                    val windDir = nyb[9] * 22.5f
                    val windSpd = (nyb[7] * 16 + nyb[8]) * 0.1f
                    val fields = linkedMapOf<String, Any?>()
                    if (msgType == 3) fields["wind_avg_m_s"] = windSpd.toDouble()
                    else fields["wind_max_m_s"] = windSpd.toDouble()
                    fields["wind_dir_deg"] = windDir.toDouble()
                    out.add(Reading(model, id, fields))
                }
                else -> {}
            }
        }
        return out
    }
}

private fun reverse8(x: Int): Int {
    var v = x and 0xFF
    v = ((v and 0xF0) shr 4) or ((v and 0x0F) shl 4)
    v = ((v and 0xCC) shr 2) or ((v and 0x33) shl 2)
    v = ((v and 0xAA) shr 1) or ((v and 0x55) shl 1)
    return v and 0xFF
}

private val MARKISOL_CONTROL = arrayOf(
    "Limit (0)",
    "Down (1)",
    "? (2)",
    "H-Down (3)",
    "Confirm (4)",
    "Stop (5)",
    "? (6)",
    "? (7)",
    "? (8)",
    "? (9)",
    "? (10)",
    "? (11)",
    "Up (12)",
    "Limit (13)",
    "H-Up (14)",
    "? (15)",
)

// unverified: markisol.c:45-98, struct markisol.c:125 (upstream disabled=1, excessive false positives, issue #3611)
internal object Markisol : Rtl433Decoder() {
    override val name = "Markisol, E-Motion, BOFU, Rollerhouse, BF-30x, BF-415 curtain remote"
    override val mod = Mod.OOK_PWM
    override val short = 368
    override val long = 704
    override val sync = 5628
    override val gap = 2000
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> {
        val buf = IntArray(5)
        var cksum = 0
        var gotProper = false
        for (i in 0 until bb.numRows) {
            if (bb.bitsPerRow[i] == 41 || bb.bitsPerRow[i] == 42) {
                val b = bb.bb[i]
                for (j in 0 until 5) {
                    buf[j] = ((b[j] shl 1) + (b[j + 1] shr 7)) and 0xFF
                    buf[j] = reverse8(buf[j]).inv() and 0xFF
                    cksum = (cksum + buf[j]) and 0xFF
                }
                gotProper = true
                break
            }
        }
        if (!gotProper) return emptyList()
        if (cksum != 1) return emptyList()
        val address = (buf[0] shl 8) or buf[1]
        val channel = buf[2] and 0xf
        val control = ((buf[2] shr 4) and 2.inv()) or ((buf[3] and 0x10) shr 3)
        val zone = ((buf[2] and 0x20) shr 5) + ((buf[3] and 0x80) shr 6) + 1
        return listOf(
            Reading(
                "Markisol",
                String.format("%04X", address),
                mapOf(
                    "control" to MARKISOL_CONTROL[control],
                    "channel" to channel,
                    "zone" to zone,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

private val LIGHTWAVE_NIBBLES = mapOf(
    0xF6 to 0x0, 0xEE to 0x1, 0xED to 0x2, 0xEB to 0x3,
    0xDE to 0x4, 0xDD to 0x5, 0xDB to 0x6, 0xBE to 0x7,
    0xBD to 0x8, 0xBB to 0x9, 0xB7 to 0xA, 0x7E to 0xB,
    0x7D to 0xC, 0x7B to 0xD, 0x77 to 0xE, 0x6F to 0xF,
)

// unverified: lightwave_rf.c:50-146, struct lightwave_rf.c:148 (upstream disabled=1)
internal object LightwaveRf : Rtl433Decoder() {
    override val name = "LightwaveRF"
    override val mod = Mod.OOK_PPM
    override val short = 250
    override val long = 1250
    override val reset = 1500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 71 || bb.numRows != 1) return emptyList()
        bb.invert()
        bb.addRow()
        for (n in 0 until bb.bitsPerRow[0]) {
            if (bitrowGetBit(bb.bb[0], n) != 0) {
                bb.addBit(1)
            } else {
                bb.addBit(1)
                bb.addBit(0)
            }
        }
        if (bb.bitsPerRow[1] != 91) return emptyList()
        var idx = 0
        if (bitrowGetBit(bb.bb[1], idx++) == 0) return emptyList()
        bb.addRow()
        for (n in 0 until 10) {
            if (bitrowGetBit(bb.bb[1], idx++) == 0) return emptyList()
            for (m in 0 until 8) bb.addBit(bitrowGetBit(bb.bb[1], idx++))
        }
        bb.addRow()
        for (n in 0 until 10) {
            val nibble = LIGHTWAVE_NIBBLES[bb.bb[2][n]] ?: return emptyList()
            for (m in 0 until 4) bb.addBit((nibble and (8 shr m)) shr (3 - m))
        }
        val b3 = bb.bb[3]
        val id = (b3[2] shl 16) or (b3[3] shl 8) or b3[4]
        val subunit = (b3[1] and 0xF0) shr 4
        val command = b3[1] and 0x0F
        val parameter = b3[0]
        return listOf(
            Reading(
                "Lightwave-RF",
                String.format("%06x", id),
                mapOf("subunit" to subunit, "command" to command, "parameter" to parameter),
            ),
        )
    }
}

// unverified: marlec_solar.c:37-150, struct marlec_solar.c:152
internal object MarlecSolar : Rtl433Decoder() {
    override val name = "Marlec Solar iBoost+ sensors"
    override val mod = Mod.FSK_PCM
    override val short = 20
    override val long = 20
    override val reset = 300

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val start = bb.search(0, 0, intArrayOf(0xaa, 0xaa, 0xd3, 0x91, 0xd3, 0x91), 48)
        if (start == bb.bitsPerRow[0]) return emptyList()
        if (bb.bitsPerRow[0] < 12 * 8) return emptyList()
        val lenBuf = IntArray(1)
        bb.extractBytes(0, start + 48, lenBuf, 8)
        val len = lenBuf[0]
        if (len > 105) return emptyList()
        val frame = IntArray(108)
        frame[0] = len
        val tmp = IntArray(107)
        bb.extractBytes(0, start + 56, tmp, (len + 2) * 8)
        for (i in 0 until len + 2) frame[1 + i] = tmp[i]
        val crc = Rtl433BitUtil.crc16(frame, len + 1, 0x8005, 0xffff)
        if (((frame[len + 1] shl 8) or frame[len + 2]) != crc) return emptyList()
        val frameType = frame[3]
        val isData = frameType == 0x22
        val savedType = frame[25]
        val savedVal = frame[26] or (frame[27] shl 8) or (frame[28] shl 16) or (frame[29] shl 24)
        val fields = linkedMapOf<String, Any?>()
        if (isData) {
            fields["boost_time"] = frame[6]
            fields["solar_off"] = frame[7]
            fields["tank_hot"] = frame[8]
            fields["battery_low"] = frame[13]
            fields["heating"] = ((frame[17] or (frame[18] shl 8)).toShort()).toInt()
            fields["import_val"] = frame[19] or (frame[20] shl 8) or (frame[21] shl 16) or (frame[22] shl 24)
            when (savedType) {
                0xCA -> fields["saved_today"] = savedVal
                0xCB -> fields["saved_yesterday"] = savedVal
                0xCC -> fields["saved_last_7"] = savedVal
                0xCD -> fields["saved_last_28"] = savedVal
                0xCE -> fields["saved_total"] = savedVal
            }
        }
        fields["raw"] = (0 until len).joinToString("") { String.format("%02x", frame[it + 1]) }
        fields["mic"] = "CRC"
        return listOf(Reading("Marlec-Solar", null, fields))
    }
}

// unverified: martec_mplcd.c:43-96, struct martec_mplcd.c:115
internal object MartecMplcd : Rtl433Decoder() {
    override val name = "Martec MPLCD Ceiling Fan Remote"
    override val mod = Mod.OOK_PWM
    override val short = 292
    override val long = 648
    override val gap = 850
    override val reset = 12000

    override fun decode(bb: BitBuffer): List<Reading> {
        val speedNames = arrayOf("off", "high", "medium", "low")
        val row = bb.findRepeatedRow(2, 22)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] > 22) return emptyList()
        val bytes = IntArray(3)
        bb.extractBytes(row, 1, bytes, 21)
        val checksum = Rtl433BitUtil.addNibbles(bytes, 2) and 0x0f
        val cks = (bytes[2] shr 3) and 0x0f
        if (checksum != cks) return emptyList()
        if (bytes[0] == 0 && bytes[1] == 0) return emptyList()
        var channel = (bytes[0].inv() shr 1) and 0x0f
        channel = reflect4(channel)
        var dimmer = (bytes[0] and 0x01) shl 6
        dimmer += (bytes[1] shr 2) and 0x3f
        if (dimmer > 0) dimmer = 42 - dimmer
        val speed = bytes[1] and 0x03
        return listOf(
            Reading(
                "Martec-MPLCD",
                channel.toString(),
                mapOf("dimmer" to dimmer, "speed" to speedNames[speed], "mic" to "CHECKSUM"),
            ),
        )
    }
}

// unverified: maverick_et73.c:46-99, struct maverick_et73.c:101
internal object MaverickEt73 : Rtl433Decoder() {
    override val name = "Maverick ET73"
    override val mod = Mod.OOK_PPM
    override val short = 1050
    override val long = 2050
    override val gap = 2200
    override val reset = 4400

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(3, 48)
        if (row < 0) return emptyList()
        val bytes = bb.bb[row]
        if ((bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0) ||
            (bytes[0] == 0xFF && bytes[1] == 0xFF && bytes[2] == 0xFF && bytes[3] == 0xFF)
        ) return emptyList()
        if (bb.bitsPerRow[row] != 48) return emptyList()
        val device = bytes[0]
        val temp1Raw = s16((bytes[1] shl 8) or (bytes[2] and 0xf0))
        val temp1C = (temp1Raw shr 4) * 0.1f
        val temp2Raw = s16(((bytes[2] and 0x0f) shl 12) or (bytes[3] shl 4))
        val temp2C = (temp2Raw shr 4) * 0.1f
        return listOf(
            Reading(
                "Maverick-ET73",
                device.toString(),
                mapOf("temperature_1_C" to temp1C.toDouble(), "temperature_2_C" to temp2C.toDouble()),
            ),
        )
    }
}

// unverified: maverick_et73x.c:43-107, struct maverick_et73x.c:116
internal object MaverickEt73x : Rtl433Decoder() {
    override val name = "Maverick ET-732/733 BBQ Sensor"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 230
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] != 104) return emptyList()
        if (bb.bb[0][0] != 0x55 || bb.bb[0][1] != 0x66 || bb.bb[0][2] != 0x6a) return emptyList()
        val mc = BitBuffer()
        bb.manchesterDecode(0, 0, mc, 104)
        if (mc.bitsPerRow[0] < 52) return emptyList()
        val b = mc.bb[0]
        val flags = b[1] and 0x0f
        val temp1 = (b[2] shl 2) or ((b[3] and 0xc0) shr 6)
        val temp2 = ((b[3] and 0x3f) shl 4) or ((b[4] and 0xf0) shr 4)
        val digest = ((b[4] and 0x0f) shl 12) or (b[5] shl 4) or (b[6] shr 4)
        val temp1C = temp1 - 532.0f
        val temp2C = temp2 - 532.0f
        val status = when (flags) {
            2 -> "default"
            7 -> "init"
            else -> "unknown"
        }
        val chk = IntArray(3)
        mc.extractBytes(0, 12, chk, 24)
        val id = Rtl433BitUtil.lfsrDigest16(chk, 3, 0x8810, 0xdd38) xor digest
        return listOf(
            Reading(
                "Maverick-ET73x",
                id.toString(),
                mapOf(
                    "status" to status,
                    "temperature_1_C" to temp1C.toDouble(),
                    "temperature_2_C" to temp2C.toDouble(),
                ),
            ),
        )
    }
}

// unverified: maverick_xr30.c:38-80, struct maverick_xr30.c:106
internal object MaverickXr30 : Rtl433Decoder() {
    override val name = "Maverick XR-30 BBQ Sensor"
    override val mod = Mod.FSK_PCM
    override val short = 360
    override val long = 360
    override val reset = 4096

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] != 104) return emptyList()
        val b = IntArray(12)
        when (bb.bb[0][0]) {
            0x55 -> bb.extractBytes(0, 7, b, 96)
            0xaa -> bb.extractBytes(0, 8, b, 96)
            else -> return emptyList()
        }
        if (b[0] != 0xaa || b[1] != 0xaa || b[2] != 0xaa || b[3] != 0xd3 || b[4] != 0x91 || b[5] != 0xd3 || b[6] != 0x91) {
            return emptyList()
        }
        val flags = (b[7] and 0xf0) shr 4
        val temp1 = ((b[7] and 0x0f) shl 6) or ((b[8] and 0xfc) shr 2)
        val temp2 = ((b[8] and 0x03) shl 8) or b[9]
        val digest = (b[10] shl 8) or b[11]
        val temp1C = temp1 - 532.0f
        val temp2C = temp2 - 532.0f
        val status = when (flags) {
            0 -> "default"
            5 -> "init"
            else -> "unknown"
        }
        val id = Rtl433BitUtil.lfsrDigest16(b.copyOfRange(7, 10), 3, 0x8810, 0x0d42) xor digest
        return listOf(
            Reading(
                "Maverick-XR30",
                id.toString(),
                mapOf(
                    "status" to status,
                    "temperature_1_C" to temp1C.toDouble(),
                    "temperature_2_C" to temp2C.toDouble(),
                ),
            ),
        )
    }
}

private fun xr50Probe(fields: MutableMap<String, Any?>, n: Int, flags: Int, tempRaw: Int, highRaw: Int, lowRaw: Int) {
    fields["probe_${n}_flags"] = flags
    if (tempRaw != 0) fields["temperature_${n}_C"] = ((tempRaw - 500) * 0.1f).toDouble()
    fields["setpoint_high_${n}_C"] = ((highRaw - 500) * 0.1f).toDouble()
    fields["setpoint_low_${n}_C"] = ((lowRaw - 500) * 0.1f).toDouble()
}

// unverified: maverick_xr50.c:50-137 (decode), struct maverick_xr50.c:176
internal object MaverickXr50 : Rtl433Decoder() {
    override val name = "Maverick XR-50 BBQ Sensor"
    override val mod = Mod.FSK_PCM
    override val short = 107
    override val long = 107
    override val reset = 2200

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows > 1) return emptyList()
        val msgLen = bb.bitsPerRow[0]
        var startPos = bb.search(0, 0, intArrayOf(0xd2, 0xaa, 0x2d, 0xd4), 32)
        if (startPos >= msgLen) return emptyList()
        if (msgLen - startPos < 184) return emptyList()
        startPos += 32
        val b = IntArray(23)
        bb.extractBytes(0, startPos, b, 23 * 8)
        if (Rtl433BitUtil.crc8(b, 23, 0x31, 0x00) != 0) return emptyList()
        val id = (b[0] shl 8) or b[1]
        val fields = linkedMapOf<String, Any?>()
        xr50Probe(fields, 1, (b[2] and 0xf0) shr 4, ((b[2] and 0x0f) shl 8) or b[3], (b[4] shl 4) or ((b[5] and 0xf0) shr 4), ((b[5] and 0x0f) shl 8) or b[6])
        xr50Probe(fields, 2, (b[7] and 0xf0) shr 4, ((b[7] and 0x0f) shl 8) or b[8], (b[9] shl 4) or ((b[10] and 0xf0) shr 4), ((b[10] and 0x0f) shl 8) or b[11])
        xr50Probe(fields, 3, (b[12] and 0xf0) shr 4, ((b[12] and 0x0f) shl 8) or b[13], (b[14] shl 4) or ((b[15] and 0xf0) shr 4), ((b[15] and 0x0f) shl 8) or b[16])
        xr50Probe(fields, 4, (b[17] and 0xf0) shr 4, ((b[17] and 0x0f) shl 8) or b[18], (b[19] shl 4) or ((b[20] and 0xf0) shr 4), ((b[20] and 0x0f) shl 8) or b[21])
        fields["mic"] = "CRC"
        return listOf(Reading("Maverick-XR50", String.format("%04x", id), fields))
    }
}

// unverified: mcpower_kinetic.c:39-75, struct mcpower_kinetic.c:100
internal object McpowerKinetic : Rtl433Decoder() {
    override val name = "McPower Kinetic battery-less wall switch"
    override val mod = Mod.FSK_PCM
    override val short = 10
    override val long = 10
    override val reset = 300

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        var pos = bb.search(0, 0, intArrayOf(0xaa, 0xaa), 16)
        if (pos >= bb.bitsPerRow[0]) return emptyList()
        pos += 16
        if (bb.bitsPerRow[0] - pos < 48) return emptyList()
        val b = IntArray(6)
        bb.extractBytes(0, pos, b, 48)
        val crc = Rtl433BitUtil.crc16(b, 4, 0x1021, 0xaa55)
        val crcRecv = (b[4] shl 8) or b[5]
        if (crc != crcRecv) return emptyList()
        val id = (b[0] shl 8) or b[1]
        val buttonLeft = (b[2] shr 6) and 1
        val buttonRight = (b[2] shr 5) and 1
        val counter = b[2] and 0xf
        val flags = b[3]
        return listOf(
            Reading(
                "McPower-Kinetic",
                String.format("%04x", id),
                mapOf(
                    "button_left" to buttonLeft,
                    "button_right" to buttonRight,
                    "counter" to counter,
                    "flags" to flags,
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: mebus.c:17-80, struct mebus.c:82 (upstream disabled=1, no samples available)
internal object Mebus433 : Rtl433Decoder() {
    override val name = "Mebus 433"
    override val mod = Mod.OOK_PPM
    override val short = 800
    override val long = 1600
    override val gap = 2400
    override val reset = 6000

    override fun decode(bb: BitBuffer): List<Reading> {
        val rows = bb.bb
        if (rows[0][0] != 0 || rows[1][4] == 0 || (rows[1][0] and 0x60) == 0 || rows[1][3] != rows[5][3] || rows[1][4] != rows[12][4]) {
            return emptyList()
        }
        val address = rows[1][0] and 0x1f
        val channel = ((rows[1][1] and 0x30) shr 4) + 1
        val unknown1 = (rows[1][1] and 0x40) shr 6
        val battery = rows[1][1] and 0x80
        val temp = s16(((rows[1][1] shl 12) and 0xFFFF) or (rows[1][2] shl 4)) shr 4
        val hum = (((rows[1][3] shl 4) or (rows[1][4] shr 4)) and 0xFF).toByte().toInt()
        val unknown2 = (rows[1][3] and 0xf0) shr 4
        return listOf(
            Reading(
                "Mebus-433",
                address.toString(),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to (if (battery != 0) 1 else 0),
                    "unknown1" to unknown1,
                    "unknown2" to unknown2,
                    "temperature_C" to (temp * 0.1f).toDouble(),
                    "humidity" to hum,
                ),
            ),
        )
    }
}

// unverified: megacode.c:42-91, struct megacode.c:93 (upstream disabled=1, fixed code with no checksum, issue #3611)
internal object Megacode : Rtl433Decoder() {
    override val name = "Linear Megacode Garage/Gate Remotes"
    override val mod = Mod.OOK_PCM
    override val short = 1000
    override val long = 1000
    override val gap = 9000
    override val reset = 20000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(1, 144)
        if (row < 0) return emptyList()
        val l = bb.bitsPerRow[row]
        if (l < 136 || l > 148) return emptyList()
        var raw = 0
        var frameCounter = 0
        val b = bb.bb[row]
        for (i in 0 until l) {
            if (((b[i / 8] shl (i % 8)) and 0x80) != 0) {
                if ((i + 4) % 6 > 2) raw = raw or (0x800000 shr ((i + 4) / 6))
                frameCounter++
            }
        }
        if (frameCounter != 24) return emptyList()
        val facility = (raw shr 19) and 0xf
        val id = (raw shr 3) and 0xffff
        val button = raw and 0x7
        return listOf(
            Reading(
                "Megacode-Remote",
                id.toString(),
                mapOf("raw" to String.format("%06X", raw), "facility" to facility, "button" to button),
            ),
        )
    }
}

// unverified: missil_ml0757.c:33-89, struct missil_ml0757.c:143
internal object MissilMl0757 : Rtl433Decoder() {
    override val name = "Missil ML0757 weather station"
    override val mod = Mod.OOK_PPM
    override val short = 975
    override val long = 1950
    override val gap = 2500
    override val reset = 4500
    override val tolerance = 100

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(5, 40)
        if (r < 0) return emptyList()
        if (bb.bitsPerRow[0] > 0) return emptyList()
        if (bb.bitsPerRow[r] > 40) return emptyList()
        val b = bb.bb[r]
        if ((b[4] and 0x0F) != 0x0F) return emptyList()
        val id = b[0]
        val flags = b[1]
        val f12bit = s16((b[2] shl 4) or (b[3] shr 4)) and 0xFFF
        val f8bit = (((b[3] and 0x0F) shl 4) or (b[4] shr 4)) and 0xFF
        val flagBat = flags and 0x80
        val flagRwp = flags and 0x04
        val tempC = if ((f12bit and 0x800) != 0) (0x1000 - f12bit) * -0.1f else f12bit * 0.1f
        val rainfall = f12bit * 0.45f
        val windKph = when (f8bit) {
            0x00 -> 0.0f
            0x80 -> 1.4f
            0xC0 -> 2.8f
            else -> (f8bit + 2) * 1.4f
        }
        val batteryOk = if (flagBat != 0) 0 else 1
        val fields = if (flagRwp != 0) {
            mapOf(
                "battery_ok" to batteryOk,
                "rain_mm" to rainfall.toDouble(),
                "wind_avg_km_h" to windKph.toDouble(),
            )
        } else {
            mapOf(
                "battery_ok" to batteryOk,
                "temperature_C" to tempC.toDouble(),
            )
        }
        return listOf(Reading("Missil-ML0757", id.toString(), fields))
    }
}

// unverified: mueller_hotrod.c:51-82, struct mueller_hotrod.c:113
internal object MuellerHotrod : Rtl433Decoder() {
    override val name = "Mueller Hot Rod water meter"
    override val mod = Mod.FSK_PCM
    override val short = 26
    override val long = 26
    override val reset = 2500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] < 96) return emptyList()
        val pos = bb.search(0, 0, intArrayOf(0xfe, 0xb1, 0x00), 24)
        if (pos + 9 * 8 >= bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(9)
        bb.extractBytes(0, pos + 24, b, 72)
        val crcCalc = Rtl433BitUtil.crc8(b, 8, 0x07, 0x00) xor 0x55
        if (crcCalc != b[8]) return emptyList()
        val idStr = String.format("%02x%02x%02x%02x", b[0], b[1], b[2], b[3])
        val volume = ((b[4] and 0xf0) shr 4) * 1000000 + (b[4] and 0x0f) * 100000 +
            ((b[5] and 0xf0) shr 4) * 10000 + (b[5] and 0x0f) * 1000 +
            ((b[6] and 0xf0) shr 4) * 100 + (b[6] and 0x0f) * 10 +
            ((b[7] and 0xf0) shr 4)
        val flag = b[7] and 0x0f
        return listOf(
            Reading(
                "Mueller-HotRod",
                idStr,
                mapOf("volume_gal" to volume, "flag" to flag, "mic" to "CRC"),
            ),
        )
    }
}

// unverified: newkaku.c:22-65, struct newkaku.c:84
internal object Newkaku : Rtl433Decoder() {
    override val name = "KlikAanKlikUit Wireless Switch"
    override val mod = Mod.OOK_PPM
    override val short = 300
    override val long = 1400
    override val sync = 2650
    override val tolerance = 200
    override val reset = 3200

    override fun decode(bb: BitBuffer): List<Reading> {
        val b0 = bb.bb[0]
        if (bb.syncsBeforeRow[0] != 1) return emptyList()
        if (bb.bitsPerRow[0] != 64 && bb.bitsPerRow[0] != 72) return emptyList()
        val dimCmd = (b0[6] and 0x03) == 0x03
        if (dimCmd) b0[6] = b0[6] and 0xfe
        val databits = BitBuffer()
        val pos = bb.manchesterDecode(0, 0, databits, 80)
        databits.invert()
        if (pos != 64 && pos != 72) return emptyList()
        val b = databits.bb[0]
        val id = (b[0] shl 18) or (b[1] shl 10) or (b[2] shl 2) or (b[3] shr 6)
        val groupCmd = (b[3] shr 5) and 1
        val onBit = (b[3] shr 4) and 1
        val unit = b[3] and 0x0f
        val dv = b[4] shr 4
        return listOf(
            Reading(
                "KlikAanKlikUit-Switch",
                id.toString(),
                mapOf(
                    "unit" to unit,
                    "group_call" to (if (groupCmd != 0) "Yes" else "No"),
                    "command" to (if (onBit != 0) "On" else "Off"),
                    "dim" to (if (dimCmd) "Yes" else "No"),
                    "dim_value" to dv,
                ),
            ),
        )
    }
}

// unverified: nexa.c:28-75, struct nexa.c:82
internal object Nexa : Rtl433Decoder() {
    override val name = "Nexa"
    override val mod = Mod.OOK_PPM
    override val short = 270
    override val long = 1300
    override val sync = 2650
    override val tolerance = 200
    override val gap = 1500
    override val reset = 2800

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.syncsBeforeRow[0] != 1) return emptyList()
        if (bb.bitsPerRow[0] != 64 && bb.bitsPerRow[0] != 72) return emptyList()
        val databits = BitBuffer()
        val pos = bb.manchesterDecode(0, 0, databits, 80)
        databits.invert()
        if (pos != 64 && pos != 72) return emptyList()
        val b = databits.bb[0]
        val id = (b[0] shl 18) or (b[1] shl 10) or (b[2] shl 2) or (b[3] shr 6)
        val groupCmd = (b[3] shr 5) and 1
        val onBit = (b[3] shr 4) and 1
        val channel = ((b[3] shr 2) and 0x03) xor 0x03
        val unit = (b[3] and 0x03) xor 0x03
        return listOf(
            Reading(
                "Nexa-Security",
                id.toString(),
                mapOf(
                    "channel" to channel,
                    "state" to (if (onBit != 0) "ON" else "OFF"),
                    "unit" to unit,
                    "group" to groupCmd,
                ),
            ),
        )
    }
}

private val NICE_LEAF_NODE = intArrayOf(
    25, 5, 63, 97, 203, 109, 69, 10, 3, 7, 64, 5, 71, 134, 180, 74,
    41, 158, 102, 199, 93, 118, 175, 101, 60, 77, 143, 174, 103, 148, 29, 85,
)

private fun niceXorArray(p: IntArray, k: Int) {
    for (i in 1 until 6) p[i] = (p[i] xor k) and 0xFF
}

private fun nicePlReverse(p: IntArray): Int {
    var k = (p[4].inv()) and 0xFF
    p[5] = (p[5].inv()) and 0xFF
    p[4] = (p[2].inv()) and 0xFF
    p[2] = (p[0].inv()) and 0xFF
    p[0] = k
    k = (p[3].inv()) and 0xFF
    p[3] = (p[1].inv()) and 0xFF
    p[1] = k
    for (y in 0 until 2) {
        k = (NICE_LEAF_NODE[p[0] shr 3] + 0x25) and 0xFF
        niceXorArray(p, k)
        p[5] = p[5] and 0x0f
        p[0] = p[0] xor (k and 0x7)
        k = NICE_LEAF_NODE[p[0] and 0x1f]
        niceXorArray(p, k)
        p[5] = p[5] and 0x0f
        p[0] = p[0] xor (k and 0xe0)
        if (y == 0) {
            k = p[0]
            p[0] = p[1]
            p[1] = k
        }
    }
    return (p[1] shl 8) or p[0]
}

// unverified: nice_flor_s.c:29-95 (decode), struct nice_flor_s.c:139 (upstream disabled=1)
internal object NiceFlorS : Rtl433Decoder() {
    override val name = "Nice Flor-s remote control for gates"
    override val mod = Mod.OOK_PWM
    override val short = 500
    override val long = 1000
    override val sync = 1500
    override val gap = 2000
    override val reset = 5000
    override val tolerance = 100

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 2 || bb.bitsPerRow[1] != 0) return emptyList()
        if (bb.bitsPerRow[0] != 52 && bb.bitsPerRow[0] != 72) return emptyList()
        bb.invert()
        val b = bb.bb[0]
        val tBuf = IntArray(7)
        tBuf[0] = (b[0] shr 4) and 0x0f
        for (i in 0 until 6) {
            tBuf[i + 1] = ((b[i] shl 4) and 0xf0) or ((b[i + 1] shr 4) and 0x0f)
        }
        val p = IntArray(7)
        p[5] = tBuf[1] and 0x0f
        p[4] = tBuf[2]
        p[3] = tBuf[3]
        p[2] = tBuf[4]
        p[1] = tBuf[5]
        p[0] = tBuf[6]
        val code = nicePlReverse(p)
        val serial = (p[5] shl 24) or (p[4] shl 16) or (p[3] shl 8) or p[2]
        val buttonId = tBuf[0] and 0x0f
        val count = ((tBuf[1] shr 4) and 0x0f) xor (tBuf[0] and 0x0f) xor 0x0f
        return listOf(
            Reading(
                "Nice-FlorS",
                null,
                mapOf(
                    "button" to buttonId,
                    "serial" to String.format("%07x", serial),
                    "code" to String.format("%04x", code),
                    "count" to count,
                ),
            ),
        )
    }
}

// unverified: nexus.c:45-159, struct nexus.c:219
internal object Nexus : Rtl433Decoder() {
    override val name = "Nexus, FreeTec NC-7345, NX-3980, Solight TE82S, TFA 30.3209 temperature/humidity sensor"
    override val mod = Mod.OOK_PPM
    override val short = 1000
    override val long = 2000
    override val gap = 3000
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(3, 36)
        if (r < 0) return emptyList()
        val b = bb.bb[r]
        if (bb.bitsPerRow[r] > 37) return emptyList()
        if ((b[3] and 0xf0) != 0xf0) return emptyList()
        if ((b[0] == 0 && b[2] == 0 && b[3] == 0) || (b[0] == 0xff && b[2] == 0xff && b[3] == 0xff)) return emptyList()
        if ((b[1] and 0x30) == 0x30) return emptyList()
        val crcIn = intArrayOf(b[0], b[1], b[2], b[3] and 0xf0, ((b[3] and 0x0f) shl 4) or ((b[4] and 0xf0) shr 4))
        if (Rtl433BitUtil.crc8(crcIn, 5, 0x31, 0x6c) == 0) return emptyList()
        val id = b[0]
        val battery = b[1] and 0x80
        val testmode = b[1] and 0x40
        val channel = ((b[1] and 0x30) shr 4) + 1
        val tempRaw = s16((b[1] shl 12) or (b[2] shl 4))
        val tempC = (tempRaw shr 4) * 0.1f
        val humidity = ((b[3] and 0x0F) shl 4) or (b[4] shr 4)
        if (humidity != 0x00 && humidity > 100) return emptyList()
        val fields = linkedMapOf<String, Any?>(
            "channel" to channel,
            "battery_ok" to (if (battery != 0) 1 else 0),
            "temperature_C" to tempC.toDouble(),
        )
        val model: String
        if (humidity == 0x00) {
            model = "Nexus-T"
        } else {
            model = "Nexus-TH"
            fields["humidity"] = humidity
        }
        if (testmode != 0) fields["test"] = 1
        return listOf(Reading(model, id.toString(), fields))
    }
}

// unverified: nexus.c:161-217, struct nexus.c:241
internal object NexusSauna : Rtl433Decoder() {
    override val name = "Nexus, CRX, Prego sauna temperature sensor"
    override val mod = Mod.OOK_PPM
    override val short = 1000
    override val long = 2000
    override val gap = 3000
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(3, 36)
        if (r < 0) return emptyList()
        val b = bb.bb[r]
        if (bb.bitsPerRow[r] > 37) return emptyList()
        if ((b[1] and 0xf) != 0xf) return emptyList()
        if (b[0] == 0 || (b[4] and 0x10) != 0x10 || (b[0] == 0xff && b[2] == 0xff && b[3] == 0xff)) return emptyList()
        if ((b[1] and 0x30) != 0x30) return emptyList()
        val id = b[0]
        val battery = b[1] and 0x80
        val testmode = b[1] and 0x40
        val channel = ((b[1] and 0x30) shr 4) + 1
        val tempRaw = s16((b[2] shl 8) or b[3])
        val tempC = tempRaw * 0.1f
        val fields = linkedMapOf<String, Any?>(
            "channel" to channel,
            "battery_ok" to (if (battery != 0) 1 else 0),
            "temperature_C" to tempC.toDouble(),
        )
        if (testmode != 0) fields["test"] = 1
        return listOf(Reading("Nexus-Sauna", id.toString(), fields))
    }
}

// unverified: nidec_car_remote.c:64-157, struct nidec_car_remote.c:159 (upstream disabled=1)
internal object NidecCarRemote : Rtl433Decoder() {
    override val name = "Nidec Car Remote (-f 313.8M -s 1024k)"
    override val mod = Mod.FSK_PWM
    override val short = 250
    override val long = 500
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 128) return emptyList()
        val offset = bb.search(0, 0, intArrayOf(0xff, 0xff, 0xff, 0xf0), 32) + 32
        if (bb.bitsPerRow[0] - offset < 56) return emptyList()
        var securityBits = bb.bitsPerRow[0] - offset - 48
        if (securityBits > 16) securityBits = 16
        bb.invert()
        val bytes = IntArray(8)
        bb.extractBytes(0, offset, bytes, 64)
        val sequence = (bytes[0] shl 8) or bytes[1]
        val id = (bytes[2] shl 16) or (bytes[3] shl 8) or bytes[4]
        val button = bytes[5] and 0xf
        val security = (bytes[6] shl 8) or bytes[7]
        if ((bytes[5] and 0xf0) != 0x50) return emptyList()
        if (id == 0 || sequence == 0 || id == 0xffffff || sequence == 0xffff || security == 0 || security == 0xffff) return emptyList()
        if (button != 0x3 && button != 0x4 && button != 0x5 && button != 0x6 && button != 0xf) return emptyList()
        val buttonStr = when (button) {
            0x3 -> "Lock"
            0x4 -> "Unlock"
            0x5 -> "Trunk/Panic Short Press"
            0x6 -> "Panic Long Press"
            0xf -> "Trunk Long Press"
            else -> "?"
        }
        return listOf(
            Reading(
                "Nidec-OUCG8D",
                String.format("%06X", id),
                mapOf(
                    "security" to String.format("%04X", security),
                    "security_bits" to securityBits,
                    "sequence" to sequence,
                    "button_code" to button,
                    "button_str" to buttonStr,
                ),
            ),
        )
    }
}

private val NORGO_CHECKSUM_TAPS = intArrayOf(
    0x4880, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x2080, 0x4000, 0x4000, 0x4000, 0x4000, 0x4000, 0x4000,
)

private fun norgoNextMask(mask: Int): Int {
    var nMask = (mask ushr 1) and 0xFFFF
    for (i in 0 until 15) {
        if ((mask and (1 shl i)) != 0) nMask = nMask xor NORGO_CHECKSUM_TAPS[i]
    }
    return nMask and 0xFFFF
}

private fun norgoCalcChecksum(data: IntArray, datalen: Int): Int {
    var mask = 0x0001
    var chks = 0
    var i = datalen - 1
    while (i > 7) {
        mask = norgoNextMask(mask)
        if (((data[i / 8] shr (i % 8)) and 1) != 0) chks = (chks xor mask) and 0xFFFF
        i--
    }
    return (chks shr 8) and 0xFF
}

// unverified: norgo.c:44-120 (taps/checksum), norgo.c:116-220 (decode), struct norgo.c:222 (bit_util reflect_bytes = reverse8)
internal object Norgo : Rtl433Decoder() {
    override val name = "Norgo NGE101"
    override val mod = Mod.OOK_DMC
    override val short = 486
    override val long = 972
    override val reset = 2100
    override val tolerance = 120

    override fun decode(bb: BitBuffer): List<Reading> {
        val bits = bb.bitsPerRow[0]
        if (bits != 56 && bits != 72 && bits != 55 && bits != 71) return emptyList()
        val b = bb.bb[0]
        if (b[0] != 0x05) return emptyList()
        val xorByte = Rtl433BitUtil.xorBytes(b.copyOfRange(1, b.size), (bits - 15) / 8)
        if (xorByte != 0xff) return emptyList()
        bb.invert()
        for (i in 0 until (bits + 1) / 8) b[i] = reverse8(b[i])
        val deviceId = ((b[1] and 0xF0) shr 4) or ((b[2] and 0x0f) shl 4)
        val channel = ((b[1] and 0x0e) shr 1) + 1
        if ((b[1] and 0x1) == 0) {
            val calcChk = norgoCalcChecksum(b, 5 * 8)
            if (calcChk != b[6]) return emptyList()
            val impulseGap = (b[2] shr 4) or (b[3] shl 4) or ((b[4] and 0x7F) shl 12)
            return listOf(
                Reading(
                    "Norgo-NGE101",
                    deviceId.toString(),
                    mapOf("channel" to channel, "gap" to impulseGap, "mic" to "CRC"),
                ),
            )
        }
        val calcChk = norgoCalcChecksum(b, 7 * 8)
        if (calcChk != b[8]) return emptyList()
        val impulses = (b[2] shr 4).toLong() or (b[3] shl 4).toLong() or (b[4] shl 12).toLong() or
            (b[5] shl 20).toLong() or ((b[6].toLong() and 0x3F) shl 28)
        val lowBattery = (b[6] and 0x40) shr 6
        return listOf(
            Reading(
                "Norgo-NGE101",
                deviceId.toString(),
                mapOf(
                    "channel" to channel,
                    "impulses" to (impulses and 0xFFFFFFFFL),
                    "battery_ok" to (if (lowBattery != 0) 0 else 1),
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

private val NEPTUNE_MAP16TO6 = intArrayOf(-1, -1, -1, 0, -1, 1, 2, -1, -1, 5, 4, -1, 3, -1, -1, -1)

private fun neptuneR900Common(bb: BitBuffer, isBcd: Boolean): List<Reading> {
    val preamble = intArrayOf(0x55, 0x55, 0x55, 0xa9, 0x66, 0x69, 0x65)
    val preambleLength = preamble.size * 8
    if (bb.numRows != 1) return emptyList()
    val startPos = bb.search(0, 0, preamble, preambleLength)
    if (startPos + preambleLength + 168 > bb.bitsPerRow[0]) return emptyList()
    if (startPos == bb.bitsPerRow[0]) return emptyList()
    val row = bb.bb[0]
    val base6 = IntArray(21)
    var count = 0
    var k = startPos + preambleLength
    while (k < startPos + preambleLength + 168) {
        val byte = bitrowGetByte(row, k)
        val highNibble = NEPTUNE_MAP16TO6[(byte shr 4) and 0xF]
        val lowNibble = NEPTUNE_MAP16TO6[byte and 0xF]
        if (highNibble < 0 || lowNibble < 0) return emptyList()
        base6[count] = (6 * highNibble) + lowNibble
        count++
        k += 8
    }
    val bytes = BitBuffer()
    for (i in 0 until 21) {
        val data = base6[i]
        bytes.addBit((data shr 4) and 0x01)
        bytes.addBit((data shr 3) and 0x01)
        bytes.addBit((data shr 2) and 0x01)
        bytes.addBit((data shr 1) and 0x01)
        bytes.addBit(data and 0x01)
    }
    val b = IntArray(13)
    bytes.extractBytes(0, 0, b, 104)
    val meterId = (b[0].toLong() shl 24) or (b[1].toLong() shl 16) or (b[2].toLong() shl 8) or b[3].toLong()
    val unkn1 = b[4] shr 4
    val metertype = b[4] and 0x0F
    val unkn2 = b[5] shr 5
    val nouse = ((b[5] shr 1) and 0x0F) shr 1
    val backflow = b[5] and 0x03
    var consumption = ((b[9] shr 5) shl 24) or (b[6] shl 16) or (b[7] shl 8) or b[8]
    if (isBcd) {
        var bcd = 0
        for (i in 5 downTo 0) {
            val digit = (consumption shr (4 * i)) and 0x0F
            if (digit > 9) return emptyList()
            bcd = bcd * 10 + digit
        }
        consumption = bcd
    }
    val leak = ((b[9] shr 1) and 0x0F) shr 1
    val leakNow = b[9] and 0x03
    val extra = String.format("%02x%02x%02x", b[10], b[11], b[12])
    return listOf(
        Reading(
            if (isBcd) "Neptune-R900BCD" else "Neptune-R900",
            meterId.toString(),
            mapOf(
                "unkn1" to unkn1,
                "metertype" to metertype,
                "unkn2" to unkn2,
                "nouse" to nouse,
                "backflow" to backflow,
                "consumption" to consumption,
                "leak" to leak,
                "leaknow" to leakNow,
                "extra" to extra,
            ),
        ),
    )
}

// unverified: neptune_r900.c:93-239 (common), neptune_r900.c:241-248 (binary), struct neptune_r900.c:281
internal object NeptuneR900 : Rtl433Decoder() {
    override val name = "Neptune R900 flow meters"
    override val mod = Mod.OOK_PCM
    override val short = 30
    override val long = 30
    override val reset = 320

    override fun decode(bb: BitBuffer): List<Reading> = neptuneR900Common(bb, false)
}

// unverified: neptune_r900.c:250-279 (bcd), struct neptune_r900.c:291 (upstream disabled=1, overlaps Neptune-R900)
internal object NeptuneR900bcd : Rtl433Decoder() {
    override val name = "Neptune R900 BCD flow meters"
    override val mod = Mod.OOK_PCM
    override val short = 30
    override val long = 30
    override val reset = 320

    override fun decode(bb: BitBuffer): List<Reading> = neptuneR900Common(bb, true)
}

// unverified: oil_smart.c:86-166 (decode), oil_smart.c:168-198 (callback), struct oil_smart.c:200
internal object OilSmart : Rtl433Decoder() {
    override val name = "Oil Ultrasonic SMART FSK"
    override val mod = Mod.FSK_PCM
    override val short = 500
    override val long = 500
    override val gap = 2000
    override val reset = 9000

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val databits = BitBuffer()
        bb.manchesterDecode(row, bitpos, databits, 64)
        if (databits.bitsPerRow[0] < 64) return null
        val b = databits.bb[0]
        if (Rtl433BitUtil.crc8le(b, 8, 0x31, 0x00) != 0) return null
        val unitId = (b[0].toLong() shl 24) or (b[1].toLong() shl 16) or (b[2].toLong() shl 8) or b[3].toLong()
        val txstatus = if ((b[4] and 0x40) != 0) "Rapid" else "Normal"
        val tempOk = if ((b[4] and 0x10) == (b[4] and 0x20)) 0 else 1
        val battery = (b[4] and 0x04) shr 2
        val sensor = b[4] and 0x03
        val counter = (b[5] and 0xf0) shr 4
        val unknown = (b[5] and 0x0d) shr 1
        val depth = ((b[5] and 0x01) shl 8) + b[6]
        return Reading(
            "Oil-Ultrasonic",
            String.format("%08x", unitId),
            mapOf(
                "depth_cm" to depth,
                "txstatus" to txstatus,
                "temp_ok" to tempOk,
                "battery_ok" to battery,
                "sensor" to sensor,
                "counter" to counter,
                "unknown" to unknown,
                "mic" to "CRC",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0x55, 0x58), 16)
            if (bitpos + 128 > bb.bitsPerRow[0]) break
            decodeAt(bb, 0, bitpos + 16)?.let { out.add(it) }
            bitpos += 2
        }
        return out
    }
}

// unverified: netatmo_thw.c:116-251; struct netatmo_thw.c:253 sets short_width=8.5 and long_width=8.5 (non-integer), which the frozen Int API cannot carry; widths left at 0 so the slicer ignores them
internal object NetatmoThw : Rtl433Decoder() {
    override val name = "NetAtmo temp/hum and wind sensors"
    override val mod = Mod.FSK_PCM
    override val reset = 800

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val rowBits = bb.bitsPerRow[0]
        val preamble = intArrayOf(0xaa, 0xaa, 0xe7, 0x12)
        val startPos = bb.search(0, 0, preamble, 32)
        if (startPos >= rowBits) return emptyList()
        val lenBuf = IntArray(1)
        bb.extractBytes(0, startPos + 32, lenBuf, 8)
        val len = lenBuf[0]
        if (startPos + 32 + (len + 2) * 8 > rowBits) return emptyList()
        val frame = IntArray(len + 3)
        frame[0] = len
        val body = IntArray(len + 2)
        bb.extractBytes(0, startPos + 40, body, (len + 2) * 8)
        for (i in body.indices) frame[i + 1] = body[i]
        val crc = Rtl433BitUtil.crc16(frame, len + 1, 0x8005, 0xffff)
        if (((frame[len + 1] shl 8) or frame[len + 2]) != crc) return emptyList()
        val b = frame
        val id = String.format("%08x", (b[1] shl 24) or (b[2] shl 16) or (b[3] shl 8) or b[4])
        val signal = b[6].toByte().toInt()
        return when (len) {
            6 -> listOf(Reading("NetAtmo-TH", id, mapOf(
                "signal_dB" to signal,
                "mic" to "CRC",
            )))
            0x19 -> {
                val batteryMv = (b[8] * 256 + b[7]) * 2
                val tempRaw = s16((b[23] shl 8) or b[22])
                val tempC = tempRaw * 0.1f
                listOf(Reading("NetAtmo-TH", id, mapOf(
                    "battery_mV" to batteryMv,
                    "signal_dB" to signal,
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to b[25],
                    "mic" to "CRC",
                )))
            }
            0x31 -> {
                val batteryMv = b[8] * 256 + b[7]
                val rawA = s16((b[26] shl 8) or b[25])
                val rawB = s16((b[28] shl 8) or b[27])
                val rawC = s16((b[30] shl 8) or b[29])
                val rawD = s16((b[32] shl 8) or b[31])
                val ws315 = rawA + rawB
                val ws45 = rawC + rawD
                val windSpeed = Math.sqrt((ws45 * ws45 + ws315 * ws315).toFloat().toDouble()).toFloat() * 0.05f
                val windDir = (Math.atan2(ws45.toFloat().toDouble(), ws315.toFloat().toDouble()).toFloat() / Math.PI.toFloat() * 180 + 315).toInt() % 360
                listOf(Reading("NetAtmo-Wind", id, mapOf(
                    "battery_mV" to batteryMv,
                    "signal_dB" to signal,
                    "raw_a_315" to rawA,
                    "raw_b_315" to rawB,
                    "raw_c_045" to rawC,
                    "raw_d_045" to rawD,
                    "wind_spd_km_h" to windSpeed.toDouble(),
                    "wind_dir_deg" to windDir,
                    "mic" to "CRC",
                )))
            }
            else -> listOf(Reading("NetAtmo-THW", id, mapOf(
                "signal_dB" to signal,
                "mic" to "CRC",
            )))
        }
    }
}

private const val MBUS_BLOCK1A = 12
private const val MBUS_BLOCK1B = 10
private const val MBUS_BLOCK2B = 118
private const val MBUS_BUF = 640

private class MBusData {
    var length = 0
    val data = IntArray(MBUS_BUF)
}

private class MBusBlock2 {
    var ci = 0
    var ac = 0
    var st = 0
    var cw = 0
    var plOffset = 0
    var ellCi = 0
    var ellCc = 0
    var ellAcc = 0
    var ellSecMode = 0
    var knxCtrl = 0
    var src = 0
    var dst = 0
    var lNpci = 0
    var tpci = 0
    var apci = 0
}

private class MBusBlock1 {
    var l = 0
    var c = 0
    var mStr = ""
    var aId = 0
    var aVersion = 0
    var aDevType = 0
    var knx = false
    val knxSn = IntArray(6)
    val block2 = MBusBlock2()
}

private fun mbusBcd2int(bcd: Int): Int = 10 * (bcd shr 4) + (bcd and 0xf)

private fun mbusRowByte(bb: BitBuffer, pos: Int): Int {
    val t = IntArray(2)
    bb.extractBytes(0, pos, t, 8)
    return t[0]
}

private fun mbus3of6(v: Int): Int = when (v) {
    22 -> 0x00
    13 -> 0x01
    14 -> 0x02
    11 -> 0x03
    28 -> 0x04
    25 -> 0x05
    26 -> 0x06
    19 -> 0x07
    44 -> 0x08
    37 -> 0x09
    38 -> 0x0A
    35 -> 0x0B
    52 -> 0x0C
    49 -> 0x0D
    50 -> 0x0E
    41 -> 0x0F
    else -> 0xF0
}

private fun mbusDecode3of6(bb: BitBuffer, bitOffset: Int, out: IntArray, numBytes: Int) {
    for (n in 0 until numBytes) {
        val h = mbus3of6(mbusRowByte(bb, n * 12 + bitOffset) shr 2)
        var l = mbus3of6(mbusRowByte(bb, n * 12 + bitOffset + 6) shr 2)
        if (h > 0xf || l > 0xf) l = l and 0x0F
        out[n] = ((h shl 4) or l) and 0xFF
    }
}

private fun mbusCrcValid(b: IntArray, off: Int, n: Int): Boolean {
    val sub = b.copyOfRange(off, off + n + 2)
    val calc = Rtl433BitUtil.crc16(sub, n, 0x3D65, 0).inv() and 0xFFFF
    val read = (sub[n] shl 8) or sub[n + 1]
    return calc == read
}

private fun mbusManufDecode(m: Int): String {
    val sb = StringBuilder()
    sb.append((((m shr 10) and 0x1F) + 0x40).toChar())
    sb.append((((m shr 5) and 0x1F) + 0x40).toChar())
    sb.append(((m and 0x1F) + 0x40).toChar())
    return sb.toString()
}

private fun mbusDeviceTypeStr(t: Int): String = when (t) {
    0x00 -> "Other"
    0x01 -> "Oil"
    0x02 -> "Electricity"
    0x03 -> "Gas"
    0x04 -> "Heat"
    0x05 -> "Steam"
    0x06 -> "Warm Water"
    0x07 -> "Water"
    0x08 -> "Heat Cost Allocator"
    0x09 -> "Compressed Air"
    0x0A, 0x0B -> "Cooling load meter"
    0x0C -> "Heat"
    0x0D -> "Heat/Cooling load meter"
    0x0E -> "Bus/System component"
    0x0F -> "Unknown"
    0x15 -> "Hot Water"
    0x16 -> "Cold Water"
    0x17 -> "Hot/Cold Water meter"
    0x18 -> "Pressure"
    0x19 -> "A/D Converter"
    0x1A -> "Smoke detector"
    0x1B -> "Room sensor"
    0x1C -> "Gas detector"
    0x20 -> "Breaker (electricity)"
    0x21 -> "Valve (gas or water)"
    0x28 -> "Waste water meter"
    0x29 -> "Garbage"
    0x2A -> "Carbon dioxide"
    0x25 -> "Customer unit (display device)"
    0x31 -> "Communication controller"
    0x32 -> "Unidirectional repeater"
    0x33 -> "Bidirectional repeater"
    0x36 -> "Radio converter (system side)"
    0x37 -> "Radio converter (meter side)"
    else -> ""
}

private fun mbusEllLen(ci: Int): Int = when (ci) {
    0x8C -> 2
    0x8D -> 8
    0x8E -> 10
    0x8F -> 16
    else -> -1
}

private fun mbusParseCi(d: IntArray, base: Int, remaining: Int, plBase: Int, b2: MBusBlock2) {
    if (remaining < 1) return
    b2.ci = d[base]
    val ellLen = mbusEllLen(b2.ci)
    if (ellLen >= 0) {
        if (remaining < 1 + ellLen) return
        b2.ellCi = d[base]
        b2.ellCc = d[base + 1]
        b2.ellAcc = d[base + 2]
        if (b2.ci == 0x8D || b2.ci == 0x8F) {
            val snOff = if (b2.ci == 0x8F) 11 else 3
            val sn = d[base + snOff] or (d[base + snOff + 1] shl 8) or (d[base + snOff + 2] shl 16) or (d[base + snOff + 3] shl 24)
            b2.ellSecMode = (sn ushr 29) and 0x7
        } else {
            b2.ellSecMode = 0
        }
        if (b2.ellSecMode != 0) return
        mbusParseCi(d, base + 1 + ellLen, remaining - 1 - ellLen, plBase + 1 + ellLen, b2)
        return
    }
    if (b2.ci == 0x90) {
        if (remaining < 2) return
        val aflLen = d[base + 1]
        if (remaining < 2 + aflLen) return
        mbusParseCi(d, base + 2 + aflLen, remaining - 2 - aflLen, plBase + 2 + aflLen, b2)
        return
    }
    if (b2.ci == 0x7A) {
        b2.ac = d[base + 1]
        b2.st = d[base + 2]
        b2.cw = (d[base + 4] shl 8) or d[base + 3]
        b2.plOffset = plBase + 5
    } else if (b2.ci == 0x72) {
        b2.ac = d[base + 9]
        b2.st = d[base + 10]
        b2.cw = (d[base + 12] shl 8) or d[base + 11]
        b2.plOffset = plBase + 13
    } else if (b2.ci == 0x78) {
        b2.plOffset = plBase + 1
    }
    if (b2.ci == 0x78 && d[base + 1] == 0x0d && d[base + 2] == 0xff && d[base + 3] == 0x5f && d[base + 4] == 0x35) {
        b2.ac = d[base + 7]
        b2.st = d[base + 5]
        b2.cw = (d[base + 9] shl 8) or d[base + 8]
        b2.plOffset = plBase + 1
    }
}

private fun mbusParseBlock2(inp: MBusData, b1: MBusBlock1, block1Size: Int, plBase: Int) {
    val b2 = b1.block2
    val d = inp.data
    if (b1.knx) {
        b2.knxCtrl = d[block1Size]
        b2.src = (d[block1Size + 1] shl 8) or d[block1Size + 2]
        b2.dst = (d[block1Size + 3] shl 8) or d[block1Size + 4]
        b2.lNpci = d[block1Size + 5]
        b2.tpci = d[block1Size + 6]
        b2.apci = d[block1Size + 7]
    } else {
        val remaining = if (inp.length > block1Size) inp.length - block1Size else 0
        mbusParseCi(d, block1Size, remaining, plBase, b2)
    }
}

private fun mbusDecodeFormatA(inp: MBusData, out: MBusData, b1: MBusBlock1): Boolean {
    val d = inp.data
    b1.l = d[0]
    b1.c = d[1]
    if (d[2] == 0xFF && d[3] == 0x03) {
        b1.knx = true
        for (i in 0 until 6) b1.knxSn[i] = d[4 + i]
    } else {
        b1.mStr = mbusManufDecode((d[3] shl 8) or d[2])
        b1.aId = mbusBcd2int(d[7]) * 1000000 + mbusBcd2int(d[6]) * 10000 + mbusBcd2int(d[5]) * 100 + mbusBcd2int(d[4])
        b1.aVersion = d[8]
        b1.aDevType = d[9]
    }
    out.length = b1.l - 9 + MBUS_BLOCK1A - 2
    if (!mbusCrcValid(d, 0, 10)) return false
    if (b1.l < 9) return false
    val numDataBlocks = (b1.l - 9 + 15) / 16
    val avail = if (inp.length >= MBUS_BLOCK1A) inp.length - MBUS_BLOCK1A else Int.MAX_VALUE
    if ((b1.l - 9) + numDataBlocks * 2 > avail) return false
    for (i in 0 until MBUS_BLOCK1A - 2) out.data[i] = d[i]
    for (n in 0 until numDataBlocks) {
        val inPtr = MBUS_BLOCK1A + n * 18
        val outPtr = n * 16 + MBUS_BLOCK1A - 2
        val blockSize = minOf(b1.l - 9 - n * 16, 16) + 2
        if (!mbusCrcValid(d, inPtr, blockSize - 2)) return false
        for (i in 0 until blockSize) out.data[outPtr + i] = d[inPtr + i]
    }
    mbusParseBlock2(inp, b1, MBUS_BLOCK1A, MBUS_BLOCK1A - 2)
    return true
}

private fun mbusDecodeFormatB(inp: MBusData, out: MBusData, b1: MBusBlock1): Boolean {
    val d = inp.data
    b1.l = d[0]
    b1.c = d[1]
    b1.mStr = mbusManufDecode((d[3] shl 8) or d[2])
    b1.aId = mbusBcd2int(d[7]) * 1000000 + mbusBcd2int(d[6]) * 10000 + mbusBcd2int(d[5]) * 100 + mbusBcd2int(d[4])
    b1.aVersion = d[8]
    b1.aDevType = d[9]
    out.length = b1.l - (9 + 2) + MBUS_BLOCK1B - 2
    if (b1.l < 12 || b1.l + 1 > inp.length) return false
    if (!mbusCrcValid(d, 0, minOf(b1.l - 1, (MBUS_BLOCK1B + MBUS_BLOCK2B) - 2))) return false
    val first = minOf(b1.l - 11, MBUS_BLOCK2B - 2) + MBUS_BLOCK1B
    for (i in 0 until first) out.data[i] = d[i]
    val lOffset = MBUS_BLOCK1B + MBUS_BLOCK2B - 1
    if (b1.l > lOffset + 2) {
        if (!mbusCrcValid(d, MBUS_BLOCK1B + MBUS_BLOCK2B, b1.l - lOffset - 2)) return false
        for (i in 0 until b1.l - lOffset - 2) out.data[(MBUS_BLOCK2B - 2) + i] = d[MBUS_BLOCK2B + i]
        out.length -= 2
    }
    out.length += 2
    mbusParseBlock2(inp, b1, MBUS_BLOCK1B, MBUS_BLOCK1B)
    return true
}

private fun mbusOutput(out: MBusData, b1: MBusBlock1, mode: String): List<Reading> {
    val b2 = b1.block2
    val f = LinkedHashMap<String, Any?>()
    val model: String
    val id: String
    if (b1.knx) {
        val sn = b1.knxSn.joinToString("") { "%02x".format(it) }
        model = "KNX-RF"
        id = sn
        f["sn"] = sn
        f["knx_ctrl"] = "0x%02X".format(b2.knxCtrl)
        f["src"] = "0x%04X".format(b2.src)
        f["dst"] = "0x%04X".format(b2.dst)
        f["l_npci"] = "0x%02X".format(b2.lNpci)
        f["tpci"] = "0x%02X".format(b2.tpci)
        f["apci"] = "0x%02X".format(b2.apci)
    } else {
        model = "Wireless-MBus"
        id = b1.aId.toString()
        f["mode"] = mode
        f["M"] = b1.mStr
        f["id"] = b1.aId
        f["version"] = b1.aVersion
        f["type"] = "0x%02X".format(b1.aDevType)
        f["type_string"] = mbusDeviceTypeStr(b1.aDevType)
        f["C"] = "0x%02X".format(b1.c)
    }
    f["data"] = (0 until out.length.coerceIn(0, out.data.size)).joinToString("") { "%02x".format(out.data[it]) }
    if (b2.ellCi != 0) {
        f["ell_ci"] = "0x%02X".format(b2.ellCi)
        f["ell_cc"] = "0x%02X".format(b2.ellCc)
        f["ell_acc"] = "0x%02X".format(b2.ellAcc)
    }
    if (b2.ci != 0 && b2.ci != b2.ellCi) {
        f["CI"] = "0x%02X".format(b2.ci)
        if (b2.plOffset != 0) {
            f["AC"] = "0x%02X".format(b2.ac)
            f["ST"] = "0x%02X".format(b2.st)
            f["CW"] = "0x%04X".format(b2.cw)
        }
    }
    if (!b1.knx && b2.plOffset == 0) {
        if (b2.ellCi != 0 && b2.ellSecMode != 0) f["payload_encrypted"] = 1
    } else if ((b2.cw and 0x0500) != 0) {
        f["payload_encrypted"] = 1
    }
    f["mic"] = "CRC"
    return listOf(Reading(model, id, f))
}

private fun mbusDecodeCT(bb: BitBuffer): List<Reading> {
    val bits = bb.bitsPerRow[0]
    if (bits < 32 + 13 * 8 || bits > 64 + 256 * 12) return emptyList()
    var off = bb.search(0, 0, intArrayOf(0x54, 0x3D), 16)
    if (off + 13 * 8 >= bits) return emptyList()
    off += 16
    var next = mbusRowByte(bb, off)
    off += 8
    val inp = MBusData()
    val out = MBusData()
    val b1 = MBusBlock1()
    val mode: String
    if (next == 0x54) {
        mode = "C"
        next = mbusRowByte(bb, off)
        off += 8
        if (next == 0xCD) {
            inp.length = (bits - off) / 8
            bb.extractBytes(0, off, inp.data, inp.length * 8)
            if (!mbusDecodeFormatA(inp, out, b1)) return emptyList()
        } else if (next == 0x3D) {
            inp.length = (bits - off) / 8
            bb.extractBytes(0, off, inp.data, inp.length * 8)
            if (!mbusDecodeFormatB(inp, out, b1)) return emptyList()
        } else {
            return emptyList()
        }
    } else {
        mode = "T"
        off -= 8
        inp.length = (bits - off) / 12
        mbusDecode3of6(bb, off, inp.data, inp.length)
        if (!mbusDecodeFormatA(inp, out, b1)) return emptyList()
    }
    return mbusOutput(out, b1, mode)
}

private fun mbusDecodeR(bb: BitBuffer): List<Reading> {
    val bits = bb.bitsPerRow[0]
    if (bits < 32 + 13 * 8 || bits > 64 + 256 * 8) return emptyList()
    var off = bb.search(0, 0, intArrayOf(0x55, 0x54, 0x76, 0x96), 32)
    if (off + 13 * 8 >= bits) return emptyList()
    off += 32
    val inp = MBusData()
    val out = MBusData()
    val b1 = MBusBlock1()
    inp.length = (bits - off) / 8
    bb.extractBytes(0, off, inp.data, inp.length * 8)
    if (!mbusDecodeFormatA(inp, out, b1)) return emptyList()
    return mbusOutput(out, b1, "R")
}

private fun mbusDecodeS(bb: BitBuffer): List<Reading> {
    val bits = bb.bitsPerRow[0]
    if (bits < 32 + 13 * 8 || bits > 64 + 256 * 8) return emptyList()
    val offset = bb.search(0, 0, intArrayOf(0xaa, 0xab, 0x32), 24) + 24
    if (offset < bits) {
        bb.invert()
        return emptyList()
    }
    var off = bb.search(0, 0, intArrayOf(0x54, 0x76, 0x96), 24)
    off += 24
    if (off >= bits) return emptyList()
    val packet = BitBuffer()
    bb.manchesterDecode(0, off, packet, 800)
    val inp = MBusData()
    val out = MBusData()
    val b1 = MBusBlock1()
    inp.length = bits
    packet.extractBytes(0, 0, inp.data, inp.length)
    if (!mbusDecodeFormatA(inp, out, b1)) return emptyList()
    return mbusOutput(out, b1, "S")
}

internal object MBusModeCT : Rtl433Decoder() {
    override val name = "Wireless M-Bus, Mode C&T, 100kbps (-f 868.95M -s 1200k)"
    override val mod = Mod.FSK_PCM
    override val short = 10
    override val long = 10
    override val reset = 500

    override fun decode(bb: BitBuffer): List<Reading> = mbusDecodeCT(bb)
}

internal object MBusModeCTDownlink : Rtl433Decoder() {
    override val name = "Wireless M-Bus, Mode T, 32.768kbps (-f 868.3M -s 1000k)"
    override val mod = Mod.FSK_PCM

    override fun decode(bb: BitBuffer): List<Reading> = mbusDecodeCT(bb)
}

// unverified: not ported - m_bus.c:1558-1566 struct (FSK_PCM, width 1000/2.4 us non-integer, left at 0; upstream disabled=1), decoder body in m_bus.c not transcribed this batch
internal object MBusModeF : Rtl433Decoder() {
    override val name = "Wireless M-Bus, Mode F, 2.4kbps"
    override val mod = Mod.FSK_PCM
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

internal object MBusModeR : Rtl433Decoder() {
    override val name = "Wireless M-Bus, Mode R, 4.8kbps (-f 868.33M)"
    override val mod = Mod.FSK_MC_ZEROBIT

    override fun decode(bb: BitBuffer): List<Reading> = mbusDecodeR(bb)
}

internal object MBusModeS : Rtl433Decoder() {
    override val name = "Wireless M-Bus, Mode S, 32.768kbps (-f 868.3M -s 1000k)"
    override val mod = Mod.FSK_PCM

    override fun decode(bb: BitBuffer): List<Reading> = mbusDecodeS(bb)
}

internal val BATCH_05: List<Rtl433Decoder> = listOf(
    LacrosseTx31u,
    LacrosseTx34,
    LacrosseTx35,
    LacrosseWr1,
    LacrosseWs6868Tx231rw,
    LacrosseWs6868Tx232th,
    LacrosseWs7000,
    Lacrossetx,
    Lacrossews,
    LightwaveRf,
    MBusModeCT,
    MBusModeCTDownlink,
    MBusModeF,
    MBusModeR,
    MBusModeS,
    Markisol,
    MarlecSolar,
    MartecMplcd,
    MaverickEt73,
    MaverickEt73x,
    MaverickXr30,
    MaverickXr50,
    McpowerKinetic,
    Mebus433,
    Megacode,
    MissilMl0757,
    MuellerHotrod,
    NeptuneR900,
    NeptuneR900bcd,
    NetatmoThw,
    Newkaku,
    Nexa,
    Nexus,
    NexusSauna,
    NiceFlorS,
    NidecCarRemote,
    Norgo,
    OilSmart,
)

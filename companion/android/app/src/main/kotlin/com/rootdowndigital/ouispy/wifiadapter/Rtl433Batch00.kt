// Kotlin transcription of rtl_433 device decoders (batch 00). GPL-3 reference; constants, bit offsets and CRC parameters transcribed as facts.
package com.rootdowndigital.ouispy.wifiadapter

private fun rv8(x: Int): Int {
    var v = x and 0xFF
    v = ((v and 0xF0) shr 4) or ((v and 0x0F) shl 4)
    v = ((v and 0xCC) shr 2) or ((v and 0x33) shl 2)
    v = ((v and 0xAA) shr 1) or ((v and 0x55) shl 1)
    return v and 0xFF
}

private fun reflectRev(b: IntArray, n: Int) {
    for (i in 0 until n) b[i] = rv8(b[i])
}

private fun bcdInt(x: Int): Int = 10 * (x shr 4) + (x and 0xF)

private fun bcdDec8(x: Int): Int = ((x and 0xF0) shr 4) * 10 + (x and 0x0F)

private fun s16(x: Int): Int = x.toShort().toInt()

private fun alectoChk(b: IntArray): Boolean {
    var csum = 0
    for (i in 0 until 4) {
        val tmp = rv8(b[i])
        csum += (tmp and 0xf) + ((tmp and 0xf0) shr 4)
    }
    csum = if ((b[1] and 0x7f) == 0x6c) csum + 0x7 else 0xf - csum
    csum = rv8((csum and 0xf) shl 4)
    return csum == (b[4] shr 4)
}

private fun tx8300Chk(b: IntArray): Int {
    var x = 0
    var y = 0
    for (i in 0 until 4) {
        x += (b[i] and 0xF) + ((b[i] and 0xF0) shr 4)
        y += (b[i] and 0x5) + ((b[i] and 0x50) shr 4)
    }
    val c0 = (x and 0xF).inv() and 0xF
    val c1 = (y and 0xF).inv() and 0xF
    return (c0 shl 4) or c1
}

private fun lsrcFrame(frame: IntArray, len: Int): Int {
    var result = 0
    var key = 0xEC
    for (i in 0 until len) {
        val byte = frame[i]
        var mask = 0x80
        while (mask > 0) {
            if ((byte and mask) != 0) result = result xor key
            key = if ((key and 1) != 0) ((key shr 1) xor 0x83) else (key shr 1)
            mask = mask shr 1
        }
    }
    return result
}

private val APATOR_WHITEN = intArrayOf(
    0xff, 0xe1, 0x1d, 0x9a, 0xed, 0x85, 0x33, 0x24, 0xea, 0x7a, 0xd2,
    0x39, 0x70, 0x97, 0x57, 0x0a, 0x54, 0x7d, 0x2d, 0xd8, 0x6d, 0x0d,
)

private val APATOR_NIBBLE = intArrayOf(0x0, 0x7, 0xf, 0x9, 0xe, 0xd, 0x3, 0x4, 0x2, 0x6, 0xc, 0xb, 0x1, 0x8, 0xa, 0x5)

private fun apatorPayload(bb: BitBuffer, expectLen: Int, maxLen: Int): IntArray? {
    if (bb.numRows != 1) return null
    val start = bb.search(0, 0, intArrayOf(0xaa, 0xaa, 0x69, 0x9a), 32)
    if (start == bb.bitsPerRow[0]) return null
    val lenBuf = IntArray(1)
    bb.extractBytes(0, start + 32, lenBuf, 8)
    val len = lenBuf[0] xor 0xff
    if (len != expectLen) return null
    val frame = IntArray(maxLen)
    bb.extractBytes(0, start + 32, frame, 8 * maxLen)
    for (i in 0 until len + 3) frame[i] = frame[i] xor APATOR_WHITEN[i]
    val frameCrc = (frame[len + 1] shl 8) or frame[len + 2]
    if (frameCrc != Rtl433BitUtil.crc16(frame, len + 1, 0x8005, 0xffff)) return null
    val p = IntArray(maxLen)
    for (i in 0 until 2 * len) {
        val shift = if (i % 2 != 0) 0 else 4
        val nibEncr = (frame[1 + i / 2] shr shift) and 0x0f
        p[i / 2] = p[i / 2] or (APATOR_NIBBLE[nibEncr] shl shift)
    }
    return p
}

// unverified: abmt.c:38-81, struct abmt.c:90
internal object Abmt : Rtl433Decoder() {
    override val name = "Amazon Basics Meat Thermometer"
    override val mod = Mod.OOK_PCM
    override val short = 550
    override val long = 550
    override val gap = 2000
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(4, 90)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] > 120) return emptyList()
        val bitpos = bb.search(row, 0, intArrayOf(0x55, 0xAA, 0xAA), 24)
        if (bitpos == bb.bitsPerRow[row] || bitpos < 72) return emptyList()
        val packet = BitBuffer()
        bb.manchesterDecode(row, bitpos - 72, packet, 48)
        packet.invert()
        val b = packet.bb[0]
        val id = b[0]
        val temp = bcdInt(b[3]) * 10 + bcdInt(b[4] shr 4)
        return listOf(Reading("Basics-Meat", id.toString(), mapOf("temperature_C" to temp.toDouble())))
    }
}

// unverified: acurite.c:2039-2122, struct acurite.c:2330
internal object Acurite00275rm : Rtl433Decoder() {
    override val name = "Acurite 00275rm,00276rm Temp/Humidity with optional probe"
    override val mod = Mod.OOK_PWM
    override val short = 232
    override val long = 420
    override val gap = 520
    override val reset = 708
    override val sync = 632

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val rows = ArrayList<IntArray>()
        for (row in 0 until bb.numRows) {
            if (rows.size < 3 && bb.bitsPerRow[row] == 88) rows.add(bb.bb[row])
        }
        if (rows.size == 3) {
            bb.addRow()
            val combined = bb.bb[bb.numRows - 1]
            for (i in 0 until 11) {
                combined[i] = (rows[0][i] and rows[1][i]) or (rows[1][i] and rows[2][i]) or (rows[2][i] and rows[0][i])
            }
            bb.bitsPerRow[bb.numRows - 1] = 88
        }
        for (row in 0 until bb.numRows) {
            if (bb.bitsPerRow[row] != 88) continue
            val b = bb.bb[row]
            if (Rtl433BitUtil.crc16lsb(b, 11, 0x00b2, 0x00d0) != 0) continue
            val id = (b[0] shl 16) or (b[1] shl 8) or b[3]
            val batteryLow = (b[2] and 0x40) == 0
            val modelFlag = b[2] and 1
            val tempRaw = (b[4] shl 4) or (b[5] shr 4)
            val tempc = (tempRaw - 1000) * 0.1f
            val probe = b[5] and 3
            val humidity = ((b[6] and 0x1f) shl 2) or (b[7] shr 6)
            val water = if ((b[7] and 0x0f) == 15) 1 else 0
            val ptempRaw = ((b[7] and 0x0f) shl 8) or b[8]
            val ptempc = (ptempRaw - 1000) * 0.1f
            val phumidity = b[9] and 0x7f
            val fields = linkedMapOf<String, Any?>(
                "subtype" to probe,
                "battery_ok" to (if (batteryLow) 0 else 1),
                "temperature_C" to tempc.toDouble(),
                "humidity" to humidity,
            )
            if (probe == 1) fields["water"] = water
            if (probe == 2 || probe == 3) fields["temperature_1_C"] = ptempc.toDouble()
            if (probe == 3) fields["humidity_1"] = phumidity
            val model = if (modelFlag != 0) "Acurite-00275rm" else "Acurite-00276rm"
            return listOf(Reading(model, id.toString(), fields))
        }
        return emptyList()
    }
}

// unverified: acurite_01185m.c:54-115, struct acurite_01185m.c:128
internal object Acurite01185m : Rtl433Decoder() {
    override val name = "Acurite Grill/Meat Thermometer 01185M"
    override val mod = Mod.OOK_PWM
    override val short = 840
    override val long = 2070
    override val sync = 6600
    override val gap = 3000
    override val reset = 6000

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        for (row in 0 until bb.numRows) {
            if (bb.bitsPerRow[row] != 56) continue
            val b = bb.bb[row]
            reflectRev(b, 7)
            val sum = Rtl433BitUtil.addBytes(b, 6)
            if ((sum and 0xff) != b[6]) continue
            if (sum == 0) return emptyList()
            val id = b[0]
            val battLow = b[1] shr 7
            val channel = b[1] and 0x0f
            val temp1Raw = (b[2] shl 8) or b[3]
            val temp2Raw = (b[4] shl 8) or b[5]
            val temp1Ok = temp1Raw > 200 && temp1Raw < 7000
            val temp2Ok = temp2Raw > 200 && temp2Raw < 7000
            val temp1f = (temp1Raw - 900) * 0.1f
            val temp2f = (temp2Raw - 900) * 0.1f
            val fields = linkedMapOf<String, Any?>(
                "channel" to channel,
                "battery_ok" to (if (battLow != 0) 0 else 1),
            )
            if (temp1Ok) fields["temperature_1_F"] = temp1f.toDouble()
            if (temp2Ok) fields["temperature_2_F"] = temp2f.toDouble()
            return listOf(Reading("Acurite-01185M", id.toString(), fields))
        }
        return emptyList()
    }
}

// unverified: acurite.c:1972-2033, struct acurite.c:2342
internal object Acurite590tx : Rtl433Decoder() {
    override val name = "Acurite 590TX Temperature with optional Humidity"
    override val mod = Mod.OOK_PPM
    override val short = 500
    override val long = 1500
    override val gap = 2000
    override val reset = 3500

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(3, 25)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] > 25) return emptyList()
        val b = bb.bb[row]
        if (b[4] != 0) return emptyList()
        if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0) return emptyList()
        var parity = b[0]
        parity = (parity shr 4) xor (parity and 0xF)
        parity = (parity shr 2) xor (parity and 0x3)
        parity = parity xor (b[1] shr 6)
        parity = (parity shr 1) xor (parity and 0x1)
        if (parity == 0) return emptyList()
        val sensorId = b[0] and 0xFE
        val batteryOk = b[0] and 0x01
        val channel = (b[1] shr 4) and 0x03
        val tempRaw = s16(((b[1] and 0x0F) shl 12) or (b[2] shl 4)) shr 4
        val tempC = (tempRaw - 500) * 0.1f
        var humidity = -1
        if (tempRaw >= 0 && tempRaw <= 100) humidity = tempRaw
        val fields = linkedMapOf<String, Any?>(
            "channel" to channel,
            "battery_ok" to batteryOk,
        )
        if (humidity != -1) fields["humidity"] = humidity else fields["temperature_C"] = tempC.toDouble()
        return listOf(Reading("Acurite-590TX", sensorId.toString(), fields))
    }
}

// unverified: acurite.c:1905-1959, struct acurite.c:2305
internal object Acurite606 : Rtl433Decoder() {
    override val name = "Acurite 606TX / Technoline TX960 Temperature Sensor"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 7000
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(3, 32)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] > 33) return emptyList()
        val b = bb.bb[row]
        if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0) return emptyList()
        val chk = Rtl433BitUtil.lfsrDigest8(b, 3, 0x98, 0xf1)
        if (chk != b[3]) return emptyList()
        val sensorId = b[0]
        val batteryOk = (b[1] and 0x80) shr 7
        val channel = ((b[1] and 0x30) shr 4) + 1
        val button = (b[1] and 0x40) shr 6
        val tempRaw = s16((b[1] shl 12) or (b[2] shl 4)) shr 4
        val tempC = tempRaw * 0.1f
        return listOf(
            Reading(
                "Acurite-606TX",
                sensorId.toString(),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to batteryOk,
                    "button" to button,
                    "temperature_C" to tempC.toDouble(),
                ),
            ),
        )
    }
}

// unverified: acurite.c:1760-1878, struct acurite.c:2258
internal object Acurite985 : Rtl433Decoder() {
    override val name = "Acurite/Chaney 985 Refrigerator / Freezer Thermometer"
    override val mod = Mod.OOK_PPM
    override val short = 556
    override val long = 1104
    override val gap = 4000
    override val reset = 7636
    override val sync = 2996

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            val b = bb.bb[row]
            val bits = bb.bitsPerRow[row]
            if (bits < 55 || bits > 59) continue
            if (b[2] == 0 && b[3] == 0 && b[4] == 0 && b[5] == 0 && b[6] == 0) continue
            val br = IntArray(7) { rv8(b[it]) }
            var tempf = br[2].toByte().toInt()
            val sensorId = (br[3] shl 8) or br[4]
            val status = br[5]
            val sensorNum = (status and 0x01) + 1
            val batteryLow = if (sensorNum == 2) (status and 0x04) != 0 else (status and 0x02) != 0
            val channel = if (sensorNum == 2) "2F" else "1R"
            val crc = br[6]
            val crcc = Rtl433BitUtil.crc8le(br.copyOfRange(2, 7), 4, 0x07, 0)
            if (crcc != crc && crcc != (crc or 0x80)) continue
            if ((tempf and 0x80) != 0) tempf = (tempf and 0x7f) * -1
            if (tempf in -40..104) {
            } else if (tempf == -127 || tempf == 127) {
            } else {
                continue
            }
            out.add(
                Reading(
                    "Acurite-985",
                    sensorId.toString(),
                    mapOf(
                        "channel" to channel,
                        "battery_ok" to (if (batteryLow) 0 else 1),
                        "temperature_F" to tempf.toDouble(),
                        "status" to status,
                    ),
                ),
            )
        }
        return out
    }
}

// unverified: acurite.c:1624-1718, struct acurite.c:2231
internal object Acurite986 : Rtl433Decoder() {
    override val name = "Acurite 986 Refrigerator / Freezer Thermometer"
    override val mod = Mod.OOK_PPM
    override val short = 520
    override val long = 880
    override val gap = 1280
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            if (bb.bitsPerRow[row] < 39 || bb.bitsPerRow[row] > 43) continue
            val b = bb.bb[row]
            if ((b[0] == 0xff && b[1] == 0xff && b[2] == 0xff) || (b[0] == 0x00 && b[1] == 0x00 && b[2] == 0x00)) continue
            val br = IntArray(5) { rv8(b[it]) }
            var tempf = br[0].toByte().toInt()
            val sensorId = (br[1] shl 8) + br[2]
            var status = br[3]
            val sensorNum = (status and 0x01) + 1
            status = status shr 1
            val batteryLow = (status and 1) == 1
            val channel = if (sensorNum == 2) "2F" else "1R"
            val crc = br[4]
            val crcc = Rtl433BitUtil.crc8le(br, 4, 0x07, 0)
            if (crcc != crc && crcc != (crc or 0x80)) continue
            if ((tempf and 0x80) != 0) tempf = (tempf and 0x7f) * -1
            out.add(
                Reading(
                    "Acurite-986",
                    sensorId.toString(),
                    mapOf(
                        "channel" to channel,
                        "battery_ok" to (if (batteryLow) 0 else 1),
                        "temperature_F" to tempf.toDouble(),
                        "status" to status,
                    ),
                ),
            )
        }
        return out
    }
}

// unverified: acurite.c:151-185, struct acurite.c:2131
internal object AcuriteRain896 : Rtl433Decoder() {
    override val name = "Acurite 896 Rain Gauge"
    override val mod = Mod.OOK_PPM
    override val short = 1000
    override val long = 2000
    override val gap = 3500
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        val b = bb.bb[0]
        if (bb.bitsPerRow[0] < 24) return emptyList()
        if (bb.numRows < 12) return emptyList()
        if (b[0] == 0 || b[1] == 0 || b[2] == 0 || b[3] != 0 || b[4] != 0) return emptyList()
        val id = b[0]
        val totalRain = (((b[1] and 0xf) shl 8) or b[2]) * 0.5
        return listOf(Reading("Acurite-Rain", id.toString(), mapOf("rain_mm" to totalRain)))
    }
}

// unverified: acurite.c:202-262, struct acurite.c:2154
internal object AcuriteTh : Rtl433Decoder() {
    override val name = "Acurite 609TXC Temperature and Humidity Sensor"
    override val mod = Mod.OOK_PPM
    override val short = 1000
    override val long = 2000
    override val gap = 3000
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (brow in 0 until bb.numRows) {
            if (bb.bitsPerRow[brow] != 40) continue
            val b = bb.bb[brow]
            val cksum = b[0] + b[1] + b[2] + b[3]
            if (cksum == 0 || ((cksum and 0xff) != b[4])) continue
            val tempRaw = s16(((b[1] and 0x0f) shl 12) or (b[2] shl 4)) shr 4
            val tempc = tempRaw * 0.1f
            val id = b[0]
            val status = (b[1] and 0xf0) shr 4
            val batteryLow = status and 0x8
            val humidity = b[3]
            if (humidity > 100) return out
            out.add(
                Reading(
                    "Acurite-609TXC",
                    id.toString(),
                    mapOf(
                        "battery_ok" to (if (batteryLow != 0) 0 else 1),
                        "temperature_C" to tempc.toDouble(),
                        "humidity" to humidity,
                        "status" to status,
                    ),
                ),
            )
        }
        return out
    }
}

// unverified: acurite.c:1342-1584 multi-protocol dispatch not ported; acurite_txr_check helper at acurite.c:1268
internal object AcuriteTxr : Rtl433Decoder() {
    override val name = "Acurite 592TXR temp/humidity, 592TX temp, 5n1, 3n1, Atlas weather station, 515 fridge/freezer, 6045 lightning, 899 rain, 1190/1192 leak"
    override val mod = Mod.OOK_PWM
    override val short = 220
    override val long = 408
    override val sync = 620
    override val gap = 500
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: akhan_100F14.c:23-62, struct akhan_100F14.c:72
internal object Akhan100F14 : Rtl433Decoder() {
    override val name = "Akhan 100F14 remote keyless entry"
    override val mod = Mod.OOK_PWM
    override val short = 316
    override val long = 1020
    override val reset = 1800
    override val sync = 0
    override val tolerance = 100

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 25) return emptyList()
        val b = bb.bb[0]
        b[0] = b[0].inv() and 0xFF
        b[1] = b[1].inv() and 0xFF
        b[2] = b[2].inv() and 0xFF
        val id = (b[0] shl 12) or (b[1] shl 4) or (b[2] shr 4)
        val cmd = b[2] and 0x0F
        val cmdStr = when (cmd) {
            0x1 -> "0x1 (Lock)"
            0x2 -> "0x2 (Unlock)"
            0x4 -> "0x4 (Mute)"
            0x8 -> "0x8 (Alarm)"
            else -> return emptyList()
        }
        return listOf(Reading("Akhan-100F14", String.format("0x%x", id), mapOf("data" to cmdStr)))
    }
}

// unverified: alecto.c:79-92 (checksum), alecto.c:99-209, struct alecto.c:226
internal object Alectov1 : Rtl433Decoder() {
    override val name = "AlectoV1 Weather Sensor (Alecto WS3500 WS4500 Ventus W155/W044 Oregon)"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 7000
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[1] != 36) return emptyList()
        val rows = bb.bb
        val b = rows[1]
        if (rows[1][0] != rows[5][0] || rows[2][0] != rows[6][0] ||
            (rows[1][4] and 0xf) != 0 || (rows[5][4] and 0xf) != 0 ||
            rows[5][0] == 0 || rows[5][1] == 0
        ) return emptyList()
        if (!alectoChk(rows[1]) || !alectoChk(rows[5])) return emptyList()
        val batteryLow = (b[1] and 0x80) shr 7
        val msgType = (b[1] and 0x60) shr 5
        val msgRain = (b[1] and 0x0f) == 0x0c
        val channel = (b[0] and 0xc) shr 2
        val sensorId = rv8(b[0])
        val batteryOk = if (batteryLow != 0) 0 else 1
        if (msgType == 0x3 && !msgRain) {
            var skip = -1
            if ((b[1] and 0xe) == 0x8 && b[2] == 0) {
                skip = 0
            } else if ((b[1] and 0xe) == 0xe) {
                skip = 4
            }
            if (skip >= 0) {
                val speed = rv8(rows[1 + skip][3]).toDouble()
                val gust = rv8(rows[5 + skip][3]).toDouble()
                val direction = (rv8(rows[5 + skip][2]) shl 1) or (rows[5 + skip][1] and 0x1)
                return listOf(
                    Reading(
                        "AlectoV1-Wind",
                        sensorId.toString(),
                        mapOf(
                            "channel" to channel,
                            "battery_ok" to batteryOk,
                            "wind_avg_m_s" to speed * 0.2,
                            "wind_max_m_s" to gust * 0.2,
                            "wind_dir_deg" to direction,
                        ),
                    ),
                )
            }
            return emptyList()
        }
        if (msgType == 0x3 && msgRain) {
            val rainMm = ((rv8(b[3]) shl 8) or rv8(b[2])) * 0.25
            return listOf(
                Reading(
                    "AlectoV1-Rain",
                    sensorId.toString(),
                    mapOf("channel" to channel, "battery_ok" to batteryOk, "rain_mm" to rainMm),
                ),
            )
        }
        if (msgType != 0x3 &&
            rows[2][0] == rows[3][0] && rows[3][0] == rows[4][0] &&
            rows[4][0] == rows[5][0] && rows[5][0] == rows[6][0] &&
            (rows[3][4] and 0xf) == 0 && (rows[5][4] and 0xf) == 0
        ) {
            val tempRaw = s16((rv8(b[1]) and 0xf0) or (rv8(b[2]) shl 8))
            val tempC = (tempRaw shr 4) * 0.1f
            val humidity = bcdDec8(rv8(b[3]))
            if (humidity > 100) return emptyList()
            return listOf(
                Reading(
                    "AlectoV1-Temperature",
                    sensorId.toString(),
                    mapOf(
                        "channel" to channel,
                        "battery_ok" to batteryOk,
                        "temperature_C" to tempC.toDouble(),
                        "humidity" to humidity,
                    ),
                ),
            )
        }
        return emptyList()
    }
}

// unverified: alps_fwb1u545.c:49-98, struct alps_fwb1u545.c:109
internal object AlpsFwb1u545CarRemote : Rtl433Decoder() {
    override val name = "Alps FWB1U545 Car Remote"
    override val mod = Mod.FSK_MC_ZEROBIT
    override val short = 500
    override val reset = 1500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 76 || bb.numRows > 1) return emptyList()
        val bytes = bb.bb[0]
        if (bytes[0] != 0x55 || bytes[5] != bytes[6]) return emptyList()
        val id = (bytes[1] shl 24) or (bytes[2] shl 16) or (bytes[3] shl 8) or bytes[4]
        if (id == 0 || id == -1) return emptyList()
        val idStr = String.format("%08X", id)
        val button = bytes[5] shr 4
        val sequence = (bytes[7] shl 8) or bytes[8]
        val buttonStr = when (button) {
            0xe -> "Lock"
            0xc -> "Panic"
            0x5 -> "Panic Held"
            0x1 -> "Unlock"
            else -> "?"
        }
        return listOf(
            Reading(
                "Alps-FWB1U545",
                idStr,
                mapOf("button_code" to button, "button_str" to buttonStr, "sequence" to sequence),
            ),
        )
    }
}

// unverified: ambient_weather.c:44-112 (decode), ambient_weather.c:118-153 (callback), lfsr via Rtl433BitUtil, struct ambient_weather.c:166
internal object AmbientWeather : Rtl433Decoder() {
    override val name = "Ambient Weather F007TH, TFA 30.3208.02, SwitchDocLabs F016TH temperature sensor"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 500
    override val long = 0
    override val reset = 2400

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val b = IntArray(6)
        bb.extractBytes(row, bitpos, b, 48)
        val expected = b[5]
        val calculated = Rtl433BitUtil.lfsrDigest8(b, 5, 0x98, 0x3e) xor 0x64
        if (expected != calculated) return null
        val deviceId = b[1]
        val batteryLow = (b[2] and 0x80) != 0
        val channel = ((b[2] and 0x70) shr 4) + 1
        val tempRaw = ((b[2] and 0x0f) shl 8) or b[3]
        val tempF = (tempRaw - 400) * 0.1f
        val humidity = b[4]
        if (humidity > 100) return null
        if (tempF < -40.0f || tempF >= 344.0f) return null
        return Reading(
            "Ambientweather-F007TH",
            deviceId.toString(),
            mapOf(
                "channel" to channel,
                "battery_ok" to (if (batteryLow) 0 else 1),
                "temperature_F" to tempF.toDouble(),
                "humidity" to humidity,
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        for (row in 0 until bb.numRows) {
            var bitpos = 0
            while (true) {
                bitpos = bb.search(row, bitpos, intArrayOf(0x01, 0x45), 12)
                if (bitpos + 8 + 6 * 8 > bb.bitsPerRow[row]) break
                decodeAt(bb, row, bitpos + 8)?.let { return listOf(it) }
                bitpos += 16
            }
            bitpos = 0
            while (true) {
                bitpos = bb.search(row, bitpos, intArrayOf(0xfd, 0x45), 12)
                if (bitpos + 8 + 6 * 8 > bb.bitsPerRow[row]) break
                decodeAt(bb, row, bitpos + 8)?.let { return listOf(it) }
                bitpos += 15
            }
        }
        return emptyList()
    }
}

// unverified: ambientweather_tx8300.c:49-60 (chk), ambientweather_tx8300.c:62-119, struct ambientweather_tx8300.c:132
internal object AmbientweatherTx8300 : Rtl433Decoder() {
    override val name = "Ambient Weather TX-8300 Temperature/Humidity Sensor"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 6500
    override val reset = 8000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 74) return emptyList()
        val b = IntArray(9)
        bb.extractBytes(0, 2, b, 72)
        b[4] = b[4] xor 0xff
        b[5] = b[5] xor 0xff
        b[6] = b[6] xor 0xff
        b[7] = b[7] xor 0xff
        b[0] = (b[0] and 0x7f) or (b[4] and 0x80)
        if (b[0] != b[4] || b[1] != b[5] || b[2] != b[6] || b[3] != b[7]) return emptyList()
        if ((tx8300Chk(b) xor b[8]) != 0) return emptyList()
        val temp = (b[2] and 0x0f) * 10 + ((b[3] and 0xf0) shr 4) + (b[3] and 0x0f) * 0.1f
        val channel = (b[1] and 0x30) shr 4
        val batteryLow = (b[1] and 0xc0) shr 6
        val minus = (b[1] and 0x08) shr 3
        var humidity = ((b[0] and 0xf0) shr 4) * 10 + (b[0] and 0x0f)
        val sensorId = ((b[1] and 0x07) shl 4) or ((b[2] and 0xf0) shr 4)
        val tempC = if (minus == 1) temp * -1 else temp
        if (((b[0] and 0xf0) shr 4) > 9 || (b[0] and 0x0f) > 9) humidity = -1
        val fields = linkedMapOf<String, Any?>(
            "channel" to channel,
            "battery" to batteryLow,
            "temperature_C" to tempC.toDouble(),
        )
        if (humidity >= 0) fields["humidity"] = humidity
        return listOf(Reading("AmbientWeather-TX8300", sensorId.toString(), fields))
    }
}

// unverified: not ported - WH31E/WH31B/RCC/clock variants span ambientweather_wh31e.c:208-440, too large for this batch
internal object AmbientweatherWh31e : Rtl433Decoder() {
    override val name = "Ambient Weather WH31E Thermo-Hygrometer Sensor, EcoWitt WH40/WN20 rain gauge, WS68 weather station"
    override val mod = Mod.FSK_PCM
    override val short = 56
    override val long = 56
    override val reset = 1500
    override val gap = 1800

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: not ported - ANT FSK packet parser (ant_antplus.c:80-139), disabled upstream, not transcribed this batch
internal object AntAntplus : Rtl433Decoder() {
    override val name = "ANT and ANT+ devices"
    override val mod = Mod.FSK_PCM
    override val short = 1
    override val long = 1
    override val sync = 8
    override val gap = 500
    override val reset = 500

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: apator_metra_eitn30.c:106-202, struct apator_metra_eitn30.c:215
internal object ApatorMetraEitn30 : Rtl433Decoder() {
    override val name = "Apator Metra E-ITN 30 heat cost allocator"
    override val mod = Mod.FSK_PCM
    override val short = 25
    override val long = 25
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        val p = apatorPayload(bb, 0x11, 20) ?: return emptyList()
        val idRaw = ((p[3] shl 24) or (p[2] shl 16) or (p[1] shl 8) or p[0]) xor 0x38000000
        val current = (p[11] shl 8) or p[10]
        val lastYr = (p[5] shl 8) or p[4]
        val date = (p[13] shl 8) or p[12]
        val day = date and 0x1f
        val month = (date shr 5) and 0x0f
        val year = (date shr 9) and 0x7f
        val dateStr = String.format("%04d-%02d-%02d", 2000 + year, month, day)
        return listOf(
            Reading(
                "ApatorMetra-EITN30",
                String.format("%09d", idRaw),
                mapOf(
                    "len" to 17,
                    "current_heating" to current,
                    "last_yr_heating" to lastYr,
                    "date" to dateStr,
                ),
            ),
        )
    }
}

// unverified: apator_metra_erm30.c:89-184, struct apator_metra_erm30.c:196
internal object ApatorMetraErm30 : Rtl433Decoder() {
    override val name = "Apator Metra E-RM 30 water meter"
    override val mod = Mod.FSK_PCM
    override val short = 25
    override val long = 25
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        val p = apatorPayload(bb, 0x13, 22) ?: return emptyList()
        val idRaw = ((p[3] shl 24) or (p[2] shl 16) or (p[1] shl 8) or p[0]) xor 0x30000000
        val volRaw = (((p[7] shl 24) or (p[6] shl 16) or (p[5] shl 8) or p[4]) and 0x0fffffff) shr 3
        val volume = volRaw / 1000.0f
        val date = (p[16] shl 8) or p[15]
        val day = date and 0x1f
        val month = (date shr 5) and 0x0f
        val year = (date shr 9) and 0x7f
        val dateStr = String.format("%04d-%02d-%02d", 2000 + year, month, day)
        return listOf(
            Reading(
                "ApatorMetra-ERM30",
                String.format("%09d", idRaw),
                mapOf(
                    "len" to 19,
                    "volume_m3" to volume.toDouble(),
                    "date" to dateStr,
                ),
            ),
        )
    }
}

// unverified: not ported - Dialog3G decoder (arad_ms_meter.c:513-627) not transcribed this batch
internal object AradMsMeter : Rtl433Decoder() {
    override val name = "Arad/Master Meter Dialog3G water utility meter"
    override val mod = Mod.FSK_MC_ZEROBIT
    override val short = 8
    override val long = 8
    override val reset = 100

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: archos_tbh.c:60-213, struct archos_tbh.c:228
internal object ArchosTbh : Rtl433Decoder() {
    override val name = "TBH weather sensor"
    override val mod = Mod.FSK_PCM
    override val short = 212
    override val long = 212
    override val reset = 3000

    private val info = intArrayOf(
        0x19, 0xF8, 0x28, 0x30, 0x6d, 0x0c, 0x94, 0x54,
        0x22, 0xf2, 0x37, 0xc9, 0x66, 0xa3, 0x97, 0x57,
    )

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val start = bb.search(0, 0, intArrayOf(0xaa, 0xaa, 0xd3, 0x91, 0xd3, 0x91), 48)
        if (start == bb.bitsPerRow[0]) return emptyList()
        if (bb.bitsPerRow[0] < 12 * 8) return emptyList()
        val lenBuf = IntArray(1)
        bb.extractBytes(0, start + 48, lenBuf, 8)
        val len = lenBuf[0]
        if (len > 60) return emptyList()
        val frame = IntArray(63)
        frame[0] = len
        val tmp = IntArray(64)
        bb.extractBytes(0, start + 56, tmp, (len + 2) * 8)
        for (i in 0 until len + 2) frame[1 + i] = tmp[i]
        val crc = Rtl433BitUtil.crc16(frame, len + 1, 0x8005, 0xffff)
        if (((frame[len + 1] shl 8) or frame[len + 2]) != crc) return emptyList()
        val payload = IntArray(62)
        payload[0] = frame[1] xor info[0]
        for (i in 1 until len) payload[i] = frame[i] xor frame[i + 1] xor info[i % info.size]
        val type = payload[4]
        val id = payload[0] or (payload[1] shl 8) or (payload[2] shl 16) or (payload[3] shl 24)
        val idStr = String.format("%08X", id)
        if (type == 1) {
            payload[4] = len - 4
            val c = Rtl433BitUtil.crc8(payload.copyOfRange(4, payload.size), len - 5, 0x07, 0x00)
            if (c != payload[len - 1]) return emptyList()
            val idx = (payload[6] shl 16) or (payload[7] shl 8) or payload[8]
            val ts = (payload[9] shl 16) or (payload[10] shl 8) or payload[11]
            val maxPower = (payload[12] shl 8) or payload[13]
            return listOf(
                Reading(
                    "Archos-TBH",
                    idStr,
                    mapOf("power_idx" to idx, "power_max" to maxPower, "timestamp" to ts / 8),
                ),
            )
        }
        if (type == 2) {
            val tempRaw = ((payload[6] shl 8) or payload[5]) - 2732
            val tempC = tempRaw * 0.1f
            return listOf(
                Reading(
                    "Archos-TBH",
                    idStr,
                    mapOf("temperature_C" to tempC.toDouble(), "humidity" to payload[7]),
                ),
            )
        }
        if (type == 3) {
            return listOf(Reading("Archos-TBH", idStr, mapOf("battery_ok" to payload[5] * 0.01)))
        }
        if (type == 4) {
            return listOf(Reading("Archos-TBH", idStr, mapOf("battery_ok" to 0)))
        }
        return emptyList()
    }
}

// unverified: arexx_ml.c:79-187, struct arexx_ml.c:200
internal object ArexxMl : Rtl433Decoder() {
    override val name = "Arexx Multilogger IP-HA90, IP-TH78EXT, TSN-70E"
    override val mod = Mod.FSK_MC_ZEROBIT
    override val short = 208
    override val long = 208
    override val reset = 450

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] < 64 || bb.bitsPerRow[0] > 140) return emptyList()
        bb.invert()
        var msgLen = -1
        val b = IntArray(9)
        for (i in 0 until bb.numRows) {
            var pos = bb.search(i, 0, intArrayOf(0xaa, 0xaa, 0x55), 24)
            pos += 24
            if (pos + 64 > bb.bitsPerRow[i]) continue
            bb.extractBytes(i, pos, b, 72)
            msgLen = b[0]
            break
        }
        if (msgLen <= 0) return emptyList()
        if (msgLen > 9 - 2) return emptyList()
        val chk = Rtl433BitUtil.crc8le(b, msgLen, 0x31, 0x00)
        if (chk != b[msgLen]) return emptyList()
        var id = (b[2] shl 8) or b[1]
        var sensVal = (b[3] shl 8) or b[4]
        var tempC = 0.0f
        var humidity = 0.0f
        var isHumi = false
        var isTemp = false
        var isAlert = false
        var tempAlert = 0
        if (msgLen == 5 && (id and 0xF000) == 0x2000) {
            isTemp = true
            tempC = s16(sensVal) * 0.0078125f
        } else if (msgLen == 5 && (id and 0xF001) == 0x4000) {
            isTemp = true
            tempC = sensVal * 0.01f - 40.0f
        } else if (msgLen == 5 && (id and 0xF001) == 0x4001) {
            isHumi = true
            sensVal = s16(sensVal)
            humidity = (-2.0468 + 0.0367 * sensVal - 1.5955E-6 * sensVal * sensVal).toFloat()
        } else if (msgLen == 6) {
            isTemp = true
            isAlert = true
            tempAlert = (sensVal shr 13) and 7
            val tempRaw = s16(sensVal shl 3)
            tempC = (tempRaw / 128).toFloat()
        } else if (msgLen == 7) {
            id = (b[3] shl 16) or (b[2] shl 8) or b[1]
            sensVal = (b[5] shl 8) or b[6]
            if ((id and 1) != 0) {
                isHumi = true
                sensVal = s16(sensVal)
                humidity = (-2.0468 + 0.0367 * sensVal - 1.5955E-6 * sensVal * sensVal).toFloat()
            } else {
                isTemp = true
                tempC = sensVal * 0.01f - 40.0f
            }
        }
        val fields = linkedMapOf<String, Any?>()
        if (isTemp) fields["temperature_C"] = tempC.toDouble()
        if (isAlert) fields["temperature_alert"] = tempAlert
        if (isHumi) fields["humidity"] = humidity.toDouble()
        fields["sensor_raw"] = sensVal
        return listOf(Reading("Arexx-ML", String.format("%06x", id), fields))
    }
}

// unverified: astrostart_2000.c:61-149, struct astrostart_2000.c:160
internal object Astrostart2000 : Rtl433Decoder() {
    override val name = "Astrostart 2000 Car Remote (-f 372.4M)"
    override val mod = Mod.OOK_PPM
    override val short = 326
    override val long = 526
    override val reset = 541
    override val gap = 541
    override val tolerance = 80

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 52) return emptyList()
        if (bb.numRows != 1) return emptyList()
        val bytes = bb.bb[0]
        if (bytes[0] != (bytes[1].inv() and 0xff)) return emptyList()
        val actual = bytes[6] shr 4
        var expected = 0
        for (i in 2 until 6) {
            expected = (expected + (bytes[i] shr 4)) and 0xf
            expected = (expected + bytes[i]) and 0xf
        }
        if (actual != expected) return emptyList()
        val id = (bytes[2] shl 24) or (bytes[3] shl 16) or (bytes[4] shl 8) or bytes[5]
        val idStr = String.format("%08X", id)
        val button = bytes[0]
        val buttonMap = listOf(
            "Lock" to intArrayOf(0x2b, 0x03, 0x27, 0x0f, 0x35, 0x37),
            "Panic" to intArrayOf(0x1f, 0x35, 0x0d, 0x25, 0x15, 0x2d),
            "Start" to intArrayOf(0x13, 0x37, 0x2d, 0x33, 0x3d, 0x3b),
            "Stop" to intArrayOf(0x2f, 0x0d, 0x33, 0x03, 0x1d, 0x17),
            "Trunk" to intArrayOf(0x23, 0x25, 0x3d, 0x1d, 0x27, 0x07),
            "Unlock" to intArrayOf(0x0b, 0x15, 0x3b, 0x17, 0x07, 0x0f),
            "Multiple" to intArrayOf(0x3F),
        )
        val matched = ArrayList<String>()
        for ((name, vals) in buttonMap) {
            if (vals.contains(button)) matched.add(name)
        }
        val buttonStr = if (matched.isEmpty()) "?" else matched.joinToString("; ")
        return listOf(
            Reading(
                "Astrostart-2000",
                idStr,
                mapOf("button_code" to button, "button_str" to buttonStr),
            ),
        )
    }
}

// unverified: not ported - atech_ws308.c:82-120 needs pwm_decode (atech_ws308.c:48), a helper not in the Rtl433 API
internal object AtechWs308 : Rtl433Decoder() {
    override val name = "Atech-WS308 temperature sensor"
    override val mod = Mod.OOK_RZI
    override val short = 1600
    override val long = 1832
    override val gap = 2500
    override val reset = 9000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: audiovox_pro_oe3b.c:48-111, struct audiovox_pro_oe3b.c:120
internal object AudiovoxProOe3b : Rtl433Decoder() {
    override val name = "Audiovox PRO-OE3B Car Remote (-f 303.4M)"
    override val mod = Mod.OOK_PWM
    override val short = 445
    override val long = 895
    override val reset = 1790
    override val gap = 1790
    override val sync = 1368

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 25) return emptyList()
        if (bb.numRows != 1) return emptyList()
        val pre = bb.bb[0]
        if ((pre[2] and 0xaa) != 0 || pre[2] == 0x55) return emptyList()
        bb.invert()
        val bytes = bb.bb[0]
        val id = (bytes[0] shl 8) or bytes[1]
        if (id == 0 || id == 0xffff) return emptyList()
        val idStr = String.format("%04X", id)
        val names = arrayOf("Lock", "Unlock", "Option", "Trunk")
        val parts = ArrayList<String>()
        var mask = 0x01
        for (i in 0 until 4) {
            if ((bytes[2] and mask) != 0) parts.add(names[i])
            mask = mask shl 2
        }
        if (parts.isEmpty()) return emptyList()
        return listOf(Reading("Audiovox-PROOE3B", idStr, mapOf("button_str" to parts.joinToString("; "))))
    }
}

// unverified: auriol_4ld5661.c:38-92, struct auriol_4ld5661.c:104
internal object Auriol4ld5661 : Rtl433Decoder() {
    override val name = "Auriol 4-LD5661/4-LD5972/4-LD6313, Sempre 4-AH0423-4 temperature/rain sensors"
    override val mod = Mod.OOK_PPM
    override val short = 1000
    override val long = 2000
    override val sync = 2500
    override val gap = 2500
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        for (i in 0 until bb.numRows) {
            if (bb.bitsPerRow[i] != 52) continue
            val b = bb.bb[i]
            val id = b[0]
            val batteryOk = b[1] shr 7
            if (b[3] != 0xf0 || (b[1] and 0x40) != 0) continue
            val tempRaw = s16(((b[1] and 0x0f) shl 12) or (b[2] shl 4)) shr 4
            val tempC = tempRaw * 0.1f
            val rainRaw = (b[4] shl 12) or (b[5] shl 4) or (b[6] shr 4)
            val rain = rainRaw * 1.0f
            return listOf(
                Reading(
                    "Auriol-4LD5661",
                    String.format("%02x", id),
                    mapOf(
                        "battery_ok" to batteryOk,
                        "temperature_C" to tempC.toDouble(),
                        "rain_mm" to rain.toDouble(),
                        "rain" to rainRaw,
                    ),
                ),
            )
        }
        return emptyList()
    }
}

// unverified: auriol_aft77b2.c:57-138 (lsrc, search_row, decode), KEY=0xEC GEN=0x83 at :52-53, struct auriol_aft77b2.c:148
internal object AuriolAft77b2 : Rtl433Decoder() {
    override val name = "Auriol AFT 77 B2 temperature sensor"
    override val mod = Mod.OOK_PPM
    override val short = 500
    override val long = 920
    override val gap = 1104
    override val reset = 2275

    override fun decode(bb: BitBuffer): List<Reading> {
        var row = -1
        for (r in 0 until bb.numRows) {
            if (bb.bitsPerRow[r] == 68) {
                row = r
                break
            }
        }
        if (row == -1) return emptyList()
        val ptr = bb.bb[row]
        if (ptr[0] != 0xA5) return emptyList()
        val frame = IntArray(8) { i -> ((ptr[i] shl 4) or (ptr[i + 1] shr 4)) and 0xFF }
        if ((Rtl433BitUtil.addBytes(frame, 6) and 0xFF) != frame[6]) return emptyList()
        if (lsrcFrame(frame, 6) != frame[7]) return emptyList()
        val id = frame[1]
        var tempRaw = (ptr[4] shr 4) * 100 + (ptr[4] and 0x0F) * 10 + (ptr[5] shr 4)
        if ((ptr[3] and 0x08) != 0) tempRaw = -tempRaw
        return listOf(Reading("Auriol-AFT77B2", id.toString(), mapOf("temperature_C" to tempRaw * 0.1)))
    }
}

// unverified: auriol_afw2a1.c:54-106, struct auriol_afw2a1.c:120
internal object AuriolAfw2a1 : Rtl433Decoder() {
    override val name = "Auriol AFW2A1 temperature/humidity sensor"
    override val mod = Mod.OOK_PPM
    override val short = 576
    override val long = 1536
    override val sync = 0
    override val gap = 2012
    override val reset = 3954

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(12, 36)
        if (row < 0) return emptyList()
        val b = bb.bb[row]
        val id = b[0]
        val batteryOk = b[1] shr 7
        val txButton = (b[1] and 0x40) shr 6
        val channel = (b[1] and 0x30) shr 4
        val tempRaw = s16(((b[1] and 0x0f) shl 12) or (b[2] shl 4)) shr 4
        val tempC = tempRaw * 0.1f
        if ((b[3] shr 4) != 0xa) return emptyList()
        val humidity = ((b[3] and 0x0f) shl 4) or (b[4] shr 4)
        if (humidity > 0x64 || humidity < 0x00 || tempC.toDouble() < -51.1 || tempC.toDouble() > 76.7) return emptyList()
        return listOf(
            Reading(
                "Auriol-AFW2A1",
                id.toString(),
                mapOf(
                    "channel" to channel + 1,
                    "battery_ok" to batteryOk,
                    "button" to txButton,
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity.toDouble(),
                ),
            ),
        )
    }
}

// unverified: auriol_ahfl.c:33-97, struct auriol_ahfl.c:111
internal object AuriolAhfl : Rtl433Decoder() {
    override val name = "Auriol AHFL temperature/humidity sensor"
    override val mod = Mod.OOK_PPM
    override val short = 2100
    override val long = 4150
    override val sync = 0
    override val gap = 4248
    override val reset = 9150

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(2, 42)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] != 42) return emptyList()
        val b = bb.bb[row]
        if (((b[4] and 0xF0) != 0x40) || ((b[3] and 0x1) != 0)) return emptyList()
        val nibbleSum = (b[0] and 0xF) + (b[0] shr 4) +
            (b[1] and 0xF) + (b[1] shr 4) +
            (b[2] and 0xF) + (b[2] shr 4) +
            (b[3] and 0xF) + (b[3] shr 4) +
            (b[4] shr 4)
        val checksum = ((b[4] and 0xF) shl 2) or ((b[5] and 0xC0) shr 6)
        if ((nibbleSum and 0x3F) != checksum) return emptyList()
        val id = b[0]
        val batteryOk = b[1] shr 7
        val channel = (b[1] and 0x30) shr 4
        val txButton = (b[1] and 0x40) shr 6
        val tempRaw = s16(((b[1] and 0x0f) shl 12) or (b[2] shl 4)) shr 4
        val tempC = tempRaw * 0.1f
        val humidity = b[3] shr 1
        return listOf(
            Reading(
                "Auriol-AHFL",
                id.toString(),
                mapOf(
                    "channel" to channel + 1,
                    "battery_ok" to batteryOk,
                    "button" to txButton,
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                ),
            ),
        )
    }
}

// unverified: auriol_hg02832.c:40-90, struct auriol_hg02832.c:104
internal object AuriolHg02832 : Rtl433Decoder() {
    override val name = "Auriol HG02832, HG05124A-DCF, Rubicson 48957 temperature/humidity sensor"
    override val mod = Mod.OOK_PWM
    override val short = 252
    override val long = 612
    override val sync = 860
    override val gap = 750
    override val reset = 62990

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 2) return emptyList()
        if (bb.bitsPerRow[0] != 1 || bb.bitsPerRow[1] != 40) return emptyList()
        bb.invert()
        val b = bb.bb[1]
        val d0 = b[0] xor b[1] xor b[2] xor b[3]
        val chk = Rtl433BitUtil.crc8(intArrayOf(d0), 1, 0x31, 0x53) xor b[4]
        if (chk != 0) return emptyList()
        val id = b[0]
        val humidity = b[1]
        val battLow = b[2] shr 7
        val button = (b[2] and 0x40) shr 6
        val channel = (b[2] and 0x30) shr 4
        val tempRaw = s16(((b[2] and 0x0f) shl 12) or (b[3] shl 4)) shr 4
        val tempC = tempRaw * 0.1f
        return listOf(
            Reading(
                "Auriol-HG02832",
                id.toString(),
                mapOf(
                    "channel" to channel + 1,
                    "battery_ok" to (if (battLow != 0) 0 else 1),
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity.toDouble(),
                    "button" to button,
                ),
            ),
        )
    }
}

// unverified: auriol_hg04641a.c:49-103, struct auriol_hg04641a.c:114
internal object AuriolHg04641a : Rtl433Decoder() {
    override val name = "Auriol HG04641A temperature station"
    override val mod = Mod.OOK_PPM
    override val short = 980
    override val long = 1976
    override val gap = 2500
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(2, 36)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] < 36) return emptyList()
        val b = IntArray(5)
        bb.extractBytes(row, 0, b, 36)
        b[4] = b[4] shr 4
        val sum = (b[0] shr 4) + (b[0] and 0xf) + (b[1] shr 4) + (b[1] and 0xf) +
            (b[2] shr 4) + (b[2] and 0xf) + (b[3] shr 4) + (b[3] and 0xf)
        if ((sum and 0xf) != b[4]) return emptyList()
        val flags = b[2] shr 4
        if ((flags and 0x6) != 0 || (flags and 0x1) == 0) return emptyList()
        val batteryOk = if ((flags and 0x8) != 0) 0 else 1
        val id = (b[0] shl 8) or b[1]
        val tempRaw = s16(((b[2] and 0x0f) shl 12) or (b[3] shl 4))
        val tempDecic = tempRaw shr 4
        if (tempDecic < -400 || tempDecic > 600) return emptyList()
        val tempC = tempDecic * 0.1f
        return listOf(
            Reading(
                "Auriol-HG04641A",
                String.format("%04x", id),
                mapOf("battery_ok" to batteryOk, "temperature_C" to tempC.toDouble()),
            ),
        )
    }
}

// unverified: not ported - badger_water.c:84-138 needs badger_decode_3of6_buffer (badger_water.c:71), a helper not in the Rtl433 API
internal object BadgerOrion : Rtl433Decoder() {
    override val name = "Badger ORION water meter, 100kbps (-f 916.45M -s 1200k)"
    override val mod = Mod.FSK_PCM
    override val short = 10
    override val long = 10
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: baldr_hcs528arf.c:56-107, struct baldr_hcs528arf.c:117
internal object BaldrHcs528arf : Rtl433Decoder() {
    override val name = "Baldr HCS528ARF Pool Thermometer sensor"
    override val mod = Mod.OOK_PCM
    override val short = 320
    override val long = 320
    override val gap = 700
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(4, 179)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] > 179) return emptyList()
        val decoded = BitBuffer()
        bb.manchesterDecode(row, 0, decoded, 11 * 2 * 8)
        decoded.invert()
        val b = decoded.bb[0]
        reflectRev(b, 11)
        if (b[0] != 0xa5) return emptyList()
        val sum = Rtl433BitUtil.addBytes(b.copyOfRange(1, 11), 9)
        if ((sum and 0xff) != b[10]) return emptyList()
        val id = (b[4] shl 24) or (b[3] shl 16) or (b[2] shl 8) or b[1]
        val batLow = (b[5] and 0x02) shr 1
        val tempRaw = ((b[8] and 0x0F) shl 8) or b[7]
        val tempF = tempRaw * 0.1f
        return listOf(
            Reading(
                "Baldr-HCS528ARF",
                String.format("%08x", id),
                mapOf(
                    "battery_ok" to (if (batLow != 0) 0 else 1),
                    "temperature_F" to tempF.toDouble(),
                ),
            ),
        )
    }
}

// unverified: baldr_rain.c:47-82, struct baldr_rain.c:92
internal object BaldrRain : Rtl433Decoder() {
    override val name = "Baldr / RainPoint rain gauge."
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
        if ((b[0] == 0 && b[2] == 0 && b[3] == 0) || (b[0] == 0xff && b[2] == 0xff && b[3] == 0xff)) return emptyList()
        val id = (b[0] shl 4) or (b[1] shr 4)
        val flags = b[1] and 0x0f
        val rainIn = (b[2] shl 12) or (b[3] shl 4) or (b[4] shr 4)
        return listOf(
            Reading(
                "Baldr-Rain",
                String.format("%03x", id),
                mapOf("flags" to flags, "rain_in" to rainIn * 0.001),
            ),
        )
    }
}

// unverified: baldr_therm.c:58-100, struct baldr_therm.c:113
internal object BaldrTherm : Rtl433Decoder() {
    override val name = "Baldr E0666TH Thermo-Hygrometer"
    override val mod = Mod.OOK_PPM
    override val short = 1000
    override val long = 2000
    override val gap = 3000
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(8, 64)
        if (r < 0) return emptyList()
        val b = bb.bb[r]
        if (bb.bitsPerRow[r] > 65) return emptyList()
        if ((b[1] and 0x40) != 0x00 || (b[3] and 0xf0) != 0xf0 ||
            (b[4] and 0x0f) != 0x00 || b[5] != 0x00 || (b[6] and 0xf7) != 0x00
        ) return emptyList()
        val id = (b[0] shl 8) or b[7]
        val battery = b[1] and 0x80
        val channel = ((b[1] and 0x30) shr 4) + 1
        val tempRaw = s16((b[1] shl 12) or (b[2] shl 4)) shr 4
        val tempC = tempRaw * 0.1f
        val humidity = ((b[3] shl 4) or (b[4] shr 4)) and 0xFF
        val startup = b[6] and 0x08
        return listOf(
            Reading(
                "Baldr-E0666TH",
                id.toString(),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to (if (battery != 0) 1 else 0),
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "startup" to (if (startup != 0) 1 else 0),
                ),
            ),
        )
    }
}

// unverified: not ported - blueline.c:241-386 is stateful (decoder_user_data context); the Rtl433Decoder API carries no per-instance state
internal object Blueline : Rtl433Decoder() {
    override val name = "BlueLine Innovations Power Cost Monitor, Black & Decker EM100B"
    override val mod = Mod.OOK_PPM
    override val short = 500
    override val long = 1000
    override val gap = 2000
    override val reset = 8000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: blyss.c:24-54, struct blyss.c:62
internal object Blyss : Rtl433Decoder() {
    override val name = "Blyss DC5-UK-WH"
    override val mod = Mod.OOK_PWM
    override val short = 500
    override val long = 1500
    override val gap = 2500
    override val reset = 8000

    override fun decode(bb: BitBuffer): List<Reading> {
        for (i in 0 until bb.numRows) {
            if (bb.bitsPerRow[i] != 33) continue
            val b = bb.bb[i]
            if (((b[0] != 0xce) || (b[1] != 0x8e) || (b[2] != 0x2a) || (b[3] != 0x6c) || (b[4] != 0x80)) &&
                ((b[0] != 0xe7) || (b[1] != 0x37) || (b[2] != 0x7a) || (b[3] != 0x2c) || (b[4] != 0x80))
            ) continue
            val idStr = String.format("%02x%02x%02x%02x", b[0], b[1], b[2], b[3])
            return listOf(Reading("Blyss-DC5ukwh", idStr, emptyMap()))
        }
        return emptyList()
    }
}

// unverified: bm5.c:65-146, struct bm5.c:162
internal object Bm5 : Rtl433Decoder() {
    override val name = "bm5-v2 12V Battery Monitor"
    override val mod = Mod.OOK_PWM
    override val short = 225
    override val long = 675
    override val reset = 6000

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] != 88) return emptyList()
        val b = IntArray(11)
        bb.extractBytes(0, 0, b, 88)
        if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[10] == 0) return emptyList()
        if (b[6] == 0 && b[7] == 0) return emptyList()
        if ((Rtl433BitUtil.addBytes(b, 10) and 0xff) != b[10]) return emptyList()
        val id = (b[0] shl 16) or (b[1] shl 8) or b[2]
        val soh = b[3] shr 1
        val chargingError = b[3] and 0x01
        val soc = b[4] shr 1
        val crankingError = b[4] and 0x01
        var temp = b[5] shr 1
        val tempSign = b[5] and 0x01
        val volt1 = (b[7] shl 8) or b[6]
        val volt2 = (b[9] shl 8) or b[8]
        if (tempSign == 1) temp = -temp
        val batteryVolt = volt1 * 0.000625f
        val startingVolt = volt2 * 0.000625f
        if (soh > 100 || soc > 100 || batteryVolt < 0.0f || batteryVolt > 20.0f ||
            startingVolt < 0.0f || startingVolt > 20.0f
        ) return emptyList()
        return listOf(
            Reading(
                "BM5-v2",
                String.format("%X", id),
                mapOf(
                    "health_pct" to soh,
                    "cranking_error" to crankingError,
                    "charge_pct" to soc,
                    "charging_error" to chargingError,
                    "temperature_C" to temp.toDouble(),
                    "battery_V" to batteryVolt.toDouble(),
                    "starting_V" to startingVolt.toDouble(),
                ),
            ),
        )
    }
}

// unverified: brennenstuhl_rcs_2044.c:24-104 (process_row), :107-114 (callback), struct brennenstuhl_rcs_2044.c:124
internal object BrennenstuhlRcs2044 : Rtl433Decoder() {
    override val name = "Brennenstuhl RCS 2044"
    override val mod = Mod.OOK_PWM
    override val short = 320
    override val long = 968
    override val gap = 1500
    override val reset = 4000

    private fun processRow(b: IntArray, length: Int): Reading? {
        if (25 != length || (b[0] and 0xaa) != 0xaa || (b[1] and 0xaa) != 0xaa || (b[2] and 0xaa) != 0xaa || b[3] != 0x80) return null
        val systemCode = ((b[0] and 0x40) shr 2) or ((b[0] and 0x10) shr 1) or (b[0] and 0x04) or ((b[0] and 0x01) shl 1) or ((b[1] and 0x40) shr 6)
        val controlKey = (b[1] and 0x10) or ((b[1] and 0x04) shl 1) or ((b[1] and 0x01) shl 2) or ((b[2] and 0x40) shr 5) or ((b[2] and 0x10) shr 4)
        val key = when (controlKey) {
            0x10 -> "A"
            0x08 -> "B"
            0x04 -> "C"
            0x02 -> "D"
            0x01 -> "E"
            else -> return null
        }
        val onOff = ((b[2] and 0x04) shr 1) or (b[2] and 0x01)
        if (onOff != 0x02 && onOff != 0x01) return null
        return Reading(
            "Brennenstuhl-RCS2044",
            systemCode.toString(),
            mapOf("key" to key, "state" to (if (onOff == 0x02) "ON" else "OFF")),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            processRow(bb.bb[row], bb.bitsPerRow[row])?.let { out.add(it) }
        }
        return out
    }
}

internal val BATCH_00: List<Rtl433Decoder> = listOf(
    Abmt,
    Acurite00275rm,
    Acurite01185m,
    Acurite590tx,
    Acurite606,
    Acurite985,
    Acurite986,
    AcuriteRain896,
    AcuriteTh,
    AcuriteTxr,
    Akhan100F14,
    Alectov1,
    AlpsFwb1u545CarRemote,
    AmbientWeather,
    AmbientweatherTx8300,
    AmbientweatherWh31e,
    AntAntplus,
    ApatorMetraEitn30,
    ApatorMetraErm30,
    AradMsMeter,
    ArchosTbh,
    ArexxMl,
    Astrostart2000,
    AtechWs308,
    AudiovoxProOe3b,
    Auriol4ld5661,
    AuriolAft77b2,
    AuriolAfw2a1,
    AuriolAhfl,
    AuriolHg02832,
    AuriolHg04641a,
    BadgerOrion,
    BaldrHcs528arf,
    BaldrRain,
    BaldrTherm,
    Blueline,
    Blyss,
    Bm5,
    BrennenstuhlRcs2044,
)

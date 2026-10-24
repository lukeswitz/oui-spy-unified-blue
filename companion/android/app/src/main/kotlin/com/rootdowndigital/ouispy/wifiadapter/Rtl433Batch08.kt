// Kotlin transcription of rtl_433 device decoders (batch 08). GPL-3 reference; constants, bit offsets and CRC parameters transcribed as facts.
package com.rootdowndigital.ouispy.wifiadapter

private fun reverse8(x: Int): Int {
    var v = x and 0xFF
    v = ((v and 0xF0) shr 4) or ((v and 0x0F) shl 4)
    v = ((v and 0xCC) shr 2) or ((v and 0x33) shl 2)
    v = ((v and 0xAA) shr 1) or ((v and 0x55) shl 1)
    return v and 0xFF
}

private fun s16(x: Int): Int = x.toShort().toInt()

private fun reflectBytes(b: IntArray, n: Int) {
    for (i in 0 until n) b[i] = reverse8(b[i])
}

private fun bcd2float(lo: Int, hi: Int): Float =
    ((hi and 0xF0) shr 4) * 100.0f + (hi and 0x0F) * 10.0f + ((lo and 0xF0) shr 4) * 1.0f + (lo and 0x0F) * 0.1f

private val TP211B_XOR = intArrayOf(
    0xC881, 0xC441, 0xC221, 0xC111, 0xC089, 0xC045, 0xC023, 0xC010,
    0xC01F, 0xC00E, 0x6007, 0x9002, 0x4801, 0x8401, 0xE201, 0xD101,
    0xDE01, 0xCF01, 0xC781, 0xC3C1, 0xC1E1, 0xC0F1, 0xC079, 0xC03D,
    0xC029, 0xC015, 0xC00B, 0xC004, 0x6002, 0x3001, 0xB801, 0xFC01,
    0xE801, 0xD401, 0xCA01, 0xC501, 0xC281, 0xC141, 0xC0A1, 0xC051,
    0xC061, 0xC031, 0xC019, 0xC00D, 0xC007, 0xC002, 0x6001, 0x9001,
)

private fun tp211bChecksum(b: IntArray): Int {
    var checksum = 0x411b
    for (n in 0 until 6) {
        for (i in 0 until 8) {
            val bit = (b[n] shl (i + 1)) and 0x100
            if (bit != 0) checksum = checksum xor TP211B_XOR[(n * 8) + i]
        }
    }
    return checksum
}

// unverified: thermopro_tp211b.c:126-189, struct thermopro_tp211b.c:200
internal object ThermoproTp211b : Rtl433Decoder() {
    override val name = "ThermoPro TP211B Thermometer"
    override val mod = Mod.FSK_PCM
    override val short = 105
    override val long = 105
    override val reset = 1500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows > 1) return emptyList()
        val msgLen = bb.bitsPerRow[0]
        var offset = bb.search(0, 0, intArrayOf(0x55, 0x2d, 0xd4), 24)
        if (offset >= msgLen) return emptyList()
        if ((msgLen - offset) < 64) return emptyList()
        offset += 24
        val b = IntArray(8)
        bb.extractBytes(0, offset, b, 64)
        if (b[5] != 0xaa) return emptyList()
        if ((b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0 && b[4] == 0) ||
            (b[0] == 0xff && b[1] == 0xff && b[2] == 0xff && b[3] == 0xff && b[4] == 0xff)
        ) return emptyList()
        val checksumCalc = tp211bChecksum(b)
        val checksumFromRow = (b[6] shl 8) or b[7]
        if (checksumFromRow != checksumCalc) return emptyList()
        val id = (b[0] shl 16) or (b[1] shl 8) or b[2]
        val tempRaw = ((b[3] and 0x0f) shl 8) or b[4]
        val tempC = (tempRaw - 500) * 0.1f
        val lowBat = (b[3] and 0x80) shr 7
        return listOf(
            Reading(
                "ThermoPro-TP211B",
                String.format("%06x", id),
                mapOf(
                    "battery_ok" to (if (lowBat == 0) 1 else 0),
                    "temperature_C" to tempC.toDouble(),
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: thermopro_tp28b.c:76-141, struct thermopro_tp28b.c:157
internal object ThermoproTp28b : Rtl433Decoder() {
    override val name = "ThermoPro TP28b Super Long Range Wireless Meat Thermometer for Smoker BBQ Grill"
    override val mod = Mod.FSK_PCM
    override val short = 105
    override val long = 105
    override val reset = 5500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows > 1) return emptyList()
        val msgLen = bb.bitsPerRow[0]
        if (msgLen < 240) return emptyList()
        if (msgLen > 451) return emptyList()
        var offset = bb.search(0, 0, intArrayOf(0xd2, 0xaa, 0x2d, 0xd4), 32)
        if (offset >= msgLen) return emptyList()
        offset += 32
        val b = IntArray(18)
        bb.extractBytes(0, offset, b, 18 * 8)
        val sum = (Rtl433BitUtil.addBytes(b, 16) and 0xff) - b[16]
        if (sum != 0) return emptyList()
        val id = b[15] or (b[14] shl 8)
        val flags = b[13] or (b[12] shl 8)
        val p1Temp = bcd2float(b[0], b[1])
        val p1SetHi = bcd2float(b[2], b[3])
        val p1SetLo = bcd2float(b[4], b[5])
        val p2Temp = bcd2float(b[6], b[7])
        val p2SetHi = bcd2float(b[8], b[9])
        val p2SetLo = bcd2float(b[10], b[11])
        return listOf(
            Reading(
                "ThermoPro-TP28b",
                String.format("%04x", id),
                linkedMapOf<String, Any?>(
                    "temperature_1_C" to p1Temp.toDouble(),
                    "alarm_high_1_C" to p1SetHi.toDouble(),
                    "alarm_low_1_C" to p1SetLo.toDouble(),
                    "temperature_2_C" to p2Temp.toDouble(),
                    "alarm_high_2_C" to p2SetHi.toDouble(),
                    "alarm_low_2_C" to p2SetLo.toDouble(),
                    "flags" to flags,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: thermopro_tp82xb.c:57-137, struct thermopro_tp82xb.c:266
internal object ThermoproTp828b : Rtl433Decoder() {
    override val name = "ThermoPro Meat Thermometers, TP828B 2 probes with Temp, BBQ Target LO and HI"
    override val mod = Mod.FSK_PCM
    override val short = 102
    override val long = 102
    override val reset = 1500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows > 1) return emptyList()
        val msgLen = bb.bitsPerRow[0]
        if (msgLen > 280) return emptyList()
        val offset0 = bb.search(0, 0, intArrayOf(0x55, 0x2d, 0xd4), 24)
        if (offset0 >= msgLen) return emptyList()
        if ((msgLen - offset0) < 96) return emptyList()
        val offset = offset0 + 24
        val b = IntArray(12)
        bb.extractBytes(0, offset, b, 12 * 8)
        val bReflect = IntArray(11)
        for (p in 10 downTo 0) bReflect[10 - p] = b[p]
        val checksum = Rtl433BitUtil.lfsrDigest8(bReflect, 11, 0x98, 0x16) xor 0xac
        if (checksum != b[11]) return emptyList()
        val id = b[0]
        val displayU = (b[1] and 0xF0) shr 4
        val flags = b[1] and 0xF
        val p1Raw = (b[2] shl 4) or ((b[3] and 0xF0) shr 4)
        val p1LoRaw = ((b[3] and 0x0F) shl 8) or b[4]
        val p1HiRaw = (b[5] shl 4) or ((b[6] and 0xF0) shr 4)
        val p2Raw = ((b[6] and 0x0F) shl 8) or b[7]
        val p2LoRaw = (b[8] shl 4) or ((b[9] and 0xF0) shr 4)
        val p2HiRaw = ((b[9] and 0x0F) shl 8) or b[10]
        val p1Temp = (p1Raw - 500) * 0.1f
        val p1TLo = (p1LoRaw - 500) * 0.1f
        val p1THi = (p1HiRaw - 500) * 0.1f
        val p2Temp = (p2Raw - 500) * 0.1f
        val p2TLo = (p2LoRaw - 500) * 0.1f
        val p2THi = (p2HiRaw - 500) * 0.1f
        val fields = linkedMapOf<String, Any?>()
        if (displayU == 0x2) fields["display_u"] = "Fahrenheit"
        if (displayU == 0x0) fields["display_u"] = "Celsius"
        if (p1Raw != 0xedd) fields["temperature_1_C"] = p1Temp.toDouble()
        if (p1LoRaw != 0xeaa) fields["temperature_1_LO_C"] = p1TLo.toDouble()
        fields["temperature_1_HI_C"] = p1THi.toDouble()
        if (p2Raw != 0xedd) fields["temperature_2_C"] = p2Temp.toDouble()
        if (p2LoRaw != 0xeaa) fields["temperature_2_LO_C"] = p2TLo.toDouble()
        fields["temperature_2_HI_C"] = p2THi.toDouble()
        fields["flags"] = flags
        fields["mic"] = "CHECKSUM"
        return listOf(Reading("ThermoPro-TP828b", String.format("%02x", id), fields))
    }
}

// unverified: thermopro_tp82xb.c:169-249, struct thermopro_tp82xb.c:290
internal object ThermoproTp829b : Rtl433Decoder() {
    override val name = "ThermoPro Meat Thermometers, TP829B 4 probes with temp only"
    override val mod = Mod.FSK_PCM
    override val short = 102
    override val long = 102
    override val reset = 1500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows > 1) return emptyList()
        val msgLen = bb.bitsPerRow[0]
        if (msgLen > 260) return emptyList()
        val offset0 = bb.search(0, 0, intArrayOf(0x55, 0x2d, 0xd4), 24)
        if (offset0 >= msgLen) return emptyList()
        if ((msgLen - offset0) < 96) return emptyList()
        val offset = offset0 + 24
        val b = IntArray(9)
        bb.extractBytes(0, offset, b, 9 * 8)
        if (b[5] == 0xaa && b[6] == 0x55 && b[7] == 0xaa && b[8] == 0) return emptyList()
        val bReflect = IntArray(8)
        for (p in 7 downTo 0) bReflect[7 - p] = b[p]
        val checksum = Rtl433BitUtil.lfsrDigest8(bReflect, 8, 0x98, 0x55)
        if (checksum != b[8]) return emptyList()
        val id = b[0]
        val displayU = (b[1] and 0xF0) shr 4
        val flags = b[1] and 0xF
        val p1Raw = (b[2] shl 4) or ((b[3] and 0xF0) shr 4)
        val p2Raw = ((b[3] and 0x0F) shl 8) or b[4]
        val p3Raw = (b[5] shl 4) or ((b[6] and 0xF0) shr 4)
        val p4Raw = ((b[6] and 0x0F) shl 8) or b[7]
        val fields = linkedMapOf<String, Any?>()
        if (displayU == 0x2) fields["display_u"] = "Fahrenheit"
        if (displayU == 0x0) fields["display_u"] = "Celsius"
        if (p1Raw != 0xedd) fields["temperature_1_C"] = ((p1Raw - 500) * 0.1f).toDouble()
        if (p2Raw != 0xedd) fields["temperature_2_C"] = ((p2Raw - 500) * 0.1f).toDouble()
        if (p3Raw != 0xedd) fields["temperature_3_C"] = ((p3Raw - 500) * 0.1f).toDouble()
        if (p4Raw != 0xedd) fields["temperature_4_C"] = ((p4Raw - 500) * 0.1f).toDouble()
        fields["flags"] = flags
        fields["mic"] = "CHECKSUM"
        return listOf(Reading("ThermoPro-TP829b", String.format("%02x", id), fields))
    }
}

// unverified: thermopro_tp86xb.c:48-129, struct thermopro_tp86xb.c:146
internal object ThermoproTp86xb : Rtl433Decoder() {
    override val name = "ThermoPro TempSpike XR TP862b / TP863b Wireless Dual-Probe Meat Thermometer"
    override val mod = Mod.FSK_PCM
    override val short = 104
    override val long = 104
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows > 1) return emptyList()
        val msgLen = bb.bitsPerRow[0]
        if (msgLen < 165) return emptyList()
        if (msgLen > 173) return emptyList()
        var offset = bb.search(0, 0, intArrayOf(0xd2, 0x55, 0x2d, 0xd4), 32)
        if (offset >= msgLen) return emptyList()
        offset += 32
        val payloadLen = msgLen - offset
        if (payloadLen < 72) return emptyList()
        val b = IntArray(9)
        bb.extractBytes(0, offset, b, 9 * 8)
        if ((b[7] and b[8]) != 0) return emptyList()
        val calcCrc = Rtl433BitUtil.crc8(b, 7, 0x07, 0x00) xor 0xdb
        if (calcCrc != b[7]) return emptyList()
        val id = b[0]
        val isWhite = (b[1] and 0x10) shr 4
        val isDocked = (b[1] and 0x40) shr 6
        val internalRaw = (b[2] shl 4) or (b[3] shr 4)
        val ambientRaw = ((b[3] and 0x0f) shl 8) or b[4]
        val isProbe = if ((b[6] and 0x0c) == 0x0c) 1 else 0
        val isBooster = if ((b[5] and 0xc0) == 0xc0) 1 else 0
        val probeBattery = (b[6] and 0x30) shr 4
        val boosterBattery = b[6] and 0x03
        val internalC = (internalRaw - 500) * 0.1f
        val ambientC = (ambientRaw - 500) * 0.1f
        val fields = linkedMapOf<String, Any?>(
            "color" to (if (isWhite != 0) "white" else "black"),
        )
        if (isDocked != 0) fields["is_docked"] = isDocked
        fields["temperature_int_C"] = internalC.toDouble()
        fields["temperature_amb_C"] = ambientC.toDouble()
        if (isProbe != 0) fields["is_probe"] = isProbe
        if (isBooster != 0) fields["is_booster"] = isBooster
        if (isProbe != 0) fields["probe_batery"] = probeBattery
        if (isBooster != 0) fields["booster_battery"] = boosterBattery
        fields["mic"] = "CRC"
        return listOf(Reading("ThermoPro-TempSpikeXR", String.format("%02x", id), fields))
    }
}

// unverified: thermopro_tx2.c:41-94, struct thermopro_tx2.c:108
internal object ThermoproTx2 : Rtl433Decoder() {
    override val name = "ThermoPro-TX2 temperature sensor"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 7000
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] <= 8 && bb.bitsPerRow[0] != 0) return emptyList()
        val r = bb.findRepeatedRow(4, 36)
        if (r < 0) return emptyList()
        if (bb.bitsPerRow[r] > 37) return emptyList()
        val b = bb.bb[r]
        if ((b[0] and 0xF0) != 0x90 && (b[0] and 0xF0) != 0x50) return emptyList()
        val type = b[0] shr 4
        val id = ((b[0] and 0x0F) shl 4) or ((b[1] and 0xF0) shr 4)
        val battery = b[1] and 0x08
        val button = (b[1] and 0x04) shr 2
        val channel = (b[1] and 0x03) + 1
        val tempRaw = s16((b[2] shl 8) or (b[3] and 0xF0)) shr 4
        val humidity = ((b[3] and 0x0F) shl 4) or (b[4] shr 4)
        val fields = linkedMapOf<String, Any?>(
            "subtype" to type,
            "channel" to channel,
            "battery_ok" to (if (battery == 0) 1 else 0),
            "temperature_C" to tempRaw * 0.1,
        )
        if (humidity != 0xcc) fields["humidity"] = humidity
        fields["button"] = button
        return listOf(Reading("Thermopro-TX2", id.toString(), fields))
    }
}

// unverified: thermopro_tx2c.c:53-98, struct thermopro_tx2c.c:112
internal object ThermoproTx2c : Rtl433Decoder() {
    override val name = "ThermoPro TX-2C, TX-2B Thermometer and Humidity sensor"
    override val mod = Mod.OOK_PPM
    override val short = 1958
    override val long = 3825
    override val gap = 7000
    override val reset = 8643

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(4, 36)
        if (row < 0) return emptyList()
        val b = bb.bb[row]
        if (bb.bitsPerRow[row] > 45) return emptyList()
        if ((b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0) ||
            (b[0] == 0xff && b[1] == 0xff && b[2] == 0xff && b[3] == 0xff)
        ) return emptyList()
        if ((b[4] and 0x0F) != 0x00 || b[5] != 0x00) return emptyList()
        val id = ((b[0] and 0xF) shl 4) or (b[1] shr 4)
        val battery = (b[1] and 0x08) shr 3
        val button = (b[1] and 0x04) shr 2
        val channel = (b[1] and 0x03) + 1
        val tempRaw = s16((b[2] shl 8) or b[3])
        val tempC = (tempRaw shr 4) * 0.1f
        val humidity = ((b[3] and 0xF) shl 4) or (b[4] shr 4)
        val fields = linkedMapOf<String, Any?>(
            "channel" to channel,
            "battery_ok" to (if (battery == 0) 1 else 0),
            "temperature_C" to tempC.toDouble(),
        )
        if (humidity != 0x0a) fields["humidity"] = humidity
        fields["button"] = button
        return listOf(Reading("Thermopro-TX2C", id.toString(), fields))
    }
}

// unverified: thermopro_tx7b.c:51-119, struct thermopro_tx7b.c:134
internal object ThermoproTx7b : Rtl433Decoder() {
    override val name = "ThermoPro TX-7B Outdoor Thermometer Hygrometer"
    override val mod = Mod.FSK_PCM
    override val short = 108
    override val long = 108
    override val reset = 1500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows > 1) return emptyList()
        val msgLen = bb.bitsPerRow[0]
        if (msgLen > 260) return emptyList()
        var offset = bb.search(0, 0, intArrayOf(0x55, 0x2d, 0xd4), 24)
        if (offset >= msgLen) return emptyList()
        if ((msgLen - offset) < 96) return emptyList()
        offset += 24
        val b = IntArray(9)
        bb.extractBytes(0, offset, b, 9 * 8)
        val checksum = Rtl433BitUtil.lfsrDigest8Reverse(b, 8, 0x98, 0x25)
        if (checksum != b[8]) return emptyList()
        val id = b[0]
        val channel = ((b[1] and 0x30) shr 4) + 1
        val lowBat = b[1] shr 7
        val txButton = (b[1] and 0x40) shr 6
        val flags = b[1] and 0xF
        val tempRaw = (b[2] shl 4) or ((b[3] and 0xF0) shr 4)
        val humidity = b[4]
        val temp = (tempRaw - 400) * 0.1f
        return listOf(
            Reading(
                "ThermoPro-TX7B",
                String.format("%02x", id),
                linkedMapOf<String, Any?>(
                    "battery_ok" to (if (lowBat == 0) 1 else 0),
                    "button" to txButton,
                    "channel" to channel,
                    "flags" to flags,
                    "temperature_C" to temp.toDouble(),
                    "humidity" to humidity,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

private val THERMOR_WIND_DIR_DEGR = intArrayOf(157, 45, 135, 67, 180, 22, 112, 90, 225, 337, 247, 315, 202, 0, 270, 292)

// unverified: thermor.c:67-197, struct thermor.c:213
internal object Thermor : Rtl433Decoder() {
    override val name = "Thermor DG950 weather station"
    override val mod = Mod.OOK_PWM
    override val short = 680
    override val long = 2100
    override val sync = 1438
    override val gap = 3000
    override val reset = 8000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 13) return emptyList()
        val b = IntArray(13)
        for (row in 0 until bb.numRows) {
            if (bb.bitsPerRow[row] != 9) return emptyList()
            if ((bb.bb[row][0] and 0x80) != 0) return emptyList()
            val tmp = IntArray(1)
            bb.extractBytes(row, 1, tmp, 8)
            b[row] = tmp[0]
        }
        reflectBytes(b, 13)
        if (b[0] == 0xff && b[1] == b[2] && b[1] == b[4] && b[1] == b[5] && b[1] == b[6] &&
            b[1] == b[7] && b[1] == b[8] && b[1] == b[10]
        ) {
            val newId = b[1].inv() and 0xff
            return listOf(
                Reading(
                    "Thermor-DG950",
                    newId.toString(),
                    mapOf("pairing" to 1, "mic" to "CHECKSUM"),
                ),
            )
        }
        val id = b[0].inv() and 0xff
        val tempChk = (b[1] + b[10]) and 0xff
        if ((tempChk + 1) != (b[3] and 0xff)) return emptyList()
        val tempInt = (b[1] - 195).toFloat()
        val tempDec = (b[10] - 245) * 0.1f
        val tempC = tempInt + tempDec
        val rainRate1 = b[2].inv() and 0xff
        val rainRate2 = (b[12].inv() and 0xff) - 7
        if (rainRate1 != rainRate2) return emptyList()
        val haveRain = true
        var windDirD = 0
        var haveWdir = false
        if (b[4] != 0xff && b[5] != 0xff) {
            if (b[4] != b[5]) return emptyList()
            windDirD = THERMOR_WIND_DIR_DEGR[b[4] and 0x0f]
            haveWdir = true
        }
        val windChk = (b[6].inv() + b[7].inv() + b[8].inv()) and 0xff
        if (windChk != (b[9].inv() and 0xff)) return emptyList()
        var windSpeedKmh = 0.0f
        var haveWspd = false
        if (b[8] != 0xff) {
            val windSpeedRaw = (b[6].inv() and 0xff) or ((b[7].inv() and 0xff) shl 8)
            val windCoef = b[8].inv() and 0xff
            val windRatio: Float = if (windSpeedRaw < 256) {
                ((windSpeedRaw * -0.0001746) + 0.155).toFloat()
            } else {
                0.11f
            }
            windSpeedKmh = windRatio * (windSpeedRaw - windCoef + 45)
            if (windSpeedKmh < 0) windSpeedKmh = 0.0f
            haveWspd = true
        }
        val fields = linkedMapOf<String, Any?>(
            "temperature_C" to tempC.toDouble(),
        )
        if (haveRain) fields["rain_rate_mm_h"] = (rainRate1 * 0.1f).toDouble()
        if (haveWdir) fields["wind_dir_deg"] = windDirD
        if (haveWspd) fields["wind_avg_km_h"] = windSpeedKmh.toDouble()
        fields["pairing"] = 0
        fields["mic"] = "CHECKSUM"
        return listOf(Reading("Thermor-DG950", id.toString(), fields))
    }
}

// unverified: thermor_a6n_132tx.c:53-117, struct thermor_a6n_132tx.c:128
internal object ThermorA6n132tx : Rtl433Decoder() {
    override val name = "Thermor A6N 132TX temperature sensor"
    override val mod = Mod.OOK_PPM
    override val short = 1000
    override val long = 2000
    override val gap = 2000
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows < 5) return emptyList()
        val row = bb.findRepeatedRow(5, 32)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] != 32) return emptyList()
        val b = bb.bb[row]
        val tempRaw = (b[1] shl 8) or b[2]
        if (tempRaw > 2500) return emptyList()
        val loSum = (b[0] and 0x0f) + (b[1] and 0x0f) + (b[2] and 0x0f)
        val overflow = loSum shr 4
        if ((loSum and 0x0f) != (b[3] and 0x0f)) return emptyList()
        val id = (b[0] shr 4) and 0x0f
        val hiSum = (b[0] shr 4) + (b[1] shr 4) + (b[2] shr 4)
        val chkHi = b[3] shr 4
        if (id == 4) {
            if (chkHi != ((hiSum + overflow) and 1)) return emptyList()
        } else {
            val chkHiMsb = Rtl433BitUtil.parity8(b[0] and 0x0f) xor
                Rtl433BitUtil.parity8(b[1] and 0x0f) xor
                Rtl433BitUtil.parity8(b[2])
            val chkHiLow = (2 + (hiSum and 1)) xor overflow
            if (chkHi != ((chkHiMsb shl 3) or chkHiLow)) return emptyList()
        }
        val channel = (b[0] shr 2) and 0x03
        val temperatureC = tempRaw * 0.1f
        return listOf(
            Reading(
                "Thermor-A6N132TX",
                id.toString(),
                mapOf(
                    "channel" to channel,
                    "temperature_C" to temperatureC.toDouble(),
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: tpms_gear_hive.c:59-117 (decode helper), tpms_gear_hive.c:120-139 (callback), struct tpms_gear_hive.c:152
internal object TmpsGearHive : Rtl433Decoder() {
    override val name = "Gear Hive TPMS sensor"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 120
    override val long = 224
    override val gap = 0
    override val reset = 800

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val payloadStart = bitpos + 16
        val remainingBits = bb.bitsPerRow[row] - payloadStart
        if (remainingBits < 72) return null
        val raw = IntArray(9)
        bb.extractBytes(row, payloadStart, raw, 72)
        val p = IntArray(9)
        p[0] = raw[0] xor 0x94
        for (i in 1 until 9) p[i] = raw[i] xor raw[i - 1]
        if ((p[6] and 0x3c) != 0x20) return null
        if ((p[7] and 0x3f) != 0x35) return null
        val sensorClass = p[1] and 0x0f
        val counter = ((p[1] shr 4) shl 8) or p[0]
        val id = (p[2] shl 16) or (p[3] shl 8) or p[4]
        val pressureRaw = p[5]
        val base = (80 + sensorClass * 64) and 0xff
        val pressureKpa = ((pressureRaw - base + 256) and 0xff).toFloat() * 6.25f
        val tempBits = (p[7] shr 6) or ((p[6] and 0x03) shl 2)
        val tempC = tempBits.toFloat() + 21.0f
        return Reading(
            "Gear-Hive",
            String.format("%06x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "counter" to counter,
                "pressure_kPa" to pressureKpa.toDouble(),
                "temperature_C" to tempC.toDouble(),
                "mic" to "CHECKSUM",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            var bitpos = 0
            while (true) {
                bitpos = bb.search(row, bitpos, intArrayOf(0x25, 0x94), 16)
                if (bitpos + 16 + 72 > bb.bitsPerRow[row]) break
                decodeAt(bb, row, bitpos)?.let { out.add(it) }
                bitpos += 16
            }
        }
        return out
    }
}

// unverified: tpms_abarth124.c:158-188 (callback), tpms_abarth124.c:71-155 (decode helper), struct tpms_abarth124.c:203
internal object TpmsAbarth124 : Rtl433Decoder() {
    override val name = "Abarth 124 Spider and Shenzhen EGQ Q85 TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 150

    private fun decodeAt(bb: BitBuffer, bitpos: Int, isQ85: Boolean): Reading? {
        val dataLen = if (isQ85) 96 else 72
        val packet = BitBuffer()
        bb.manchesterDecode(0, bitpos, packet, dataLen)
        if (packet.bitsPerRow[0] < dataLen) return null
        val b = packet.bb[0]
        if (Rtl433BitUtil.xorBytes(b, 9) != 0) return null
        val pressRaw = b[5]
        val tempRaw = b[6]
        val status = b[7]
        val flags = String.format("%02x", b[4])
        val idStr = String.format("%02x%02x%02x%02x", b[0], b[1], b[2], b[3])
        val tempCCheck = if (isQ85) tempRaw.toFloat() - 55.0f else tempRaw.toFloat() - 50.0f
        val tempMin = if (isQ85) -20.0f else -50.0f
        val tempMax = if (isQ85) 80.0f else 125.0f
        if (tempCCheck < tempMin || tempCCheck > tempMax) return null
        if (isQ85) {
            val crcLittleEndian = (b[11] shl 8) or b[10]
            if (Rtl433BitUtil.crc16(b, 10, 0x1021, 0xffff) != crcLittleEndian) return null
        }
        return if (isQ85) {
            Reading(
                "Shenzhen-EGQQ85",
                idStr,
                linkedMapOf<String, Any?>(
                    "type" to "TPMS",
                    "flags" to flags,
                    "pressure_kPa" to pressRaw.toDouble() * 3,
                    "temperature_C" to tempRaw.toDouble() - 55.0,
                    "status" to status,
                    "mic" to "CRC",
                ),
            )
        } else {
            Reading(
                "Abarth-124Spider",
                idStr,
                linkedMapOf<String, Any?>(
                    "type" to "TPMS",
                    "flags" to flags,
                    "pressure_kPa" to pressRaw.toDouble() * 1.38,
                    "temperature_C" to tempRaw.toDouble() - 50.0,
                    "status" to status,
                    "mic" to "CHECKSUM",
                ),
            )
        }
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val bits = bb.bitsPerRow[0]
        val isQ85 = when {
            bits > 150 && bits < 210 -> false
            bits > 210 && bits < 400 -> true
            else -> return emptyList()
        }
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0xaa, 0xaa, 0xa9), 24)
            if (bitpos + 80 > bb.bitsPerRow[0]) break
            decodeAt(bb, bitpos + 24, isQ85)?.let { out.add(it) }
            bitpos += 2
        }
        return out
    }
}

// unverified: tpms_airpuxem.c:108-133 (callback), tpms_airpuxem.c:37-105 (decode helper), struct tpms_airpuxem.c:149
internal object TpmsAirpuxem : Rtl433Decoder() {
    override val name = "Airpuxem TPMS TYH11_EU6_ZQ"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 150

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val dec = BitBuffer()
        bb.manchesterDecode(row, bitpos, dec, 354)
        if (dec.bitsPerRow[0] < 84) return null
        val b = dec.bb[0]
        if ((b[0] shr 4) != 0x5) return null
        val payload = IntArray(16)
        dec.extractBytes(0, 4, payload, 64)
        val crcCalc = Rtl433BitUtil.crc8(payload, 8, 0x2f, 0xaa)
        val crcs = IntArray(2)
        dec.extractBytes(0, 4 + 64, crcs, 16)
        if (crcs[0] != crcCalc) return null
        val idBytes = IntArray(10)
        dec.extractBytes(0, 4, idBytes, 10 * 8)
        val id = (idBytes[0] shl 24) or (idBytes[1] shl 16) or (idBytes[2] shl 8) or idBytes[3]
        val flags = (idBytes[4] shr 4) and 0x07
        val position = idBytes[4] and 0x07
        val pressure = (idBytes[5] or (((idBytes[4] shr 7) and 1) shl 8) or (((idBytes[4] shr 3) and 1) shl 9)) - 100
        val temperature = idBytes[6].toByte().toInt()
        val battery = idBytes[7]
        return Reading(
            "Airpuxem-TYH11EU6ZQ",
            String.format("%08x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "position" to position,
                "flags" to flags,
                "pressure_kPa" to pressure.toDouble(),
                "temperature_C" to temperature.toDouble(),
                "battery_V" to battery.toDouble() * 0.02,
                "code" to bitrowSnprint(b, 11 * 8),
                "mic" to "CRC",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            var bitpos = 0
            while (true) {
                bitpos = bb.search(row, bitpos, intArrayOf(0xaa, 0xaa, 0xa9), 24)
                if (bitpos + 80 > bb.bitsPerRow[row]) break
                decodeAt(bb, row, bitpos + 24)?.let { out.add(it) }
                bitpos += 2
            }
        }
        return out
    }
}

// unverified: tpms_ave.c:115-139 (callback), tpms_ave.c:33-109 (decode helper), struct tpms_ave.c:155
internal object TpmsAve : Rtl433Decoder() {
    override val name = "AVE TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 100
    override val long = 100
    override val reset = 400
    override val tolerance = 15

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.differentialManchesterDecode(row, bitpos, packet, 160)
        if (packet.bitsPerRow[row] < 64) return null
        val b = packet.bb[row]
        if (Rtl433BitUtil.crc8(b, 8, 0x31, 0xff) != 0) return null
        val id = (b[0] shl 24) or (b[1] shl 16) or (b[2] shl 8) or b[3]
        val pressureRaw = b[4]
        val temperature = b[5]
        val mode = (b[6] shr 6) and 0x3
        val batteryRaw = (b[6] shr 3) and 0x7
        val flags = b[6] and 0x7
        val batteryPct = when (batteryRaw) {
            6 -> 75
            7 -> 25
            else -> 100
        }
        val ratio: Double
        val offset: Double
        when (mode) {
            0 -> {
                ratio = 2.352f.toDouble()
                offset = 47.0f.toDouble()
            }
            2 -> {
                ratio = 5.491f.toDouble()
                offset = 18.2f.toDouble()
            }
            3 -> {
                ratio = 5.491f.toDouble()
                offset = 0.0
            }
            else -> {
                ratio = 2.352f.toDouble()
                offset = 0.0
            }
        }
        val pressure = (pressureRaw.toDouble() - offset) * ratio
        return Reading(
            "AVE",
            String.format("%08x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "mode" to mode,
                "pressure_kPa" to pressure,
                "temperature_C" to (temperature.toDouble() - 50.0),
                "battery_ok" to (if (batteryRaw != 7) 1 else 0),
                "battery_pct" to batteryPct,
                "flags" to flags,
                "mic" to "CRC",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            var bitpos = 0
            while (true) {
                bitpos = bb.search(0, bitpos, intArrayOf(0xcc, 0xcc, 0xcc, 0xcd), 32)
                if (bitpos + 132 > bb.bitsPerRow[0]) break
                val r = decodeAt(bb, row, bitpos + 32)
                if (r != null) {
                    out.add(r)
                    bitpos += 132
                }
                bitpos += 31
            }
        }
        return out
    }
}

// unverified: tpms_citroen.c:96-118 (callback), tpms_citroen.c:32-93 (decode helper), struct tpms_citroen.c:135
internal object TpmsCitroen : Rtl433Decoder() {
    override val name = "Citroen TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 150

    private fun decodeAt(bb: BitBuffer, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.manchesterDecode(0, bitpos, packet, 88)
        if (packet.bitsPerRow[0] < 80) return null
        val b = packet.bb[0]
        if (b[6] == 0 || b[7] == 0) return null
        var crc = 0
        for (i in 1..9) crc = crc xor b[i]
        if (crc != 0) return null
        val state = b[0]
        val id = (b[1] shl 24) or (b[2] shl 16) or (b[3] shl 8) or b[4]
        val flags = b[5] shr 4
        val repeat = b[5] and 0x0f
        val pressure = b[6]
        val temperature = b[7]
        val maybeBattery = b[8]
        return Reading(
            "Citroen",
            String.format("%08x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "state" to String.format("%02x", state),
                "flags" to flags,
                "repeat" to repeat,
                "pressure_kPa" to pressure.toDouble() * 1.364,
                "temperature_C" to (temperature.toDouble() - 50.0),
                "maybe_battery" to maybeBattery,
                "mic" to "CHECKSUM",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0xaa, 0xa9), 16)
            if (bitpos + 178 > bb.bitsPerRow[0]) break
            decodeAt(bb, bitpos + 16)?.let { out.add(it) }
            bitpos += 2
        }
        return out
    }
}

// unverified: tpms_bmw_g3.c:52-139, struct tpms_bmw_g3.c:156
internal object TpmsBmwg3 : Rtl433Decoder() {
    override val name = "BMW Gen2 and Gen3 TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 160

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val pos = bb.search(0, 0, intArrayOf(0xcc, 0xcd), 16)
        if (pos >= bb.bitsPerRow[0]) return emptyList()
        val decoded = BitBuffer()
        bb.differentialManchesterDecode(0, pos + 16, decoded, 88)
        val msgLen = decoded.bitsPerRow[0]
        val isGen2 = 80 <= msgLen && msgLen < 88
        if (msgLen < 80) return emptyList()
        val b = decoded.bb[0]
        if (Rtl433BitUtil.crc16(b, if (isGen2) 10 else 11, 0x1021, 0x0000) != 0) return emptyList()
        val pressureKpa = (b[4] - 43) * 2.5f
        val temperatureC = (b[5] - 40).toFloat()
        val flags1 = b[6]
        val flags2 = b[7]
        val flags3 = b[8]
        val id = (b[0] shl 24) or (b[1] shl 16) or (b[2] shl 8) or b[3]
        val idStr = (id.toLong() and 0xFFFFFFFFL).toString()
        val msgStr = bitrowSnprint(b, if (isGen2) 80 else 88)
        val fields = linkedMapOf<String, Any?>(
            "type" to "TPMS",
            "uid" to idStr,
            "pressure_kPa" to pressureKpa.toDouble(),
            "temperature_C" to temperatureC.toDouble(),
            "flags1" to flags1,
            "flags2" to flags2,
        )
        if (!isGen2) fields["flags3"] = flags3
        fields["msg"] = msgStr
        fields["mic"] = "CRC"
        return listOf(Reading(if (isGen2) "BMW-GEN2" else "BMW-GEN3", idStr, fields))
    }
}

// unverified: tpms_bmw.c:82-168, struct tpms_bmw.c:186
internal object TpmsBmw : Rtl433Decoder() {
    override val name = "BMW Gen4-Gen5 TPMS and Audi TPMS Pressure Alert, multi-brand HUF/Beru, Continental, Schrader/Sensata, Audi"
    override val mod = Mod.FSK_PCM
    override val short = 25
    override val long = 25
    override val reset = 100

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val pos = bb.search(0, 0, intArrayOf(0xaa, 0x59), 16)
        if (pos >= bb.bitsPerRow[0]) return emptyList()
        val decoded = BitBuffer()
        var lenMsg = 11
        bb.manchesterDecode(0, pos + 16, decoded, lenMsg * 8)
        if (decoded.bitsPerRow[0] < 88) {
            if (decoded.bitsPerRow[0] >= 64) {
                lenMsg = 8
            } else {
                return emptyList()
            }
        }
        decoded.invert()
        val b = decoded.bb[0]
        if (Rtl433BitUtil.crc8(b, lenMsg, 0x2f, 0xaa) != 0) return emptyList()
        val brandId = b[0]
        val pressureKpa = (b[5] * 2.45).toFloat()
        val temperatureC = b[6] - 52
        val idStr = String.format("%02x%02x%02x%02x", b[1], b[2], b[3], b[4])
        val fields = linkedMapOf<String, Any?>(
            "type" to "TPMS",
        )
        if (lenMsg == 8) fields["alert"] = "Alert Pressure increase/decrease !"
        fields["brand"] = brandId
        fields["pressure_kPa"] = pressureKpa.toDouble()
        fields["temperature_C"] = temperatureC.toDouble()
        if (lenMsg == 11) {
            fields["flags1"] = b[7]
            fields["flags2"] = b[8]
            fields["flags3"] = b[9]
        }
        fields["msg"] = bitrowSnprint(b, lenMsg * 8)
        fields["mic"] = "CRC"
        return listOf(Reading(if (lenMsg == 11) "BMW-GEN5" else "Audi-PressureAlert", idStr, fields))
    }
}

// unverified: tpms_eezrv.c:73-152, struct tpms_eezrv.c:168
internal object TpmsEezrv : Rtl433Decoder() {
    override val name = "EezTire E618, Carchet TPMS, TST-507 TPMS"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 50
    override val long = 50
    override val reset = 120

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        bb.invert()
        val pos = bb.search(0, 0, intArrayOf(0xff, 0xff), 16)
        if (pos >= bb.bitsPerRow[0]) return emptyList()
        if (pos > 0) return emptyList()
        if (pos + 10 * 8 > bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(7)
        val cc = IntArray(1)
        bb.extractBytes(0, pos + 16, cc, 8)
        bb.extractBytes(0, pos + 24, b, 7 * 8)
        var computedChecksum = Rtl433BitUtil.addBytes(b, 7)
        if (computedChecksum > 0xff) computedChecksum = computedChecksum or 0x80
        if ((computedChecksum and 0xff) != cc[0]) return emptyList()
        val temperatureC = b[4] - 50
        val flags1 = b[5]
        val flags2 = b[6]
        val fastLeakDetected = flags1 and 0x10
        val inflDetected = (flags1 and 0x20) shr 5
        val fastLeak = if (fastLeakDetected != 0 && inflDetected == 0) 1 else 0
        val pressureKpa = (((flags2 and 0x01) shl 8) + b[3]) * 2.5f
        val lowBatt = flags1 shr 7
        val idStr = String.format("%02x%02x%02x", b[0], b[1], b[2])
        val flagsStr = String.format("%02x%02x", flags1, flags2)
        return listOf(
            Reading(
                "EezTire-E618",
                idStr,
                linkedMapOf<String, Any?>(
                    "type" to "TPMS",
                    "battery_ok" to (if (lowBatt == 0) 1 else 0),
                    "pressure_kPa" to pressureKpa.toDouble(),
                    "temperature_C" to temperatureC.toDouble(),
                    "flags" to flagsStr,
                    "fast_leak" to fastLeak,
                    "inflate" to inflDetected,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: tpms_elantra2012.c:100-126 (callback), tpms_elantra2012.c:53-97 (decode helper), struct tpms_elantra2012.c:142
internal object TpmsElantra2012 : Rtl433Decoder() {
    override val name = "Elantra2012 TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 49
    override val long = 49
    override val reset = 200

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.manchesterDecode(row, bitpos, packet, 64)
        if (packet.bitsPerRow[0] < 64) return null
        val b = packet.bb[0]
        if (Rtl433BitUtil.crc8(b, 8, 0x07, 0x00) != 0) return null
        val id = (b[2] shl 24) or (b[3] shl 16) or (b[4] shl 8) or b[5]
        val flags = b[6]
        val pressureKpa = b[0] + 60
        val temperatureC = b[1] - 50
        val storage = (b[6] and 0x04) shr 2
        val batteryLow = (b[6] and 0x02) shr 1
        val triggered = (b[6] and 0x01) shr 0
        return Reading(
            "Elantra2012",
            String.format("%08x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "pressure_kPa" to pressureKpa.toFloat().toDouble(),
                "temperature_C" to temperatureC.toFloat().toDouble(),
                "battery_ok" to (if (batteryLow == 0) 1 else 0),
                "triggered" to triggered,
                "storage" to storage,
                "flags" to String.format("%x", flags),
                "mic" to "CRC",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            var bitpos = 0
            while (true) {
                bitpos = bb.search(row, bitpos, intArrayOf(0x71, 0x55), 16)
                if (bitpos + 128 > bb.bitsPerRow[row]) break
                decodeAt(bb, row, bitpos + 16)?.let { out.add(it) }
                bitpos += 15
            }
        }
        return out
    }
}

// unverified: tpms_ford.c:172-198 (callback), tpms_ford.c:56-169 (decode helper), struct tpms_ford.c:216
internal object TpmsFord : Rtl433Decoder() {
    override val name = "Ford TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 150

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.manchesterDecode(row, bitpos, packet, 160)
        if (packet.bitsPerRow[0] < 64) return null
        val b = packet.bb[0]
        if (((b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6]) and 0xff) != b[7]) return null
        val id = (b[0] shl 24) or (b[1] shl 16) or (b[2] shl 8) or b[3]
        val code = (b[4] shl 16) or (b[5] shl 8) or b[6]
        val psibits = ((b[6] and 0x20) shl 3) or b[4]
        val pressurePsi = psibits * 0.25f
        var temperatureValid = false
        var temperatureC = -1000
        if ((b[5] and 0x80) == 0) {
            temperatureValid = true
            temperatureC = (b[5] and 0x7f) - 56
        }
        var learn = 0
        var moving = 0
        var unknown = 0
        when (b[6] and 0x4c) {
            0x8 -> learn = 1
            0x4 -> {}
            0x44 -> moving = 1
            else -> unknown = b[6] and 0x4c
        }
        unknown = unknown or (b[6] and 0x90)
        if (unknown != 0) return null
        val unknown3 = b[6] and 0x3
        val fields = linkedMapOf<String, Any?>(
            "type" to "TPMS",
            "pressure_PSI" to pressurePsi.toDouble(),
        )
        if (temperatureValid) fields["temperature_C"] = temperatureC.toFloat().toDouble()
        fields["moving"] = moving
        fields["learn"] = learn
        fields["code"] = String.format("%06x", code)
        fields["unknown"] = String.format("%02x", unknown)
        fields["unknown_3"] = String.format("%01x", unknown3)
        fields["mic"] = "CHECKSUM"
        return Reading("Ford", String.format("%08x", id), fields)
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            var bitpos = 0
            while (true) {
                bitpos = bb.search(row, bitpos, intArrayOf(0xaa, 0xa9), 16)
                if (bitpos + 144 > bb.bitsPerRow[row]) break
                decodeAt(bb, row, bitpos + 16)?.let { out.add(it) }
                bitpos += 15
            }
        }
        return out
    }
}

// unverified: tpms_gm.c:52-126, struct tpms_gm.c:142
internal object TpmsGm : Rtl433Decoder() {
    override val name = "GM-Aftermarket TPMS"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 120
    override val reset = 15600

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] != 130) return emptyList()
        val b = IntArray(17)
        bb.extractBytes(0, 0, b, 130)
        for (i in 0 until 6) if (b[i] != 0) return emptyList()
        var computedChecksum = 0
        var allZero = true
        for (i in 6 until 15) {
            computedChecksum = (computedChecksum + b[i]) and 0xff
            if (b[i] != 0) allZero = false
        }
        if (computedChecksum != b[15]) return emptyList()
        if (allZero && b[15] == 0) return emptyList()
        val sensorId = (b[8].toLong() shl 32) or (b[9].toLong() shl 24) or (b[10].toLong() shl 16) or (b[11].toLong() shl 8) or b[12].toLong()
        val flags = (b[6] shl 8) or b[7]
        val pressureRaw = b[13]
        val temperatureRaw = b[14]
        val pressureKpa = (pressureRaw * 2.75).toFloat()
        val temperatureC = (temperatureRaw - 60).toFloat()
        val bit8 = (flags shr 8) and 1
        val bit1 = (flags shr 1) and 1
        val bit0 = flags and 1
        val learnMode = if (bit8 == 0 && bit1 == 0 && bit0 == 0) 1 else 0
        val batteryOk = if (((flags shr 5) and 1) == 0) 1 else 0
        return listOf(
            Reading(
                "GM-Aftermarket",
                sensorId.toInt().toString(),
                linkedMapOf<String, Any?>(
                    "type" to "TPMS",
                    "flags" to flags,
                    "learn_mode" to learnMode,
                    "battery_ok" to batteryOk,
                    "pressure_kPa" to pressureKpa.toDouble(),
                    "temperature_C" to temperatureC.toDouble(),
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: tpms_honda.c:44-106, struct tpms_honda.c:119
internal object TpmsHonda : Rtl433Decoder() {
    override val name = "Honda (TRW PPA-GF33) TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 50
    override val long = 50
    override val reset = 200

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        if (bb.search(0, 0, intArrayOf(0xda, 0xe3, 0x54), 23) != 0) return emptyList()
        val bitpos = 23
        if (bitpos + 128 > bb.bitsPerRow[0]) return emptyList()
        val packet = BitBuffer()
        bb.manchesterDecode(0, bitpos, packet, 64)
        if (packet.bitsPerRow[0] < 64) return emptyList()
        val b = packet.bb[0]
        if (Rtl433BitUtil.crc8(b, 7, 0x07, 0x00) != b[7]) return emptyList()
        val pressureRaw = b[0]
        val pressurePsi = pressureRaw * 0.2f
        val temperatureRaw = b[1]
        val temperatureC = temperatureRaw - 50
        val id = (b[2] shl 24) or (b[3] shl 16) or (b[4] shl 8) or b[5]
        val flags = b[6]
        if (pressureRaw > 0 && pressureRaw < 50) return emptyList()
        return listOf(
            Reading(
                "Honda-TRW",
                String.format("%08x", id),
                linkedMapOf<String, Any?>(
                    "type" to "TPMS",
                    "pressure_PSI" to pressurePsi.toDouble(),
                    "temperature_C" to temperatureC,
                    "flags" to flags,
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: tpms_hyundai_vdo.c:107-128 (callback), tpms_hyundai_vdo.c:43-101 (decode helper), struct tpms_hyundai_vdo.c:144
internal object TpmsHyundaiVdo : Rtl433Decoder() {
    override val name = "Hyundai TPMS (VDO)"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 150

    private fun decodeAt(bb: BitBuffer, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.manchesterDecode(0, bitpos, packet, 80)
        if (packet.bitsPerRow[0] < 80) return null
        val b = packet.bb[0]
        val crc = b[9]
        if (Rtl433BitUtil.crc8(b, 9, 0x07, 0xaa) != crc) return null
        val state = b[0]
        val id = (b[1] shl 24) or (b[2] shl 16) or (b[3] shl 8) or b[4]
        val flags = b[5] shr 4
        val repeat = b[5] and 0x0f
        val pressure = b[6]
        val temperature = b[7]
        val maybeBattery = b[8]
        return Reading(
            "Hyundai-VDO",
            String.format("%08x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "state" to state,
                "flags" to flags,
                "repeat" to repeat,
                "pressure_kPa" to pressure.toDouble() * 1.375,
                "temperature_C" to (temperature.toDouble() - 50.0),
                "maybe_battery" to maybeBattery,
                "mic" to "CRC",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0xaa, 0xaa, 0xaa, 0xa9), 32)
            if (bitpos + 80 > bb.bitsPerRow[0]) break
            decodeAt(bb, bitpos + 32)?.let { out.add(it) }
            bitpos += 2
        }
        return out
    }
}

// unverified: tpms_imars_t240.c:47-102, struct tpms_imars_t240.c:112
internal object TpmsImarsT240 : Rtl433Decoder() {
    override val name = "iMars T240 TPMS"
    override val mod = Mod.OOK_PCM
    override val short = 50
    override val long = 50
    override val reset = 200

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val len = bb.bitsPerRow[0]
        val pos = bb.search(0, 0, intArrayOf(0xaa, 0xaa, 0xaa), 24)
        if (pos >= len) return emptyList()
        if (len - pos < 160) return emptyList()
        val packet = BitBuffer()
        bb.manchesterDecode(0, pos + 32, packet, 64)
        packet.invert()
        if (packet.bitsPerRow[0] < 64) return emptyList()
        val b = packet.bb[0]
        if (b[7] != b[0]) return emptyList()
        if ((b[0] and 0x0f) != (b[1] and 0x0f)) return emptyList()
        val checksum = (b[3] + b[4]) and 0xff
        if (checksum != 0x41 && checksum != 0x3c) return emptyList()
        val codeStr = String.format("%02x%02x%02x%02x%02x%02x%02x", b[0], b[1], b[2], b[3], b[4], b[5], b[6])
        return listOf(
            Reading(
                "iMars-T240",
                null,
                mapOf(
                    "type" to "TPMS",
                    "code" to codeStr,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: tpms_jansite.c:80-102 (callback), tpms_jansite.c:32-77 (decode helper), struct tpms_jansite.c:116
internal object TpmsJansite : Rtl433Decoder() {
    override val name = "Jansite TPMS Model TY02S"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 150

    private fun decodeAt(bb: BitBuffer, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.manchesterDecode(0, bitpos, packet, 56)
        if (packet.bitsPerRow[0] < 56) return null
        val b = packet.bb[0]
        val id = (b[0] shl 20) or (b[1] shl 12) or (b[2] shl 4) or (b[3] shr 4)
        val flags = b[3] and 0x0F
        val pressure = b[4]
        val temperature = b[5]
        val codeStr = String.format("%02x%02x%02x%02x%02x%02x%02x", b[0], b[1], b[2], b[3], b[4], b[5], b[6])
        return Reading(
            "Jansite",
            String.format("%07x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "flags" to flags,
                "pressure_kPa" to pressure.toDouble() * 1.7,
                "temperature_C" to (temperature.toDouble() - 50.0),
                "code" to codeStr,
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0xaa, 0xaa, 0xa9), 24)
            if (bitpos + 80 > bb.bitsPerRow[0]) break
            decodeAt(bb, bitpos + 24)?.let { out.add(it) }
            bitpos += 2
        }
        return out
    }
}

// unverified: tpms_jansite_solar.c:101-119 (callback), tpms_jansite_solar.c:44-98 (decode helper), struct tpms_jansite_solar.c:133
internal object TpmsJansiteSolar : Rtl433Decoder() {
    override val name = "Jansite TPMS Model Solar"
    override val mod = Mod.FSK_PCM
    override val short = 51
    override val long = 51
    override val reset = 5000

    private fun decodeAt(bb: BitBuffer, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.manchesterDecode(0, bitpos, packet, 88)
        packet.invert()
        if (packet.bitsPerRow[0] < 88) return null
        val b = packet.bb[0]
        if (((b[0] shl 8) or b[1]) != 0xdd33) return null
        val crcCalc = Rtl433BitUtil.crc16(b.copyOfRange(2, 9), 7, 0x8005, 0x0000)
        if (((b[9] shl 8) or b[10]) != crcCalc) return null
        val id = (b[2] shl 16) or (b[3] shl 8) or b[4]
        val flags = b[5]
        val temperature = b[6]
        val pressure = b[7]
        val codeStr = String.format("%02x%02x%02x%02x%02x%02x%02x%02x%02x", b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10])
        return Reading(
            "Jansite-Solar",
            String.format("%06x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "flags" to flags,
                "pressure_kPa" to pressure.toDouble() * 1.6,
                "temperature_C" to (temperature.toDouble() - 55.0),
                "code" to codeStr,
                "mic" to "CRC",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0xa6, 0xa6, 0x5a), 24)
            if (bitpos + 80 > bb.bitsPerRow[0]) break
            decodeAt(bb, bitpos)?.let { out.add(it) }
            bitpos += 2
        }
        return out
    }
}

// unverified: tpms_jansite_ty468.c:56-127, struct tpms_jansite_ty468.c:139
internal object TpmsJansiteTy468 : Rtl433Decoder() {
    override val name = "Jansite TPMS TY-468-eu2 / KKMOON TPMS"
    override val mod = Mod.OOK_PCM
    override val short = 50
    override val long = 50
    override val reset = 200

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val len = bb.bitsPerRow[0]
        val pos = bb.search(0, 0, intArrayOf(0xaa, 0xaa, 0xaa), 24)
        if (pos >= len) return emptyList()
        if (len - pos < 160) return emptyList()
        val packet = BitBuffer()
        bb.manchesterDecode(0, pos + 32, packet, 64)
        packet.invert()
        if (packet.bitsPerRow[0] < 64) return emptyList()
        val b = packet.bb[0]
        if (b[7] != b[0]) return emptyList()
        if ((b[0] and 0x0f) != (b[1] and 0x0f)) return emptyList()
        val checksum = (b[3] + b[4]) and 0xff
        val tempOffset: Int
        val pressureOffset: Int
        if (checksum == 0xfb) {
            tempOffset = 224
            pressureOffset = 273
        } else if (checksum == 0x64) {
            tempOffset = 153
            pressureOffset = 201
        } else {
            return emptyList()
        }
        val temperatureC = (tempOffset - ((b[2] + b[5]) and 0xff)).toFloat()
        val pressureKpa = (pressureOffset - ((b[5] + b[6]) and 0xff)) * 2.5f
        val codeStr = String.format("%02x%02x%02x%02x%02x%02x%02x", b[0], b[1], b[2], b[3], b[4], b[5], b[6])
        return listOf(
            Reading(
                "Jansite-TY468",
                null,
                mapOf(
                    "type" to "TPMS",
                    "temperature_C" to temperatureC.toDouble(),
                    "pressure_kPa" to pressureKpa.toDouble(),
                    "code" to codeStr,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: tpms_jansite_ty588.c:109-129 (callback), tpms_jansite_ty588.c:57-106 (decode helper), struct tpms_jansite_ty588.c:141
internal object TpmsJansiteTy588 : Rtl433Decoder() {
    override val name = "Jansite TPMS TY588-EU2"
    override val mod = Mod.FSK_PCM
    override val short = 51
    override val long = 51
    override val reset = 5000

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.manchesterDecode(row, bitpos + 44, packet, 64)
        if (packet.bitsPerRow[0] < 64) return null
        val b = packet.bb[0]
        if (b[7] != b[0]) return null
        if (((b[3] + b[4]) and 0xff) != 0x30 || (b[0] and 0x0f) != (b[1] and 0x0f)) return null
        val rawTemp = (b[2] + b[5]) and 0xff
        val rawPressure = (b[5] + b[6]) and 0xff
        val temperature = rawTemp - 139
        val pressureRaw = rawPressure - 90
        if (pressureRaw < 0 || temperature < -40 || temperature > 120) return null
        val codeStr = String.format("%02x%02x%02x%02x%02x%02x%02x", b[0], b[1], b[2], b[3], b[4], b[5], b[6])
        return Reading(
            "Jansite-TY588",
            null,
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "pressure_kPa" to pressureRaw.toDouble() * 2.5,
                "temperature_C" to temperature.toDouble(),
                "code" to codeStr,
                "mic" to "CHECKSUM",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0x99, 0xaa, 0x5a), 24)
            if (bitpos + 172 > bb.bitsPerRow[0]) break
            decodeAt(bb, 0, bitpos)?.let { out.add(it) }
            bitpos += 2
        }
        return out
    }
}

// unverified: tpms_jeep.c:106-128 (callback), tpms_jeep.c:43-103 (decode helper), struct tpms_jeep.c:145
internal object TpmsJeep : Rtl433Decoder() {
    override val name = "Jeep TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 150

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.manchesterDecode(row, bitpos, packet, 88)
        if (packet.bitsPerRow[0] < 80) return null
        val b = packet.bb[0]
        if (b[6] == 0 || b[7] == 0) return null
        var crc = 0
        for (i in 1..9) crc = crc xor b[i]
        if (crc != 0) return null
        val state = b[0]
        val id = (b[1] shl 24) or (b[2] shl 16) or (b[3] shl 8) or b[4]
        val flags = b[5] shr 4
        val repeat = b[5] and 0x0f
        val pressure = b[6]
        val temperature = b[7]
        val maybeBattery = b[8]
        return Reading(
            "Jeep",
            String.format("%08x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "state" to String.format("%02x", state),
                "flags" to flags,
                "repeat" to repeat,
                "pressure_kPa" to pressure.toDouble() * 2.728,
                "temperature_C" to (temperature.toDouble() - 50.0),
                "maybe_battery" to maybeBattery,
                "mic" to "CHECKSUM",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0xaa, 0xa9), 16)
            if (bitpos + 178 > bb.bitsPerRow[0]) break
            decodeAt(bb, 0, bitpos + 16)?.let { out.add(it) }
            bitpos += 2
        }
        return out
    }
}

// unverified: tpms_kia.c:112-131 (callback), tpms_kia.c:44-106 (decode helper), struct tpms_kia.c:146
internal object TpmsKia : Rtl433Decoder() {
    override val name = "Kia TPMS (-s 1000k)"
    override val mod = Mod.FSK_PCM
    override val short = 50
    override val long = 50
    override val reset = 200

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val packet = BitBuffer()
        val startPos = bb.manchesterDecode(row, bitpos, packet, 154 - 16)
        if (startPos - bitpos < 154 - 16) return null
        val b = packet.bb[0]
        val unknown1 = b[0] shr 4
        val pressure = ((b[0] shl 4) or (b[1] shr 4)) and 0xff
        val temperature = ((b[1] shl 4) or (b[2] shr 4)) and 0xff
        val id = (b[2] shl 28) or (b[3] shl 20) or (b[4] shl 12) or (b[5] shl 4) or (b[6] shr 4)
        val unknown2 = ((b[6] shl 8) or b[7]) and 0xff
        val crc = b[8] and 0xF8
        val c = Rtl433BitUtil.crc8(b, 8, 0x07, 0x76)
        if (crc != c) return null
        val raw = String.format("%02x%02x%02x%02x%02x%02x%02x%02x%02x", b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8])
        val pressureFloat = pressure / 5.0f
        val temperatureFloat = temperature - 50.0f
        return Reading(
            "Kia",
            String.format("%08x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "unknown1" to String.format("%02x", unknown1),
                "unknown2" to String.format("%03x", unknown2),
                "pressure_PSI" to pressureFloat.toDouble(),
                "temperature_C" to temperatureFloat.toDouble(),
                "raw" to raw,
                "mic" to "CRC",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0xed, 0x71), 16)
            if (bitpos + 154 > bb.bitsPerRow[0]) break
            decodeAt(bb, 0, bitpos + 16)?.let { out.add(it) }
            bitpos += 2
        }
        return out
    }
}

// unverified: tpms_mercedes_benz.c:37-97, struct tpms_mercedes_benz.c:112
internal object TpmsMercedesBenz : Rtl433Decoder() {
    override val name = "Mercedes Benz Sprinter 4500 TPMS sensor"
    override val mod = Mod.FSK_MC_ZEROBIT
    override val short = 25
    override val long = 25
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        var pos = bb.search(0, 0, intArrayOf(0x00, 0x20), 12)
        if (pos >= bb.bitsPerRow[0]) return emptyList()
        if (bb.bitsPerRow[0] < 80) return emptyList()
        pos += 12
        val b = IntArray(10)
        bb.extractBytes(0, pos, b, 80)
        if (Rtl433BitUtil.crc8(b, 10, 0x2f, 0xaa) != 0) return emptyList()
        if (b[0] != 0x83 && b[0] != 0xa3) return emptyList()
        val idStr = String.format("%02x%02x%02x%02x", b[1], b[2], b[3], b[4])
        val pressurePsi = b[5] / 2.75f
        val temperatureC = b[6] - 51
        val counter = b[7] and 0x1f
        val flags1 = b[7] shr 5
        val flags2 = b[8]
        return listOf(
            Reading(
                "MercedesBenz-Sprinter",
                idStr,
                linkedMapOf<String, Any?>(
                    "type" to "TPMS",
                    "pressure_PSI" to pressurePsi.toDouble(),
                    "temperature_C" to temperatureC.toDouble(),
                    "counter" to counter,
                    "flags1" to flags1,
                    "flags2" to flags2,
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

private fun nissanChecksum(b: IntArray): Int {
    var chk = 0
    for (i in 0 until 4) {
        chk = (chk + (b[i] shr 7)) and 0xff
        chk = (chk + (b[i] shr 5)) and 0xff
        chk = (chk + (b[i] shr 3)) and 0xff
        chk = (chk + (b[i] shr 1)) and 0xff
        chk = (chk + ((b[i] shl 1) and 0xff)) and 0xff
    }
    chk = (chk + (b[4] shr 7)) and 0xff
    chk = (chk + (b[4] shr 5)) and 0xff
    chk = (chk + (b[4] shr 3)) and 0xff
    return chk.inv() and 0x03
}

// unverified: tpms_nissan.c:91-110 (callback), tpms_nissan.c:40-88 (decode helper), struct tpms_nissan.c:123
internal object TpmsNissan : Rtl433Decoder() {
    override val name = "Nissan TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 120
    override val long = 120
    override val reset = 250

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.manchesterDecode(row, bitpos, packet, 113)
        if (packet.bitsPerRow[0] < 37) return null
        packet.invert()
        val b = packet.bb[0]
        if (nissanChecksum(b) != 0) return null
        val mode = b[0] shr 5
        val id = ((b[0] and 0x1F) shl 19) or (b[1] shl 11) or (b[2] shl 3) or (b[3] shr 5)
        val pressureRaw = ((b[3] and 0x1F) shl 3) or (b[4] shr 5)
        val pressurePsi = pressureRaw / 4.0f - 3.0f
        val unknown = (b[4] and 0x1F) shr 3
        return Reading(
            "Nissan",
            String.format("%06x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "mode" to mode,
                "pressure_PSI" to pressurePsi.toDouble(),
                "unknown" to unknown,
                "mic" to "CHECKSUM",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0xf5, 0x55, 0x55, 0x55, 0xe0), 36)
            if (bitpos + 77 > bb.bitsPerRow[0]) break
            decodeAt(bb, 0, bitpos + 36)?.let { out.add(it) }
            bitpos += 1
        }
        return out
    }
}

// unverified: tpms_pmv107j.c:99-118 (callback), tpms_pmv107j.c:36-96 (decode helper), struct tpms_pmv107j.c:135
internal object TpmsPmv107j : Rtl433Decoder() {
    override val name = "PMV-107J (Toyota) TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 100
    override val long = 100
    override val reset = 250

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val packet = BitBuffer()
        val startPos = bb.differentialManchesterDecode(row, bitpos, packet, 70)
        if (startPos - bitpos < 67 * 2) return null
        val b = IntArray(9)
        b[0] = packet.bb[0][0] shr 6
        val tmp = IntArray(8)
        packet.extractBytes(0, 2, tmp, 64)
        for (i in 0 until 8) b[i + 1] = tmp[i]
        val crc = b[8]
        if (Rtl433BitUtil.crc8(b, 8, 0x13, 0x00) != crc) return null
        val id = (b[0] shl 26) or (b[1] shl 18) or (b[2] shl 10) or (b[3] shl 2) or (b[4] shr 6)
        val status = b[4] and 0x3f
        val batteryLow = (b[4] and 0x20) shr 5
        val counter = (b[4] and 0x18) shr 3
        val rapidChange = (b[4] and 0x2) shr 1
        val failed = b[4] and 0x01
        val pressure1 = b[5]
        val pressure2 = b[6] xor 0xff
        val temp = b[7]
        val pressureKpa = (pressure1 - 40.0f) * 2.48f
        val temperatureC = temp - 40.0f
        if (pressure1 != pressure2) return null
        return Reading(
            "PMV-107J",
            String.format("%08x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "status" to status,
                "battery_ok" to (if (batteryLow == 0) 1 else 0),
                "counter" to counter,
                "rapid_change" to rapidChange,
                "failed" to (if (failed != 0) "FAIL" else "OK"),
                "pressure_kPa" to pressureKpa.toDouble(),
                "temperature_C" to temperatureC.toDouble(),
                "mic" to "CRC",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0xf8), 6)
            if (bitpos + 67 * 2 > bb.bitsPerRow[0]) break
            decodeAt(bb, 0, bitpos + 6)?.let { out.add(it) }
            bitpos += 2
        }
        return out
    }
}

// unverified: tpms_porsche.c:87-103 (callback), tpms_porsche.c:40-84 (decode helper), struct tpms_porsche.c:116
internal object TpmsPorsche : Rtl433Decoder() {
    override val name = "Porsche Boxster/Cayman TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 150

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.differentialManchesterDecode(row, bitpos, packet, 80)
        if (packet.bitsPerRow[0] < 80) return null
        val b = packet.bb[0]
        val checksum = Rtl433BitUtil.crc16(b, 10, 0x1021, 0xffff)
        if (checksum != 0) return null
        val id = (b[0] shl 24) or (b[1] shl 16) or (b[2] shl 8) or b[3]
        val pressure = b[4]
        val temperature = b[5]
        val flags = (b[6] shl 8) or b[7]
        val pressureKpa = pressure * 5 / 2 - 100
        val temperatureC = temperature - 40
        return Reading(
            "Porsche",
            String.format("%08x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "pressure_kPa" to pressureKpa.toFloat().toDouble(),
                "temperature_C" to temperatureC.toFloat().toDouble(),
                "flags" to flags,
                "mic" to "CRC",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0x33, 0x33, 0x20), 20)
            if (bitpos + 100 > bb.bitsPerRow[0]) break
            decodeAt(bb, 0, bitpos + 20)?.let { out.add(it) }
            bitpos += 2
        }
        return out
    }
}

// unverified: tpms_renault.c:82-108 (callback), tpms_renault.c:36-79 (decode helper), struct tpms_renault.c:121
internal object TpmsRenault : Rtl433Decoder() {
    override val name = "Renault TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 150

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.manchesterDecode(row, bitpos, packet, 160)
        if (packet.bitsPerRow[0] < 72) return null
        val b = packet.bb[0]
        if (Rtl433BitUtil.crc8(b, 8, 0x07, 0x00) != b[8]) return null
        val flags = b[0] shr 2
        val id = (b[5] shl 16) or (b[4] shl 8) or b[3]
        val pressureRaw = ((b[0] and 0x03) shl 8) or b[1]
        val pressureKpa = pressureRaw * 0.75
        val tempC = b[2] - 30
        return Reading(
            "Renault",
            String.format("%06x", id),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "flags" to String.format("%02x", flags),
                "pressure_kPa" to pressureKpa,
                "temperature_C" to tempC.toDouble(),
                "mic" to "CRC",
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            var bitpos = 0
            while (true) {
                bitpos = bb.search(row, bitpos, intArrayOf(0xaa, 0xa9), 16)
                if (bitpos + 160 > bb.bitsPerRow[row]) break
                decodeAt(bb, row, bitpos + 16)?.let { out.add(it) }
                bitpos += 15
            }
        }
        return out
    }
}

// unverified: tpms_renault_0435r.c:136-161 (callback), tpms_renault_0435r.c:73-133 (decode helper), struct tpms_renault_0435r.c:177
internal object TpmsRenault0435r : Rtl433Decoder() {
    override val name = "Renault 0435R TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 150

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.manchesterDecode(row, bitpos, packet, 160)
        if (packet.bitsPerRow[0] < 72) return null
        val b = packet.bb[0]
        if (Rtl433BitUtil.xorBytes(b, 9) != 0) return null
        val tick = b[8] and 0x7f
        val hasTick = b[8] shr 7
        if (b[8] != 0 && (hasTick == 0 || tick > 30)) return null
        val flags = b[3]
        val pressureRaw = b[4]
        val pressureKpa = pressureRaw / 0.75
        val tempC = b[5] - 50
        val radAcc = b[6] * 5
        return Reading(
            "Renault-0435R",
            String.format("%02x%02x%02x", b[0], b[1], b[2]),
            linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "flags" to String.format("%02x", flags),
                "pressure_kPa" to pressureKpa,
                "temperature_C" to tempC.toDouble(),
                "centrifugal_acc" to radAcc.toDouble(),
                "mic" to "CHECKSUM",
                "has_tick" to hasTick,
                "tick" to (tick - 0x80 * (1 - hasTick)),
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            var bitpos = 0
            while (true) {
                bitpos = bb.search(row, bitpos, intArrayOf(0xaa, 0xa9), 16)
                if (bitpos + 160 > bb.bitsPerRow[row]) break
                decodeAt(bb, row, bitpos + 16)?.let { out.add(it) }
                bitpos += 15
            }
        }
        return out
    }
}

// unverified: tpms_schrader_motorcycle.c:57-110, struct tpms_schrader_motorcycle.c:122
internal object TpmsSchraderMotorcycle : Rtl433Decoder() {
    override val name = "Schrader Motorcycle TPMS sensor"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 122
    override val long = 122
    override val reset = 375

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val len = bb.bitsPerRow[0]
        var pos = bb.search(0, 0, intArrayOf(0x7f, 0xf8), 13)
        if (pos >= len) return emptyList()
        pos += 13
        if (len - pos < 56) return emptyList()
        val b = IntArray(7)
        bb.extractBytes(0, pos, b, 7 * 8)
        if (Rtl433BitUtil.crc8(b, 7, 0x07, 0xe0) != 0) return emptyList()
        val id = ((b[0] and 0x03) shl 22) or (b[1] shl 14) or (b[2] shl 6) or (b[3] shr 2)
        val pressureRaw = ((b[3] and 0x03) shl 8) or b[4]
        val pressureKpa = pressureRaw * 0.5f
        val temperatureC = (b[5] - 50).toFloat()
        return listOf(
            Reading(
                "Schrader-Motorcycle",
                id.toString(),
                linkedMapOf<String, Any?>(
                    "type" to "TPMS",
                    "pressure_kPa" to pressureKpa.toDouble(),
                    "temperature_C" to temperatureC.toDouble(),
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: tpms_sefis_m3.c:66-137, struct tpms_sefis_m3.c:149
internal object TpmsSefisM3 : Rtl433Decoder() {
    override val name = "Sefis M3 / Careud / Sykik SRTP300 TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        var pos = bb.search(0, 0, intArrayOf(0x66, 0x99, 0x96, 0xa6), 32)
        if (pos == bb.bitsPerRow[0]) return emptyList()
        if (pos + 176 > bb.bitsPerRow[0]) return emptyList()
        pos += 32
        val packet = BitBuffer()
        bb.manchesterDecode(0, pos, packet, 72)
        if (packet.bitsPerRow[0] < 72) return emptyList()
        val b = IntArray(9)
        for (i in 0 until 9) b[i] = packet.bb[0][i] xor 0xff
        val crc = Rtl433BitUtil.crc16(b, 7, 0x1021, 0x0000)
        val crcRecv = (b[7] shl 8) or b[8]
        if (crc != crcRecv) return emptyList()
        val pressurePage = when (b[4] shr 5) {
            7 -> 0
            4 -> 1
            5 -> 2
            2 -> 3
            else -> -1
        }
        val hasPressure = pressurePage >= 0
        var pressureKpa = 0.0f
        if (hasPressure) {
            val code = (pressurePage shl 13) or ((b[4] and 0x1f) shl 8) or b[5]
            pressureKpa = (code - 0x0e00) / 102.4f
            if (pressureKpa < 0.0f) pressureKpa = 0.0f
        }
        val tempCode = (b[2] + b[5]) and 0xff
        val temperatureC = 14 + (tempCode and 0x0f)
        val codeStr = String.format("%02x%02x%02x%02x%02x%02x%02x", b[0], b[1], b[2], b[3], b[4], b[5], b[6])
        val fields = linkedMapOf<String, Any?>("type" to "TPMS")
        if (hasPressure) fields["pressure_kPa"] = pressureKpa.toDouble()
        fields["temperature_C"] = temperatureC.toDouble()
        fields["code"] = codeStr
        fields["mic"] = "CRC"
        return listOf(Reading("Sefis-M3", null, fields))
    }
}

private fun crc7(msg: IntArray, nBytes: Int, polynomial: Int, init: Int): Int {
    var remainder = init shl 1
    val poly = polynomial shl 1
    for (byte in 0 until nBytes) {
        remainder = remainder xor msg[byte]
        for (bit in 0 until 8) {
            remainder = if ((remainder and 0x80) != 0) (remainder shl 1) xor poly else remainder shl 1
        }
    }
    return (remainder shr 1) and 0x7f
}

// unverified: tpms_smartire.c:59-127, struct tpms_smartire.c:141
internal object TpmsSmartire : Rtl433Decoder() {
    override val name = "SmarTire TPMS sensor, Aston Martin/Vantage DB9 protocol"
    override val mod = Mod.OOK_PCM
    override val short = 167
    override val long = 167
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val pos = bb.search(0, 0, intArrayOf(0x32, 0xb4), 16)
        if (pos >= bb.bitsPerRow[0]) return emptyList()
        val decoded = BitBuffer()
        bb.differentialManchesterDecode(0, pos + 16, decoded, 6 * 8)
        if (decoded.bitsPerRow[0] < (6 * 8) - 1) return emptyList()
        val b = decoded.bb[0]
        if (crc7(b, 6, 0x45, 0x6f) != 0) return emptyList()
        val id = ((b[1] and 0x3f) shl 16) or (b[2] shl 8) or b[3]
        val msgType = (b[1] and 0xc0) shr 6
        val value = b[0] - 40
        var pressureKpa = 0.0f
        var temperatureC = 0
        if (msgType == 0) {
            pressureKpa = (value * 2.5).toFloat()
        } else if (msgType == 1) {
            temperatureC = value
        } else {
            return emptyList()
        }
        val inflate = (b[4] and 0x80) shr 7
        val flags = b[4] and 0x7f
        val fields = linkedMapOf<String, Any?>("type" to "TPMS")
        if (msgType == 0) fields["pressure_kPa"] = pressureKpa.toDouble()
        if (msgType == 1) fields["temperature_C"] = temperatureC.toDouble()
        if (inflate == 1) fields["inflate"] = 1
        fields["flags"] = flags
        fields["mic"] = "CRC"
        return listOf(Reading("SmarTire-AM", id.toString(), fields))
    }
}

internal val BATCH_08: List<Rtl433Decoder> = listOf(
    ThermoproTp211b,
    ThermoproTp28b,
    ThermoproTp828b,
    ThermoproTp829b,
    ThermoproTp86xb,
    ThermoproTx2,
    ThermoproTx2c,
    ThermoproTx7b,
    Thermor,
    ThermorA6n132tx,
    TmpsGearHive,
    TpmsAbarth124,
    TpmsAirpuxem,
    TpmsAve,
    TpmsBmw,
    TpmsBmwg3,
    TpmsCitroen,
    TpmsEezrv,
    TpmsElantra2012,
    TpmsFord,
    TpmsGm,
    TpmsHonda,
    TpmsHyundaiVdo,
    TpmsImarsT240,
    TpmsJansite,
    TpmsJansiteSolar,
    TpmsJansiteTy468,
    TpmsJansiteTy588,
    TpmsJeep,
    TpmsKia,
    TpmsMercedesBenz,
    TpmsNissan,
    TpmsPmv107j,
    TpmsPorsche,
    TpmsRenault,
    TpmsRenault0435r,
    TpmsSchraderMotorcycle,
    TpmsSefisM3,
    TpmsSmartire,
)

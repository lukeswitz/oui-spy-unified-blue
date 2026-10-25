// Kotlin transcription of rtl_433 device decoders (batch 07). GPL-3 reference; constants, bit offsets and CRC parameters transcribed as facts.
package com.rootdowndigital.ouispy.wifiadapter

private fun rv8(x: Int): Int {
    var v = x and 0xFF
    v = ((v and 0xF0) shr 4) or ((v and 0x0F) shl 4)
    v = ((v and 0xCC) shr 2) or ((v and 0x33) shl 2)
    v = ((v and 0xAA) shr 1) or ((v and 0x55) shl 1)
    return v and 0xFF
}

private fun s16(x: Int): Int = x.toShort().toInt()

private fun uart8n1(msg: IntArray, offsetBits: Int, numBits: Int, dst: IntArray): Int {
    var ret = 0
    var off = offsetBits
    var nb = numBits
    while (nb >= 10) {
        val startb = msg[off / 8] shr (7 - (off % 8))
        off += 1
        var datab = msg[off / 8]
        if (off % 8 != 0) {
            datab = (msg[off / 8] shl 8) or msg[off / 8 + 1]
            datab = datab shr (8 - (off % 8))
        }
        off += 8
        val stopb = msg[off / 8] shr (7 - (off % 8))
        off += 1
        if ((startb and 1) != 0) break
        if ((stopb and 1) != 1) break
        dst[ret] = rv8(datab and 0xff)
        ret += 1
        nb -= 10
    }
    return ret
}

// unverified: sainlogic_sa8.c:64-139, struct sainlogic_sa8.c:159
internal object SainlogicSa8 : Rtl433Decoder() {
    override val name = "Sainlogic SA8, Gevanti SA8 Weather Station"
    override val mod = Mod.OOK_PCM
    override val short = 200
    override val long = 200
    override val reset = 2500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val offset = bb.search(0, 0, intArrayOf(0xfc, 0x95), 16) + 16
        if (offset >= bb.bitsPerRow[0]) return emptyList()
        val numBits = minOf(bb.bitsPerRow[0] - offset, 41 * 10)
        val b = IntArray(41)
        val len = uart8n1(bb.bb[0], offset, numBits, b)
        if (len < 41) return emptyList()
        val id = String.format("%02x%02x%02x%02x%02x%02x", b[4], b[3], b[6], b[5], b[8], b[7])
        val counter = (b[16] shl 8) or b[15]
        val tempRaw = s16((b[20] shl 8) or b[19])
        val humidity = b[21]
        val gustRaw = (b[28] shl 8) or b[27]
        val windRaw = (b[30] shl 8) or b[29]
        val dirDegree = (b[32] shl 8) or b[31]
        val rainRaw = (b[34] shl 8) or b[33]
        val unknown = (b[36] shl 8) or b[35]
        val batteryOk = (b[38] and 0x10) shr 4
        val batMv = (b[38] shl 8) or b[37]
        val tempC = tempRaw * 0.1f
        val gustKmh = gustRaw * 0.036f
        val windKmh = windRaw * 0.036f
        val rainMm = rainRaw * 0.42893617f
        return listOf(
            Reading(
                "Sainlogic-SA8",
                id,
                linkedMapOf<String, Any?>(
                    "battery_ok" to batteryOk,
                    "counter" to counter,
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "wind_avg_km_h" to windKmh.toDouble(),
                    "wind_max_km_h" to gustKmh.toDouble(),
                    "wind_dir_deg" to dirDegree,
                    "rain_mm" to rainMm.toDouble(),
                    "unknown" to unknown,
                    "flags" to batMv,
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: schou_72543_rain.c:53-104, struct schou_72543_rain.c:118
internal object Schou72543Rain : Rtl433Decoder() {
    override val name = "Schou 72543 Day Rain Gauge, Motonet MTX Rain, MarQuant Rain Gauge, TFA Dostmann 30.3252.01/47.3006.01 Rain Gauge and Thermometer, ADE WS1907"
    override val mod = Mod.OOK_PWM
    override val short = 972
    override val long = 2680
    override val sync = 7328
    override val reset = 2712

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows < 2) return emptyList()
        val row = bb.findRepeatedPrefix(2, 64)
        if (row < 0) return emptyList()
        val b = bb.bb[row]
        val chk = b[7]
        val sum = Rtl433BitUtil.addBytes(b, 7)
        if (sum == 0) return emptyList()
        if (chk != (sum and 0xff)) return emptyList()
        val deviceId = (b[0] shl 8) or b[1]
        val batteryLow = (b[2] and 0x80) > 0
        val messageRepeat = if ((b[2] and 0x40) > 0) 1 else 0
        val messageCounter = (b[2] and 0x0e) shr 1
        val rainMm = (((b[4] shl 8) or b[3]) * 0.1f)
        val temperatureF = ((((b[6] shl 8) or b[5]) - 900) * 0.1f)
        return listOf(
            Reading(
                "Schou-72543",
                deviceId.toString(),
                linkedMapOf<String, Any?>(
                    "temperature_F" to temperatureF.toDouble(),
                    "rain_mm" to rainMm.toDouble(),
                    "battery_ok" to (if (batteryLow) 0 else 1),
                    "msg_counter" to messageCounter,
                    "msg_repeat" to messageRepeat,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: schraeder.c:35-80, struct schraeder.c:539
internal object Schraeder : Rtl433Decoder() {
    override val name = "Schrader TPMS"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 120
    override val long = 0
    override val reset = 480

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 68) return emptyList()
        val b = IntArray(8)
        bb.extractBytes(0, 4, b, 64)
        if (b[7] != Rtl433BitUtil.crc8(b, 7, 0x07, 0xf0)) return emptyList()
        val serialId = ((b[1] and 0x0F) shl 24) or (b[2] shl 16) or (b[3] shl 8) or b[4]
        val flags = ((b[0] and 0x0F) shl 4) or (b[1] shr 4)
        val pressure = b[5] * 25
        val temperature = b[6] - 50
        return listOf(
            Reading(
                "Schrader",
                String.format("%07X", serialId),
                linkedMapOf<String, Any?>(
                    "type" to "TPMS",
                    "flags" to String.format("%02x", flags),
                    "pressure_kPa" to (pressure * 0.1f).toDouble(),
                    "temperature_C" to temperature.toDouble(),
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: schraeder.c:100-154, struct schraeder.c:549
internal object SchraderEG53MA4 : Rtl433Decoder() {
    override val name = "Schrader TPMS EG53MA4, Saab, Opel, Vauxhall, Chevrolet"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 123
    override val long = 0
    override val reset = 300

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 120) return emptyList()
        val b = IntArray(10)
        bb.extractBytes(0, 40, b, 80)
        if (b[1] == 0 && b[2] == 0 && b[4] == 0 && b[5] == 0 && b[7] == 0 && b[8] == 0) return emptyList()
        val checksum = Rtl433BitUtil.addBytes(b, 9) and 0xff
        if (checksum != b[9]) return emptyList()
        val serialId = (b[4] shl 16) or (b[5] shl 8) or b[6]
        val flags = (b[0] shl 24) or (b[1] shl 16) or (b[2] shl 8) or b[3]
        val pressure = b[7] * 25
        val temperature = b[8]
        return listOf(
            Reading(
                "Schrader-EG53MA4",
                String.format("%06X", serialId),
                linkedMapOf<String, Any?>(
                    "type" to "TPMS",
                    "flags" to String.format("%08x", flags),
                    "pressure_kPa" to (pressure * 0.1f).toDouble(),
                    "temperature_F" to temperature.toDouble(),
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

private fun schraderSmd3ma4Family(bb: BitBuffer, model: Int): List<Reading> {
    val numBitsPreamble = 36
    val numBitsData = 38
    val numBitsTotalMin = numBitsPreamble / 2 + 2 * numBitsData
    val numBitsTotalMax = numBitsPreamble + 2 * numBitsData + 8
    if (bb.bitsPerRow[0] < numBitsTotalMin || bb.bitsPerRow[0] >= numBitsTotalMax) return emptyList()
    var bitpos = bb.search(0, 0, intArrayOf(0x55, 0x5e), 16)
    bitpos += 14
    if (bitpos + numBitsData * 2 > bb.bitsPerRow[0]) return emptyList()
    val decoded = BitBuffer()
    val ret = bb.manchesterDecode(0, bitpos, decoded, numBitsData)
    if (ret != bitpos + numBitsData * 2) return emptyList()
    decoded.invert()
    val b = decoded.bb[0]
    if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0) return emptyList()
    var sum = 0
    for (i in 0 until 5) {
        sum += (b[i] and 0x3) + ((b[i] shr 2) and 0x3) + ((b[i] shr 4) and 0x3) + ((b[i] shr 6) and 0x3)
    }
    if ((sum and 0x3) != 1) return emptyList()
    val flags = (b[0] and 0x70) shr 4
    val serialId = ((b[0] and 0x0f) shl 20) or (b[1] shl 12) or (b[2] shl 4) or (b[3] shr 4)
    val pressure = ((b[3] and 0x0f) shl 4) or (b[4] shr 4)
    val flagLearn = flags == 0x0
    val flagAlarm = flags == 0x3
    val flagWakeup = flags == 0x5
    val pressureScale = if (model == 1) 0.2f else 0.25f
    val fields = linkedMapOf<String, Any?>(
        "type" to "TPMS",
        "flags" to flags,
    )
    if (flagLearn) fields["learn"] = 1
    if (flagAlarm) fields["alarm"] = 1
    if (flagWakeup) fields["wakeup"] = 1
    fields["pressure_PSI"] = (pressure * pressureScale).toDouble()
    fields["mic"] = "PARITY"
    val modelName = if (model == 1) "Schrader-SMD3MA4" else "Schrader-NIS315G3"
    return listOf(Reading(modelName, String.format("%06X", serialId), fields))
}

// unverified: schraeder.c:249-337, struct schraeder.c:559
internal object SchraderSMD3MA4 : Rtl433Decoder() {
    override val name = "Schrader TPMS SMD3MA4 (Subaru)"
    override val mod = Mod.OOK_PCM
    override val short = 120
    override val long = 120
    override val reset = 480

    override fun decode(bb: BitBuffer): List<Reading> = schraderSmd3ma4Family(bb, 1)
}

// unverified: schraeder.c:249-343, struct schraeder.c:569
internal object SchraderNIS315G3 : Rtl433Decoder() {
    override val name = "Schrader TPMS MRXNIS315G3, 3039 (Infiniti, Nissan, Renault), aka Redi-Sensor SE10001HP/SE10001HPR"
    override val mod = Mod.OOK_PCM
    override val short = 120
    override val long = 120
    override val reset = 480

    override fun decode(bb: BitBuffer): List<Reading> = schraderSmd3ma4Family(bb, 2)
}

// unverified: schraeder.c:388-490, struct schraeder.c:579
internal object SchraderMRXBC5A4 : Rtl433Decoder() {
    override val name = "Schrader TPMS MRXBC5A4 (BMW)"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 123
    override val long = 0
    override val reset = 800

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] != 61) return emptyList()
        if (bb.search(0, 0, intArrayOf(0x7f, 0xff), 16) != 0) return emptyList()
        val b = IntArray(6)
        bb.extractBytes(0, 16, b, 46)
        val serialId = ((b[0] and 0x1f) shl 19) or (b[1] shl 11) or (b[2] shl 3) or (b[3] shr 5)
        if (serialId == 0 || serialId == 0xFFFFFF) return emptyList()
        var evenOnes = 0
        var n = 0
        for (i in 3 until 38) {
            val bit = (b[i / 8] shr (7 - (i % 8))) and 1
            if (bit != 0) {
                n++
                if ((i - 3) % 2 == 0) evenOnes++
            }
        }
        val c1c2 = (evenOnes + 2 * n - 1) and 0x3
        val c1 = (b[4] shr 3) and 1
        val c2 = (b[4] shr 2) and 1
        if (c1c2 != ((c1 shl 1) or c2)) return emptyList()
        val flags = (b[0] shr 5) and 0x7
        val pressure = ((b[3] and 0x1f) shl 4) or (b[4] shr 4)
        val temperature = ((b[4] and 0x03) shl 5) or (b[5] shr 3)
        if (pressure > 450 || temperature - 50 < -40 || temperature - 50 > 85) return emptyList()
        return listOf(
            Reading(
                "Schrader-MRXBC5A4",
                String.format("%06X", serialId),
                linkedMapOf<String, Any?>(
                    "type" to "TPMS",
                    "flags" to String.format("%01x", flags),
                    "pressure_kPa" to pressure.toDouble(),
                    "temperature_C" to (temperature - 50).toDouble(),
                    "sleep" to (if (flags == 2) "True" else "False"),
                    "mic" to "PARITY",
                ),
            ),
        )
    }
}

// unverified: scmplus.c:28-157, struct scmplus.c:176
internal object Scmplus : Rtl433Decoder() {
    override val name = "Standard Consumption Message Plus (SCMplus)"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 30
    override val reset = 64

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 128) return emptyList()
        val syncIndex = bb.search(0, 0, intArrayOf(0x16, 0xA3, 0x1E), 24)
        if (syncIndex >= bb.bitsPerRow[0]) return emptyList()
        if (bb.bitsPerRow[0] - syncIndex < 128) return emptyList()
        val b = IntArray(16)
        bb.extractBytes(0, syncIndex, b, 16 * 8)
        val pktChecksum = (b[14] shl 8) or b[15]
        val crc = Rtl433BitUtil.crc16(b.copyOfRange(2, 16), 12, 0x1021, 0x0971)
        if (crc != pktChecksum) return emptyList()
        val endpointId = (b[4].toLong() shl 24) or (b[5].toLong() shl 16) or (b[6].toLong() shl 8) or b[7].toLong()
        val consumptionData = (b[8].toLong() shl 24) or (b[9].toLong() shl 16) or (b[10].toLong() shl 8) or b[11].toLong()
        val physicalTamper = (b[12] shl 8) or b[13]
        val meterType = when (b[3] and 0x0f) {
            4, 5, 7, 8 -> "Electric"
            0, 1, 2, 9, 12 -> "Gas"
            3, 11, 13 -> "Water"
            else -> "unknown"
        }
        return listOf(
            Reading(
                "SCMplus",
                endpointId.toString(),
                linkedMapOf<String, Any?>(
                    "ProtocolID" to String.format("0x%02X", b[2]),
                    "EndpointType" to String.format("0x%02X", b[3]),
                    "EndpointID" to endpointId,
                    "Consumption" to consumptionData,
                    "Tamper" to String.format("0x%04X", physicalTamper),
                    "PacketCRC" to String.format("0x%04X", crc),
                    "MeterType" to meterType,
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: sharp_spc775.c:36-84, struct sharp_spc775.c:96
internal object SharpSpc775 : Rtl433Decoder() {
    override val name = "Sharp SPC775 weather station"
    override val mod = Mod.FSK_PWM
    override val short = 225
    override val long = 425
    override val gap = 2900
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val r = bb.findRepeatedRow(2, 48)
        if (r < 0) return emptyList()
        val pos = bb.search(r, 0, intArrayOf(0xa5), 8)
        if (pos + 6 * 8 > bb.bitsPerRow[r]) return emptyList()
        val b = IntArray(6)
        bb.extractBytes(r, pos, b, 6 * 8)
        val id = b[1]
        val batteryLow = b[2] and 0x80
        val tempRaw = s16(((b[2] and 0x0f) shl 12) or (b[3] shl 4))
        val tempC = (tempRaw shr 4) * 0.1f
        val humidity = b[4]
        val chkDigest = b[5]
        val chkCalc = Rtl433BitUtil.xorBytes(b, 5)
        val chkExpected = Rtl433BitUtil.lfsrDigest8Reflect(intArrayOf(chkCalc), 1, 0x31, 0x31)
        if (chkExpected != chkDigest) return emptyList()
        if (humidity > 100) return emptyList()
        return listOf(
            Reading(
                "Sharp-SPC775",
                id.toString(),
                linkedMapOf<String, Any?>(
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: shenzhen_wale_wl_th6r.c:75-155, struct shenzhen_wale_wl_th6r.c:189
internal object ShenzhenWaleWlTh6r : Rtl433Decoder() {
    override val name = "Shenzhen Wale WL-TH6R Temperature & Humidity Sensor"
    override val mod = Mod.OOK_PWM
    override val short = 365
    override val long = 605
    override val gap = 780
    override val reset = 4000
    override val tolerance = 50

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedPrefix(2, 72)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] > 72 + 1) return emptyList()
        val b = bb.bb[row]
        for (i in 0 until 9) {
            b[i] = b[i].inv() and 0xFF
        }
        for (i in 0 until 7) {
            b[i] = b[i] xor b[7]
        }
        val xor = Rtl433BitUtil.xorBytes(b, 7)
        val sum = Rtl433BitUtil.addBytes(b, 7)
        val mic = 0xA5 xor xor xor (sum and 0xFF) xor (sum shr 8)
        if (b[8] != mic) return emptyList()
        val tempRaw = s16((b[3] shl 8) or b[4])
        val tempC = tempRaw * 0.1f
        if (tempC < -20.0f || tempC > 60.0f) return emptyList()
        val humidityPct = b[5]
        if (humidityPct > 127) return emptyList()
        val sensorId = (b[0] shl 16) or (b[1] shl 8) or b[2]
        val batteryPct = b[6]
        val pairing = b[7] shr 7
        val cycle = if ((b[7] and 0x40) != 0) 0x40 else (b[7] and 0x3F)
        val fields = linkedMapOf<String, Any?>()
        if (batteryPct < 20) fields["battery_ok"] = 0
        fields["battery_pct"] = batteryPct
        fields["temperature_C"] = tempC.toDouble()
        fields["humidity"] = humidityPct
        if (pairing != 0) fields["pairing"] = pairing
        fields["cycle"] = cycle
        fields["mic"] = "CHECKSUM"
        return listOf(Reading("WL-TH6R", String.format("%06X", sensorId), fields))
    }
}

// unverified: siemens_5wy72xx.c:50-118, struct siemens_5wy72xx.c:131
internal object Siemens5wy72xxCarRemote : Rtl433Decoder() {
    override val name = "Siemens 5WY72XX Car Remote (-f 315.1M)"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 220
    override val reset = 10000

    private val buttonStrings = arrayOf("Lock", "Unlock", "Trunk", "Panic", "Left Door", "Right Door")

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 113 || bb.numRows > 1) return emptyList()
        val offset = bb.search(0, 0, intArrayOf(0x60, 0x01), 16) + 16
        val bytes = IntArray(12)
        bb.extractBytes(0, offset, bytes, 96)
        val sum = Rtl433BitUtil.addBytes(bytes, 12)
        if (sum == 0 || sum == 0xff * 12) return emptyList()
        if (Rtl433BitUtil.xorBytes(bytes, 12) != 0) return emptyList()
        val idStr = String.format("%02X%02X%02X%02X", bytes[3], bytes[2], bytes[1], bytes[0])
        val button = bytes[4]
        val sequence = (bytes[5] shl 8) or bytes[6]
        val encryptedStr = String.format("%02X%02X%02X%02X", bytes[10], bytes[9], bytes[8], bytes[7])
        val names = ArrayList<String>()
        for (i in 0 until 6) {
            if ((button and (1 shl i)) != 0) names.add(buttonStrings[i])
        }
        return listOf(
            Reading(
                "Siemens-5WY72XX",
                idStr,
                linkedMapOf<String, Any?>(
                    "encrypted" to encryptedStr,
                    "button_code" to button,
                    "button_str" to names.joinToString("; "),
                    "sequence" to sequence,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: mic6sc2_car_remote.c:50-103, struct mic6sc2_car_remote.c:116
internal object SixScTwoCarRemote : Rtl433Decoder() {
    override val name = "MIC 6SC2 Car Remote (-f 315.1M)"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 250
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(1, 48)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] > 88) return emptyList()
        val b = bb.bb[row]
        if (b[0] != 0x55 || b[1] != 0x54) return emptyList()
        if (Rtl433BitUtil.xorBytes(b.copyOfRange(2, 11), 9) != 0) return emptyList()
        val encrypted = (rv8(b[5]) shl 24) or (rv8(b[4]) shl 16) or (rv8(b[3]) shl 8) or rv8(b[2])
        val button = rv8(b[6]) and 0xf
        val sequence = (rv8(b[8]) shl 8) or rv8(b[7])
        val buttonStr = when (button) {
            0x1 -> "Unlock"
            0x2 -> "Lock"
            0x3 -> "Trunk"
            0x4 -> "Panic"
            else -> "?"
        }
        return listOf(
            Reading(
                "MIC6SC2-CarRemote",
                null,
                linkedMapOf<String, Any?>(
                    "encrypted" to String.format("%08X", encrypted),
                    "button_code" to button,
                    "button_str" to buttonStr,
                    "sequence" to sequence,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: silvercrest.c:19-49, struct silvercrest.c:58
internal object Silvercrest : Rtl433Decoder() {
    override val name = "Silvercrest Remote Control"
    override val mod = Mod.OOK_PWM
    override val short = 264
    override val long = 744
    override val reset = 12000
    override val gap = 5000

    private val cmdLuTab = intArrayOf(2, 3, 0, 1, 4, 5, 7, 6, 0xC, 0xD, 0xF, 0xE, 8, 9, 0xB, 0xA)

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[1] != 33) return emptyList()
        val b = bb.bb[1]
        if (b[0] != 0x7c || b[1] != 0x26) return emptyList()
        val cmd = b[2] and 0xF
        if ((b[3] and 0xF) != cmdLuTab[cmd]) return emptyList()
        return listOf(Reading("Silvercrest-Remote", null, mapOf("button" to cmd)))
    }
}

// unverified: simplisafe_gen3.c:37-86, struct simplisafe_gen3.c:100
internal object SimplisafeGen3 : Rtl433Decoder() {
    override val name = "SimpliSafe Gen 3 Home Security System"
    override val mod = Mod.FSK_PCM
    override val short = 208
    override val long = 208
    override val reset = 7000

    override fun decode(bb: BitBuffer): List<Reading> {
        val bitpos0 = bb.search(0, 0, intArrayOf(0x93, 0x0b, 0x51, 0xde), 32) + 32
        if (bitpos0 >= bb.bitsPerRow[0]) return emptyList()
        if (bitpos0 + 24 * 8 > bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(27)
        bb.extractBytes(0, bitpos0, b, 27 * 8)
        if (b[0] != 0x15 && b[0] != 0x16 && b[0] != 0x18) return emptyList()
        val len = b[0]
        val msgType = b[1]
        val id = (b[2] shl 24) or (b[3] shl 16) or (b[4] shl 8) or b[5]
        val ctr = (b[8] shl 16) or (b[7] shl 8) or b[6]
        val cmac = (b[9] shl 24) or (b[10] shl 16) or (b[11] shl 8) or b[12]
        val encr = bitrowSnprint(b.copyOfRange(13, 27), (len - 12) * 8)
        val chk = Rtl433BitUtil.crc16(b, len + 3, 0x8005, 0xffff)
        if (chk != 0) return emptyList()
        return listOf(
            Reading(
                "SimpliSafe-Gen3",
                String.format("%08x", id),
                linkedMapOf<String, Any?>(
                    "msg_type" to msgType,
                    "ctr" to ctr,
                    "cmac" to cmac,
                    "encr" to encr,
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: smoke_gs558.c:50-117, struct smoke_gs558.c:128. upstream .disabled=1 (false positives with EV1527) not represented in API
internal object SmokeGs558 : Rtl433Decoder() {
    override val name = "Wireless Smoke and Heat Detector GS 558"
    override val mod = Mod.OOK_PWM
    override val short = 436
    override val long = 1202
    override val gap = 1948
    override val reset = 14116

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows < 3) return emptyList()
        bb.invert()
        var learn = 0
        for (r in 0 until bb.numRows) {
            val b = bb.bb[r]
            if (bb.bitsPerRow[r] >= 24 && b[0] == 0x55 && b[1] == 0x55 && b[2] == 0x55) {
                learn++
                bb.bitsPerRow[r] = 0
            }
            if ((bb.bitsPerRow[r] == 26 || bb.bitsPerRow[r] == 27) && b[3] == 0) {
                bb.bitsPerRow[r] = 24
            }
        }
        val r = bb.findRepeatedRow(3, 24)
        if (r < 0) return emptyList()
        if (bb.bitsPerRow[r] > 4 * 8) return emptyList()
        val b = bb.bb[r]
        b[0] = rv8(b[0])
        b[1] = rv8(b[1])
        b[2] = rv8(b[2])
        val unit = b[0] and 0x1f
        val id = ((b[2] and 0x0f) shl 11) or (b[1] shl 3) or (b[0] shr 5)
        if (id == 0 || id == 0x7fff) return emptyList()
        return listOf(
            Reading(
                "Smoke-GS558",
                id.toString(),
                linkedMapOf<String, Any?>(
                    "unit" to unit,
                    "learn" to (if (learn > 1) 1 else 0),
                    "code" to String.format("%02x%02x%02x", b[2], b[1], b[0]),
                ),
            ),
        )
    }
}

// unverified: solight_te44.c:41-91, struct solight_te44.c:103. upstream .priority=5 (dispatch order) not represented in API
internal object SolightTe44 : Rtl433Decoder() {
    override val name = "Solight TE44/TE66, EMOS E0107T, NX-6876-917"
    override val mod = Mod.OOK_PPM
    override val short = 972
    override val long = 1932
    override val gap = 3000
    override val reset = 6000

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(3, 36)
        if (r < 0) return emptyList()
        val b = bb.bb[r]
        if (bb.bitsPerRow[r] != 37) return emptyList()
        if ((b[3] and 0xf0) != 0xf0) return emptyList()
        val tmp = IntArray(5)
        tmp[0] = b[0]
        tmp[1] = b[1]
        tmp[2] = b[2]
        tmp[3] = b[3] and 0xf0
        tmp[4] = ((b[3] and 0x0f) shl 4) or ((b[4] and 0xf0) shr 4)
        val chk = Rtl433BitUtil.crc8(tmp, 5, 0x31, 0x6c)
        if (chk != 0) return emptyList()
        val id = b[0]
        val channel = (b[1] and 0x30) shr 4
        val tempRaw = s16((b[1] shl 12) or (b[2] shl 4))
        val tempC = (tempRaw shr 4) * 0.1f
        return listOf(
            Reading(
                "Solight-TE44",
                id.toString(),
                linkedMapOf<String, Any?>(
                    "channel" to channel + 1,
                    "temperature_C" to tempC.toDouble(),
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: springfield.c:34-94, struct springfield.c:110. upstream .priority=10 (Alecto collision ordering) not represented in API
internal object Springfield : Rtl433Decoder() {
    override val name = "Springfield Temperature and Soil Moisture"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 5000
    override val reset = 9200

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(3, 36)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] != 36 && bb.bitsPerRow[row] != 37) return emptyList()
        val b = bb.bb[row]
        val tmpData = (b[0] shl 24) or (b[1] shl 16) or (b[2] shl 8) or b[3]
        if (tmpData == -1 || tmpData == 0) return emptyList()
        var chk = Rtl433BitUtil.xorBytes(b, 4)
        chk = (chk shr 4) xor (chk and 0x0f)
        if (chk != 0) return emptyList()
        val sid = b[0]
        val battery = (b[1] shr 7) and 1
        val button = (b[1] shr 6) and 1
        val channel = ((b[1] shr 4) and 0x03) + 1
        val temp = s16(((b[1] and 0x0f) shl 12) or (b[2] shl 4))
        val tempC = (temp shr 4) * 0.1f
        val moisture = (b[3] shr 4) * 10
        if (tempC < -30 || tempC > 70) return emptyList()
        if (moisture > 100) return emptyList()
        return listOf(
            Reading(
                "Springfield-Soil",
                sid.toString(),
                linkedMapOf<String, Any?>(
                    "channel" to channel,
                    "battery_ok" to (if (battery != 0) 0 else 1),
                    "transmit" to (if (button != 0) "MANUAL" else "AUTO"),
                    "temperature_C" to tempC.toDouble(),
                    "moisture" to moisture,
                    "button" to button,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: thermopro_tp11.c:26-63, struct thermopro_tp11.c:73
internal object ThermoproTp11 : Rtl433Decoder() {
    override val name = "Thermopro TP11 Thermometer"
    override val mod = Mod.OOK_PPM
    override val short = 500
    override val long = 1500
    override val gap = 2000
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(2, 32)
        if (row < 0) return emptyList()
        val b = bb.bb[row]
        if (bb.bitsPerRow[row] > 33) return emptyList()
        val ic = Rtl433BitUtil.lfsrDigest8Reflect(b, 3, 0x51, 0x04)
        if (ic != b[3]) return emptyList()
        if ((b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0) ||
            (b[0] == 0xff && b[1] == 0xff && b[2] == 0xff && b[3] == 0xff)
        ) return emptyList()
        val device = (b[0] shl 4) or (b[1] shr 4)
        val tempRaw = ((b[1] and 0x0f) shl 8) or b[2]
        val tempC = (tempRaw - 200) * 0.1f
        return listOf(
            Reading(
                "Thermopro-TP11",
                device.toString(),
                linkedMapOf<String, Any?>(
                    "temperature_C" to tempC.toDouble(),
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: thermopro_tp12.c:49-104, struct thermopro_tp12.c:115
internal object ThermoproTp12 : Rtl433Decoder() {
    override val name = "ThermoPro TP08/TP12/TP20 thermometer"
    override val mod = Mod.OOK_PPM
    override val short = 500
    override val long = 1500
    override val gap = 2000
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedPrefix(if (bb.numRows > 5) 5 else 2, 41 - 1)
        if (row < 0) return emptyList()
        val bytes = bb.bb[row]
        if (bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0) return emptyList()
        if (bb.bitsPerRow[row] != 41) return emptyList()
        val ic = Rtl433BitUtil.lfsrDigest8Reflect(bytes, 4, 0x51, 0x04)
        if (ic != bytes[4]) return emptyList()
        val device = bytes[0]
        val temp1Raw = ((bytes[2] and 0xf0) shl 4) or bytes[1]
        val temp2Raw = ((bytes[2] and 0x0f) shl 8) or bytes[3]
        val temp1C = (temp1Raw - 200) * 0.1f
        val temp2C = (temp2Raw - 200) * 0.1f
        return listOf(
            Reading(
                "Thermopro-TP12",
                device.toString(),
                linkedMapOf<String, Any?>(
                    "temperature_1_C" to temp1C.toDouble(),
                    "temperature_2_C" to temp2C.toDouble(),
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: tfa_marbella.c:45-93, struct tfa_marbella.c:105. upstream sanity check tests unset bitpos (always 0), transcribed as-is
internal object TfaMarbella : Rtl433Decoder() {
    override val name = "TFA Marbella Pool Thermometer"
    override val mod = Mod.FSK_PCM
    override val short = 105
    override val long = 105
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> {
        val bitpos = 0
        val startPos = bb.search(0, 0, intArrayOf(0xaa, 0x2d, 0xd4), 24)
        if (bitpos == bb.bitsPerRow[0]) return emptyList()
        val msg = IntArray(11)
        bb.extractBytes(0, startPos, msg, 11 * 8)
        if (msg[9] != 0xAA) return emptyList()
        val ic = Rtl433BitUtil.lfsrDigest8Reflect(msg.copyOfRange(3, 11), 7, 0x31, 0x31)
        if (ic != msg[10]) return emptyList()
        val tempRaw = (msg[7] shl 4) or (msg[8] shr 4)
        val tempC = (tempRaw - 400) * 0.1f
        val batteryLow = (msg[6] shr 7) and 0x01
        val counter = (msg[6] shr 1) and 0x07
        val serialnr = (msg[3] shl 16) or (msg[4] shl 8) or msg[5]
        return listOf(
            Reading(
                "TFA-Marbella",
                String.format("%06x", serialnr),
                linkedMapOf<String, Any?>(
                    "counter" to counter,
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "temperature_C" to tempC.toDouble(),
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: tfa_pool_thermometer.c:33-77, struct tfa_pool_thermometer.c:90
internal object TfaPoolThermometer : Rtl433Decoder() {
    override val name = "TFA pool temperature sensor"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4600
    override val gap = 7800
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(7, 28)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] != 28) return emptyList()
        val b = bb.bb[row]
        val checksumRx = (b[0] and 0xF0) shr 4
        val checksum = (b[0] and 0x0F) + (b[1] shr 4) + (b[1] and 0x0F) + (b[2] shr 4) + (b[2] and 0x0F) + (b[3] shr 4) - 1
        if (checksumRx != (checksum and 0x0F)) return emptyList()
        val device = ((b[0] and 0x0F) shl 4) or ((b[1] and 0xF0) shr 4)
        val tempRaw = ((b[1] and 0x0F) shl 8) or b[2]
        val tempF = (if (tempRaw > 2048) tempRaw - 4096 else tempRaw) * 0.1f
        val channel = (b[3] and 0xC0) shr 6
        val battery = (b[3] and 0x20) shr 5
        return listOf(
            Reading(
                "TFA-Pool",
                device.toString(),
                linkedMapOf<String, Any?>(
                    "channel" to channel,
                    "battery_ok" to battery,
                    "temperature_C" to tempF.toDouble(),
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: tfa_twin_plus_30.3049.c:52-107, struct tfa_twin_plus_30.3049.c:121
internal object TfaTwinPlus303049 : Rtl433Decoder() {
    override val name = "TFA-Twin-Plus-30.3049, Conrad KW9010, Ea2 BL999"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 6000
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(2, 36)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] != 36) return emptyList()
        val b = bb.bb[row]
        if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0 && b[4] == 0) return emptyList()
        val rb = intArrayOf(rv8(b[0]), rv8(b[1]), rv8(b[2]), rv8(b[3]), rv8(b[4]))
        val sumNibbles = (rb[0] shr 4) + (rb[0] and 0xF) +
            (rb[1] shr 4) + (rb[1] and 0xF) +
            (rb[2] shr 4) + (rb[2] and 0xF) +
            (rb[3] shr 4) + (rb[3] and 0xF)
        val checksum = rb[4] and 0x0F
        if (checksum != (sumNibbles and 0xF)) return emptyList()
        val negativeSign = b[2] and 7
        val temp = ((rb[2] and 0x1F) shl 4) or (rb[1] shr 4)
        val humidity = (rb[3] and 0x7F) - 28
        val sensorId = (rb[0] and 0x0F) or ((rb[0] and 0xC0) shr 2)
        val batteryLow = b[1] shr 7
        val channel = (b[0] shr 2) and 3
        val tempC = (if (negativeSign != 0) -((1 shl 9) - temp) else temp) * 0.1f
        return listOf(
            Reading(
                "TFA-TwinPlus",
                sensorId.toString(),
                linkedMapOf<String, Any?>(
                    "channel" to channel,
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: tfa_30_3221.c:37-91, struct tfa_30_3221.c:106. upstream .priority=10 (LaCrosse-TX141THBv2 collision ordering) not represented in API
internal object Tfa303221 : Rtl433Decoder() {
    override val name = "TFA Dostmann 30.3221.02 T/H Outdoor Sensor (also 30.3249.02)"
    override val mod = Mod.OOK_PWM
    override val short = 235
    override val long = 480
    override val reset = 850
    override val sync = 836

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(if (bb.numRows > 4) 4 else 2, 40)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] > 41) return emptyList()
        bb.invert()
        val b = bb.bb[row]
        val device = b[0]
        if (device == 0) return emptyList()
        val observedChecksum = b[4]
        val computedChecksum = Rtl433BitUtil.lfsrDigest8Reflect(b, 4, 0x31, 0xf4)
        if (observedChecksum != computedChecksum) return emptyList()
        val tempRaw = ((b[1] and 0x0F) shl 8) or b[2]
        val tempC = (tempRaw - 500) * 0.1f
        val humidity = b[3]
        val batteryLow = b[1] shr 7
        val channel = ((b[1] shr 4) and 3) + 1
        val sendmode = (b[1] shr 6) and 1
        return listOf(
            Reading(
                "TFA-303221",
                device.toString(),
                linkedMapOf<String, Any?>(
                    "channel" to channel,
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "sendmode" to sendmode,
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: tfa_drop_30.3233.c:120-177, struct tfa_drop_30.3233.c:188
internal object TfaDrop303233 : Rtl433Decoder() {
    override val name = "TFA Drop Rain Gauge 30.3233.01"
    override val mod = Mod.OOK_PWM
    override val short = 255
    override val long = 510
    override val gap = 1300
    override val reset = 2500
    override val sync = 750

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val rowIndex = bb.findRepeatedRow(2, 66)
        if (rowIndex < 0 || bb.bitsPerRow[rowIndex] > 66 + 16) return emptyList()
        val rowData = bb.bb[rowIndex]
        if ((rowData[0] and 0xf0) != (0x3 shl 4)) return emptyList()
        val observedChecksum = rowData[7]
        val computedChecksum = Rtl433BitUtil.lfsrDigest8Reflect(rowData, 7, 0x31, 0xf4)
        if (observedChecksum != computedChecksum) return emptyList()
        val sensorId = ((rowData[0] and 0x0f) shl 16) or (rowData[1] shl 8) or rowData[2]
        val rainCounter = (((rowData[6] shl 8) or rowData[4]) + 10) and 0xFFFF
        val rainMm = rainCounter * 0.254f
        val batteryLow = (rowData[3] and 0x80) shr 7
        return listOf(
            Reading(
                "TFA-Drop",
                String.format("%5x", sensorId),
                linkedMapOf<String, Any?>(
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "rain_mm" to rainMm.toDouble(),
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

internal object Tfa303307 : Rtl433Decoder() {
    override val name = "TFA 30.3307.02 Wind sensor"
    override val mod = Mod.OOK_RZI
    override val short = 30
    override val long = 167
    override val reset = 500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val len = bb.bitsPerRow[0]
        val b = bb.bb[0]
        var lastBit = 0
        var psk = 0
        var lastPsk = 0
        var nrzs = 0
        var lfsr = 0
        var sr = 0
        var srCnt = -1
        val rdata = IntArray(48)
        var byteCnt = 0
        var i = 0
        while (i < len && byteCnt < rdata.size) {
            val bit = bitrowGetBit(b, i)
            if (bit == lastBit) psk = 1 - psk
            if (psk == lastPsk) nrzs = 1 - nrzs
            lastBit = bit
            lastPsk = psk
            val descrambled = nrzs xor ((lfsr ushr 16) and 1) xor ((lfsr ushr 11) and 1)
            lfsr = (lfsr shl 1) or nrzs
            sr = (sr ushr 1) or (descrambled shl 31)
            if (sr == 0x2bd42d4b) {
                srCnt = 0
                rdata[0] = sr and 0xff
                rdata[1] = (sr ushr 8) and 0xff
                rdata[2] = (sr ushr 16) and 0xff
                byteCnt = 3
            }
            if (srCnt == 0) {
                rdata[byteCnt] = (sr ushr 24) and 0xff
                byteCnt++
            }
            if (srCnt >= 0) srCnt = (srCnt + 1) and 7
            i++
        }
        if (byteCnt < 12) return emptyList()
        val plen = rdata[4]
        if (plen < 11 || plen + 4 > byteCnt) return emptyList()
        if (rdata[5] != 0x0b) return emptyList()
        var crcCalc = 0xe7720ae4.toInt()
        for (j in 4 until plen) {
            crcCalc = crcCalc xor (rdata[j] shl 24)
            for (k in 0 until 8) {
                crcCalc = if ((crcCalc and Int.MIN_VALUE) != 0) (crcCalc shl 1) xor 0x04c11db7 else crcCalc shl 1
            }
        }
        val crcMsg = (rdata[plen] shl 24) or (rdata[plen + 1] shl 16) or (rdata[plen + 2] shl 8) or rdata[plen + 3]
        if (crcCalc != crcMsg) return emptyList()
        val msgLen = plen - 11
        if (msgLen < 7) return emptyList()
        val v = (rdata[14] shl 24) or (rdata[15] shl 16) or (rdata[16] shl 8) or rdata[17]
        val direction = 22.5f * (v ushr 28)
        val speed = (((v ushr 16) and 0xff) + 256 * ((v ushr 25) and 1)) / 10.0f
        val gust = (((v ushr 8) and 0xff) + 256 * ((v ushr 24) and 1)) / 10.0f
        val idStr = (5 until 11).joinToString("") { "%02x".format(rdata[it]) }
        return listOf(Reading("TFA-303307", idStr, mapOf(
            "wind_dir_deg" to direction.toDouble(),
            "wind_avg_m_s" to speed.toDouble(),
            "wind_max_m_s" to gust.toDouble(),
            "mic" to "CRC",
        )))
    }
}

// unverified: tfa_14_1504_v2.c:51-116, struct tfa_14_1504_v2.c:128
internal object Tfa141504v2 : Rtl433Decoder() {
    override val name = "TFA Dostmann 14.1504.V2 Radio-controlled grill and meat thermometer"
    override val mod = Mod.FSK_PCM
    override val short = 360
    override val long = 360
    override val reset = 4096

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        var availableBits = bb.bitsPerRow[0]
        if (availableBits < 64) return emptyList()
        val startPos = bb.search(0, 0, intArrayOf(0xaa, 0xaa, 0x5c), 24)
        availableBits -= startPos
        if (availableBits < 24) return emptyList()
        if (availableBits < 64 || availableBits > 76) return emptyList()
        val b = IntArray(5)
        bb.extractBytes(0, startPos + 24, b, 40)
        val flags = b[0] shr 4
        if ((flags and 0x5) == 0x5) return emptyList()
        val batteryOk = if ((flags and 0x2) != 0) 1 else 0
        if (b[2] != 0xff) return emptyList()
        val calcMic = (Rtl433BitUtil.lfsrDigest16(b, 3, 0x8810, 0x0d42) xor 0x16eb) and 0xFFFF
        val dataMic = (b[3] shl 8) + b[4]
        if (calcMic != dataMic) return emptyList()
        val rawTempC = ((b[0] and 0xf) shl 6) + (b[1] shr 2)
        val probeConnected = rawTempC != 0x1c0
        val tempC = (rawTempC - 532).toFloat()
        val fields = linkedMapOf<String, Any?>(
            "battery_ok" to batteryOk,
            "probe_fail" to (if (probeConnected) 0 else 1),
        )
        if (probeConnected) fields["temperature_C"] = tempC.toDouble()
        fields["mic"] = "CRC"
        return listOf(Reading("TFA-141504v2", null, fields))
    }
}

// unverified: steelmate.c:56-122, struct steelmate.c:137
internal object Steelmate : Rtl433Decoder() {
    override val name = "Steelmate TPMS"
    override val mod = Mod.FSK_MC_ZEROBIT
    override val short = 50
    override val long = 50
    override val reset = 120

    override fun decode(bb: BitBuffer): List<Reading> {
        for (row in 0 until bb.numRows) {
            val rowLen = bb.bitsPerRow[row]
            if (rowLen != 72 && rowLen != 73 && rowLen != 209 && rowLen != 208) continue
            val bitpos = bb.search(row, 0, intArrayOf(0x00, 0x00, 0x7f), 24)
            if (bitpos > rowLen - 72) continue
            bb.invert()
            val b = IntArray(9)
            bb.extractBytes(row, bitpos, b, 72)
            for (i in 0 until 9) b[i] = rv8(b[i])
            if ((Rtl433BitUtil.addBytes(b.copyOfRange(2, 8), 6) and 0xFF) != b[8]) continue
            val id1 = b[3]
            val id2 = b[4]
            val p1 = b[5]
            val tempC = b[6] - 50
            val b1 = b[7]
            val batteryMv = 3900 - b1 * 10
            val sensorId = (id1 shl 8) or id2
            val pressureKpa = p1 * 3.125f
            val fields = linkedMapOf<String, Any?>(
                "type" to "TPMS",
                "pressure_kPa" to pressureKpa.toDouble(),
                "temperature_C" to tempC,
            )
            if (b1 < 0xFE) fields["battery_mV"] = batteryMv
            if (b1 == 0xFF) fields["alarm"] = "fast leak"
            if (b1 == 0xFE) fields["alarm"] = "slow leak"
            fields["mic"] = "CHECKSUM"
            return listOf(Reading("Steelmate", String.format("0x%04x", sensorId), fields))
        }
        return emptyList()
    }
}

// unverified: telldus_ft0385r.c:80-190, struct telldus_ft0385r.c:209
internal object TelldusFt0385r : Rtl433Decoder() {
    override val name = "Telldus weather station FT0385R sensors"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 500
    override val gap = 1200
    override val reset = 2400

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows > 2) return emptyList()
        if (bb.bitsPerRow[0] < 296 && bb.bitsPerRow[1] < 296) return emptyList()
        var r = -1
        val b = IntArray(37)
        for (i in 0 until bb.numRows) {
            var pos = bb.search(i, 0, intArrayOf(0x14, 0xe0), 9)
            pos += 8
            if (pos + 296 > bb.bitsPerRow[i]) continue
            r = i
            bb.extractBytes(i, pos, b, 296)
            break
        }
        if (r < 0) return emptyList()
        if (Rtl433BitUtil.crc8(b, 37, 0x31, 0xc0) != 0) return emptyList()
        val degMsb = (b[2] and 0x04) shr 2
        val gustMsb = (b[2] and 0x02) shr 1
        val windMsb = b[2] and 0x01
        val wind = (windMsb shl 8) or b[3]
        val gust = (gustMsb shl 8) or b[4]
        val windDir = (degMsb shl 8) or b[5]
        val rainTot = (b[20] shl 8) or b[21]
        val temp2Msb = (b[24] and 0xf0) shr 4
        val tempRaw = ((b[24] and 0x0f) shl 8) or b[25]
        val humidity = b[26]
        val temp2Raw = (temp2Msb shl 8) or b[27]
        val humidity2 = b[28]
        val pressure = (b[29] shl 8) or b[30]
        val tempF = (tempRaw - 400) * 0.1f
        val temp2F = (temp2Raw - 400) * 0.1f
        val fields = linkedMapOf<String, Any?>()
        if (tempRaw != 0x7fb) {
            fields["temperature_F"] = tempF.toDouble()
            fields["humidity"] = humidity
            fields["temperature_2_F"] = temp2F.toDouble()
            fields["humidity_2"] = humidity2
            fields["pressure_hPa"] = (pressure * 0.1f).toDouble()
            fields["rain_mm"] = (rainTot * 0.1f).toDouble()
            fields["wind_dir_deg"] = windDir
            fields["wind_avg_m_s"] = (wind * 0.1f).toDouble()
            fields["wind_max_m_s"] = (gust * 0.1f).toDouble()
            fields["mic"] = "CRC"
        } else {
            fields["temperature_2_F"] = temp2F.toDouble()
            fields["humidity_2"] = humidity2
            fields["pressure_hPa"] = (pressure * 0.1f).toDouble()
            fields["mic"] = "CRC"
        }
        return listOf(Reading("Telldus-FT0385R", null, fields))
    }
}

// unverified: srsmith_pool_srs_2c_tx.c:49-148, struct srsmith_pool_srs_2c_tx.c:161. sub-packet parity and pin string are log-only upstream, not ported
internal object SrsmithPoolSrs2cTx : Rtl433Decoder() {
    override val name = "SRSmith Pool Light Remote Control SRS-2C-TX (-f 915M)"
    override val mod = Mod.FSK_PCM
    override val short = 100
    override val long = 100
    override val reset = 4096

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] < 120 || bb.bitsPerRow[0] > 144) return emptyList()
        val startPos = bb.search(0, 0, intArrayOf(0xaa, 0xd3, 0x91, 0xd3, 0x91), 40) + 40
        if (startPos >= bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(10)
        bb.extractBytes(0, startPos, b, 10 * 8)
        val unknownField = (b[1] shl 24) or (b[2] shl 16) or (b[3] shl 8) or b[4]
        val reversedPin = rv8(b[5].inv() and 0xFF)
        val buttonId = b[6]
        val buttonString = when (buttonId) {
            0x0d -> "On/Off Channel 1"
            0x1f -> "On/Off Channel 2"
            0x07 -> "Color Sync"
            0x0b -> "ON/OFF Control - M"
            else -> "Unknown"
        }
        val totalCrc = (b[8] shl 8) or b[9]
        val calculatedTotalCrc = Rtl433BitUtil.crc16(b, 8, 0x8005, 0xFFFF)
        if (totalCrc != calculatedTotalCrc) return emptyList()
        return listOf(
            Reading(
                "SRSmith-SRS2CTX",
                reversedPin.toString(),
                linkedMapOf<String, Any?>(
                    "button_press" to buttonId,
                    "button_press_name" to buttonString,
                    "unknown" to unknownField,
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: tfa_30_3196.c:51-104, struct tfa_30_3196.c:117
internal object Tfa303196 : Rtl433Decoder() {
    override val name = "TFA Dostmann 30.3196 T/H outdoor sensor"
    override val mod = Mod.FSK_MC_ZEROBIT
    override val short = 245
    override val reset = 22000
    override val tolerance = 60

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(2, 48 * 2 + 12)
        if (row < 0) return emptyList()
        var startPos = bb.search(row, 0, intArrayOf(0x55, 0x56), 16)
        startPos += 12
        if (bb.bitsPerRow[row] - startPos < 48 * 2) return emptyList()
        val databits = BitBuffer()
        bb.manchesterDecode(row, startPos, databits, 48)
        if (databits.bitsPerRow[0] < 48) return emptyList()
        val b = databits.bb[0]
        if (b[0] != 0xa8) return emptyList()
        val digest = (b[4] shl 8) or b[5]
        val chk = Rtl433BitUtil.lfsrDigest16(b, 4, 0x8810, 0x22d0) xor digest
        val channel = (b[1] shr 4) + 1
        val tempRaw = ((b[1] and 0x0F) shl 8) or b[2]
        val tempC = (tempRaw - 400) * 0.1f
        val batteryLow = b[3] shr 7
        val humidity = b[3] and 0x7F
        return listOf(
            Reading(
                "TFA-303196",
                chk.toString(),
                linkedMapOf<String, Any?>(
                    "channel" to channel,
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "mic" to "missing",
                ),
            ),
        )
    }
}

private const val FO_TYPE_OOK = 1
private const val FO_TYPE_FSK = 2

private fun fineoffsetWh1050Decode(bb: BitBuffer, bitpos: Int, type: Int): Reading? {
    val br = IntArray(9)
    bb.extractBytes(0, bitpos, br, 9 * 8)
    if (Rtl433BitUtil.crc8(br, 9, 0x31, 0x00) != 0) return null
    val msgType = br[0] shr 4
    val model = if (type == FO_TYPE_OOK) "Fineoffset-WH1050" else "TFA-303151"
    val deviceId = ((br[0] shl 4) and 0xf0) or (br[1] shr 4)
    val batteryLow = br[1] and 0x04
    if (msgType == 5) {
        val tempSign = (br[1] and 0x08) shr 3
        val tempRaw = ((br[1] and 0x03) shl 8) or br[2]
        val rainRaw = (br[6] shl 8) or br[7]
        val temperature: Float
        val rain: Float
        if (type == FO_TYPE_OOK) {
            temperature = (tempRaw - 400) * 0.1f
            rain = rainRaw * 0.3f
        } else {
            var t = tempRaw * 0.1f
            rain = rainRaw * 0.5f
            if (tempSign != 0) t = -t
            temperature = t
        }
        val humidity = br[3]
        val speed = (br[4] * 0.34f) * 3.6f
        val gust = (br[5] * 0.34f) * 3.6f
        return Reading(
            model,
            String.format("%02X", deviceId),
            linkedMapOf<String, Any?>(
                "msg_type" to msgType,
                "battery_ok" to (if (batteryLow != 0) 0 else 1),
                "temperature_C" to temperature.toDouble(),
                "humidity" to humidity,
                "wind_avg_km_h" to speed.toDouble(),
                "wind_max_km_h" to gust.toDouble(),
                "rain_mm" to rain.toDouble(),
                "mic" to "CRC",
            ),
        )
    }
    if (msgType == 6) {
        val hours = ((br[2] and 0x30) shr 4) * 10 + (br[2] and 0x0F)
        val minutes = ((br[3] and 0xF0) shr 4) * 10 + (br[3] and 0x0F)
        val seconds = ((br[4] and 0xF0) shr 4) * 10 + (br[4] and 0x0F)
        val year = ((br[5] and 0xF0) shr 4) * 10 + (br[5] and 0x0F) + 2000
        val month = ((br[6] and 0x10) shr 4) * 10 + (br[6] and 0x0F)
        val day = ((br[7] and 0xF0) shr 4) * 10 + (br[7] and 0x0F)
        return Reading(
            model,
            String.format("%02X", deviceId),
            linkedMapOf<String, Any?>(
                "msg_type" to msgType,
                "battery_ok" to (if (batteryLow != 0) 0 else 1),
                "radio_clock" to String.format("%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hours, minutes, seconds),
                "mic" to "CRC",
            ),
        )
    }
    return null
}

private fun fineoffsetWh1050Callback(bb: BitBuffer): List<Reading> {
    if (bb.numRows != 1) return emptyList()
    val out = ArrayList<Reading>()
    val bits = bb.bitsPerRow[0]
    val preambleByte = bb.bb[0][0]
    if (bits == 79 && preambleByte == 0xfe) {
        fineoffsetWh1050Decode(bb, 7, FO_TYPE_OOK)?.let { out.add(it) }
    } else if (bits == 80 && preambleByte == 0xff) {
        fineoffsetWh1050Decode(bb, 8, FO_TYPE_OOK)?.let { out.add(it) }
    } else if (bits > 112 && bits < 760) {
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0xAA, 0x2D, 0xD4), 24)
            if (bitpos + 72 > bits) break
            fineoffsetWh1050Decode(bb, bitpos + 24, FO_TYPE_FSK)?.let { out.add(it) }
            bitpos += 123
        }
    } else {
        return emptyList()
    }
    return out
}

// unverified: fineoffset_wh1050.c:201-241 callback, fineoffset_wh1050.c:108-195 decode, struct fineoffset_wh1050.c:268. upstream .priority=10 (WH55 collision ordering) not represented in API
internal object Tfa303151 : Rtl433Decoder() {
    override val name = "TFA 30.3151 Weather Station"
    override val mod = Mod.FSK_PCM
    override val short = 60
    override val long = 60
    override val reset = 2500

    override fun decode(bb: BitBuffer): List<Reading> = fineoffsetWh1050Callback(bb)
}

private fun tfa30390xCrc32(msg: IntArray, off: Int, n: Int): Int {
    var crc = -1
    for (k in 0 until n) {
        crc = crc xor msg[off + k]
        for (i in 0 until 8) {
            crc = if ((crc and 1) != 0) (crc ushr 1) xor 0xedb88320.toInt() else crc ushr 1
        }
    }
    return crc xor -1
}

private fun le16(b: IntArray, i: Int): Int = b[i] or (b[i + 1] shl 8)

// unverified: tfa_30_390x.c:89-232, struct tfa_30_390x.c:252
internal object Tfa30390x : Rtl433Decoder() {
    override val name = "TFA Dostmann 30.390X T/H sensors series"
    override val mod = Mod.FSK_PCM
    override val short = 61
    override val long = 61
    override val reset = 3500
    override val tolerance = 5

    override fun decode(bb: BitBuffer): List<Reading> {
        val bitpos = bb.search(0, 0, intArrayOf(0x4b, 0x2d, 0xd4, 0x2b), 32)
        if (bitpos + 32 + 8 > bb.bitsPerRow[0]) return emptyList()
        val lenBuf = IntArray(1)
        bb.extractBytes(0, bitpos + 32, lenBuf, 8)
        val len = lenBuf[0]
        if (len != 24 && len != 30 && len != 36) return emptyList()
        if (bitpos + 32 + len * 8 > bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(36 + 4)
        bb.extractBytes(0, bitpos, b, 32 + len * 8)
        val crcCalc = tfa30390xCrc32(b, 4, len - 4)
        val crcFrame = (b[len + 3] shl 24) or (b[len + 2] shl 16) or (b[len + 1] shl 8) or b[len]
        if (crcCalc != crcFrame) return emptyList()
        if (b[5] == 0 && b[6] == 0 && b[7] == 0 && b[8] == 0) return emptyList()
        val idStr = String.format("%02X%02X%02X%02X", b[5], b[6], b[7], b[8])
        val batteryOk = if ((b[9] and 0x08) != 0) 0 else 1
        val manualTransmit = (b[9] and 0x02) shr 1
        val seqNumber = b[10] or (b[11] shl 8)
        val fields = linkedMapOf<String, Any?>(
            "battery_ok" to batteryOk,
            "manual_transmit" to manualTransmit,
            "seq_number" to seqNumber,
        )
        when (b[5]) {
            0xa0, 0xa6 -> {
                if (len != 30) return emptyList()
                val temp = DoubleArray(3) { k -> (s16(le16(b, 12 + k * 6) shl 5) shr 5) * 0.1 }
                val humidity = DoubleArray(3) { k -> le16(b, 14 + k * 6) * 0.1 }
                fields["temperature_C"] = temp[0]
                fields["temperature_C_last"] = temp.toList()
                fields["humidity"] = humidity[0]
                fields["humidity_last"] = humidity.toList()
                fields["mic"] = "CRC"
                val model = if (b[5] == 0xa0) "TFA-303908" else "TFA-303906"
                return listOf(Reading(model, idStr, fields))
            }
            0xa3 -> {
                if (len != 30) return emptyList()
                val temp = DoubleArray(3) { k -> (s16(le16(b, 12 + k * 6) shl 5) shr 5) * 0.1 }
                val ext = DoubleArray(3) { k -> (s16(le16(b, 14 + k * 6) shl 5) shr 5) * 0.1 }
                fields["temperature_C"] = temp[0]
                fields["temperature_C_last"] = temp.toList()
                fields["temperature_C_ext"] = ext[0]
                fields["temperature_C_ext_last"] = ext.toList()
                fields["mic"] = "CRC"
                return listOf(Reading("TFA-303902", idStr, fields))
            }
            0xa4 -> {
                if (len != 36) return emptyList()
                val temp = DoubleArray(3) { k -> (s16(le16(b, 12 + k * 8) shl 4) shr 4) * 0.1 }
                val humidity = DoubleArray(3) { k -> le16(b, 14 + k * 8) * 0.1 }
                val ext = DoubleArray(3) { k -> (s16(le16(b, 16 + k * 8) shl 4) shr 4) * 0.1 }
                fields["temperature_C"] = temp[0]
                fields["temperature_C_last"] = temp.toList()
                fields["humidity"] = humidity[0]
                fields["humidity_last"] = humidity.toList()
                fields["temperature_C_ext"] = ext[0]
                fields["temperature_C_ext_last"] = ext.toList()
                fields["mic"] = "CRC"
                return listOf(Reading("TFA-303905", idStr, fields))
            }
            0xa5 -> {
                if (len != 24) return emptyList()
                val temp = DoubleArray(3) { k -> (s16(le16(b, 12 + k * 4) shl 5) shr 5) * 0.1 }
                fields["temperature_C"] = temp[0]
                fields["temperature_C_last"] = temp.toList()
                fields["mic"] = "CRC"
                return listOf(Reading("TFA-303901", idStr, fields))
            }
            else -> return emptyList()
        }
    }
}

private val RH_SYMBOLS = intArrayOf(
    0x0d, 0x0e, 0x13, 0x15, 0x16, 0x19, 0x1a, 0x1c,
    0x23, 0x25, 0x26, 0x29, 0x2a, 0x2c, 0x32, 0x34,
)

private fun rhSymbol6to4(symbol: Int): Int {
    var i = (symbol shr 2) and 8
    while (i < 16) {
        if (symbol == RH_SYMBOLS[i]) return i
        i++
    }
    return 0xFF
}

private fun radioheadAskExtract(bb: BitBuffer, row: Int, payload: IntArray): Int {
    val len = bb.bitsPerRow[row]
    var msgLen = 67 - 4 - 3
    val initPattern = intArrayOf(0x55, 0x55, 0x55, 0x51, 0xcd)
    var pos = bb.search(row, 0, initPattern, 40)
    if (pos == len) return -1
    var nbBytes = 0
    pos += 40
    val rx = IntArray(2)
    while (pos < len && nbBytes < msgLen) {
        bb.extractBytes(row, pos, rx, 16)
        rx[0] = rv8(rx[0])
        rx[1] = rv8(rx[1])
        rx[1] = ((rx[1] and 0x0F) shl 2) + (rx[0] shr 6)
        rx[0] = rx[0] and 0x3F
        val hi = rhSymbol6to4(rx[0])
        if (hi > 0xF) return -1
        val lo = rhSymbol6to4(rx[1])
        if (lo > 0xF) return -1
        val byte = (hi shl 4) or lo
        payload[nbBytes] = byte
        if (nbBytes == 0) {
            msgLen = byte
            if (msgLen < 2 || msgLen > 60) break
        }
        nbBytes++
        pos += 12
    }
    if (msgLen < 2) return -1
    if (msgLen > 60) return -1
    val crc = (payload[msgLen - 1] shl 8) or payload[msgLen - 2]
    val crcRecompute = Rtl433BitUtil.crc16lsb(payload, msgLen - 2, 0x8408, 0xFFFF).inv() and 0xFFFF
    if (crcRecompute != crc) return -1
    return msgLen
}

// unverified: radiohead_ask.c:186-236, struct radiohead_ask.c:261
internal object SensibleLiving : Rtl433Decoder() {
    override val name = "Sensible Living Mini-Plant Moisture Sensor"
    override val mod = Mod.OOK_PCM
    override val short = 1000
    override val long = 1000
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        val p = IntArray(67)
        val msgLen = radioheadAskExtract(bb, 0, p)
        if (msgLen <= 0) return emptyList()
        val houseId = p[1]
        val moduleId = (p[2] shl 8) or p[3]
        val sensorType = p[4]
        val sensorCount = p[5]
        val alarms = p[6]
        val sensorValue = (p[7] shl 8) or p[8]
        val batteryVoltage = (p[9] shl 8) or p[10]
        return listOf(
            Reading(
                "SensibleLiving-Moisture",
                null,
                linkedMapOf<String, Any?>(
                    "house_id" to houseId,
                    "module_id" to moduleId,
                    "sensor_type" to sensorType,
                    "sensor_count" to sensorCount,
                    "alarms" to alarms,
                    "sensor_value" to sensorValue,
                    "battery_mV" to batteryVoltage * 10,
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

private fun ssGetId(b: IntArray): String {
    val sb = StringBuilder()
    for (k in 3..7) {
        val c = rv8(b[k])
        if (c < 32 || c > 126) sb.append('?') else sb.append(c.toChar())
    }
    return sb.toString()
}

// unverified: simplisafe.c:54-96 (ss_sensor_parser), 101-133 (ss_pinentry_parser), 138-172 (ss_keypad_commands), 174-198 (callback), struct simplisafe.c:209
internal object SsSensor : Rtl433Decoder() {
    override val name = "SimpliSafe Home Security System (May require disabling automatic gain for KeyPad decodes)"
    override val mod = Mod.OOK_PIWM_DC
    override val short = 500
    override val long = 1000
    override val reset = 2200
    override val tolerance = 100

    private fun sensorParser(bb: BitBuffer, row: Int): List<Reading> {
        val b = bb.bb[row]
        if (bb.bitsPerRow[row] != 92) return emptyList()
        val seq = rv8(b[8])
        val state = rv8(b[9])
        val csum = rv8(b[10])
        if (((seq + state) and 0xff) != csum) return emptyList()
        val id = ssGetId(b)
        val extradata = when (state) {
            1 -> "Contact Open"
            2 -> "Contact Closed"
            3 -> "Alarm Off"
            else -> ""
        }
        return listOf(
            Reading(
                "SimpliSafe-Sensor",
                id,
                linkedMapOf<String, Any?>(
                    "seq" to seq,
                    "state" to state,
                    "extradata" to extradata,
                ),
            ),
        )
    }

    private fun pinentryParser(bb: BitBuffer, row: Int): List<Reading> {
        val b = bb.bb[row]
        val pina = rv8(b[10])
        val pinb = rv8(b[11])
        val digits = intArrayOf(pina and 0xf, (pina and 0xf0) shr 4, pinb and 0xf, (pinb and 0xf0) shr 4)
        val id = ssGetId(b)
        val extradata = String.format("Disarm Pin: %x%x%x%x", digits[0], digits[1], digits[2], digits[3])
        return listOf(
            Reading(
                "SimpliSafe-Keypad",
                id,
                linkedMapOf<String, Any?>(
                    "seq" to b[9],
                    "extradata" to extradata,
                ),
            ),
        )
    }

    private fun keypadCommands(bb: BitBuffer, row: Int): List<Reading> {
        val b = bb.bb[row]
        val extradata = when (b[10]) {
            0x6a -> "Arm System - Away"
            0xca -> "Arm System - Home"
            0x3a -> "Arm System - Canceled"
            0x2a -> "Keypad Panic Button"
            0x86 -> "Keypad Menu Button"
            else -> String.format("Unknown Keypad: %02x", b[10])
        }
        val id = ssGetId(b)
        return listOf(
            Reading(
                "SimpliSafe-Keypad",
                id,
                linkedMapOf<String, Any?>(
                    "seq" to b[9],
                    "extradata" to extradata,
                ),
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(2, 90)
        if (row < 0) return emptyList()
        val first = bb.bb[row]
        if (first[0] != 0xcc || first[1] != 0x5f) return emptyList()
        bb.invert()
        return when (bb.bb[row][2]) {
            0x88 -> sensorParser(bb, row)
            0x66 -> pinentryParser(bb, row)
            0x44 -> keypadCommands(bb, row)
            else -> emptyList()
        }
    }
}

private val SOMFY_CONTROL_STRS = arrayOf(
    "? (0)", "My (1)", "Up (2)", "My + Up (3)", "Down (4)", "My + Down (5)", "Up + Down (6)", "My + Up + Down (7)",
    "Prog (8)", "Sun + Flag (9)", "Flag (10)", "? (11)", "? (12)", "? (13)", "? (14)", "? (15)",
)

private val SOMFY_SEED_STRS = arrayOf(
    "? (0)", "? (1)", "? (2)", "? (3)", "? (4)", "Stop (5)", "Up (6)", "? (7)",
    "Down (8)", "? (9)", "? (10)", "? (11)", "Prog (12)", "? (13)", "? (14)", "? (15)",
)

// unverified: somfy_rts.c:74-205, struct somfy_rts.c:221. upstream .tolerance=20 and gap/reset limits transcribed
internal object SomfyRts : Rtl433Decoder() {
    override val name = "Somfy RTS"
    override val mod = Mod.OOK_PCM
    override val short = 604
    override val long = 604
    override val gap = 3000
    override val reset = 10000
    override val tolerance = 20

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamblePatternLong = intArrayOf(0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xff, 0x00)
        val preambleLengthLong = 49
        val preamblePatternRate = intArrayOf(0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xfe, 0x00)
        val preambleLengthRate = 48
        val preamblePatternShort = intArrayOf(0xf0, 0xf0, 0xff, 0x00)
        val preambleLengthShort = 25

        var isRetransmission = 0
        var decodeRow = -1
        var bitpos = 0

        for (row in 0 until bb.numRows) {
            if (bb.bitsPerRow[row] > 170) {
                isRetransmission = 1
                bitpos = bb.search(row, 0, preamblePatternLong, preambleLengthLong) + preambleLengthLong
                if (bitpos + 56 * 2 > bb.bitsPerRow[row]) {
                    bitpos = bb.search(row, 0, preamblePatternRate, preambleLengthRate) + preambleLengthRate
                }
                if (bitpos + 56 * 2 <= bb.bitsPerRow[row]) {
                    decodeRow = row
                    break
                }
            } else if (bb.bitsPerRow[row] > 130) {
                isRetransmission = 0
                bitpos = bb.search(row, 0, preamblePatternShort, preambleLengthShort) + preambleLengthShort
                if (bitpos + 56 * 2 <= bb.bitsPerRow[row]) {
                    decodeRow = row
                    break
                }
            }
        }

        if (decodeRow < 0) return emptyList()
        if (bitpos + 56 * 2 > bb.bitsPerRow[decodeRow]) return emptyList()

        val decoded = BitBuffer()
        bb.manchesterDecode(decodeRow, bitpos, decoded, 80)
        if (decoded.numRows == 0 || decoded.bitsPerRow[0] < 56) return emptyList()

        val b = decoded.bb[0]
        for (i in 6 downTo 1) {
            b[i] = b[i] xor b[i - 1]
        }

        var chksumCalc = Rtl433BitUtil.xorBytes(b, 7)
        chksumCalc = (chksumCalc and 0xf) xor (chksumCalc shr 4)
        if (chksumCalc != 0) return emptyList()

        val seed = b[0]
        val control = (b[1] and 0xf0) shr 4
        val counter = (b[2] shl 8) or b[3]
        val address = (b[6] shl 16) or (b[5] shl 8) or b[4]

        val controlStr = if (control == 0xf) SOMFY_SEED_STRS[seed and 0xf] else SOMFY_CONTROL_STRS[control]

        return listOf(
            Reading(
                "Somfy-RTS",
                String.format("%06X", address),
                linkedMapOf<String, Any?>(
                    "control" to controlStr,
                    "counter" to counter,
                    "retransmission" to isRetransmission,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: somfy_iohc.c:94-197, struct somfy_iohc.c:221
internal object SomfyIohc : Rtl433Decoder() {
    override val name = "Somfy io-homecontrol"
    override val mod = Mod.FSK_PCM
    override val short = 26
    override val long = 26
    override val reset = 300

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val offset = bb.search(0, 0, intArrayOf(0x57, 0xfd, 0x99), 24) + 24
        if (offset >= bb.bitsPerRow[0]) return emptyList()
        val numBits = minOf(bb.bitsPerRow[0] - offset, 34 * 10)
        val b = IntArray(34)
        var len = uart8n1(bb.bb[0], offset, numBits, b)
        if (len < 11) return emptyList()
        val msgLen = b[0] and 0x1f
        if (len < msgLen + 3) return emptyList()
        if (msgLen < 8) return emptyList()
        len = msgLen + 3
        val msgEndFlag = (b[0] and 0x80) shr 7
        val msgStartFlag = (b[0] and 0x40) shr 6
        val msgProtocolMode = (b[0] and 0x20) shr 5
        val msgUseBeacon = (b[1] and 0x80) shr 7
        val msgIsRouted = (b[1] and 0x40) shr 6
        val msgLowPowerMode = (b[1] and 0x20) shr 5
        val msgProtocolVersion = b[1] and 0x03
        val msgDstAddr = (b[2] shl 16) or (b[3] shl 8) or b[4]
        val msgSrcAddr = (b[5] shl 16) or (b[6] shl 8) or b[7]
        val msgCmdId = b[8]
        var msgSeqNr = 0
        var msgMac = ""
        var dataLength = msgLen - 8
        val msgData: String
        if (msgProtocolMode == 0 || dataLength < 8) {
            msgData = bitrowSnprint(b.copyOfRange(9, 9 + dataLength), dataLength * 8)
        } else {
            dataLength -= 8
            msgData = bitrowSnprint(b.copyOfRange(9, 9 + dataLength), dataLength * 8)
            msgSeqNr = (b[9 + dataLength] shl 8) or b[9 + dataLength + 1]
            msgMac = bitrowSnprint(b.copyOfRange(9 + dataLength + 2, 9 + dataLength + 2 + 6), 6 * 8)
        }
        if (Rtl433BitUtil.crc16lsb(b, len, 0x8408, 0x0000) != 0) return emptyList()
        val fields = linkedMapOf<String, Any?>(
            "dst_id" to String.format("%06x", msgDstAddr),
            "msg_type" to msgCmdId,
            "msg" to msgData,
            "mode" to (if (msgProtocolMode != 0) "One-way" else "Two-way"),
            "version" to msgProtocolVersion,
            "flag_end" to msgEndFlag,
            "flag_start" to msgStartFlag,
            "flag_mode" to msgProtocolMode,
            "flag_beacon" to msgUseBeacon,
            "flag_routed" to msgIsRouted,
            "flag_lpm" to msgLowPowerMode,
            "mic" to "CRC",
        )
        if (msgProtocolMode == 1) {
            fields["counter"] = msgSeqNr
            fields["mac"] = msgMac
        }
        return listOf(Reading("Somfy-IOHC", String.format("%06x", msgSrcAddr), fields))
    }
}

private class SsOut(private val cap: Int) {
    val sb = StringBuilder()
    fun add(s: String) {
        val room = cap - 1 - sb.length
        if (room > 0) sb.append(if (s.length > room) s.substring(0, room) else s)
    }
    fun hasText(): Boolean = sb.isNotEmpty()
}

private class SsExtras {
    var seenDll2 = false
    var seenDll4 = false
    var seenDll9 = false
    var seenMpdu = false
    var haveSeq = false
    var retry = 0
    var fragMore = 0
    var fragNum = 0
    var seqNum = 0
    var haveFet = false
    var fet = 0
    var haveRssi = false
    var rssi = 0
    var haveCli = false
    var cliTxPri = 0
    var cliTxTime = 0
    var cliRxPri = 0
    var cliRxTime = 0
    var haveSync = false
    var syncChannel = 0
    var routes = ""
    var ipv6 = ""
}

private class SsTlv(val used: Int, val type: Int, val isDll: Boolean)

private fun ssHex(a: IntArray, o: Int, n: Int): String {
    val sb = StringBuilder()
    for (k in 0 until n) sb.append(String.format("%02x", a[o + k] and 0xFF))
    return sb.toString()
}

private fun ssCrc32(data: IntArray, len: Int): Long {
    var crc = 0xffffffffL
    for (i in 0 until len) {
        crc = crc xor ((data[i].toLong() and 0xFF) shl 24)
        for (b in 0 until 8) {
            crc = if ((crc and 0x80000000L) != 0L) ((crc shl 1) xor 0x04c11db7L) and 0xffffffffL else (crc shl 1) and 0xffffffffL
        }
    }
    return crc
}

private fun ssDescramble(buf: IntArray, len: Int, seed: Int) {
    var reg = seed and 0xFF
    for (i in 0 until len) {
        var k = 0
        for (b in 0 until 8) {
            k = ((k shl 1) or ((reg shr 7) and 1)) and 0xFF
            var t = reg and 0x8e
            t = t xor (t shr 4)
            t = t xor (t shr 2)
            t = t xor (t shr 1)
            reg = ((reg shl 1) or (t and 1)) and 0xFF
        }
        buf[i] = buf[i] xor k
    }
}

private fun ssAppendRoute(buf: IntArray, len: Int, o: Int, out: SsOut): Int {
    if (o + 36 > len || buf[o] != 0x21) return 0
    val count = buf[o + 28]
    val total = 36 + 8 * count
    if (o + total > len) return 0
    val pathCost = (buf[o + 32] shl 8) or buf[o + 33]
    val linkCost = (buf[o + 34] shl 8) or buf[o + 35]
    out.add("${if (out.hasText()) "; " else ""}hop<=${buf[o + 1]} cost=$pathCost/$linkCost egress=")
    out.add(ssHex(buf, o + 20, 8))
    for (n in 0 until count) {
        out.add(" next=")
        out.add(ssHex(buf, o + 36 + 8 * n, 8))
    }
    return total
}

private fun ssParseRoutes(buf: IntArray): String {
    val out = SsOut(384)
    var o = 0
    while (o < buf.size) {
        val used = ssAppendRoute(buf, buf.size, o, out)
        if (used == 0) break
        o += used
    }
    return out.sb.toString()
}

private fun ssIpSum(sumIn: Long, data: IntArray, off: Int, len: Int): Long {
    var sum = sumIn
    var i = 0
    while (i + 1 < len) {
        sum += ((data[off + i] shl 8) or data[off + i + 1]).toLong()
        i += 2
    }
    if (i < len) sum += (data[off + i] shl 8).toLong()
    return sum
}

private fun ssParseIpv6(p: IntArray): String {
    val len = p.size
    if (len < 40) return ""
    val plen = (p[4] shl 8) or p[5]
    val nextHdr = p[6]
    if (40 + plen > len) return ""
    val out = SsOut(256)
    out.add("[")
    for (i in 0 until 16 step 2) out.add("${if (i != 0) ":" else ""}${ssHex(p, 8 + i, 2)}")
    out.add("] -> [")
    for (i in 0 until 16 step 2) out.add("${if (i != 0) ":" else ""}${ssHex(p, 24 + i, 2)}")
    out.add("]")
    if (nextHdr == 17 && plen >= 8) {
        val sport = (p[40] shl 8) or p[41]
        val dport = (p[42] shl 8) or p[43]
        val ulen = (p[44] shl 8) or p[45]
        if (ulen <= plen) {
            var sum = 17L + ulen
            sum = ssIpSum(sum, p, 8, 16)
            sum = ssIpSum(sum, p, 24, 16)
            sum = ssIpSum(sum, p, 40, ulen)
            while ((sum ushr 16) != 0L) sum = (sum and 0xffff) + (sum ushr 16)
            val ok = (sum and 0xffff) == 0xffffL
            out.add(" $sport->$dport len=$ulen cksum=${if (ok) "ok" else "bad"}")
            if (dport == 648 && ulen >= 14) out.add(" mgmt_len=${(p[52] shl 8) or p[53]}")
        }
    }
    return out.sb.toString()
}

private fun ssParseMpdu16(v: IntArray, extras: SsExtras) {
    val vlen = v.size
    if (vlen < 1) return
    if (v[0] == 0x21) {
        extras.routes = ssParseRoutes(v)
        return
    }
    if (vlen < 4) return
    val pid = v[0] and 0x0f
    val addrCnt = v[3] and 0x3f
    val hdrLen = 4 + 8 * addrCnt
    if (hdrLen > vlen) return
    val payload = v.copyOfRange(hdrLen, vlen)
    if (pid == 3) extras.routes = ssParseRoutes(payload)
    else if (pid == 6) extras.ipv6 = ssParseIpv6(payload)
}

private fun ssAppendTlv(psdu: IntArray, len: Int, i: Int, out: SsOut, extras: SsExtras?): SsTlv? {
    if (i + 2 > len) return null
    val h0 = psdu[i]
    val h1 = psdu[i + 1]
    val isMpdu = (h0 and 0x80) != 0
    val type = if (isMpdu) h0 shr 3 else (h0 shl 1) or (h1 shr 7)
    val vlen = if (isMpdu) ((h0 and 0x07) shl 8) or h1 else h1 and 0x7f
    if (i + 2 + vlen > len) return null
    val v = psdu.copyOfRange(i + 2, i + 2 + vlen)
    out.add("${if (out.hasText()) " " else ""}${if (isMpdu) "M" else "D"}$type/$vlen")
    if (isMpdu && type == 17 && vlen > 0) {
        out.add("{")
        ssAppendTlv(psdu, i + 2 + vlen, i + 2, out, null)
        out.add("}")
    }
    if (extras != null) {
        if (isMpdu) {
            extras.seenMpdu = true
            if (type == 16) ssParseMpdu16(v, extras)
        } else {
            when (type) {
                2 -> {
                    extras.seenDll2 = true
                    if (vlen == 3) {
                        val raw = (v[0] shl 16) or (v[1] shl 8) or v[2]
                        extras.haveCli = true
                        extras.cliTxPri = (raw shr 21) and 0x7
                        extras.cliTxTime = (raw shr 12) and 0x1ff
                        extras.cliRxPri = (raw shr 9) and 0x7
                        extras.cliRxTime = raw and 0x1ff
                    }
                }
                4 -> {
                    extras.seenDll4 = true
                    if (vlen == 2) {
                        val raw = (v[0] shl 8) or v[1]
                        extras.haveSeq = true
                        extras.retry = (raw shr 15) and 1
                        extras.fragMore = (raw shr 14) and 1
                        extras.fragNum = (raw shr 10) and 0xf
                        extras.seqNum = raw and 0x3ff
                    }
                }
                9 -> {
                    extras.seenDll9 = true
                    if (vlen == 1) {
                        extras.haveRssi = true
                        extras.rssi = if (v[0] >= 128) v[0] - 256 else v[0]
                    }
                }
                1 -> {
                    if (vlen == 2) {
                        extras.haveFet = true
                        extras.fet = (v[0] shl 8) or v[1]
                    }
                }
                8 -> {
                    if (vlen == 5) {
                        extras.haveSync = true
                        extras.syncChannel = v[4]
                    }
                }
            }
        }
    }
    return SsTlv(2 + vlen, type, !isMpdu)
}

private fun ssParseTlvs(psdu: IntArray, psduLen: Int, start: Int, extras: SsExtras): String {
    val out = SsOut(256)
    var i = start
    var sawCrc = false
    while (i < psduLen) {
        val t = ssAppendTlv(psdu, psduLen, i, out, extras) ?: break
        i += t.used
        if (t.isDll && t.type == 6) {
            sawCrc = true
            continue
        }
        if (t.isDll && t.type == 5) {
            if (i < psduLen) out.add(" +${psduLen - i}B")
            return out.sb.toString()
        }
    }
    if (sawCrc && i + 4 == psduLen) {
        val want = (psdu[i].toLong() shl 24) or (psdu[i + 1].toLong() shl 16) or (psdu[i + 2].toLong() shl 8) or psdu[i + 3].toLong()
        val got = ssCrc32(psdu, i)
        out.add("${if (out.hasText()) " " else ""}:${if (got == want) "ok" else "bad"}")
    } else if (i < psduLen) {
        out.add("${if (out.hasText()) " " else ""}+${psduLen - i}B")
    }
    return out.sb.toString()
}

private fun ssClassifyLink(fctrl: Int, e: SsExtras): String {
    if (fctrl == 2) return "broadcast"
    if (fctrl == 3) return "poll"
    if (fctrl == 1) {
        if (e.seenDll4 || e.seenMpdu) return "data"
        if (e.seenDll2) return "poll_ack"
        if (e.seenDll9) return "data_ack"
    }
    return ""
}

internal object SilverSpringMesh : Rtl433Decoder() {
    override val name = "Silver Spring Networks mesh endpoint (-s 1600k)"
    override val mod = Mod.FSK_PCM
    override val short = 10
    override val long = 10
    override val reset = 1000

    private val syncPattern = intArrayOf(0xaa, 0xaa, 0x18, 0xbf)

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        var pos = bb.search(0, 0, syncPattern, 32)
        if (pos >= bb.bitsPerRow[0]) {
            bb.invert()
            pos = bb.search(0, 0, syncPattern, 32)
            if (pos >= bb.bitsPerRow[0]) return emptyList()
        }
        val frameStart = pos + 32 - 1
        val availBits = bb.bitsPerRow[0] - frameStart
        if (availBits < (3 + 4) * 8) return emptyList()
        var availBytes = availBits / 8
        if (availBytes > 512) availBytes = 512
        bb.invert()
        val frame = IntArray(512 + 2)
        bb.extractBytes(0, frameStart, frame, availBytes * 8)

        if ((frame[1] and 0xf8) != 0) return emptyList()

        val channel = frame[0]
        val psduLen = ((frame[1] and 0x07) shl 8) or frame[2]
        val frameLen = 3 + psduLen + 4
        if (psduLen < 1 || frameLen > availBytes) return emptyList()

        val psdu = IntArray(512 + 8)
        val scrLen = psduLen + 4
        var seedFound = -1
        var seed = 1
        while (seed < 256 && seedFound < 0) {
            for (k in 0 until scrLen) psdu[k] = frame[3 + k]
            ssDescramble(psdu, scrLen, seed)
            val fcs = (psdu[psduLen].toLong() shl 24) or (psdu[psduLen + 1].toLong() shl 16) or
                (psdu[psduLen + 2].toLong() shl 8) or psdu[psduLen + 3].toLong()
            if (ssCrc32(psdu, psduLen) == fcs) seedFound = seed
            seed++
        }
        if (seedFound < 0) return emptyList()

        val psduStr = ssHex(psdu, 0, psduLen)

        val fctrl = psdu[0]
        var addrOff = 1
        var dstStr = ""
        var srcStr = ""
        if ((fctrl and 0x01) != 0 && addrOff + 8 <= psduLen) {
            dstStr = ssHex(psdu, addrOff, 8)
            addrOff += 8
        }
        if ((fctrl and 0x02) != 0 && addrOff + 8 <= psduLen) {
            srcStr = ssHex(psdu, addrOff, 8)
            addrOff += 8
        }

        val extras = SsExtras()
        val tlvStr = ssParseTlvs(psdu, psduLen, addrOff, extras)
        val link = ssClassifyLink(fctrl, extras)

        val fields = linkedMapOf<String, Any?>()
        if (dstStr.isNotEmpty()) fields["dst_id"] = dstStr
        if (srcStr.isNotEmpty()) fields["src_id"] = srcStr
        fields["channel"] = channel
        fields["seed"] = String.format("%02x", seedFound)
        fields["len"] = psduLen
        if (link.isNotEmpty()) fields["link"] = link
        if (extras.haveSeq) {
            fields["seq_num"] = extras.seqNum
            fields["frag_num"] = extras.fragNum
            fields["frag_more"] = extras.fragMore
            fields["retry"] = extras.retry
        }
        if (extras.haveFet) fields["fet"] = extras.fet
        if (extras.haveRssi) fields["rssi"] = extras.rssi
        if (extras.haveCli) {
            fields["cli_tx_pri"] = extras.cliTxPri
            fields["cli_tx_time"] = extras.cliTxTime
            fields["cli_rx_pri"] = extras.cliRxPri
            fields["cli_rx_time"] = extras.cliRxTime
        }
        if (extras.haveSync) fields["sync_channel"] = extras.syncChannel
        if (extras.routes.isNotEmpty()) fields["routes"] = extras.routes
        if (extras.ipv6.isNotEmpty()) fields["ipv6"] = extras.ipv6
        if (tlvStr.isNotEmpty()) fields["tlvs"] = tlvStr
        fields["data"] = psduStr
        fields["mic"] = "CRC"
        val id = if (srcStr.isNotEmpty()) srcStr else if (dstStr.isNotEmpty()) dstStr else null
        return listOf(Reading("SilverSpring-Mesh", id, fields))
    }
}

private fun spReverse32(x: Int): Int {
    var r = 0
    for (i in 0 until 32) r = (r shl 1) or ((x ushr i) and 1)
    return r
}

internal object SecplusV1 : Rtl433Decoder() {
    override val name = "Security+ (Keyfob)"
    override val mod = Mod.OOK_PCM
    override val short = 500
    override val long = 500
    override val gap = 15000
    override val reset = 80000
    override val tolerance = 20

    private const val CACHE_MAX_AGE_MS = 800L
    private val cachedResult = IntArray(24)
    private var cachedMs = 0L
    private val preamble1 = intArrayOf(0x02)
    private val preamble2 = intArrayOf(0x07)

    private fun decodeHalf(bits: IntArray, result: IntArray): Int {
        var r = 0
        var x = 0
        for (i in 0 until 11) {
            for (j in 0 until 8) {
                val k = (bits[i] shl j) and 0x80
                if (k != 0) {
                    x++
                } else {
                    if (x == 0) continue
                    if (x > 3) return -1
                    result[r++] = x - 1
                    x = 0
                }
            }
        }
        return result[0]
    }

    private fun findNext(bb: BitBuffer, cur: Int): Int {
        val b0 = bb.bb[0][0]
        if (cur == 0 && ((b0 and 0xf0) == 0x10 || (b0 and 0xf0) == 0x70)) return 0
        if (cur == 0 && ((b0 and 0xE0) == 0xe0 || (b0 and 0xc0) == 0x80)) return 0
        val s1 = bb.search(0, cur, preamble1, 8) + 3
        val s2 = bb.search(0, cur, preamble2, 8) + 3
        return if (s1 < s2) s1 else s2
    }

    @Synchronized
    override fun decode(bb: BitBuffer): List<Reading> {
        val len0 = bb.bitsPerRow[0]
        if (len0 < 84 || len0 > 130) return emptyList()
        val result1 = IntArray(24)
        val result2 = IntArray(24)
        var status = 0
        var searchIndex = 0
        while (searchIndex < bb.bitsPerRow[0] && status == 0) {
            val buffy = IntArray(44)
            val buffi = IntArray(11)
            searchIndex = findNext(bb, searchIndex)
            if (searchIndex == -1 || searchIndex + 84 > bb.bitsPerRow[0]) break
            bb.extractBytes(0, searchIndex, buffi, 84)
            val dr = decodeHalf(buffi, buffy)
            if (dr < 0 || dr == 1) {
                searchIndex += 4
                continue
            } else if (dr == 0) {
                buffy.copyInto(result1, 0, 0, 22)
                status = status xor 1
                searchIndex += 88
            } else if (dr == 2) {
                buffy.copyInto(result2, 0, 0, 22)
                status = status xor 2
                searchIndex += 88
            }
            if (status == 3) break
        }
        if (status == 0) return emptyList()

        val now = System.currentTimeMillis()
        if (cachedMs != 0L) {
            if (now - cachedMs < CACHE_MAX_AGE_MS) {
                if (status == 2 && cachedResult[0] == 0) {
                    cachedResult.copyInto(result1, 0, 0, 21)
                    status = 3
                } else if (status == 1 && cachedResult[0] == 2) {
                    cachedResult.copyInto(result2, 0, 0, 21)
                    status = 3
                }
            }
            cachedResult.fill(0)
            cachedMs = 0L
        }

        if (status == 1) {
            cachedMs = now
            result1.copyInto(cachedResult, 0, 0, 21)
            return emptyList()
        } else if (status == 2) {
            cachedMs = now
            result2.copyInto(cachedResult, 0, 0, 21)
            return emptyList()
        } else if (status != 3) {
            return emptyList()
        }

        var rollingTemp = 0
        var fixed = 0L
        for (src in arrayOf(result1, result2)) {
            var acc = 0
            var i = 0
            while (i < 20) {
                var digit = src[1 + i]
                rollingTemp = rollingTemp * 3 + digit
                acc += digit
                digit = (60 + src[2 + i] - acc) % 3
                fixed = (fixed * 3 + digit) and 0xffffffffL
                acc += digit
                i += 2
            }
        }
        val rolling = spReverse32(rollingTemp).toLong() and 0xffffffffL

        val switchId = (fixed % 3).toInt()
        val id: Int
        val id0 = ((fixed / 3) % 3).toInt()
        val id1 = ((fixed / 9).toInt()) % 3
        var padId = 0
        var pin = 0
        var pinS = ""
        var remoteId = 0
        var button = ""

        if (id1 == 0) {
            padId = ((fixed / 27) % 2187).toInt()
            id = padId
            pin = ((fixed / 59049) % 19683).toInt()
            if (pin in 0..9999) {
                pinS = String.format("%04d", pin)
            } else if (pin in 10000..11029) {
                pinS = "enter"
            }
            val pinSuffix = ((fixed / 1162261467L) % 3).toInt()
            if (pinSuffix == 1) pinS += "#" else if (pinSuffix == 2) pinS += "*"
        } else {
            remoteId = fixed.toInt() / 27
            id = remoteId
            button = when (switchId) {
                1 -> "left"
                0 -> "middle"
                else -> "right"
            }
        }

        val fields = linkedMapOf<String, Any?>()
        fields["id0"] = id0
        fields["id1"] = id1
        fields["switch_id"] = switchId
        if (padId != 0) fields["pad_id"] = padId
        if (pin != 0) fields["pin"] = pinS
        if (remoteId != 0) {
            fields["remote_id"] = remoteId
            fields["button_id"] = button
        }
        fields["fixed"] = fixed.toString()
        fields["rolling"] = rolling.toString()
        return listOf(Reading("Secplus-v1", id.toString(), fields))
    }
}

internal object SecplusV2 : Rtl433Decoder() {
    override val name = "Security+ 2.0 (Keyfob)"
    override val mod = Mod.OOK_PCM
    override val short = 250
    override val long = 250
    override val gap = 1500
    override val reset = 9000
    override val tolerance = 50

    private const val CACHE_TIMEOUT_MS = 800L
    private val preamble = intArrayOf(0xaa, 0xaa, 0x95, 0x60)
    private var cachedFixed1: BitBuffer? = null
    private var cachedRolling1 = IntArray(16)
    private var cachedTv1 = 0L
    private var cachedFixed2: BitBuffer? = null
    private var cachedRolling2 = IntArray(16)
    private var cachedTv2 = 0L

    private fun decodeHalf(bits: BitBuffer, rollArray: IntArray, fixedP: BitBuffer): Int {
        val buffy = IntArray(10)
        bits.extractBytes(0, 4, buffy, 8)
        val order = buffy[0] shr 4
        val invert = buffy[0] and 0x0f
        bits.extractBytes(0, 12, buffy, 30)
        var x = (buffy[0] shl 24) or (buffy[1] shl 16) or (buffy[2] shl 8) or buffy[3]
        x = x ushr 2
        var p0 = 0
        var p1 = 0
        var p2 = 0
        for (i in 0 until 10) {
            p2 = p2 xor ((x and 1) shl i)
            x = x ushr 1
            p1 = p1 xor ((x and 1) shl i)
            x = x ushr 1
            p0 = p0 xor ((x and 1) shl i)
            x = x ushr 1
        }
        when (invert) {
            0x00 -> { p0 = p0.inv() and 0x03FF; p1 = p1.inv() and 0x03FF }
            0x01 -> p1 = p1.inv() and 0x03FF
            0x02 -> p2 = p2.inv() and 0x03FF
            0x04 -> { p0 = p0.inv() and 0x03FF; p1 = p1.inv() and 0x03FF; p2 = p2.inv() and 0x03FF }
            0x05, 0x0a -> { p0 = p0.inv() and 0x03FF; p2 = p2.inv() and 0x03FF }
            0x06 -> { p1 = p1.inv() and 0x03FF; p2 = p2.inv() and 0x03FF }
            0x08 -> p0 = p0.inv() and 0x03FF
            0x09 -> {}
            else -> return 1
        }
        val a = p0
        val b = p1
        val c = p2
        when (order) {
            0x06, 0x09 -> { p2 = a; p1 = b; p0 = c }
            0x08, 0x04 -> { p1 = a; p2 = b; p0 = c }
            0x01 -> { p2 = a; p0 = b; p1 = c }
            0x00 -> { p0 = a; p2 = b; p1 = c }
            0x05 -> { p1 = a; p0 = b; p2 = c }
            0x02, 0x0a -> { p0 = a; p1 = b; p2 = c }
            else -> return 2
        }
        bits.extractBytes(0, 4, buffy, 8)
        val rx = buffy[0]
        var k = 0
        var i = 6
        while (i >= 0) {
            rollArray[k++] = (rx shr i) and 0x03
            i -= 2
        }
        i = 8
        while (i >= 0) {
            rollArray[k++] = (p2 shr i) and 0x03
            i -= 2
        }
        for (n in 0 until 9) if (rollArray[n] == 3) return 1
        for (n in 9 downTo 0) fixedP.addBit((p0 shr n) and 1)
        for (n in 9 downTo 0) fixedP.addBit((p1 shr n) and 1)
        return 0
    }

    @Synchronized
    override fun decode(bb: BitBuffer): List<Reading> {
        val bits = BitBuffer()
        var fixed1 = BitBuffer()
        var rolling1 = IntArray(16)
        var fixed2 = BitBuffer()
        var rolling2 = IntArray(16)

        for (row in 0 until bb.numRows) {
            if (bb.bitsPerRow[row] < 110) continue
            val searchIndex = bb.search(row, 0, preamble, 28)
            if (searchIndex >= bb.bitsPerRow[row]) break
            bits.clear()
            bb.manchesterDecode(row, searchIndex + 26, bits, 80)
            if (bits.bitsPerRow[0] < 42) continue
            if ((bits.bb[0][0] and 0xB0) != 0) continue
            if ((bits.bb[0][0] and 0xC0) != 0) {
                decodeHalf(bits, rolling2, fixed2)
            } else {
                decodeHalf(bits, rolling1, fixed1)
            }
            if (fixed1.bitsPerRow[0] > 1 && fixed2.bitsPerRow[0] > 1) break
        }

        val got1 = fixed1.bitsPerRow[0] > 1
        val got2 = fixed2.bitsPerRow[0] > 1
        if (got1 && got2) {
            cachedFixed1 = null
            cachedFixed2 = null
        } else {
            val now = System.currentTimeMillis()
            if (cachedFixed1 != null && now - cachedTv1 >= CACHE_TIMEOUT_MS) cachedFixed1 = null
            if (cachedFixed2 != null && now - cachedTv2 >= CACHE_TIMEOUT_MS) cachedFixed2 = null
            if (got1) {
                cachedFixed1 = fixed1
                cachedRolling1 = rolling1
                cachedTv1 = now
            }
            if (got2) {
                cachedFixed2 = fixed2
                cachedRolling2 = rolling2
                cachedTv2 = now
            }
            val c1 = cachedFixed1
            val c2 = cachedFixed2
            if (c1 != null && c2 != null) {
                fixed1 = c1
                rolling1 = cachedRolling1
                fixed2 = c2
                rolling2 = cachedRolling2
                cachedFixed1 = null
                cachedFixed2 = null
            } else {
                return emptyList()
            }
        }

        if (fixed1.bitsPerRow[0] == 0 || fixed2.bitsPerRow[0] == 0) return emptyList()

        val rollingDigits = IntArray(24)
        var r = 0
        rollingDigits[r++] = rolling2[8]
        rollingDigits[r++] = rolling1[8]
        for (i in 4 until 8) rollingDigits[r++] = rolling2[i]
        for (i in 4 until 8) rollingDigits[r++] = rolling1[i]
        for (i in 0 until 4) rollingDigits[r++] = rolling2[i]
        for (i in 0 until 4) rollingDigits[r++] = rolling1[i]

        var rollingTemp = 0L
        for (i in 0 until 18) rollingTemp = (rollingTemp * 3 + rollingDigits[i]) and 0xffffffffL
        if (rollingTemp >= 0x10000000L) return emptyList()
        val rollingTotal = (spReverse32(rollingTemp.toInt()).toLong() and 0xffffffffL) ushr 4

        var fixedTotal = 0L
        var f = fixed1.bb[0]
        fixedTotal = fixedTotal xor (f[0].toLong() shl 32)
        fixedTotal = fixedTotal xor (f[1].toLong() shl 24)
        fixedTotal = fixedTotal xor (f[2].toLong() shl 16)
        f = fixed2.bb[0]
        fixedTotal = fixedTotal xor (f[0].toLong() shl 12)
        fixedTotal = fixedTotal xor (f[1].toLong() shl 4)
        fixedTotal = fixedTotal xor ((f[2] shr 4) and 0x0f).toLong()

        val remoteId = (fixedTotal and 0xffffffffL).toInt()
        val fields = linkedMapOf<String, Any?>(
            "button_id" to (fixedTotal shr 32).toInt(),
            "remote_id" to remoteId,
            "fixed" to fixedTotal.toString(),
            "rolling" to rollingTotal.toString(),
        )
        return listOf(Reading("Secplus-v2", remoteId.toString(), fields))
    }
}

internal val BATCH_07: List<Rtl433Decoder> = listOf(
    SainlogicSa8,
    Schou72543Rain,
    SchraderEG53MA4,
    SchraderMRXBC5A4,
    SchraderNIS315G3,
    SchraderSMD3MA4,
    Schraeder,
    Scmplus,
    SecplusV1,
    SecplusV2,
    SensibleLiving,
    SharpSpc775,
    ShenzhenWaleWlTh6r,
    Siemens5wy72xxCarRemote,
    SilverSpringMesh,
    Silvercrest,
    SimplisafeGen3,
    SixScTwoCarRemote,
    SmokeGs558,
    SolightTe44,
    SomfyIohc,
    SomfyRts,
    Springfield,
    SrsmithPoolSrs2cTx,
    SsSensor,
    Steelmate,
    TelldusFt0385r,
    Tfa141504v2,
    Tfa303221,
    Tfa303307,
    Tfa30390x,
    Tfa303151,
    Tfa303196,
    TfaDrop303233,
    TfaMarbella,
    TfaPoolThermometer,
    TfaTwinPlus303049,
    ThermoproTp11,
    ThermoproTp12,
)

// Kotlin transcription of rtl_433 device decoders (batch 03). GPL-3 reference; constants, bit offsets and CRC parameters transcribed as facts.
package com.rootdowndigital.ouispy.wifiadapter

private fun s16(x: Int): Int = x.toShort().toInt()

// unverified: fineoffset_wh55.c:46-97, struct fineoffset_wh55.c:111
internal object FineoffsetWh55 : Rtl433Decoder() {
    override val name = "Fine Offset / Ecowitt WH55 water leak sensor"
    override val mod = Mod.FSK_PCM
    override val short = 60
    override val long = 60
    override val reset = 2500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        var bitpos = bb.search(0, 0, intArrayOf(0xAA, 0x2D, 0xD4, 0x55), 32)
        bitpos += 24
        if (bitpos + 9 * 8 > bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(12)
        bb.extractBytes(0, bitpos, b, 12 * 8)
        if (Rtl433BitUtil.crc8(b, 9, 0x31, 0x00) != 0) return emptyList()
        val channel = (b[1] shr 4) + 1
        val deviceId = (b[2] shl 8) or b[3]
        val battery = b[4] * 0.2f
        val rawValue = (b[5] shl 8) or b[6]
        val sensitivity = (b[7] shr 7) and 1
        val alarm = (b[7] shr 6) and 1
        return listOf(
            Reading(
                "Fineoffset-WH55",
                String.format("%05X", deviceId),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to battery.toDouble(),
                    "raw_value" to rawValue,
                    "sensitivity" to sensitivity,
                    "alarm" to alarm,
                ),
            ),
        )
    }
}

// unverified: fineoffset.c:183-233, struct fineoffset.c:1208; disabled upstream (collides with WH2)
internal object FineoffsetWh5rb : Rtl433Decoder() {
    override val name = "Agimex Rosenborg 66796 (collides with Fine Offset Electronics WH5) Temperature/Humidity Sensor"
    override val mod = Mod.OOK_PWM
    override val short = 500
    override val long = 1500
    override val reset = 1200
    override val tolerance = 160

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 47 || bb.bb[0][0] != 0xFE) return emptyList()
        val b = IntArray(6)
        bb.extractBytes(0, 7, b, 40)
        if (b[4] != Rtl433BitUtil.crc8(b, 4, 0x31, 0)) return emptyList()
        val type = b[0] shr 4
        if (type != 4) return emptyList()
        val id = ((b[0] and 0x0F) shl 4) or ((b[1] and 0xF0) shr 4)
        var tempRaw = ((b[1] and 0x0F) shl 8) or b[2]
        if ((tempRaw and 0x800) != 0) {
            tempRaw = tempRaw and 0x7FF
            tempRaw = -tempRaw
        }
        val temperature = tempRaw * 0.1f
        val humidity = b[3]
        val fields = linkedMapOf<String, Any?>("temperature_C" to temperature.toDouble())
        if (humidity != 0xff) fields["humidity"] = humidity
        return listOf(Reading("Rosenborg-66796", id.toString(), fields))
    }
}

// unverified: fineoffset_wn34.c:42-126, struct fineoffset_wn34.c:138
internal object FineoffsetWn34 : Rtl433Decoder() {
    override val name = "Fine Offset Electronics WN34S/L/D, WN38 and Froggit DP150/D35 temperature sensor"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 2500

    override fun decode(bb: BitBuffer): List<Reading> {
        val bitOffset = bb.search(0, 0, intArrayOf(0xAA, 0x2D, 0xD4), 24) + 24
        if (bitOffset + 9 * 8 > bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(9)
        bb.extractBytes(0, bitOffset, b, 9 * 8)
        if (b[0] != 0x34 && b[0] != 0x38) return emptyList()
        val crc = Rtl433BitUtil.crc8(b, 7, 0x31, 0x00)
        val chk = Rtl433BitUtil.addBytes(b, 8) and 0xFF
        if (crc != b[7] || chk != b[8]) return emptyList()
        val id = (b[1] shl 16) or (b[2] shl 8) or b[3]
        val tempRaw = s16(((b[4] and 0x0F) shl 12) or (b[5] shl 4))
        val subType = (b[4] and 0xF0) shr 4
        val temperature: Float = if (subType == 4) {
            (tempRaw shr 4) * 0.1f
        } else {
            ((tempRaw shr 4) * 0.1f) - 40
        }
        val batteryMv = (b[6] and 0x7f) * 20
        val batteryBars = if (batteryMv > 1440) {
            5
        } else if (batteryMv > 1380) {
            4
        } else if (batteryMv > 1300) {
            3
        } else if (batteryMv > 1200) {
            2
        } else {
            1
        }
        val batteryOk = (batteryBars - 1) * 0.25f
        val model = if (b[0] == 0x38) {
            "Fineoffset-WN38"
        } else if (subType != 4) {
            "Fineoffset-WN34"
        } else {
            "Fineoffset-WN34D"
        }
        return listOf(
            Reading(
                model,
                String.format("%x", id),
                mapOf(
                    "battery_ok" to batteryOk.toDouble(),
                    "battery_mV" to batteryMv,
                    "temperature_C" to temperature.toDouble(),
                ),
            ),
        )
    }
}

// unverified: fineoffset_ws80.c:46-114, struct fineoffset_ws80.c:134
internal object FineoffsetWs80 : Rtl433Decoder() {
    override val name = "Fine Offset Electronics WS80 weather station"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 1500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 168 || bb.bitsPerRow[0] > 240) return emptyList()
        val bitOffset = bb.search(0, 0, intArrayOf(0xaa, 0x2d, 0xd4), 24) + 24
        if (bitOffset + 18 * 8 > bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(18)
        bb.extractBytes(0, bitOffset, b, 18 * 8)
        if (b[0] != 0x80) return emptyList()
        val crc = Rtl433BitUtil.crc8(b, 17, 0x31, 0x00)
        val chk = Rtl433BitUtil.addBytes(b, 17) and 0xFF
        if (crc != 0 || chk != b[17]) return emptyList()
        val id = (b[1] shl 16) or (b[2] shl 8) or b[3]
        val lightRaw = (b[4] shl 8) or b[5]
        val lightLux = (lightRaw * 10).toFloat()
        val batteryMv = b[6] * 20
        val batteryLvl = if (batteryMv < 1400) 0 else (batteryMv - 1400) / 16
        val flags = b[7]
        val tempRaw = ((b[7] and 0x03) shl 8) or b[8]
        val tempC = (tempRaw - 400) * 0.1f
        val humidity = b[9]
        val windAvg = ((b[7] and 0x10) shl 4) or b[10]
        val windDir = ((b[7] and 0x20) shl 3) or b[11]
        val windMax = ((b[7] and 0x40) shl 2) or b[12]
        val uvIndex = b[13]
        val unknown = (b[14] shl 8) or b[15]
        val fields = linkedMapOf<String, Any?>(
            "battery_ok" to (batteryLvl * 0.01f).toDouble(),
            "battery_mV" to batteryMv,
        )
        if (tempRaw != 0x3ff) fields["temperature_C"] = tempC.toDouble()
        if (humidity != 0xff) fields["humidity"] = humidity
        if (windDir != 0x1ff) fields["wind_dir_deg"] = windDir
        if (windAvg != 0x1ff) fields["wind_avg_m_s"] = (windAvg * 0.1f).toDouble()
        if (windMax != 0x1ff) fields["wind_max_m_s"] = (windMax * 0.1f).toDouble()
        if (uvIndex != 0xff) fields["uvi"] = (uvIndex * 0.1f).toDouble()
        if (lightRaw != 0xffff) fields["light_lux"] = lightLux.toDouble()
        fields["flags"] = flags
        if (unknown != 0x3fff) fields["unknown"] = unknown
        return listOf(Reading("Fineoffset-WS80", String.format("%06x", id), fields))
    }
}

// unverified: fineoffset_ws85.c:62-144, struct fineoffset_ws85.c:166
internal object FineoffsetWs85 : Rtl433Decoder() {
    override val name = "Fine Offset Electronics WS85 weather station"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 3000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 168 || bb.bitsPerRow[0] > 500) return emptyList()
        val bitOffset = bb.search(0, 0, intArrayOf(0xaa, 0xaa, 0x2d, 0xd4), 32) + 32
        if (bitOffset + 32 * 8 > bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(32)
        bb.extractBytes(0, bitOffset, b, 32 * 8)
        if (b[0] != 0x85) return emptyList()
        val crc = Rtl433BitUtil.crc8(b, 26, 0x31, 0x00)
        val chk = Rtl433BitUtil.addBytes(b, 27) and 0xFF
        if (crc != b[26] || chk != b[27]) return emptyList()
        val id = (b[1] shl 16) or (b[2] shl 8) or b[3]
        val batteryMv = b[4] * 20
        val flags = b[5]
        val windAvg = ((b[5] and 0x10) shl 4) or b[7]
        val windDir = ((b[5] and 0x20) shl 3) or b[8]
        val windMax = ((b[5] and 0x40) shl 2) or b[9]
        val rainStart = (b[12] and 0x10) shr 4
        val rainRaw = (b[15] shl 8) or b[16]
        val supercapV = b[17] and 0x3f
        val firmware = b[25]
        val batteryOk = if (batteryMv > 2400) 1 else 0
        var batteryLvl = if (batteryMv < 1400) 0 else (batteryMv - 1400) / 16
        if (batteryLvl > 100) batteryLvl = 100
        val extra = String.format(
            "%02x%02x---%02x%02x%02x%02x%02x%02x%02x---%02x",
            b[13], b[14], b[18], b[19], b[20], b[21], b[22], b[23], b[24], b[28],
        )
        val fields = linkedMapOf<String, Any?>(
            "battery_ok" to batteryOk,
            "battery_pct" to batteryLvl,
            "battery_mV" to batteryMv,
        )
        if (windDir != 0x1ff) fields["wind_dir_deg"] = windDir
        if (windAvg != 0x1ff) fields["wind_avg_m_s"] = (windAvg * 0.1f).toDouble()
        if (windMax != 0x1ff) fields["wind_max_m_s"] = (windMax * 0.1f).toDouble()
        fields["flags"] = flags
        fields["rain_mm"] = (rainRaw * 0.1f).toDouble()
        fields["rain_start"] = rainStart
        if (supercapV != 0xff) fields["supercap_V"] = (supercapV * 0.1f).toDouble()
        fields["firmware"] = firmware
        fields["data"] = extra
        return listOf(Reading("Fineoffset-WS85", String.format("%06x", id), fields))
    }
}

// unverified: fineoffset_ws90.c:67-153, struct fineoffset_ws90.c:179
internal object FineoffsetWs90 : Rtl433Decoder() {
    override val name = "Fine Offset Electronics WS90 weather station"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 3000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 168 || bb.bitsPerRow[0] > 500) return emptyList()
        val bitOffset = bb.search(0, 0, intArrayOf(0xaa, 0xaa, 0x2d, 0xd4), 32) + 32
        if (bitOffset + 32 * 8 > bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(32)
        bb.extractBytes(0, bitOffset, b, 32 * 8)
        if (b[0] != 0x90) return emptyList()
        val crc = Rtl433BitUtil.crc8(b, 31, 0x31, 0x00)
        val chk = Rtl433BitUtil.addBytes(b, 31) and 0xFF
        if (crc != 0 || chk != b[31]) return emptyList()
        val id = (b[1] shl 16) or (b[2] shl 8) or b[3]
        val lightRaw = (b[4] shl 8) or b[5]
        val lightLux = (lightRaw * 10).toFloat()
        val batteryMv = b[6] * 20
        var batteryLvl = if (batteryMv < 1400) 0 else (batteryMv - 1400) / 16
        val flags = b[7]
        val tempRaw = ((b[7] and 0x03) shl 8) or b[8]
        val tempC = (tempRaw - 400) * 0.1f
        val humidity = b[9]
        val windAvg = ((b[7] and 0x10) shl 4) or b[10]
        val windDir = ((b[7] and 0x20) shl 3) or b[11]
        val windMax = ((b[7] and 0x40) shl 2) or b[12]
        val uvIndex = b[13]
        val pressure = (b[14] shl 8) or b[15]
        val rainRaw = (b[19] shl 8) or b[20]
        val rainStart = (b[16] and 0x10) shr 4
        val supercapV = b[21] and 0x3f
        val firmware = b[29]
        if (batteryLvl > 100) batteryLvl = 100
        val extra = String.format(
            "%02x%02x%02x%02x%02x------%02x%02x%02x%02x%02x%02x%02x",
            b[14], b[15], b[16], b[17], b[18], b[22], b[23], b[24], b[25], b[26], b[27], b[28],
        )
        val fields = linkedMapOf<String, Any?>(
            "battery_ok" to (batteryLvl * 0.01f).toDouble(),
            "battery_mV" to batteryMv,
        )
        if (tempRaw != 0x3ff) fields["temperature_C"] = tempC.toDouble()
        if (humidity != 0xff) fields["humidity"] = humidity
        if (pressure != 0x3fff) fields["pressure_hPa"] = pressure.toDouble()
        if (windDir != 0x1ff) fields["wind_dir_deg"] = windDir
        if (windAvg != 0x1ff) fields["wind_avg_m_s"] = (windAvg * 0.1f).toDouble()
        if (windMax != 0x1ff) fields["wind_max_m_s"] = (windMax * 0.1f).toDouble()
        if (uvIndex != 0xff) fields["uvi"] = (uvIndex * 0.1f).toDouble()
        if (lightRaw != 0xffff) fields["light_lux"] = lightLux.toDouble()
        fields["flags"] = flags
        fields["rain_mm"] = (rainRaw * 0.1f).toDouble()
        fields["rain_start"] = rainStart
        if (supercapV != 0xff) fields["supercap_V"] = (supercapV * 0.1f).toDouble()
        fields["firmware"] = firmware
        fields["data"] = extra
        return listOf(Reading("Fineoffset-WS90", String.format("%06x", id), fields))
    }
}

// unverified: not ported - flex_decoder is a runtime-configured generic decoder (flex.c:154-369, struct flex.c:870 create_fn); mod OOK_PWM is a placeholder, upstream struct declares no modulation
internal object FlexDecoder : Rtl433Decoder() {
    override val name = "General purpose decoder"
    override val mod = Mod.OOK_PWM

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: florabest.c:47-94, struct florabest.c:104
internal object Florabest : Rtl433Decoder() {
    override val name = "Florabest FB-TH-1 BBQ Thermometer"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 6000
    override val reset = 11000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(3, 30)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] != 30) return emptyList()
        val b = bb.bb[row]
        if (b[0] != 0x49) return emptyList()
        if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0) return emptyList()
        var parity = 0
        for (i in 0 until 30) parity = parity xor bitrowGetBit(b, i)
        if (parity != 1) return emptyList()
        val id = (b[0] shl 8) or b[1]
        val tempRaw = (b[2] shl 5) or (b[3] shr 3)
        val tempF = tempRaw * 0.1f - 90.0f
        return listOf(
            Reading(
                "Florabest-FBTH1",
                String.format("%04x", id),
                mapOf("temperature_F" to tempF.toDouble()),
            ),
        )
    }
}

// unverified: flowis.c:49-124, struct flowis.c:138
internal object Flowis : Rtl433Decoder() {
    override val name = "Flowis flow meters"
    override val mod = Mod.FSK_PCM
    override val short = 10
    override val long = 10
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val startPos = bb.search(0, 0, intArrayOf(0xaa, 0xaa, 0xd3, 0x91, 0xd3, 0x91), 48)
        if (startPos == bb.bitsPerRow[0]) return emptyList()
        val lenBuf = IntArray(1)
        bb.extractBytes(0, startPos + 48, lenBuf, 8)
        val len = lenBuf[0]
        if (startPos + 48 + (len + 2) * 8 > bb.bitsPerRow[0]) return emptyList()
        val frame = IntArray(256 + 2 + 1)
        frame[0] = len
        val tmp = IntArray(256 + 2)
        bb.extractBytes(0, startPos + 56, tmp, (len + 2) * 8)
        for (i in 0 until len + 2) frame[1 + i] = tmp[i]
        val crc = Rtl433BitUtil.crc16(frame, len + 1, 0x8005, 0xffff)
        if (((frame[len + 1] shl 8) or frame[len + 2]) != crc) return emptyList()
        val b = frame
        val type = b[1]
        if (type != 1) return emptyList()
        val id = (b[5] shl 24) or (b[4] shl 16) or (b[3] shl 8) or b[2]
        val volume = (b[13] shl 16) or (b[12] shl 8) or b[11]
        val ftsYear = b[10] shr 2
        val ftsMth = (b[9] shr 6) or ((b[10] and 3) shl 2)
        val ftsDay = (b[9] and 0x3E) shr 1
        val ftsHour = (b[8] shr 4) or ((b[9] and 1) shl 4)
        val ftsMin = ((b[8] and 0xF) shl 2) or ((b[7] and 0xC0) shr 6)
        val ftsSec = b[7] and 0x3F
        val ftsStr = String.format("%4d-%02d-%02dT%02d:%02d:%02d", ftsYear + 2000, ftsMth, ftsDay, ftsHour, ftsMin, ftsSec)
        return listOf(
            Reading(
                "Flowis",
                id.toString(),
                mapOf(
                    "msg_type" to type,
                    "volume_m3" to volume / 1000.0,
                    "device_time" to ftsStr,
                    "alarm" to b[15],
                    "backflow" to b[14],
                ),
            ),
        )
    }
}

// unverified: fordremote.c:26-63, struct fordremote.c:72; disabled upstream (rolling code not decrypted)
internal object Fordremote : Rtl433Decoder() {
    override val name = "Ford Car Key"
    override val mod = Mod.OOK_DMC
    override val short = 250
    override val long = 500
    override val reset = 4000
    override val tolerance = 50

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (i in 3 until bb.numRows) {
            if (bb.bitsPerRow[i] < 78) continue
            if (bb.bitsPerRow[i - 3] != 1 || bb.bitsPerRow[i - 1] != 1 ||
                bb.bitsPerRow[i - 2] != 9 || bb.bb[i - 2][0] != 0
            ) continue
            val bytes = bb.bb[i]
            val deviceId = (bytes[0] shl 16) or (bytes[1] shl 8) or bytes[2]
            val code = bytes[7]
            out.add(Reading("Ford-CarRemote", deviceId.toString(), mapOf("code" to code)))
        }
        return out
    }
}

// unverified: not ported - fs20.c:104-324 parity-byte preamble scan (fs20_find_preamble, get_byte, fs20_frame_fits helpers in fs20.c) with FS20/FHT plausibility gates; disabled upstream (false decodes, issue #3611)
internal object Fs20 : Rtl433Decoder() {
    override val name = "FS20 / FHT"
    override val mod = Mod.OOK_PWM
    override val short = 400
    override val long = 600
    override val reset = 9000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

private fun reverse8(x: Int): Int {
    var v = x and 0xFF
    v = ((v and 0xF0) shr 4) or ((v and 0x0F) shl 4)
    v = ((v and 0xCC) shr 2) or ((v and 0x33) shl 2)
    v = ((v and 0xAA) shr 1) or ((v and 0x55) shl 1)
    return v and 0xFF
}

private fun reflect4(x0: Int): Int {
    var x = ((x0 and 0xCC) shr 2) or ((x0 and 0x33) shl 2)
    x = ((x and 0xAA) shr 1) or ((x and 0x55) shl 1)
    return x and 0xFF
}

private fun fbBitsReflect(bitrow: IntArray, start: Int, len: Int): Int {
    val end = start + len - 1
    var result = 0
    var mask = 1
    var s = start
    while (s <= end) {
        if (bitrowGetBit(bitrow, s) != 0) result = result or mask
        s++
        mask = mask shl 1
    }
    return result
}

private fun fbChecksum(bitrow: IntArray, len: Int): Int {
    val fullBytes = len / 8
    val bitsLeft = len % 8
    var xorByte = Rtl433BitUtil.xorBytes(bitrow, fullBytes) and 0xFF
    val mask = (0xff shl (8 - bitsLeft)) and 0xFF
    xorByte = xorByte xor (bitrow[fullBytes] and mask)
    val xorNibble = ((xorByte and 0xF0) shr 4) xor (xorByte and 0x0F)
    var result = 0
    if ((xorNibble and 0x8) != 0) result = result xor 0x8C
    if ((xorNibble and 0x4) != 0) result = result xor 0x32
    if ((xorNibble and 0x2) != 0) result = result xor 0xC8
    if ((xorNibble and 0x1) != 0) result = result xor 0x23
    result = result and 0xF
    result = result or (Rtl433BitUtil.parity8(xorByte) shl 4)
    return result
}

private fun geBit(bytes: IntArray, b: Int): Int = (bytes[b shr 3] shr (7 - (b and 7))) and 1

private fun geDecode(inbuf: BitBuffer, row: Int, start: Int, outbuf: BitBuffer) {
    val bits = inbuf.bb[row]
    val len = inbuf.bitsPerRow[row]
    var ipos = start
    while (ipos < len) {
        var bit1 = geBit(bits, ipos++)
        var bit2 = geBit(bits, ipos++)
        if (bit1 == 1 && bit2 == 0) {
            outbuf.addBit(0)
        } else if (bit1 == 1 && bit2 == 1) {
            bit1 = geBit(bits, ipos++)
            bit2 = geBit(bits, ipos++)
            if (bit1 == 0 && bit2 == 0) {
                outbuf.addBit(1)
            } else {
                break
            }
        } else {
            break
        }
    }
}

private fun geColorFrame(bb: BitBuffer, start: Int): Reading? {
    val packet = BitBuffer()
    geDecode(bb, 0, start, packet)
    if (packet.bitsPerRow[0] != 17) return null
    val b = packet.bb[0]
    if ((b[0] and 0xc0) != 0) return null
    if ((b[2] and 0x80) != 0) return null
    val deviceId = b[0]
    val command = b[1]
    val cmd = when (command) {
        0x5a -> "change"
        0xaa -> "on"
        0x55 -> "off"
        else -> String.format("0x%x", command)
    }
    return Reading(
        "GE-ColorEffects",
        String.format("0x%x", deviceId),
        mapOf("command" to cmd),
    )
}

private fun geFindPreamble(bb: BitBuffer, from: Int): Int? {
    val bits = bb.bitsPerRow[0]
    val p1 = intArrayOf(0xcc, 0xff, 0x00)
    val p2 = intArrayOf(0xcc, 0xfe, 0x00)
    val candidates = listOf(Pair(p1, 24), Pair(p1, 23), Pair(p2, 23), Pair(p2, 22))
    for ((pattern, n) in candidates) {
        val found = bb.search(0, from, pattern, n) + n
        if (found + 33 <= bits) return found
    }
    return null
}

// unverified: fsl_scoreboard.c:59-132, struct fsl_scoreboard.c:141
internal object FslScoreboard : Rtl433Decoder() {
    override val name = "FSL Cricket Scoreboard Controller"
    override val mod = Mod.FSK_PCM
    override val short = 528
    override val long = 528
    override val reset = 3000

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0xaa, 0xaa, 0xaa, 0xaa)
        val sync = intArrayOf(0xe0)
        val b = IntArray(4)
        for (row in 0 until bb.numRows) {
            if (bb.bitsPerRow[row] < 700) continue
            val preamblePos = bb.search(row, 0, preamble, 32)
            if (preamblePos + 38 + 72 >= bb.bitsPerRow[row]) continue
            var blockPos = preamblePos + 38
            while (blockPos + 72 < bb.bitsPerRow[row]) {
                val cur = blockPos
                blockPos += 72
                if (bb.search(row, cur, sync, 3) != cur) continue
                val dataStart = cur + 3
                val decoded = BitBuffer()
                bb.manchesterDecode(row, dataStart, decoded, 32)
                if (decoded.bitsPerRow[0] < 32) continue
                decoded.extractBytes(0, 0, b, 32)
                val pos3 = b[0] shr 4
                val fieldId = b[0] and 0xf
                val pos2 = b[1] shr 4
                val hundreds = b[1] and 0xf
                val pos1 = b[2] shr 4
                val tens = b[2] and 0xf
                val pos0 = b[3] shr 4
                val units = b[3] and 0xf
                if (pos3 != 0x3 || pos2 != 0x2 || pos1 != 0x1 || pos0 != 0x0) continue
                var value = 0
                if (hundreds != 0xf) value += hundreds * 100
                if (tens != 0xf) value += tens * 10
                if (units != 0xf) value += units
                return listOf(Reading("FSL-Scoreboard", fieldId.toString(), mapOf("value" to value)))
            }
        }
        return emptyList()
    }
}

// unverified: ft004b.c:32-66, struct ft004b.c:74
internal object Ft004b : Rtl433Decoder() {
    override val name = "FT-004-B Temperature Sensor"
    override val mod = Mod.OOK_PPM
    override val short = 1956
    override val long = 3900
    override val gap = 4000
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 137 && bb.bitsPerRow[0] != 138) return emptyList()
        val msg = bb.bb[0]
        for (i in 0 until (46 + 7) / 8) {
            val a = bitrowGetByte(msg, i * 8)
            val b = bitrowGetByte(msg, i * 8 + 46)
            val c = bitrowGetByte(msg, i * 8 + 46 * 2)
            msg[i] = reverse8((a and b) or (b and c) or (a and c))
        }
        if (msg[0] != 0xf4) return emptyList()
        val tempRaw = ((msg[4] and 0x7) shl 8) or msg[3]
        val temperature = tempRaw * 0.05f - 40.0f
        return listOf(Reading("FT-004B", null, mapOf("temperature_C" to temperature.toDouble())))
    }
}

// unverified: funkbus.c:101-158, struct funkbus.c:173
internal object FunkbusRemote : Rtl433Decoder() {
    override val name = "Funkbus / Instafunk (Berker, Gira, Jung)"
    override val mod = Mod.OOK_DMC
    override val short = 500
    override val long = 1000
    override val reset = 2000
    override val gap = 1500
    override val sync = 4000
    override val tolerance = 300

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            if (bb.bitsPerRow[row] < 48) return out
            val b = bb.bb[row]
            val typ = fbBitsReflect(b, 0, 4)
            val subtyp = fbBitsReflect(b, 4, 4)
            if (typ != 0x4 || subtyp != 0x3) return out
            val sn = fbBitsReflect(b, 8, 20)
            val bat = fbBitsReflect(b, 30, 1)
            val command = fbBitsReflect(b, 33, 3)
            val group = fbBitsReflect(b, 36, 2)
            val action = fbBitsReflect(b, 39, 2)
            val repeat = fbBitsReflect(b, 41, 1)
            val longpress = fbBitsReflect(b, 42, 1)
            val parity = fbBitsReflect(b, 43, 1)
            val check = fbBitsReflect(b, 44, 4)
            val checksum = fbChecksum(b, 43)
            if (check != reflect4(checksum and 0xF) || parity != (checksum shr 4)) return out
            out.add(
                Reading(
                    "Funkbus-Remote",
                    sn.toString(),
                    mapOf(
                        "battery_ok" to (if (bat != 0) 0 else 1),
                        "command" to command,
                        "group" to group,
                        "action" to action,
                        "repeat" to repeat,
                        "longpress" to longpress,
                    ),
                ),
            )
        }
        return out
    }
}

// unverified: gasmate_ba1008.c:47-93, struct gasmate_ba1008.c:103
internal object GasmateBa1008 : Rtl433Decoder() {
    override val name = "Gasmate BA1008 meat thermometer"
    override val mod = Mod.OOK_PPM
    override val short = 536
    override val long = 1668
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] != 32) return emptyList()
        val b = bb.bb[0]
        if ((b[0] and 0xf8) != 0xf0) return emptyList()
        if ((Rtl433BitUtil.addNibbles(b, 4) and 0x0f) != 0x0c) return emptyList()
        val sign = (b[0] and 0x04) shr 2
        val huns = b[0] and 0x03
        val tens = (b[1] and 0xf0) shr 4
        val ones = b[1] and 0x0f
        val tempRaw = huns * 100 + tens * 10 + ones
        val tempC = if (sign != 0) -tempRaw else tempRaw
        val unknown1 = (b[2] shl 4) or (b[3] shr 4)
        return listOf(
            Reading(
                "Gasmate-BA1008",
                null,
                mapOf("temperature_C" to tempC, "unknown_1" to unknown1),
            ),
        )
    }
}

// unverified: ge_coloreffects.c:126-158 (callback), ge_coloreffects.c:32-60 (ge_decode), ge_coloreffects.c:61-96 (frame), struct ge_coloreffects.c:167
internal object GeColoreffects : Rtl433Decoder() {
    override val name = "GE Color Effects"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 450

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            val found = geFindPreamble(bb, bitpos) ?: break
            geColorFrame(bb, found)?.let { out.add(it) }
            bitpos = found + 1
        }
        return out
    }
}

// unverified: geevon.c:54-109, struct geevon.c:122
internal object GeevonTx16 : Rtl433Decoder() {
    override val name = "Geevon TX16-3 outdoor sensor"
    override val mod = Mod.OOK_PWM
    override val short = 250
    override val long = 500
    override val sync = 750
    override val gap = 625
    override val reset = 1700

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val r = bb.findRepeatedPrefix(if (bb.numRows > 5) 5 else 3, 72)
        if (r < 0) return emptyList()
        val b = bb.bb[r]
        if (bb.bitsPerRow[r] != 73) return emptyList()
        if (b[5] != 0xAA || b[6] != 0x55 || b[7] != 0xAA) return emptyList()
        val chk = Rtl433BitUtil.crc8(b, 9, 0x31, 0x7b)
        if (chk != 0) return emptyList()
        val batteryLow = b[1] shr 7
        val channel = ((b[1] and 0x30) shr 4) + 1
        val tempRaw = (b[2] shl 4) or (b[3] shr 4)
        val tempC = (tempRaw - 500) * 0.1f
        val humidity = b[4]
        return listOf(
            Reading(
                "Geevon-TX163",
                b[0].toString(),
                mapOf(
                    "battery_ok" to (if (batteryLow == 0) 1 else 0),
                    "channel" to channel,
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                ),
            ),
        )
    }
}

// unverified: geevon_tx19.c:59-114, struct geevon_tx19.c:127
internal object GeevonTx19 : Rtl433Decoder() {
    override val name = "Geevon TX19-1 outdoor sensor"
    override val mod = Mod.OOK_PWM
    override val short = 250
    override val long = 500
    override val sync = 750
    override val gap = 625
    override val reset = 1700

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val r = bb.findRepeatedPrefix(if (bb.numRows > 5) 5 else 3, 72)
        if (r < 0) return emptyList()
        val b = bb.bb[r]
        if (bb.bitsPerRow[r] != 73) return emptyList()
        if (b[5] != 0xAA || b[6] != 0x55 || b[7] != 0xAA) return emptyList()
        val chk = Rtl433BitUtil.lfsrDigest8Reverse(b, 8, 0x98, 0x25)
        if (chk != b[8]) return emptyList()
        val batteryLow = b[1] shr 7
        val channel = ((b[1] and 0x30) shr 4) + 1
        val tempRaw = (b[2] shl 4) or (b[3] shr 4)
        val tempC = (tempRaw - 500) * 0.1f
        val humidity = b[4]
        return listOf(
            Reading(
                "Geevon-TX191",
                b[0].toString(),
                mapOf(
                    "battery_ok" to (if (batteryLow == 0) 1 else 0),
                    "channel" to channel,
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                ),
            ),
        )
    }
}

// unverified: generic_motion.c:33-59, struct generic_motion.c:67
internal object GenericMotion : Rtl433Decoder() {
    override val name = "Generic wireless motion sensor"
    override val mod = Mod.OOK_PWM
    override val short = 888
    override val long = 1558
    override val sync = 2454
    override val gap = 1200
    override val reset = 4086

    override fun decode(bb: BitBuffer): List<Reading> {
        for (i in 0 until bb.numRows) {
            val b = bb.bb[i]
            if (bb.bitsPerRow[i] != 20 ||
                (b[1] == 0 && b[2] == 0) ||
                (b[1] == 0xff && b[2] == 0xf0) ||
                bb.countRepeats(i, 0) < 3
            ) continue
            val code = (b[0] shl 12) or (b[1] shl 4) or (b[2] shr 4)
            return listOf(Reading("Generic-Motion", null, mapOf("code" to String.format("%05x", code))))
        }
        return emptyList()
    }
}

// unverified: generic_remote.c:22-72, struct generic_remote.c:82; duplicates GenericRemoteDecoder in Rtl433Registry.kt
internal object GenericRemoteSc226x : Rtl433Decoder() {
    override val name = "Generic Remote SC226x EV1527"
    override val mod = Mod.OOK_PWM
    override val short = 464
    override val long = 1404
    override val reset = 1800
    override val sync = 0
    override val tolerance = 200

    override fun decode(bb: BitBuffer): List<Reading> {
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
        for (i in 22 downTo 0 step 2) {
            sb.append(
                when ((full shr i) and 0x03) {
                    0x00 -> '0'
                    0x01 -> 'Z'
                    0x02 -> 'X'
                    else -> '1'
                },
            )
        }
        return listOf(
            Reading(
                "Generic-Remote",
                id16.toString(),
                mapOf("cmd" to cmd8, "tristate" to sb.toString()),
            ),
        )
    }
}

// unverified: generic_temperature_sensor.c:25-61, struct generic_temperature_sensor.c:71
internal object GenericTemperatureSensor : Rtl433Decoder() {
    override val name = "Generic temperature sensor 1"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 4800
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        for (i in 1 until 10) {
            if (bb.bitsPerRow[i] != 24) return emptyList()
        }
        val b = bb.bb[1]
        if ((b[0] == 0 && b[1] == 0 && b[2] == 0) || (b[0] == 0xff && b[1] == 0xff && b[2] == 0xff)) return emptyList()
        val device = b[0]
        val battery = (b[1] and 0xC0) shr 6
        val tempRaw = s16(((b[1] and 0x3f) shl 10) or (b[2] shl 2))
        val tempF = (tempRaw shr 4) * 0.1f
        return listOf(
            Reading(
                "Generic-Temperature",
                device.toString(),
                mapOf("battery_ok" to battery, "temperature_C" to tempF.toDouble()),
            ),
        )
    }
}

// unverified: gm_car_remote.c:49-115, struct gm_car_remote.c:128
internal object GmCarRemote : Rtl433Decoder() {
    override val name = "GM ABO1502T Car Remote (-f 314.9M)"
    override val mod = Mod.OOK_PPM
    override val short = 300
    override val long = 500
    override val reset = 20000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 113 || bb.numRows > 1) return emptyList()
        val offset = bb.bitsPerRow[0] - 113
        val bytes = IntArray(14)
        bb.extractBytes(0, offset, bytes, 112)
        if (bytes[0] != 0xff) return emptyList()
        val buttonChecksum = Rtl433BitUtil.addNibbles(bytes.copyOfRange(2, 3), 1)
        if (buttonChecksum == 0 || (buttonChecksum and 0xf) != 0) return emptyList()
        val fullChecksum = Rtl433BitUtil.addBytes(bytes.copyOfRange(1, 14), 13)
        if (fullChecksum == 0 || (fullChecksum and 0xff) != 0) return emptyList()
        val button = bytes[2] and 0x7
        val id = (bytes[3] shl 24) or (bytes[4] shl 16) or (bytes[5] shl 8) or bytes[6]
        val sequence = (bytes[7] shl 16) or (bytes[8] shl 8) or bytes[9]
        val encrypted = (bytes[10] shl 16) or (bytes[11] shl 8) or bytes[12]
        val idStr = String.format("%02X%08X", bytes[1], id)
        val encryptedStr = String.format("%06X", encrypted)
        val buttonStr = when (button) {
            0x1 -> "Unlock"
            0x2 -> "Lock"
            0x3 -> "Trunk"
            0x4 -> "Panic"
            else -> "?"
        }
        return listOf(
            Reading(
                "GM-ABO1502T",
                idStr,
                mapOf(
                    "encrypted" to encryptedStr,
                    "button_code" to button,
                    "button_str" to buttonStr,
                    "sequence" to sequence,
                ),
            ),
        )
    }
}

// unverified: grill_thermometer.c:37-87, struct grill_thermometer.c:97
internal object GrillThermometer : Rtl433Decoder() {
    override val name = "RF-T0912 Grill Thermometer"
    override val mod = Mod.OOK_PWM
    override val short = 252
    override val long = 736
    override val gap = 5000
    override val reset = 8068
    override val sync = 980

    override fun decode(bb: BitBuffer): List<Reading> {
        var tempF = 0
        var repeats = 0
        bb.invert()
        for (row in 0 until bb.numRows) {
            val rowData = bb.bb[row]
            val checksum = (rowData[0] + rowData[1]) and 0xFF
            if (bb.bitsPerRow[row] != 24 || checksum != rowData[2] || checksum == 0) continue
            val currentValue = s16((rowData[0] shl 8) or rowData[1])
            if (tempF != currentValue) {
                tempF = currentValue
                repeats = 0
            } else {
                repeats++
            }
        }
        if (repeats < 1) return emptyList()
        val overload = if (tempF == -1029) 1 else 0
        val fields = linkedMapOf<String, Any?>()
        if (overload == 0) fields["temperature_F"] = tempF.toDouble()
        fields["overload"] = overload
        return listOf(Reading("RF-T0912", null, fields))
    }
}

private fun chkRollbyte(message: IntArray, bytes: Int, gen: Int): Int {
    var sum = 0
    for (k in 0 until bytes) {
        val data = message[k]
        var key = gen
        for (i in 7 downTo 0) {
            if (((data shr i) and 1) != 0) sum = sum xor (key and 0xff)
            key = key shr 1
        }
    }
    return sum and 0xFF
}

// unverified: gt_tmbbq05.c:73-128, struct gt_tmbbq05.c:138
internal object GtTmbbq05 : Rtl433Decoder() {
    override val name = "Globaltronics QUIGG GT-TMBBQ-05"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 4200
    override val reset = 9100

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(5, 33)
        if (r < 0 || bb.bitsPerRow[r] != 33) return emptyList()
        val b = IntArray(4)
        bb.extractBytes(r, 1, b, 32)
        if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0) return emptyList()
        val p = b.copyOf()
        p[3] = p[3] and 0xF0
        if (Rtl433BitUtil.parityBytes(p, 4) != 0) return emptyList()
        val sum = Rtl433BitUtil.addNibbles(b, 3) + (b[3] shr 4)
        if ((sum and 0xf) != (b[3] and 0xf)) return emptyList()
        val tempf = (((b[3] and 0xc0) shl 2) or b[1]) - 90
        val deviceId = (b[0] shl 8) or b[2]
        return listOf(
            Reading(
                "GT-TMBBQ05",
                deviceId.toString(),
                mapOf("temperature_F" to tempf.toFloat().toDouble()),
            ),
        )
    }
}

private fun gtWt02Row(bb: BitBuffer, row: Int): Reading? {
    var b = bb.bb[row]
    if (bb.bitsPerRow[row] == 39) {
        val shifted = IntArray(5)
        bb.extractBytes(row, 2, shifted, 37)
        b = shifted
    } else if (bb.bitsPerRow[row] != 37) {
        return null
    }
    if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0 && b[4] == 0) return null
    val sumNibbles = (b[0] shr 4) + (b[0] and 0xF) +
        (b[1] shr 4) + (b[1] and 0xF) +
        (b[2] shr 4) + (b[2] and 0xF) +
        (b[3] shr 4) + (b[3] and 0xe)
    val checksum = ((b[3] and 1) shl 5) + (b[4] shr 3)
    if ((sumNibbles and 0x3F) != checksum) return null
    val sensorId = b[0]
    val batteryLow = (b[1] shr 7) and 1
    val buttonPressed = (b[1] shr 6) and 1
    val channel = (b[1] shr 4) and 3
    val tempRaw = s16(((b[1] and 0x0f) shl 12) or (b[2] shl 4))
    val tempC = (tempRaw shr 4) * 0.1f
    if (channel > 2) return null
    if (tempC < -20.0f || tempC > 60.0f) return null
    val humidityRaw = b[3] shr 1
    if (humidityRaw != 10 && humidityRaw != 110 && (humidityRaw < 20 || humidityRaw > 90)) return null
    val humidity = when (humidityRaw) {
        10 -> 0
        110 -> 100
        else -> humidityRaw
    }
    return Reading(
        "GT-WT02",
        sensorId.toString(),
        mapOf(
            "channel" to channel + 1,
            "battery_ok" to (if (batteryLow != 0) 0 else 1),
            "temperature_C" to tempC.toDouble(),
            "humidity" to humidity.toDouble(),
            "button" to buttonPressed,
        ),
    )
}

// unverified: gt_wt_02.c:126-137 (decode), gt_wt_02.c:20-125 (process_row), struct gt_wt_02.c:151
internal object GtWt02 : Rtl433Decoder() {
    override val name = "Globaltronics GT-WT-02 Sensor"
    override val mod = Mod.OOK_PPM
    override val short = 2500
    override val long = 5000
    override val gap = 8000
    override val reset = 12000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows < 2) return emptyList()
        for (row in 0 until bb.numRows) {
            val r = gtWt02Row(bb, row)
            if (r != null) return listOf(r)
        }
        return emptyList()
    }
}

// unverified: gt_wt_03.c:89-160, struct gt_wt_03.c:174
internal object GtWt03 : Rtl433Decoder() {
    override val name = "Globaltronics GT-WT-03 Sensor"
    override val mod = Mod.OOK_PWM
    override val short = 256
    override val long = 625
    override val sync = 855
    override val gap = 1000
    override val reset = 61000

    override fun decode(bb: BitBuffer): List<Reading> {
        var row = 0
        if (bb.numRows > 1) row = bb.findRepeatedRow(bb.numRows / 2 + 1, 41)
        if (row < 0) return emptyList()
        if (41 != bb.bitsPerRow[row]) return emptyList()
        bb.invert()
        val b = bb.bb[row]
        if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0 && b[4] == 0) return emptyList()
        val chk = chkRollbyte(b, 4, 0x3100) xor b[4] xor 0x2d
        if (chk != 0) return emptyList()
        val sensorId = b[0]
        val batteryLow = (b[2] shr 7) and 1
        val buttonPressed = (b[2] shr 6) and 1
        val channel = (b[2] shr 4) and 3
        val tempRaw = s16(((b[2] and 0x0f) shl 12) or (b[3] shl 4))
        val tempC = (tempRaw shr 4) * 0.1f
        if (tempC <= -50.2f || tempC >= 70.2f) return emptyList()
        val humidityRaw = b[1]
        if (humidityRaw != 10 && humidityRaw != 110 && (humidityRaw < 20 || humidityRaw > 95)) return emptyList()
        val humidity = when (humidityRaw) {
            10 -> 0
            110 -> 100
            else -> humidityRaw
        }
        return listOf(
            Reading(
                "GT-WT03",
                sensorId.toString(),
                mapOf(
                    "channel" to channel + 1,
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity.toDouble(),
                    "button" to buttonPressed,
                ),
            ),
        )
    }
}

// unverified: hanwell_ml4000.c:48-89, struct hanwell_ml4000.c:100; disabled upstream (engineering-unit conversion unknown), raw values only
internal object HanwellMl4000 : Rtl433Decoder() {
    override val name = "Hanwell ML/RL4000-series Radiologger temperature/humidity sensor"
    override val mod = Mod.FSK_PWM
    override val short = 1000
    override val long = 2000
    override val sync = 3000
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        if (bb.numRows < 1) return emptyList()
        val row = bb.numRows - 1
        if (bb.bitsPerRow[row] != 40) return emptyList()
        val b = IntArray(5)
        bb.extractBytes(row, 0, b, 40)
        for (i in 0 until 5) b[i] = reverse8(b[i])
        val checksum = (b[0] + b[1] + b[2] + b[3]) and 0xff
        if (checksum != b[4]) return emptyList()
        val id = b[0]
        val humidityRaw = (b[1] shl 4) or (b[3] shr 4)
        val temperatureRaw = (b[2] shl 4) or (b[3] and 0x0f)
        return listOf(
            Reading(
                "Hanwell-ML4000",
                id.toString(),
                mapOf("temperature_raw" to temperatureRaw, "humidity_raw" to humidityRaw),
            ),
        )
    }
}

private fun hcs200Frame(bb: BitBuffer): List<Reading> {
    if (bb.bitsPerRow[0] != 12 || bb.bitsPerRow[1] != 66) return emptyList()
    var b = bb.bb[0]
    if (b[0] != 0xff || (b[1] and 0xf0) != 0xf0) return emptyList()
    b = bb.bb[1]
    if (b[1] == 0xff && b[2] == 0xff && b[3] == 0xff && b[4] == 0xff && b[5] == 0xff && b[6] == 0xff && b[7] == 0xff) {
        return emptyList()
    }
    val encrypted = (reverse8(b[3]) shl 24) or (reverse8(b[2]) shl 16) or (reverse8(b[1]) shl 8) or reverse8(b[0])
    val serial = (reverse8(b[7] and 0xf0) shl 24) or (reverse8(b[6]) shl 16) or (reverse8(b[5]) shl 8) or reverse8(b[4])
    val btn = b[7] and 0x0f
    val btnNum = (btn and 0x08) or ((btn and 0x01) shl 2) or (btn and 0x02) or ((btn and 0x04) shr 2)
    val learn = if ((b[7] and 0x0f) == 0x0f) 1 else 0
    val batteryLow = (b[8] and 0x80) == 0x80
    val repeat = if ((b[8] and 0x40) == 0x40) 1 else 0
    val encryptedStr = String.format("%08X", encrypted)
    val serialStr = String.format("%07X", serial)
    return listOf(
        Reading(
            "Microchip-HCS200",
            serialStr,
            mapOf(
                "battery_ok" to (if (batteryLow) 0 else 1),
                "button" to btnNum,
                "learn" to learn,
                "repeat" to repeat,
                "encrypted" to encryptedStr,
            ),
        ),
    )
}

// unverified: hcs200.c:36-87, struct hcs200.c:100
internal object Hcs200 : Rtl433Decoder() {
    override val name = "Microchip HCS200/HCS300 KeeLoq Hopping Encoder based remotes"
    override val mod = Mod.OOK_PWM
    override val short = 370
    override val long = 772
    override val gap = 1500
    override val reset = 9000
    override val tolerance = 152

    override fun decode(bb: BitBuffer): List<Reading> = hcs200Frame(bb)
}

// unverified: hcs200.c:36-87 (shared callback), struct hcs200.c:112
internal object Hcs200Fsk : Rtl433Decoder() {
    override val name = "Microchip HCS200/HCS300 KeeLoq Hopping Encoder based remotes (FSK)"
    override val mod = Mod.FSK_PWM
    override val short = 370
    override val long = 772
    override val gap = 1500
    override val reset = 9000
    override val tolerance = 152

    override fun decode(bb: BitBuffer): List<Reading> = hcs200Frame(bb)
}

private fun hcs361Frame(bb: BitBuffer): List<Reading> {
    if (bb.numRows < 2 || bb.bitsPerRow[1] != 67) return emptyList()
    if (bb.bitsPerRow[0] == 6 && bb.bb[0][0] != 0xfc) return emptyList()
    if (bb.bitsPerRow[0] == 7 && bb.bb[0][0] != 0xfe) return emptyList()
    if (bb.bitsPerRow[0] == 12) {
        val preamble = (bb.bb[0][0] shl 8) or bb.bb[0][1]
        if (preamble != 0xaaa0 && preamble != 0xfff0) return emptyList()
    }
    val b = bb.bb[1]
    if (b[0] == 0xff && b[1] == 0xff && b[2] == 0xff && b[3] == 0xff && b[4] == 0xff && b[5] == 0xff && b[6] == 0xff && b[7] == 0xff) {
        return emptyList()
    }
    var crc = 0
    var crcBatLow = 0
    val actualCrc = (b[8] shr 5) and 0x3
    for (i in 0 until 65) {
        val bit = b[i / 8] shr (7 - (i % 8))
        val crcBit = ((crc shr 1) xor bit) and 0x1
        if (i == 64) {
            val crcBitBatLow = ((crc shr 1) xor bit.inv()) and 0x1
            crcBatLow = crcBitBatLow or (((crcBitBatLow xor crc) shl 1) and 0x2)
        }
        crc = crcBit or (((crcBit xor crc) shl 1) and 0x2)
    }
    if (actualCrc != crc && actualCrc != crcBatLow) return emptyList()
    val encrypted = (reverse8(b[3]) shl 24) or (reverse8(b[2]) shl 16) or (reverse8(b[1]) shl 8) or reverse8(b[0])
    val serial = (reverse8(b[7] and 0xf0) shl 24) or (reverse8(b[6]) shl 16) or (reverse8(b[5]) shl 8) or reverse8(b[4])
    val btn = b[7] and 0x0f
    val btnNum = (btn and 0x08) or ((btn and 0x01) shl 2) or (btn and 0x02) or ((btn and 0x04) shr 2)
    val batteryOk = if ((b[8] and 0x80) == 0x80) 1 else 0
    if (serial == 0) return emptyList()
    val encryptedStr = String.format("%08X", encrypted)
    val serialStr = String.format("%08X", serial)
    return listOf(
        Reading(
            "Microchip-HCS361",
            serialStr,
            mapOf(
                "battery_ok" to batteryOk,
                "button" to btnNum,
                "encrypted" to encryptedStr,
            ),
        ),
    )
}

// unverified: hcs361.c:65-156, struct hcs361.c:174
internal object Hcs361TxwakBsel0 : Rtl433Decoder() {
    override val name = "Microchip HCS361 KeeLoq Hopping Encoder based remotes (-f 315.1M) (Sync, 833 bit/s)"
    override val mod = Mod.OOK_PWM
    override val short = 400
    override val long = 800
    override val gap = 1200
    override val reset = 7200
    override val sync = 4000
    override val tolerance = 140

    override fun decode(bb: BitBuffer): List<Reading> = hcs361Frame(bb)
}

// unverified: not ported - geo_minim.c:264-344 frame parser with display and CT-sensor sub-decoders (geo_minim.c:~100-262) and mktime clock normalization; not transcribed this batch
internal object GeoMinim : Rtl433Decoder() {
    override val name = "GEO minim+ energy monitor"
    override val mod = Mod.FSK_PCM
    override val short = 24
    override val long = 24
    override val reset = 3000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: govee.c:138-259, struct govee.c:273
internal object Govee : Rtl433Decoder() {
    override val name = "Govee Water Leak Detector H5054, Door Contact Sensor B5023"
    override val mod = Mod.OOK_PWM
    override val short = 440
    override val long = 940
    override val gap = 900
    override val reset = 9000

    override fun decode(bb: BitBuffer): List<Reading> {
        var model = "Govee-Water"
        if (bb.numRows < 3) return emptyList()
        val r = bb.findRepeatedRow(3, 6 * 8)
        if (r < 0) return emptyList()
        if (bb.bitsPerRow[r] > 6 * 8) return emptyList()
        val b = bb.bb[r]
        val codeStr = String.format("%02x%02x%02x%02x%02x%02x", b[0], b[1], b[2], b[3], b[4], b[5])
        bb.invert()
        if ((b[0] or b[1] or b[2] or b[3] or b[4]) == 0) return emptyList()
        val id = (b[0] shl 8) or b[1]
        if (id == 0xffff) return emptyList()
        if (b[5] == 0) return emptyList()
        val eventType = b[2] and 0x0f
        var event = (b[2] shl 8) or b[3]
        if (event == 0xffff) return emptyList()
        val parity = (b[5] shr 1) and 0x0F
        var chk = Rtl433BitUtil.xorBytes(b, 5)
        chk = (chk shr 4) xor (chk and 0xf)
        if (chk != parity) return emptyList()
        val battery = if (eventType == 0xc) b[3] else 0
        val batteryLevel = battery * 0.01f
        val batteryMv = 1800 + 12 * battery
        event = event and 0x0FFF
        var wet = -1
        val eventStr: String
        if (event == 0xafa) {
            eventStr = "Button Press"
            wet = 0
        } else if (event == 0xbfb) {
            eventStr = "Water Leak"
            wet = 1
        } else if (eventType == 0xc) {
            eventStr = "Battery Report"
        } else if (event == 0xdfd) {
            eventStr = "Heartbeat"
        } else if (event == 0xe7f) {
            model = "Govee-Contact"
            eventStr = "Open"
        } else {
            eventStr = "Unknown"
        }
        val fields = linkedMapOf<String, Any?>()
        if (battery != 0) {
            fields["battery_ok"] = batteryLevel.toDouble()
            fields["battery_mV"] = batteryMv
        }
        if (wet >= 0) fields["detect_wet"] = wet
        fields["event"] = eventStr
        fields["code"] = codeStr
        return listOf(Reading(model, id.toString(), fields))
    }
}

// unverified: govee.c:332-421, struct govee.c:423; GOVEE_H5054_BITLEN 48 at govee.c:136
internal object GoveeH5054 : Rtl433Decoder() {
    override val name = "Govee Water Leak Detector H5054"
    override val mod = Mod.OOK_PWM
    override val short = 440
    override val long = 940
    override val gap = 900
    override val reset = 9000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows < 3) return emptyList()
        val r = bb.findRepeatedRow(3, 48)
        if (r < 0) return emptyList()
        if (bb.bitsPerRow[r] > 48) return emptyList()
        bb.invert()
        val b = bb.bb[r]
        val codeStr = String.format("%02x%02x%02x%02x%02x%02x", b[0], b[1], b[2], b[3], b[4], b[5])
        val chk = Rtl433BitUtil.crc16(b, 6, 0x1021, 0x1d0f)
        if (chk != 0) return emptyList()
        val id = (b[0] shl 8) or b[1]
        val event = b[2] and 0xf
        val eventData = b[3]
        var wet = -1
        var leakNum = -1
        var battery = -1
        val eventStr: String
        when (event) {
            0x0 -> {
                eventStr = "Button Press"
                wet = 0
            }
            0x1 -> {
                eventStr = "Battery Report"
                battery = eventData
            }
            0x2 -> {
                eventStr = "Water Leak"
                wet = 1
                leakNum = eventData
            }
            else -> eventStr = "Unknown"
        }
        val batteryLevel = battery * 0.01f
        val batteryMv = 1800 + 12 * battery
        val fields = linkedMapOf<String, Any?>()
        if (battery >= 0) {
            fields["battery_ok"] = batteryLevel.toDouble()
            fields["battery_mV"] = batteryMv
        }
        fields["event"] = eventStr
        if (wet >= 0) fields["detect_wet"] = wet
        if (leakNum >= 0) fields["leak_num"] = leakNum
        fields["code"] = codeStr
        return listOf(Reading("Govee-Water", id.toString(), fields))
    }
}

// unverified: not ported - govee_h5059.c:152-293 sync/skew search, per-family XOR key table and decrypt pass; priority-ordered frame claims against govee_h5310/govee_h5112 not modeled
internal object GoveeH5059 : Rtl433Decoder() {
    override val name = "Govee Water Leak Detector H5059"
    override val mod = Mod.FSK_PCM
    override val short = 100
    override val long = 100
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: not ported - govee_h5112.c:246-421 sync/skew search, per-family XOR key table and decrypt pass; priority-ordered frame claims not modeled
internal object GoveeH5112 : Rtl433Decoder() {
    override val name = "Govee H5112 Dual-Probe Thermometer"
    override val mod = Mod.FSK_PCM
    override val short = 100
    override val long = 100
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: not ported - govee_h5310.c:238-382 sync/skew search, per-family XOR key table and decrypt pass; priority-ordered frame claims not modeled
internal object GoveeH5310 : Rtl433Decoder() {
    override val name = "Govee Pool/Spa Thermometer H5310"
    override val mod = Mod.FSK_PCM
    override val short = 100
    override val long = 100
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: not ported - gridstream.c:119-261 UART 8N1 extraction, gridstream_checksum with known_crc_init table, subtype-dependent field layout; shared decoder for the three 96/192/384 variants
internal object Gridstream96 : Rtl433Decoder() {
    override val name = "Landis & Gyr Gridstream Power Meters 9.6k"
    override val mod = Mod.FSK_PCM
    override val short = 104
    override val long = 104
    override val reset = 20000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: not ported - gridstream.c:119-261 (shared decoder, see Gridstream96); struct gridstream.c:295
internal object Gridstream192 : Rtl433Decoder() {
    override val name = "Landis & Gyr Gridstream Power Meters 19.2k"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 20000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: not ported - gridstream.c:119-261 (shared decoder, see Gridstream96); struct gridstream.c:306
internal object Gridstream384 : Rtl433Decoder() {
    override val name = "Landis & Gyr Gridstream Power Meters 38.4k"
    override val mod = Mod.FSK_PCM
    override val short = 22
    override val long = 22
    override val reset = 20000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

internal val BATCH_03: List<Rtl433Decoder> = listOf(
    FineoffsetWh55,
    FineoffsetWh5rb,
    FineoffsetWn34,
    FineoffsetWs80,
    FineoffsetWs85,
    FineoffsetWs90,
    FlexDecoder,
    Florabest,
    Flowis,
    Fordremote,
    Fs20,
    FslScoreboard,
    Ft004b,
    FunkbusRemote,
    GasmateBa1008,
    GeColoreffects,
    GeevonTx16,
    GeevonTx19,
    GenericMotion,
    GenericRemoteSc226x,
    GenericTemperatureSensor,
    GeoMinim,
    GmCarRemote,
    Govee,
    GoveeH5054,
    GoveeH5059,
    GoveeH5112,
    GoveeH5310,
    Gridstream192,
    Gridstream384,
    Gridstream96,
    GrillThermometer,
    GtTmbbq05,
    GtWt02,
    GtWt03,
    HanwellMl4000,
    Hcs200,
    Hcs200Fsk,
    Hcs361TxwakBsel0,
)

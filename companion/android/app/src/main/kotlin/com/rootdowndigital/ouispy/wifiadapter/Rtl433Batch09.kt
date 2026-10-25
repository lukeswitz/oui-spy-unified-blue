// Kotlin transcription of rtl_433 device decoders (batch 09). GPL-3 reference; constants, bit offsets and CRC parameters transcribed as facts.
package com.rootdowndigital.ouispy.wifiadapter

private fun rv8(x: Int): Int {
    var v = x and 0xFF
    v = ((v and 0xF0) shr 4) or ((v and 0x0F) shl 4)
    v = ((v and 0xCC) shr 2) or ((v and 0x33) shl 2)
    v = ((v and 0xAA) shr 1) or ((v and 0x55) shl 1)
    return v and 0xFF
}

private fun s16(x: Int): Int = x.toShort().toInt()

// unverified: tpms_toyota.c (tpms_toyota_decode, tpms_toyota_callback), struct tpms_toyota.c
internal object TpmsToyota : Rtl433Decoder() {
    override val name = "Toyota TPMS"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 150

    private fun decodeAt(bb: BitBuffer, bitpos: Int): Reading? {
        val packet = BitBuffer()
        val startPos = bb.differentialManchesterDecode(0, bitpos, packet, 80)
        if (startPos - bitpos < 144) return null
        val b = packet.bb[0]
        val crc = b[8]
        if (Rtl433BitUtil.crc8(b, 8, 0x07, 0x80) != crc) return null
        val id = (b[0] shl 24) or (b[1] shl 16) or (b[2] shl 8) or b[3]
        val status = (b[4] and 0x80) or (b[6] and 0x7f)
        val pressure1 = ((b[4] and 0x7f) shl 1) or (b[5] shr 7)
        val temp = ((b[5] and 0x7f) shl 1) or (b[6] shr 7)
        val pressure2 = b[7] xor 0xff
        if (pressure1 != pressure2) return null
        return Reading(
            "Toyota",
            String.format("%08x", id),
            mapOf(
                "status" to status,
                "pressure_PSI" to (pressure1 * 0.25 - 7.0),
                "temperature_C" to (temp - 40.0),
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0xa9, 0xe0)
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, preamble, 12)
            if (bitpos + 156 > bb.bitsPerRow[0]) break
            decodeAt(bb, bitpos + 11)?.let { out.add(it) }
            bitpos += 2
        }
        return out
    }
}

// unverified: tpms_truck.c (tpms_truck_decode, tpms_truck_callback), struct tpms_truck.c
internal object TpmsTruck : Rtl433Decoder() {
    override val name = "Unbranded SolarTPMS for trucks"
    override val mod = Mod.FSK_PCM
    override val short = 52
    override val long = 52
    override val reset = 150

    private fun decodeAt(bb: BitBuffer, bitpos: Int): Reading? {
        val packet = BitBuffer()
        bb.manchesterDecode(0, bitpos, packet, 76)
        if (packet.bitsPerRow[0] < 76) return null
        val b = IntArray(9)
        packet.extractBytes(0, 4, b, 72)
        if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0) return null
        if (Rtl433BitUtil.xorBytes(b, 9) != 0) return null
        val id = (b[0] shl 24) or (b[1] shl 16) or (b[2] shl 8) or b[3]
        val wheel = b[4]
        val flags = b[5] shr 4
        val pressure = ((b[5] and 0x0f) shl 8) or b[6]
        val temperature = b[7]
        val pressureAlert = (flags and 0x4) == 0x4
        val batteryOk = (flags and 0x3) == 0x3
        val fields = linkedMapOf<String, Any?>(
            "wheel" to wheel,
            "pressure_kPa" to pressure.toDouble(),
            "temperature_C" to temperature.toDouble(),
        )
        if (pressureAlert) fields["pressure_alert"] = 1
        fields["battery_ok"] = if (batteryOk) 1 else 0
        fields["flags"] = flags
        return Reading("Truck", String.format("%08x", id), fields)
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val preamble = intArrayOf(0xaa, 0xaa, 0xa9)
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, preamble, 24)
            if (bitpos + 160 > bb.bitsPerRow[0]) break
            decodeAt(bb, bitpos + 24)?.let { out.add(it) }
            bitpos += 2
        }
        return out
    }
}

private val TRW_PREAMBLE_OOK = intArrayOf(0x00, 0x01)
private val TRW_PREAMBLE_FSK = intArrayOf(0x7f, 0xff)

private fun tpmsTrwDecode(bb: BitBuffer, preamble: IntArray): List<Reading> {
    if (bb.numRows != 1) return emptyList()
    val msgLen = bb.bitsPerRow[0]
    if (msgLen > 98) return emptyList()
    var pos = bb.search(0, 0, preamble, 16)
    if (pos >= bb.bitsPerRow[0]) return emptyList()
    if (pos + 8 * 11 > bb.bitsPerRow[0]) return emptyList()
    pos += 16
    if (msgLen - pos < 81) return emptyList()
    val b = IntArray(11)
    bb.extractBytes(0, pos, b, 88)
    if (Rtl433BitUtil.crc8(b, 10, 0x07, 0x00) != 0) return emptyList()
    val mode = b[0]
    val id = (b[1] shl 24) or (b[2] shl 16) or (b[3] shl 8) or b[4]
    val flags = (b[5] and 0xF0) shr 4
    val seqNum = b[5] and 0x0F
    val pressureRaw = b[6]
    val pressurePsi = pressureRaw * 0.4f
    val tempRaw = b[7]
    val temperatureC = tempRaw - 50
    val motionFlags = b[8]
    val oemModel = (b[10] and 0xf0) shr 4
    val fields = linkedMapOf<String, Any?>(
        "mode" to mode,
        "flags" to flags,
    )
    if (flags == 0x6 || flags == 0x9) fields["alert"] = "Pressure increase/decrease !"
    fields["seq_num"] = seqNum
    fields["pressure_PSI"] = pressurePsi.toDouble()
    fields["temperature_C"] = temperatureC.toDouble()
    fields["motion_flags"] = motionFlags
    fields["motion_status"] = if (motionFlags == 0x0e) "Parked" else "Moving"
    if (oemModel == 0x4) fields["oem_model"] = "OEM"
    if (oemModel == 0x0) fields["oem_model"] = "Clone"
    return listOf(Reading("TRW", String.format("%08x", id), fields))
}

// unverified: tpms_trw.c (tpms_trw_decode shared via tpmsTrwDecode), struct tpms_trw.c
internal object TpmsTrwOok : Rtl433Decoder() {
    override val name = "TRW TPMS OOK OEM and Clone models"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 52
    override val long = 52
    override val reset = 150

    override fun decode(bb: BitBuffer): List<Reading> = tpmsTrwDecode(bb, TRW_PREAMBLE_OOK)
}

// unverified: tpms_trw.c (tpms_trw_decode shared via tpmsTrwDecode), struct tpms_trw.c
internal object TpmsTrwFsk : Rtl433Decoder() {
    override val name = "TRW TPMS FSK OEM and Clone models"
    override val mod = Mod.FSK_MC_ZEROBIT
    override val short = 52
    override val long = 52
    override val reset = 150

    override fun decode(bb: BitBuffer): List<Reading> = tpmsTrwDecode(bb, TRW_PREAMBLE_FSK)
}

// unverified: tpms_tyreguard400.c (tpms_tyreguard400_decode, tpms_tyreguard400_callback), struct tpms_tyreguard400.c
internal object TpmsTyreguard400 : Rtl433Decoder() {
    override val name = "TyreGuard 400 TPMS"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 100
    override val long = 100
    override val gap = 0
    override val reset = 500

    private fun decodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val b = IntArray(11)
        bb.extractBytes(row, bitpos, b, 88)
        if (Rtl433BitUtil.crc8(b, 11, 0x31, 0xdd) != 0) return null
        val flags = b[9]
        val peeringRequest = flags and 0x3
        val ackLeaking = flags and 0x8
        val leaking = flags and 0x3
        val idRaw = ((b[3] and 0xf) shl 24) or (b[4] shl 16) or (b[5] shl 8) or b[6]
        val pressureKpa = b[7] or ((flags and 0x70) shl 4)
        val tempC = b[8] - 40
        return Reading(
            "TyreGuard400",
            String.format("%07x", idRaw),
            mapOf(
                "pressure_kPa" to pressureKpa.toDouble(),
                "temperature_C" to tempC.toDouble(),
                "peering_request" to peeringRequest,
                "leaking" to leaking,
                "ack_leaking" to ackLeaking,
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val sync = intArrayOf(0xfd, 0x5f, 0xd5, 0xf0)
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            if (bb.bitsPerRow[row] < 88) continue
            var bitpos = 0
            while (true) {
                bitpos = bb.search(row, bitpos, sync, 28)
                if (bitpos + 88 > bb.bitsPerRow[row]) break
                decodeAt(bb, row, bitpos)?.let { out.add(it) }
                bitpos += 88
            }
        }
        return out
    }
}

// unverified: tr_502msv.c (tr502msv_decode), struct tr_502msv.c
internal object Tr502msv : Rtl433Decoder() {
    override val name = "TR-502MSV remote smart socket controller"
    override val mod = Mod.OOK_PWM
    override val short = 740
    override val long = 1400
    override val tolerance = 70
    override val reset = 84000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1 || bb.bitsPerRow[0] != 21) return emptyList()
        val b = bb.bb[0]
        if ((b[0] and 0x80) == 0) return emptyList()
        if ((b[2] and 0x20) != 0) return emptyList()
        val deviceId = ((b[0] and 0x7f) shl 5) or (b[1] shr 3)
        val socketId = b[1] and 0x07
        val onOff = (b[2] and 0x80) shr 7
        val command = (b[2] and 0x40) shr 6
        val chk1 = (b[2] and 0x10) shr 4
        val chk0 = (b[2] and 0x08) shr 3
        val s2 = (socketId shr 2) and 1
        val s1 = (socketId shr 1) and 1
        val s0 = socketId and 1
        if (chk1 != (command xor s2 xor s0) || chk0 != (onOff xor s1)) return emptyList()
        val sockets = arrayOf("1", "3", "2", "4", "ALL")
        val socketStr = if (socketId % 2 == 0) {
            sockets[socketId shr 1]
        } else if (socketId == 0x7) {
            sockets[4]
        } else {
            return emptyList()
        }
        val commands = arrayOf("OFF", "BRIGHT", "ON", "DIM")
        val commandStr = commands[(onOff shl 1) or command]
        return listOf(
            Reading(
                "TR-502MSV",
                deviceId.toString(),
                mapOf("socket_id" to socketStr, "command" to commandStr),
            ),
        )
    }
}

// unverified: ts_ft002.c (ts_ft002_decoder), struct ts_ft002.c
internal object TsFt002 : Rtl433Decoder() {
    override val name = "TS-FT002 Wireless Ultrasonic Tank Liquid Level Meter With Temperature Sensor"
    override val mod = Mod.OOK_PPM
    override val short = 464
    override val long = 948
    override val gap = 1200
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> {
        val b = IntArray(9)
        val n = bb.bitsPerRow[0]
        if (n == 72) {
            bb.extractBytes(0, 0, b, 72)
        } else if (n == 71) {
            val tmp = IntArray(8)
            bb.extractBytes(0, 7, tmp, 64)
            for (i in 0 until 8) b[1 + i] = tmp[i]
            b[0] = bb.bb[0][0] shr 1
        } else if (n == 70) {
            val tmp = IntArray(8)
            bb.extractBytes(0, 6, tmp, 64)
            for (i in 0 until 8) b[1 + i] = tmp[i]
            b[0] = (bb.bb[0][0] shr 2) or 0x80
        } else {
            return emptyList()
        }
        if (Rtl433BitUtil.xorBytes(b, 9) != 0) return emptyList()
        for (i in 0 until 8) b[i] = rv8(b[i])
        val id = b[1]
        val type = b[2]
        val depth = (b[3] shl 4) or (b[4] and 0x0f)
        val battLow = b[4] shr 4
        val transmitRaw = b[5] shr 4
        val tempRaw = (b[6] shl 4) or (b[5] and 0x0f)
        val tempC = (tempRaw - 400) * 0.1f
        val transmit = when {
            (transmitRaw and 0x07) == 0x07 -> 5
            (transmitRaw and 0x08) == 0x08 -> 30
            transmitRaw == 0 -> 180
            else -> 0
        }
        if (type != 0x11) return emptyList()
        return listOf(
            Reading(
                "TS-FT002",
                id.toString(),
                mapOf(
                    "depth_cm" to depth,
                    "temperature_C" to tempC.toDouble(),
                    "transmit_s" to transmit,
                    "flags" to battLow,
                ),
            ),
        )
    }
}

// unverified: ttx201.c (ttx201_decode, ttx201_callback), struct ttx201.c
internal object Ttx201 : Rtl433Decoder() {
    override val name = "Emos TTX201 Temperature Sensor"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 510
    override val reset = 1700
    override val tolerance = 250

    private fun decodeRow(bb: BitBuffer, row: Int): Reading? {
        val rowlen = bb.bitsPerRow[row]
        if (rowlen != 50 && rowlen != 54) return null
        val b = IntArray(7)
        bb.extractBytes(row, 2, b, 56)
        val chk = b[0] and 0x3f
        val sum = Rtl433BitUtil.addNibbles(b.copyOfRange(1, 6), 5)
        val dataType = (b[2] and 0x70) shr 4
        if (sum == 0) return null
        if (chk != (sum and 0x3f)) return null
        if (dataType == 0x05) {
            val cest = (b[1] and 0x80) != 0
            val year = b[1] and 0x7f
            val month = b[2] and 0x0f
            val day = (b[3] and 0xf8) shr 3
            val hour = ((b[3] and 0x07) shl 2) or ((b[4] and 0xc0) shr 6)
            val minute = b[4] and 0x3f
            val second = (b[5] and 0x7e) shr 1
            val clockStr = String.format(
                "%04d-%02d-%02dT%02d:%02d:%02d %s",
                year + 2000, month, day, hour, minute, second, if (cest) "CEST" else "CET",
            )
            return Reading("Emos-TTX201", null, mapOf("radio_clock" to clockStr))
        }
        val deviceId = b[1]
        val batteryLow = (b[2] and 0x08) != 0
        val channel = (b[2] and 0x07) + 1
        val temperature = s16(((b[3] and 0x0f) shl 12) or (b[4] shl 4))
        val temperatureC = (temperature shr 4) * 0.1f
        return Reading(
            "Emos-TTX201",
            deviceId.toString(),
            mapOf(
                "channel" to channel,
                "battery_ok" to (if (batteryLow) 0 else 1),
                "temperature_C" to temperatureC.toDouble(),
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows < 2 || bb.numRows > 10) return emptyList()
        for (row in 0 until bb.numRows) {
            decodeRow(bb, row)?.let { return listOf(it) }
        }
        return emptyList()
    }
}

// unverified: typhur_sync_gold.c (typhur_sync_gold_decode), struct typhur_sync_gold.c
internal object TyphurSyncGold : Rtl433Decoder() {
    override val name = "Typhur Sync Gold meat thermometer probe"
    override val mod = Mod.FSK_PCM
    override val short = 13
    override val long = 13
    override val reset = 3000

    override fun decode(bb: BitBuffer): List<Reading> {
        val sync = intArrayOf(0x57, 0x54)
        for (row in 0 until bb.numRows) {
            var pos = bb.search(row, 0, sync, 16)
            if (pos >= bb.bitsPerRow[row]) continue
            pos += 16
            if (bb.bitsPerRow[row] - pos < 24 * 8) continue
            val b = IntArray(24)
            bb.extractBytes(row, pos, b, 24 * 8)
            val crc = Rtl433BitUtil.crc16(b, 22, 0x8005, 0x0000)
            val crcRecv = (b[22] shl 8) or b[23]
            if (crc != crcRecv) continue
            val id = (b[0] shl 16) or (b[1] shl 8) or b[2]
            val inBase = if ((b[4] and 0x08) != 0) 1 else 0
            val temp1C = (b[6] or (b[7] shl 8)) * 0.01f
            val temp2C = (b[8] or (b[9] shl 8)) * 0.01f
            val temp3C = (b[10] or (b[11] shl 8)) * 0.01f
            val temp4C = (b[12] or (b[13] shl 8)) * 0.01f
            val temp5C = (b[14] or (b[15] shl 8)) * 0.01f
            val ambientC = (b[16] or (b[17] shl 8)) * 0.1f
            val batteryV = (b[18] or (b[19] shl 8)) * 0.01f
            val counter = b[20] or (b[21] shl 8)
            return listOf(
                Reading(
                    "Typhur-SyncGold",
                    String.format("%06x", id),
                    mapOf(
                        "in_base" to inBase,
                        "counter" to counter,
                        "battery_V" to batteryV.toDouble(),
                        "temperature_1_C" to temp1C.toDouble(),
                        "temperature_2_C" to temp2C.toDouble(),
                        "temperature_3_C" to temp3C.toDouble(),
                        "temperature_4_C" to temp4C.toDouble(),
                        "temperature_5_C" to temp5C.toDouble(),
                        "ambient_C" to ambientC.toDouble(),
                    ),
                ),
            )
        }
        return emptyList()
    }
}

// unverified: universalfanctrl.c (universalfan_decode), struct universalfanctrl.c
internal object Universalfanctrl : Rtl433Decoder() {
    override val name = "Universal (Reverseable) 24V Fan Controller"
    override val mod = Mod.OOK_PWM
    override val short = 256
    override val long = 756
    override val gap = 8000
    override val sync = 3616
    override val reset = 8800

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(3, 33)
        if (row < 0) return emptyList()
        val b = bb.bb[row]
        if ((b[4] and 0x80) == 0) return emptyList()
        var sum = Rtl433BitUtil.xorBytes(b, 4)
        sum = (sum shr 4) xor (sum and 0xf)
        if (sum != 0xa) return emptyList()
        val address = (b[0] shl 12) + (b[1] shl 4) + (b[2] shr 4)
        val button = ((b[2] and 0x0F) shl 1) + ((b[3] and 0x80) shr 7)
        val counter = (b[3] and 0x7F) shr 4
        val buttonStr = when (button) {
            0x19 -> "All Off"
            0x17 -> "Light On/Off"
            0x1b -> "Forward"
            0x0a -> "Fan"
            0x0e -> "Reverse"
            0x09 -> "Fan Off"
            0x0f -> "Speed 1"
            0x0d -> "Speed 2"
            0x03 -> "Speed 3"
            0x15 -> "Speed 4"
            0x10 -> "Speed 5"
            0x13 -> "speed 6"
            0x1d -> "1H"
            0x16 -> "2H"
            0x06 -> "3H"
            else -> "Unknown"
        }
        return listOf(
            Reading(
                "UniFan-24V",
                address.toString(),
                mapOf(
                    "button" to buttonStr,
                    "button_code" to button,
                    "counter" to counter,
                ),
            ),
        )
    }
}

private fun vaillantChecksumOk(b: IntArray, from: Int, to: Int, csFrom: Int, csTo: Int): Boolean {
    val expected = (b[csFrom] shl 8) or b[csTo]
    val n = to - from + 1
    val calculated = Rtl433BitUtil.addBytes(b.copyOfRange(from, from + n), n)
    return ((calculated + expected) and 0xffff) == 0
}

// unverified: vaillant_vrt340f.c (vaillant_vrt340_callback, validate_checksum), struct vaillant_vrt340f.c
internal object VaillantVrt340f : Rtl433Decoder() {
    override val name = "Vaillant calorMatic VRT340f Central Heating Control"
    override val mod = Mod.OOK_DMC
    override val short = 836
    override val long = 1648
    override val reset = 4000
    override val tolerance = 120

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 128) return emptyList()
        val bits = BitBuffer()
        var ones = 0
        val raw = bb.bb[0]
        for (k in 0 until bb.bitsPerRow[0]) {
            val bit = bitrowGetBit(raw, k)
            if (bit == 1) {
                bits.addBit(1)
                ones++
            } else {
                if (ones != 5) bits.addBit(0)
                ones = 0
            }
        }
        val b = bits.bb[0]
        val bitcount = bits.bitsPerRow[0]
        for (i in 0 until (bitcount - 1) / 8) b[i] = rv8(b[i])
        if (!(bitcount in 128..131) && !(bitcount in 168..171)) return emptyList()
        if (b[0] == 0x00 && b[1] == 0x00 && b[2] == 0x7e && bitcount in 128..131) {
            if (!vaillantChecksumOk(b, 3, 11, 12, 13)) return emptyList()
            val deviceId = (b[3] shl 8) or b[4]
            val heatingMode = b[10] shr 7
            val targetTemperature = b[10] and 0x7f
            val waterPreheated = (b[9] and 8) == 0
            val batteryLow = b[11] != 0
            val heating = if (heatingMode == 0 && targetTemperature == 0) {
                "OFF"
            } else if (heatingMode != 0) {
                "ON (2-point)"
            } else {
                "ON (analogue)"
            }
            return listOf(
                Reading(
                    "Vaillant-VRT340f",
                    String.format("0x%04X", deviceId),
                    mapOf(
                        "heating" to heating,
                        "heating_temp" to targetTemperature,
                        "water" to (if (waterPreheated) "ON" else "off"),
                        "battery_ok" to (if (batteryLow) 0 else 1),
                    ),
                ),
            )
        }
        if (b[0] == 0x00 && b[1] == 0x00 && b[2] == 0x7e && bitcount in 168..171) {
            if (!vaillantChecksumOk(b, 3, 16, 17, 18)) return emptyList()
            val deviceId = (b[11] shl 8) or b[12]
            return listOf(Reading("Vaillant-VRT340f", deviceId.toString(), emptyMap()))
        }
        return emptyList()
    }
}

// unverified: vauno_en8822c.c (vauno_en8822c_decode), struct vauno_en8822c.c
internal object VaunoEn8822c : Rtl433Decoder() {
    override val name = "Vauno EN8822C"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val tolerance = 500
    override val gap = 5000
    override val reset = 9500

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedPrefix(4, 42)
        if (row < 0) return emptyList()
        val b = bb.bb[row]
        val chk = ((b[4] and 0x0f) shl 2) or (b[5] shr 6)
        val sum = Rtl433BitUtil.addNibbles(b, 4) + (b[4] shr 4)
        if (sum == 0) return emptyList()
        if ((sum and 0x3f) != chk) return emptyList()
        val deviceId = b[0]
        val channel = ((b[1] and 0x30) shr 4) + 1
        val batteryLow = (b[4] and 0x10) shr 4
        val tempRaw = s16(((b[1] and 0x0f) shl 12) or ((b[2] and 0xff) shl 4))
        val tempC = (tempRaw shr 4) * 0.1f
        val humidity = b[3] shr 1
        return listOf(
            Reading(
                "Vauno-EN8822C",
                deviceId.toString(),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                ),
            ),
        )
    }
}

// unverified: vevor_7in1.c (vevor_7in1_decode), struct vevor_7in1.c
internal object Vevor7in1 : Rtl433Decoder() {
    override val name = "Vevor Wireless Weather Station 7-in-1"
    override val mod = Mod.FSK_PCM
    override val short = 87
    override val long = 87
    override val reset = 9000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val preamble = intArrayOf(0xaa, 0xaa, 0xca, 0xca, 0x54)
        var pos = 0
        while (true) {
            pos = bb.search(0, pos, preamble, 40)
            if (pos + 264 > bb.bitsPerRow[0]) break
            pos += 40
            if (pos + 21 * 8 > bb.bitsPerRow[0]) continue
            val b = IntArray(21)
            bb.extractBytes(0, pos, b, 21 * 8)
            if ((Rtl433BitUtil.addBytes(b, 19) and 0xff) != b[19]) continue
            if (b[20] != ((b[18] + 1) and 0xff)) continue
            for (i in intArrayOf(8, 9, 11, 12, 13, 14, 16, 17)) b[i] = (b[i] - 1) and 0xff
            val channel = b[1] and 0x0f
            val id = (b[2] shl 8) or b[3]
            val batteryLow = (b[4] and 0x80) shr 7
            if (b[0] == 0xAA && b[1] == 0) {
                val tempRaw = (b[5] shl 8) or b[6]
                val tempC = (tempRaw - 500) * 0.1f
                val humidity = b[7]
                val windRaw = (b[8] shl 8) or b[9]
                val speedKmh = windRaw / 8.333f
                val gustRaw = b[10]
                val gustKmh = gustRaw / 1.25f
                val directionDeg = ((b[11] and 0x0f) shl 8) or b[12]
                val rainRaw = (b[13] shl 8) or b[14]
                val rainMm = rainRaw * 0.233f
                val uvIndex = (b[15] and 0x1f) - 1
                var lightLux = (b[16] shl 8) or b[17]
                val luxMulti = (lightLux and 0x8000) shr 15
                if (luxMulti == 1) lightLux = (lightLux and 0x7fff) * 10
                return listOf(
                    Reading(
                        "Vevor-7in1",
                        String.format("%04x", id),
                        mapOf(
                            "channel" to channel,
                            "battery_ok" to (if (batteryLow != 0) 0 else 1),
                            "temperature_C" to tempC.toDouble(),
                            "humidity" to humidity,
                            "wind_avg_km_h" to speedKmh.toDouble(),
                            "wind_max_km_h" to gustKmh.toDouble(),
                            "wind_dir_deg" to directionDeg,
                            "rain_mm" to rainMm.toDouble(),
                            "uvi" to uvIndex.toDouble(),
                            "light_lux" to lightLux,
                        ),
                    ),
                )
            }
            pos += 264
        }
        return emptyList()
    }
}

// unverified: visonic_powercode.c (visonic_powercode_decode), struct visonic_powercode.c
internal object VisonicPowercode : Rtl433Decoder() {
    override val name = "Visonic powercode"
    override val mod = Mod.OOK_PWM
    override val short = 400
    override val long = 800
    override val gap = 900
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(2, 37)
        if (row == -1) return emptyList()
        if (bb.bitsPerRow[row] != 37) return emptyList()
        val msg = IntArray(5)
        bb.extractBytes(row, 1, msg, 36)
        if (msg[0] == 0 && msg[1] == 0 && msg[2] == 0 && msg[3] == 0 && msg[4] == 0) return emptyList()
        val lrc = Rtl433BitUtil.xorBytes(msg, 5)
        if (((lrc shr 4) xor (lrc and 0xf)) != 0) return emptyList()
        val idStr = String.format("%02x%02x%02x", msg[0], msg[1], msg[2])
        val flags = msg[3]
        return listOf(
            Reading(
                "Visonic-Powercode",
                idStr,
                mapOf(
                    "tamper" to (if ((0x80 and flags) == 0x80) 1 else 0),
                    "alarm" to (if ((0x40 and flags) == 0x40) 1 else 0),
                    "battery_ok" to (if ((0x20 and flags) == 0x20) 0 else 1),
                    "else" to (if ((0x10 and flags) == 0x10) 1 else 0),
                    "restore" to (if ((0x08 and flags) == 0x08) 1 else 0),
                    "supervised" to (if ((0x04 and flags) == 0x04) 1 else 0),
                    "spidernet" to (if ((0x02 and flags) == 0x02) 1 else 0),
                    "repeater" to (if ((0x01 and flags) == 0x01) 1 else 0),
                ),
            ),
        )
    }
}

// unverified: wallarge_cltx001.c (wallarge_cltx001_decode), struct wallarge_cltx001.c
internal object WallargeCltx001 : Rtl433Decoder() {
    override val name = "WallarGe CLTX001 Outdoor Temperature Sensor"
    override val mod = Mod.OOK_PWM
    override val tolerance = 75
    override val short = 250
    override val long = 500
    override val gap = 650
    override val reset = 1250

    override fun decode(bb: BitBuffer): List<Reading> {
        for (rowIndex in 0 until bb.numRows) {
            if (bb.bitsPerRow[rowIndex] != 56) continue
            val b = bb.bb[rowIndex]
            for (i in 0 until 7) b[i] = b[i].inv() and 0xFF
            val checksum = Rtl433BitUtil.addBytes(b, 5) and 0xFF
            if (b[6] != checksum) continue
            val parityByte = b[5]
            var parityValid = true
            if ((parityByte and 0x07) != 0) {
                parityValid = false
            } else {
                for (byteIndex in 0 until 5) {
                    if (Rtl433BitUtil.parity8(b[byteIndex]) == ((parityByte shr (7 - byteIndex)) and 1)) {
                        parityValid = false
                        break
                    }
                }
            }
            if (!parityValid) continue
            val sensorId = (b[0] shl 8) or b[1]
            val batteryLow = (b[3] and 0x80) shr 7
            val testMode = (b[3] and 0x40) shr 6
            val channel = (b[3] and 0x30) shr 4
            val tempRaw = s16(((b[3] and 0x0F) shl 12) or (b[4] shl 4))
            val tempC = ((tempRaw shr 4) * 0.1f).toDouble()
            val fields = linkedMapOf<String, Any?>(
                "channel" to channel + 1,
                "temperature_C" to tempC,
            )
            if (batteryLow != 0) fields["battery_ok"] = 0
            if (testMode != 0) fields["test"] = 1
            return listOf(Reading("WallarGe-CLTX001", sensorId.toString(), fields))
        }
        return emptyList()
    }
}

private fun reverse32(x: Int): Int {
    var r = 0
    for (i in 0 until 32) r = (r shl 1) or ((x ushr i) and 1)
    return r
}

// unverified: watchman_plus.c (watchman_plus_decode), struct watchman_plus.c
internal object WatchmanPlus : Rtl433Decoder() {
    override val name = "Kingspan/Watchman Plus (Niveau) oil tank monitor"
    override val mod = Mod.OOK_PWM
    override val short = 3299
    override val long = 4107
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1 || bb.bitsPerRow[0] < 13 + 40) return emptyList()
        val preamble = intArrayOf(0xff, 0xf0)
        val row = 0
        val b = bb.bb[row]
        val rowLen = bb.bitsPerRow[row]
        var id = 0
        var level = 0
        var batteryLow = 0
        var found = false
        var searchStart = 0
        while (searchStart + 13 + 40 <= rowLen) {
            val match = bb.search(row, searchStart, preamble, 13)
            if (match + 13 + 40 > rowLen) break
            var pos = match + 13
            searchStart = match + 1
            var stuffOk = true
            var idRaw = 0
            for (i in 0 until 3) {
                for (j in 0 until 8) {
                    idRaw = (idRaw shl 1) or bitrowGetBit(b, pos++)
                }
                if (i < 2) {
                    val s0 = bitrowGetBit(b, pos++)
                    val s1 = bitrowGetBit(b, pos++)
                    stuffOk = stuffOk && (s0 == 1 && s1 == 0)
                }
            }
            val s0 = bitrowGetBit(b, pos++)
            val s1 = bitrowGetBit(b, pos++)
            stuffOk = stuffOk && (s0 == 1 && s1 == 0)
            var lvl = 0
            for (j in 0 until 4) {
                lvl = lvl or (bitrowGetBit(b, pos++) shl j)
            }
            pos += 3
            val battLow = bitrowGetBit(b, pos++)
            val s2 = bitrowGetBit(b, pos++)
            val s3 = bitrowGetBit(b, pos++)
            stuffOk = stuffOk && (s2 == 1 && s3 == 0)
            if (!stuffOk || lvl > 10) continue
            val idRev = reverse32(idRaw shl 8) and 0xffffff
            var idVal = 0
            for (n in 7 downTo 0) {
                val digit = (idRev shr (n * 3)) and 0x7
                idVal = idVal * 10 + digit
            }
            id = idVal
            level = lvl
            batteryLow = battLow
            found = true
            break
        }
        if (!found) return emptyList()
        val levelStr = if (level <= 9) ('0' + level).toString() else "F"
        val idStr = String.format("%08d", id)
        return listOf(
            Reading(
                "Watchman-Plus",
                idStr,
                mapOf(
                    "level" to levelStr,
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                ),
            ),
        )
    }
}

private fun crc4(msg: IntArray, nBytes: Int, poly: Int, init: Int): Int {
    var rem = init shl 4
    val p = poly shl 4
    for (i in 0 until nBytes) {
        rem = rem xor (msg[i] and 0xFF)
        for (bit in 0 until 8) {
            rem = if ((rem and 0x80) != 0) (rem shl 1) xor p else rem shl 1
        }
    }
    return (rem shr 4) and 0x0f
}

// unverified: watts_thermostat.c (watts_thermostat_decode), struct watts_thermostat.c
internal object WattsThermostat : Rtl433Decoder() {
    override val name = "Watts WFHT-RF Thermostat"
    override val mod = Mod.OOK_PWM
    override val short = 260
    override val long = 600
    override val sync = 6000
    override val reset = 900

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        bb.invert()
        val rowLen = bb.bitsPerRow[0]
        if (rowLen != 54) return emptyList()
        val preamble = IntArray(1)
        bb.extractBytes(0, 0, preamble, 8)
        if (preamble[0] != 0xa5) return emptyList()
        var bitpos = 8
        val idRaw = IntArray(2)
        bb.extractBytes(0, bitpos, idRaw, 16)
        for (i in 0 until 2) idRaw[i] = rv8(idRaw[i])
        val id = (idRaw[1] shl 8) or idRaw[0]
        bitpos += 16
        val flags = IntArray(1)
        bb.extractBytes(0, bitpos, flags, 4)
        flags[0] = rv8(flags[0])
        val pairing = flags[0] and 1
        bitpos += 4
        val tempRaw = IntArray(2)
        bb.extractBytes(0, bitpos, tempRaw, 9)
        for (i in 0 until 2) tempRaw[i] = rv8(tempRaw[i])
        val temp = (tempRaw[1] shl 8) or tempRaw[0]
        bitpos += 9
        val setpRaw = IntArray(2)
        bb.extractBytes(0, bitpos, setpRaw, 9)
        for (i in 0 until 2) setpRaw[i] = rv8(setpRaw[i])
        val setp = (setpRaw[1] shl 8) or setpRaw[0]
        bitpos += 9
        val chksum = (Rtl433BitUtil.addBytes(idRaw, 2) + Rtl433BitUtil.addBytes(flags, 1) +
            Rtl433BitUtil.addBytes(tempRaw, 2) + Rtl433BitUtil.addBytes(setpRaw, 2)) and 0xff
        val chk = IntArray(1)
        bb.extractBytes(0, bitpos, chk, 8)
        chk[0] = rv8(chk[0])
        if (chk[0] != chksum) return emptyList()
        if (id == 0 && flags[0] == 0 && temp == 0 && setp == 0 && chk[0] == 0) return emptyList()
        return listOf(
            Reading(
                "Watts-WFHTRF",
                id.toString(),
                mapOf(
                    "pairing" to pairing,
                    "temperature_C" to (temp * 0.1f).toDouble(),
                    "setpoint_C" to (setp * 0.1f).toDouble(),
                    "flags" to flags[0],
                ),
            ),
        )
    }
}

// unverified: waveman.c (waveman_callback), struct waveman.c
internal object Waveman : Rtl433Decoder() {
    override val name = "Waveman Switch Transmitter"
    override val mod = Mod.OOK_PWM
    override val short = 357
    override val long = 1064
    override val gap = 1400
    override val reset = 12000
    override val tolerance = 200

    override fun decode(bb: BitBuffer): List<Reading> {
        val b = bb.bb[0]
        if (bb.bitsPerRow[0] != 25) return emptyList()
        if (b[0] == 0xFF && b[1] == 0xFF && b[2] == 0xFF) return emptyList()
        if (((b[0] and 0xaa) != 0xaa) || ((b[1] and 0xaa) != 0xaa) || ((b[2] and 0xaa) != 0xaa)) return emptyList()
        val nb = IntArray(3)
        for (i in 0 until 3) {
            nb[i] = (if ((b[i] and 0x40) != 0) 0x00 else 0x01) or
                (if ((b[i] and 0x10) != 0) 0x00 else 0x02) or
                (if ((b[i] and 0x04) != 0) 0x00 else 0x04) or
                (if ((b[i] and 0x01) != 0) 0x00 else 0x08)
        }
        if (nb[2] != 0xe && nb[2] != 0x6) return emptyList()
        val idStr = ('A' + nb[0]).toString()
        val state = if (nb[2] == 0xe) "ON" else "OFF"
        return listOf(
            Reading(
                "Waveman-Switch",
                idStr,
                mapOf(
                    "channel" to ((nb[1] shr 2) + 1),
                    "button" to ((nb[1] and 3) + 1),
                    "state" to state,
                ),
            ),
        )
    }
}

// unverified: wec2103.c (wec2103_decode), struct wec2103.c
internal object Wec2103 : Rtl433Decoder() {
    override val name = "WEC-2103 temperature/humidity sensor"
    override val mod = Mod.OOK_PPM
    override val short = 1900
    override val long = 3800
    override val gap = 4400
    override val reset = 9400

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 6 || bb.bitsPerRow[2] != 42) return emptyList()
        val b = IntArray(5)
        bb.extractBytes(3, 0, b, 40)
        val crcReceived = b[1] shr 4
        b[1] = (b[1] and 0x0F) or ((b[4] and 0x0f) shl 4)
        val crcCalculated = crc4(b, 4, 3, 0) xor (b[4] shr 4)
        if (crcCalculated != crcReceived) return emptyList()
        val tempRaw = (b[2] shl 4) or ((b[3] and 0xf0) shr 4)
        val deviceId = b[0]
        val channel = b[4] and 0x0f
        val flags = b[1] and 0xf
        val tempF = (tempRaw - 900) * 0.1f
        val humidity = ((b[3] and 0x0f) * 10) + ((b[4] and 0xf0) shr 4)
        val button = (b[1] and 0x08) shr 3
        val batteryLow = (b[1] and 0x04) shr 3
        return listOf(
            Reading(
                "WEC-2103",
                deviceId.toString(),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "button" to button,
                    "temperature_F" to tempF.toDouble(),
                    "humidity" to humidity,
                    "flags" to flags,
                ),
            ),
        )
    }
}

// unverified: wg_pb12v1.c (wg_pb12v1_decode), struct wg_pb12v1.c
internal object WgPb12v1 : Rtl433Decoder() {
    override val name = "WG-PB12V1 Temperature Sensor"
    override val mod = Mod.OOK_PWM
    override val short = 564
    override val long = 1476
    override val reset = 2500

    override fun decode(bb: BitBuffer): List<Reading> {
        val b = bb.bb[0]
        if (bb.bitsPerRow[0] < 48) return emptyList()
        if (b[0] != 0xFF) return emptyList()
        if ((b[1] and 0xf0) != 0x30) return emptyList()
        if (b[5] != Rtl433BitUtil.crc8(b.copyOfRange(1, 5), 4, 0x31, 0)) return emptyList()
        if (b[4] != 0xFF) return emptyList()
        val id = b[3] and 0x1F
        val tempRaw = ((b[1] and 0x0F) shl 8) or b[2]
        val tempC = (tempRaw - 400) * 0.1f
        return listOf(
            Reading(
                "WG-PB12V1",
                id.toString(),
                mapOf("temperature_C" to tempC.toDouble()),
            ),
        )
    }
}

// unverified: ws2032.c (fineoffset_ws2032_decode), struct ws2032.c
internal object Ws2032 : Rtl433Decoder() {
    override val name = "WS2032 weather station"
    override val mod = Mod.OOK_PWM
    override val short = 500
    override val long = 1000
    override val gap = 750
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0x0a)
        val row = bb.findRepeatedRow(2, 14 * 8)
        if (row < 0) return emptyList()
        val offset = bb.search(row, 0, preamble, 8)
        if (offset + 14 * 8 > bb.bitsPerRow[row]) return emptyList()
        bb.invert()
        val b = IntArray(14)
        bb.extractBytes(row, offset, b, 14 * 8)
        val sum = Rtl433BitUtil.addBytes(b, 12)
        if (sum == 0) return emptyList()
        if ((sum and 0xff) != b[12]) return emptyList()
        if (Rtl433BitUtil.crc8(b, 14, 0x31, 0x00) != 0) return emptyList()
        val deviceId = (b[1] shl 8) or b[2]
        val flags = b[3] and 0xfe
        val batteryLow = b[3] and 0x01
        val dir = (b[4] shr 4) * 22.5f
        val tempSign = if ((b[4] and 0x08) != 0) -1 else 1
        val tempRaw = ((b[4] and 0x07) shl 8) or b[5]
        val temperature = tempSign * tempRaw * 0.1f
        val humidity = b[6]
        val speed = (b[7] * 0.43f) * 3.6f
        val gust = (b[8] * 0.43f) * 3.6f
        val rainRaw = (b[9] shl 16) or (b[10] shl 8) or b[11]
        return listOf(
            Reading(
                "WS2032",
                String.format("%04X", deviceId),
                mapOf(
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "temperature_C" to temperature.toDouble(),
                    "humidity" to humidity,
                    "wind_dir_deg" to dir.toDouble(),
                    "wind_avg_km_h" to speed.toDouble(),
                    "wind_max_km_h" to gust.toDouble(),
                    "rain" to rainRaw,
                    "flags" to flags,
                ),
            ),
        )
    }
}

// unverified: wssensor.c (wssensor_decode), struct wssensor.c
internal object Wssensor : Rtl433Decoder() {
    override val name = "Hyundai WS SENZOR Remote Temperature Sensor"
    override val mod = Mod.OOK_PPM
    override val short = 1000
    override val long = 2000
    override val gap = 2400
    override val reset = 4400

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(4, 23)
        if (r < 0 || bb.bitsPerRow[r] != 24) return emptyList()
        val b = bb.bb[r]
        if ((b[0] == 0 && b[1] == 0 && b[2] == 0) || (b[0] == 0xff && b[1] == 0xff && b[2] == 0xff)) return emptyList()
        val temperature = s16((b[0] shl 8) or (b[1] and 0xf0))
        val batteryStatus = (b[1] and 0x08) shr 3
        val startup = (b[1] and 0x04) shr 2
        val channel = (b[1] and 0x03) + 1
        val sensorId = b[2]
        val temperatureC = (temperature shr 4) * 0.1f
        return listOf(
            Reading(
                "Hyundai-WS",
                sensorId.toString(),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to (if (batteryStatus != 0) 1 else 0),
                    "temperature_C" to temperatureC.toDouble(),
                    "button" to startup,
                ),
            ),
        )
    }
}

// unverified: wt0124.c (wt1024_callback), struct wt0124.c
internal object Wt1024 : Rtl433Decoder() {
    override val name = "WT0124 Pool Thermometer"
    override val mod = Mod.OOK_PWM
    override val short = 680
    override val long = 1850
    override val reset = 30000
    override val gap = 4000
    override val sync = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[1] != 49) return emptyList()
        val b = bb.bb[1]
        if ((b[0] shr 4) != 0x5) return emptyList()
        if (Rtl433BitUtil.xorBytes(b, 4) != b[4]) return emptyList()
        var sum = Rtl433BitUtil.addBytes(b, 4)
        sum += sum shr 8
        sum += b[4]
        sum = sum and 0xFF
        if (sum != b[5]) return emptyList()
        val sensorRid = ((b[0] and 0x0F) shl 4) or (b[1] and 0x0F)
        val tempC = ((((b[1] and 0xF) shl 8) or b[2]) - 0x990) * 0.1f
        val channel = (b[3] shr 4) and 0x3
        return listOf(
            Reading(
                "WT0124-Pool",
                sensorRid.toString(),
                mapOf(
                    "channel" to channel,
                    "temperature_C" to tempC.toDouble(),
                ),
            ),
        )
    }
}

// unverified: wt450.c (wt450_callback), struct wt450.c
internal object Wt450 : Rtl433Decoder() {
    override val name = "WT450, WT260H, WT405H"
    override val mod = Mod.OOK_DMC
    override val short = 976
    override val long = 1952
    override val reset = 18000
    override val tolerance = 100

    override fun decode(bb: BitBuffer): List<Reading> {
        val b = bb.bb[0]
        if (bb.bitsPerRow[0] != 36) return emptyList()
        if ((b[0] shr 4) != 0xC) return emptyList()
        var parity = Rtl433BitUtil.xorBytes(b, 5)
        parity = parity xor (parity shr 4)
        parity = parity xor (parity shr 2)
        parity = parity and 0x3
        if (parity != 0) return emptyList()
        val houseCode = b[0] and 0xF
        val channel = (b[1] shr 6) + 1
        val batteryLow = b[1] and 0x8
        val humidity = ((b[1] and 0x7) shl 4) or (b[2] shr 4)
        val tempWhole = ((b[2] shl 4) or (b[3] shr 4)) and 0xFF
        val tempFraction = b[3] and 0xF
        val temp = (tempWhole - 50.0f) + (tempFraction / 16.0f)
        val seq = b[4] shr 6
        if (humidity > 100) return emptyList()
        if (temp < -35.0f || temp > 75.0f) return emptyList()
        return listOf(
            Reading(
                "WT450-TH",
                houseCode.toString(),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "temperature_C" to temp.toDouble(),
                    "humidity" to humidity,
                    "seq" to seq,
                ),
            ),
        )
    }
}

// unverified: yale_hsa.c (yale_hsa_decode), struct yale_hsa.c
internal object YaleHsa : Rtl433Decoder() {
    override val name = "Yale HSA (Home Security Alarm), YES-Alarmkit"
    override val mod = Mod.OOK_PWM
    override val short = 850
    override val long = 1460
    override val sync = 5380
    override val reset = 1500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows < 6) return emptyList()
        val msg = IntArray(6)
        var row = 0
        while (row < bb.numRows) {
            var ok = false
            var i = 0
            while (i < 6) {
                if (bb.bitsPerRow[row] != 13) break
                val b = bb.bb[row]
                if ((b[0] and 0xf0) != 0x50) break
                val eom = b[0] and 0x08
                if ((i < 5 && eom != 0) || (i == 5 && eom == 0)) break
                val tmp = IntArray(1)
                bb.extractBytes(row, 5, tmp, 8)
                msg[i] = tmp[0]
                if (i == 5) ok = true
                i++
                row++
            }
            if (!ok) {
                while (row < bb.numRows) {
                    val eom = bb.bb[row][0] and 0x08
                    if (eom != 0) break
                    row++
                }
                row++
                continue
            }
            val chk = Rtl433BitUtil.addBytes(msg, 6)
            if ((chk and 0xff) != 0) {
                row++
                continue
            }
            val id = (msg[0] shl 8) or msg[1]
            return listOf(
                Reading(
                    "Yale-HSA",
                    String.format("%04x", id),
                    mapOf(
                        "stype" to msg[2],
                        "state" to msg[3],
                        "event" to msg[4],
                    ),
                ),
            )
        }
        return emptyList()
    }
}

// unverified: x10_rf.c (x10_rf_callback), struct X10_RF
internal object X10Rf : Rtl433Decoder() {
    override val name = "X10 RF"
    override val mod = Mod.OOK_PPM
    override val short = 562
    override val long = 1687
    override val gap = 2200
    override val reset = 6000

    override fun decode(bb: BitBuffer): List<Reading> {
        val b = bb.bb[1]
        val knownConstBitMask = intArrayOf(0x0B, 0x0B, 0x07, 0x07)
        val knownConstBitValue = intArrayOf(0x00, 0x0B, 0x00, 0x07)
        if (bb.bitsPerRow[1] != 32) return emptyList()
        if ((b[0] xor b[1]) != 0xff || (b[2] xor b[3]) != 0xff) return emptyList()
        for (bIdx in 0 until 4) {
            val bTest = knownConstBitMask[bIdx] and b[bIdx]
            if (bTest != knownConstBitValue[bIdx]) return emptyList()
        }
        val code = (b[0] shl 24) or (b[1] shl 16) or (b[2] shl 8) or b[3]
        val a0 = (b[0] and 0x80) shr 7
        val a1 = (b[0] and 0x40) shr 6
        val a2 = (b[0] and 0x20) shr 5
        val a3 = (b[0] and 0x10) shr 4
        val houseCode = (((a0 xor a1).inv() and 0x01) shl 3) or
            ((a1.inv() and 0x01) shl 2) or
            (((a1 xor a2) and 0x01) shl 1) or
            (a3 and 0x01)
        var deviceCode = (b[0] and 0x04) shl 1
        deviceCode = deviceCode or ((b[2] and 0x40) shr 4)
        deviceCode = deviceCode or ((b[2] and 0x08) shr 2)
        deviceCode = deviceCode or ((b[2] and 0x10) shr 4)
        deviceCode += 1
        val housecode = ('A' + houseCode).toString()
        val state = if ((b[2] and 0x20) == 0x00) 1 else 0
        var eventStr = "UNKNOWN"
        if ((b[2] and 0x80) == 0x80) {
            deviceCode = 0
            when (b[2]) {
                0x98 -> eventStr = "DIM"
                0x88 -> eventStr = "BRI"
                0x90 -> eventStr = "ALL LTS ON"
                0x80 -> eventStr = "ALL OFF"
            }
        } else {
            eventStr = if (state != 0) "ON" else "OFF"
        }
        return listOf(
            Reading(
                "X10-RF",
                deviceCode.toString(),
                mapOf(
                    "channel" to housecode,
                    "state" to eventStr,
                    "data" to code,
                ),
            ),
        )
    }
}

// unverified: x10_sec.c (x10_sec_callback), struct X10_SEC
internal object X10Sec : Rtl433Decoder() {
    override val name = "X10 Security"
    override val mod = Mod.OOK_PPM
    override val short = 562
    override val long = 1687
    override val gap = 2200
    override val reset = 6000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 2) return emptyList()
        if (bb.bitsPerRow[1] < 41) return emptyList()
        val b = bb.bb[1]
        if ((b[0] xor b[1]) != 0x0f || (b[2] xor b[3]) != 0xff) return emptyList()
        var parity = b[0] xor b[1] xor b[2] xor b[3] xor b[4] xor (b[5] and 0x80)
        parity = (parity shr 4) xor (parity and 0xf)
        parity = (parity shr 2) xor (parity and 0x3)
        parity = (parity shr 1) xor (parity and 0x1)
        if (parity != 0) return emptyList()
        val batteryLow = b[2] and 0x01
        var eventStr = "UNKNOWN"
        var delay = 0
        var tamper = 0
        when (b[2] and 0xfe) {
            0x00, 0x04, 0x40, 0x44 -> {
                eventStr = "DOOR/WINDOW OPEN"
                delay = if ((b[2] and 0x04) != 0) 0 else 1
                tamper = (b[2] and 0x40) shr 6
            }
            0x80, 0x84, 0xc0, 0xc4 -> {
                eventStr = "DOOR/WINDOW CLOSED"
                delay = if ((b[2] and 0x04) != 0) 0 else 1
                tamper = (b[2] and 0x40) shr 6
            }
            0x06 -> eventStr = "KEY-FOB ARM"
            0x0c, 0x4c -> {
                eventStr = "MOTION TRIPPED"
                tamper = (b[2] and 0x40) shr 6
            }
            0x26 -> eventStr = "KR18 PANIC"
            0x42 -> eventStr = "KEY-FOB LIGHTS A ON"
            0x46 -> eventStr = "KEY-FOB LIGHTS B ON"
            0x82 -> eventStr = "SH624 SEC-REMOTE DISARM"
            0x86 -> eventStr = "KEY-FOB DISARM"
            0x88 -> eventStr = "KR15 PANIC"
            0x8c, 0xcc -> {
                eventStr = "MOTION READY"
                tamper = (b[2] and 0x40) shr 6
            }
            0x98 -> eventStr = "KR15 PANIC-3SECOND"
            0xc2 -> eventStr = "KEY-FOB LIGHTS A OFF"
            0xc6 -> eventStr = "KEY-FOB LIGHTS B OFF"
        }
        val idStr = String.format("%02x%02x", b[0], b[4])
        val codeStr = String.format("%02x", b[2])
        val fields = linkedMapOf<String, Any?>(
            "code" to codeStr,
            "event" to eventStr,
        )
        if (delay != 0) fields["delay"] = delay
        if (batteryLow != 0) fields["battery_ok"] = 0
        if (tamper != 0) fields["tamper"] = tamper
        return listOf(Reading("X10-Security", idStr, fields))
    }
}

// unverified: watts_wfht_rf.c (watts_wfht_rf_decode), struct watts_wfht_rf.c
internal object WattsWfhtRf : Rtl433Decoder() {
    override val name = "Watts WFHT-RF / WFHC-MASTERH&C-RF underfloor heating thermostat"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 460
    override val reset = 900

    override fun decode(bb: BitBuffer): List<Reading> {
        val syncPattern = intArrayOf(0xD3, 0x91, 0xD3, 0x91)
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] < 32 + 128) return emptyList()
        var offset = bb.search(0, 0, syncPattern, 32)
        offset += 32
        if (offset + 128 > bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(16)
        bb.extractBytes(0, offset, b, 128)
        if (b[0] != 0x0D) return emptyList()
        if (b[1] != 0xFF || b[2] != 0xFF || b[3] != 0xFE) return emptyList()
        if ((b[4] and 0xFC) != 0) return emptyList()
        if (b[5] == 0 && b[6] == 0 && b[7] == 0) return emptyList()
        val crc8Calc = Rtl433BitUtil.crc8(b, 12, 0xE6, 0x00) xor 0xBE xor b[12]
        if (crc8Calc != b[13]) return emptyList()
        val crc16Calc = Rtl433BitUtil.crc16(b, 14, 0x8005, 0xFFFF)
        val crc16Recv = (b[14] shl 8) or b[15]
        if (crc16Calc != crc16Recv) return emptyList()
        val idStr = String.format("%02X:%02X:%02X", b[5], b[6], b[7])
        val mode = if ((b[4] and 0x02) != 0) "heat" else "cool"
        val pairing = if ((b[4] and 0x01) != 0) "true" else "false"
        val callForHeat = if (b[12] == 0x64) 100 else 0
        val tempRaw = s16((b[8] shl 8) or b[9])
        val setpointRaw = s16((b[10] shl 8) or b[11])
        val temperatureC = (tempRaw / 10.0).toFloat().toDouble()
        val setpointC = (setpointRaw / 10.0).toFloat().toDouble()
        return listOf(
            Reading(
                "Watts-WFHTLCDRF",
                idStr,
                mapOf(
                    "mode" to mode,
                    "pairing" to pairing,
                    "temperature_C" to temperatureC,
                    "setpoint_C" to setpointC,
                    "call_for_heat" to callForHeat,
                ),
            ),
        )
    }
}

// unverified: watts_vision.c (watts_vision_decode, watts_vision_setpoint_mode_str, watts_vision_sensor_mode_str), struct watts_vision.c
internal object WattsVision : Rtl433Decoder() {
    override val name = "Watts Vision thermostat (-f 868.3M)"
    override val mod = Mod.FSK_PCM
    override val short = 26
    override val long = 26
    override val reset = 1000

    private fun setpointModeStr(mode: Int): String = when (mode) {
        0x00 -> "Comfort"
        0x01 -> "Off"
        0x02 -> "Anti-freeze"
        0x03 -> "Reduced/ECO"
        0x04 -> "Boost/Timer"
        0x08 -> "Auto (Comfort phase)"
        0x0b -> "Auto (Reduced phase)"
        0x10 -> "Manual/Temporary"
        else -> "unknown"
    }

    private fun sensorModeStr(flags: Int): String = when (flags and 0x3) {
        0 -> "Amb"
        1 -> "FLR"
        2 -> "FLL"
        else -> "Air"
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0xaa, 0xd3, 0x91, 0xd3, 0x91)
        if (bb.numRows != 1) return emptyList()
        val row = 0
        val rowLen = bb.bitsPerRow[row]
        var bitpos = bb.search(row, 0, preamble, 40)
        if (bitpos >= rowLen) return emptyList()
        bitpos += 40
        if (bitpos + 8 > rowLen) return emptyList()
        val lenb = IntArray(1)
        bb.extractBytes(row, bitpos, lenb, 8)
        val length = lenb[0]
        if (length != 0x14 && length != 0x22) return emptyList()
        val totalBits = (length + 3) * 8
        if (bitpos + totalBits > rowLen) return emptyList()
        val b = IntArray(40)
        bb.extractBytes(row, bitpos, b, totalBits)
        val crcMdbCalc = Rtl433BitUtil.crc16lsb(b.copyOfRange(1, length), length - 2, 0xa001, 0xffff)
        val crcMdb = (b[length] shl 8) or b[length - 1]
        if (crcMdbCalc != crcMdb) return emptyList()
        val crcCmsCalc = Rtl433BitUtil.crc16(b, length + 1, 0x8005, 0xffff)
        val crcCms = (b[length + 1] shl 8) or b[length + 2]
        if (crcCmsCalc != crcCms) return emptyList()
        if (b[5] != 0xc6) return emptyList()
        val id = (b[1] shl 24) or (b[2] shl 16) or (b[3] shl 8) or b[4]
        val dest = (b[6] shl 24) or (b[7] shl 16) or (b[8] shl 8) or b[9]
        val idStr = String.format("%08x", id)
        val destStr = String.format("%08x", dest)
        val msgType = if (length == 0x14) "command" else "status"
        val fields = linkedMapOf<String, Any?>(
            "dest" to destStr,
            "msg_type" to msgType,
        )
        val recordsLen = length - 11
        var pos = 0
        while (pos < recordsLen) {
            val tag = b[10 + pos]
            if (tag == 0x00) break
            val valueLen = (tag shr 6) + 1
            if (pos + 1 + valueLen > recordsLen) break
            val base = 10 + pos + 1
            when (tag) {
                0x03 -> fields["association_id"] = b[base]
                0xdf -> fields["state_raw"] = String.format("%02x%02x%02x%02x", b[base], b[base + 1], b[base + 2], b[base + 3])
                0x3b -> fields["flags_raw"] = b[base]
                0x8d -> {
                    fields["report_flags_0"] = b[base]
                    fields["report_flags_1"] = b[base + 1]
                    fields["report_flags_2"] = b[base + 2]
                }
                0x8a -> {
                    val setpointRaw = (b[base] shl 8) or b[base + 1]
                    if (setpointRaw != 0x084c) fields["mode_setpoint_F"] = (setpointRaw / 10.0f).toDouble()
                    fields["setpoint_mode"] = setpointModeStr(b[base + 2])
                }
                0x4b -> {
                    val temperatureRaw = (b[base] shl 8) or b[base + 1]
                    if (temperatureRaw != 0x084c) fields["temperature_F"] = (temperatureRaw / 10.0f).toDouble()
                }
                0x5e -> {
                    val temperature2Raw = (b[base] shl 8) or b[base + 1]
                    if (temperature2Raw != 0x084c) fields["temperature_2_F"] = (temperature2Raw / 10.0f).toDouble()
                }
                0xcc -> {
                    val floorLimit1Raw = (b[base] shl 8) or b[base + 1]
                    val floorLimit2Raw = (b[base + 2] shl 8) or b[base + 3]
                    if (floorLimit1Raw != 0) fields["floor_limit_1_F"] = (floorLimit1Raw / 10.0f).toDouble()
                    if (floorLimit2Raw != 0) fields["floor_limit_2_F"] = (floorLimit2Raw / 10.0f).toDouble()
                }
                0x8e -> {
                    fields["setpoint_min_C"] = b[base]
                    fields["setpoint_max_C"] = b[base + 1]
                    fields["sensor_mode"] = sensorModeStr(b[base + 2])
                    fields["sensor_flags_raw"] = b[base + 2]
                }
                0x4c -> {
                    fields["diagnostic_code"] = b[base]
                    fields["diagnostic_flags"] = b[base + 1]
                }
            }
            pos += 1 + valueLen
        }
        return listOf(Reading("Watts-Vision", idStr, fields))
    }
}

internal object TwogigKey2e : Rtl433Decoder() {
    override val name = "2GIG-KEY2E-345 encrypted keyfob"
    override val mod = Mod.OOK_PCM
    override val short = 136
    override val long = 136
    override val reset = 408

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1 || bb.bitsPerRow[0] < 96) return emptyList()
        val rawLen = bb.bitsPerRow[0]
        val rawPos = bb.search(0, 0, intArrayOf(0x55, 0x55, 0x56), 24)
        if (rawPos + 24 >= rawLen) return emptyList()
        val decoded = BitBuffer()
        bb.manchesterDecode(0, rawPos + 24, decoded, 72)
        if (decoded.bitsPerRow[0] < 72) return emptyList()
        val b = IntArray(9) { decoded.bb[0][it] }
        if (b[4] != 0x25) return emptyList()
        val crcCalc = Rtl433BitUtil.crc16(b, 7, 0x8005, 0x4c57)
        val crcRecv = (b[7] shl 8) or b[8]
        if (crcCalc != crcRecv) return emptyList()
        val encId = String.format("%02x%02x%02x%02x", b[0], b[1], b[2], b[3])
        val encStatus = String.format("%02x%02x", b[5], b[6])
        return listOf(Reading("TwoGig-KEY2E345", null, mapOf(
            "encrypted_id" to encId,
            "encrypted_status" to encStatus,
            "mic" to "CRC",
        )))
    }
}

internal object Vivint : Rtl433Decoder() {
    override val name = "Vivint Door/Window Sensor, V-DW21R-345/V-DW11-345"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 150
    override val reset = 300

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        bb.invert()
        val pos = bb.search(0, 0, intArrayOf(0xff, 0xe0), 12) + 12
        val len = bb.bitsPerRow[0] - pos
        if (len < 80) return emptyList()
        val b = IntArray(11)
        bb.extractBytes(0, pos, b, 80)
        val eventType = b[0]
        val counter = (b[1] shl 8) or b[2]
        val flags = b[3]
        val id = (b[4] shl 24) or (b[5] shl 16) or (b[6] shl 8) or b[7]
        val crc = (b[8] shl 8) or b[9]
        if (id == 0 || id == -1) return emptyList()
        val crcValid = if (eventType == 0xd0) {
            crc == Rtl433BitUtil.crc16(b, 8, 0x8050, 0)
        } else {
            val b8Full = b[8]
            b[8] = b[8] and 0xF0
            val crcFull = Rtl433BitUtil.crc16(b, 9, 0x8050, 0)
            b[8] = b8Full
            (crcFull shr 4) == (((b8Full and 0x0F) shl 8) or b[9])
        }
        if (!crcValid) return emptyList()
        val idStr = "%04d-%07d".format((id ushr 20) and 0xfff, id and 0xfffff)
        val payload = (0 until 10).joinToString("") { "%02x".format(b[it]) }
        return listOf(Reading("Vivint-Security", idStr, mapOf(
            "counter" to "%04x".format(counter),
            "flags" to "%02x".format(flags),
            "event_type" to "%02x".format(eventType),
            "data" to payload,
            "mic" to "CRC",
        )))
    }
}

internal val BATCH_09: List<Rtl433Decoder> = listOf(
    TpmsToyota,
    TpmsTruck,
    TpmsTrwFsk,
    TpmsTrwOok,
    TpmsTyreguard400,
    Tr502msv,
    TsFt002,
    Ttx201,
    TwogigKey2e,
    TyphurSyncGold,
    Universalfanctrl,
    VaillantVrt340f,
    VaunoEn8822c,
    Vevor7in1,
    VisonicPowercode,
    Vivint,
    WallargeCltx001,
    WatchmanPlus,
    WattsThermostat,
    WattsVision,
    WattsWfhtRf,
    Waveman,
    Wec2103,
    WgPb12v1,
    Ws2032,
    Wssensor,
    Wt1024,
    Wt450,
    X10Rf,
    X10Sec,
    YaleHsa,
)

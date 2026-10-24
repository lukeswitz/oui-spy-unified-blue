// Kotlin transcription of rtl_433 device decoders (batch 06). GPL-3 reference; constants, bit offsets and CRC parameters transcribed as facts.
package com.rootdowndigital.ouispy.wifiadapter

private fun rv8(x: Int): Int {
    var v = x and 0xFF
    v = ((v and 0xF0) shr 4) or ((v and 0x0F) shl 4)
    v = ((v and 0xCC) shr 2) or ((v and 0x33) shl 2)
    v = ((v and 0xAA) shr 1) or ((v and 0x55) shl 1)
    return v and 0xFF
}

private fun reflectBytes(b: IntArray, n: Int) {
    for (i in 0 until n) b[i] = rv8(b[i])
}

private fun s16(x: Int): Int = x.toShort().toInt()

private fun crc4(msg: IntArray, nBytes: Int, polynomial: Int, init: Int): Int {
    var remainder = init shl 4
    val poly = polynomial shl 4
    for (i in 0 until nBytes) {
        remainder = remainder xor (msg[i] and 0xFF)
        for (bit in 0 until 8) {
            remainder = if ((remainder and 0x80) != 0) (remainder shl 1) xor poly else remainder shl 1
        }
    }
    return (remainder ushr 4) and 0x0f
}

private fun uart8o1(message: IntArray, offsetIn: Int, numBitsIn: Int, dst: IntArray): Int {
    var offset = offsetIn
    var numBits = numBitsIn
    var ret = 0
    var d = 0
    while (numBits >= 11) {
        val startb = message[offset / 8] shr (7 - (offset % 8))
        offset += 1
        var datab = message[offset / 8]
        if (offset % 8 != 0) {
            datab = (message[offset / 8] shl 8) or message[offset / 8 + 1]
            datab = datab shr (8 - (offset % 8))
        }
        offset += 8
        val parityb = message[offset / 8] shr (7 - (offset % 8))
        offset += 1
        val stopb = message[offset / 8] shr (7 - (offset % 8))
        offset += 1
        val dataParity = Rtl433BitUtil.parity8(datab)
        if ((startb and 1) != 1) break
        if ((parityb and 1) != dataParity) break
        if ((stopb and 1) != 0) break
        dst[d++] = datab and 0xff
        ret += 1
        numBits -= 11
    }
    return ret
}

private fun grayDecode(n: Int): Int {
    var m = n
    var p = n
    while (true) {
        m = m shr 1
        if (m == 0) break
        p = p xor m
    }
    return p
}

private fun oriaNibble(m: IntArray, k: Int): Int {
    val byte = m[k / 2]
    return if (k % 2 == 0) (byte shr 4) and 0x0f else byte and 0x0f
}

private fun oriaReflect4(n: Int): Int =
    ((n and 0x1) shl 3) or ((n and 0x2) shl 1) or ((n and 0x4) shr 1) or ((n and 0x8) shr 3)

private val RH_ASK_SYMBOLS = intArrayOf(
    0x0d, 0x0e, 0x13, 0x15, 0x16, 0x19, 0x1a, 0x1c,
    0x23, 0x25, 0x26, 0x29, 0x2a, 0x2c, 0x32, 0x34,
)

private fun rhSymbol6to4(symbol: Int): Int {
    var i = (symbol shr 2) and 8
    while (i < 16) {
        if (symbol == RH_ASK_SYMBOLS[i]) return i
        i++
    }
    return 0xFF
}

private fun rhAskExtract(bb: BitBuffer, row: Int, payload: IntArray): Int {
    val len = bb.bitsPerRow[row]
    var msgLen = 60
    val initPattern = intArrayOf(0x55, 0x55, 0x55, 0x51, 0xcd)
    var pos = bb.search(row, 0, initPattern, 40)
    if (pos == len) return -1
    var nbBytes = 0
    pos += 40
    val rxBits = IntArray(2)
    while (pos < len && nbBytes < msgLen) {
        bb.extractBytes(row, pos, rxBits, 16)
        rxBits[0] = rv8(rxBits[0])
        rxBits[1] = rv8(rxBits[1])
        rxBits[1] = ((rxBits[1] and 0x0F) shl 2) + (rxBits[0] shr 6)
        rxBits[0] = rxBits[0] and 0x3F
        val hi = rhSymbol6to4(rxBits[0])
        if (hi > 0xF) return -1
        val lo = rhSymbol6to4(rxBits[1])
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

private fun proflame2Mc(bb: BitBuffer, row: Int, start: Int, out: IntArray): Int {
    val b = bb.bb[row]
    var pos = start
    var f = 0
    while (true) {
        if (bb.bitsPerRow[row] - pos < 26) return f
        val sync = (bitrowGetBit(b, pos + 0) shl 3) or
            (bitrowGetBit(b, pos + 1) shl 2) or
            (bitrowGetBit(b, pos + 2) shl 1) or
            (bitrowGetBit(b, pos + 3) shl 0)
        pos += 4
        if (sync != 0xe) return f
        val decoded = BitBuffer()
        pos = bb.manchesterDecode(row, pos, decoded, 11)
        if (decoded.bitsPerRow[0] != 11) return f
        val data = decoded.bb[0][0] xor 0xff
        val flag = decoded.bb[0][1] xor 0xe0
        val pad = (flag shr 7) and 1
        val par = (flag shr 6) and 1
        val end = (flag shr 5) and 1
        if (pad != (if (f == 0) 1 else 0)) return f
        val parChk = Rtl433BitUtil.parity8(data) xor pad xor par
        if (parChk != 0) return f
        if (end != 1) return f
        if (f >= out.size) return f
        out[f] = data
        f++
    }
}

private fun oilStandardDecodeAt(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
    val smartPreamble = intArrayOf(0x55, 0x55, 0x58)
    if (bitpos >= 24 && bb.search(row, bitpos - 24, smartPreamble, 24) == bitpos - 24) return null
    val databits = BitBuffer()
    bb.manchesterDecode(row, bitpos, databits, 41)
    if (databits.bitsPerRow[0] < 32 || databits.bitsPerRow[0] > 40 || (databits.bb[0][4] and 0xfe) != 0) return null
    val b = databits.bb[0]
    val unitId = (b[0] shl 8) or b[1]
    val flags = b[2] and 0x0A.inv()
    val alarm = (b[2] and 0x08) shr 3
    var depth = 0
    var bindingCountdown = 0
    if ((flags and 1) != 0) {
        bindingCountdown = b[3]
    } else {
        depth = ((b[2] and 0x02) shl 7) or b[3]
        if (depth > 305) return null
    }
    return Reading(
        "Oil-SonicStd",
        String.format("%04x", unitId),
        mapOf(
            "flags" to flags,
            "alarm" to alarm,
            "binding_countdown" to bindingCountdown,
            "depth_cm" to depth,
        ),
    )
}

private fun oilStandardCallback(bb: BitBuffer): List<Reading> {
    val preamble0 = intArrayOf(0x55, 0x5D)
    val preamble1 = intArrayOf(0x55, 0x62)
    val out = ArrayList<Reading>()
    var bitpos = 0
    while (true) {
        bitpos = bb.search(0, bitpos, preamble0, 16)
        if (bitpos + 78 > bb.bitsPerRow[0]) break
        oilStandardDecodeAt(bb, 0, bitpos + 14)?.let { out.add(it) }
        bitpos += 2
    }
    bitpos = 0
    while (true) {
        bitpos = bb.search(0, bitpos, preamble1, 16)
        if (bitpos + 78 > bb.bitsPerRow[0]) break
        oilStandardDecodeAt(bb, 0, bitpos + 14)?.let { out.add(it) }
        bitpos += 2
    }
    return out
}

private fun orionEndpointDecode(bb: BitBuffer): List<Reading> {
    val preamble = intArrayOf(0xaa, 0xaa, 0xec, 0x62, 0xec, 0x62)
    val ibmWhitenKey = intArrayOf(
        0xff, 0xe1, 0x1d, 0x9a, 0xed, 0x85, 0x33, 0x24, 0xea, 0x7a, 0xd2, 0x39,
        0x70, 0x97, 0x57, 0x0a, 0x54, 0x7d, 0x2d, 0xd8, 0x6d, 0x0d, 0xba,
    )
    if (bb.numRows > 1) return emptyList()
    val msgLen = bb.bitsPerRow[0]
    if (msgLen < 232 || msgLen > 290) return emptyList()
    var offset = bb.search(0, 0, preamble, 48)
    if (offset >= msgLen) return emptyList()
    offset += 48
    if (msgLen - offset < 184) return emptyList()
    val b = IntArray(23)
    bb.extractBytes(0, offset, b, 184)
    for (i in 0 until 23) b[i] = b[i] xor ibmWhitenKey[i]
    if (Rtl433BitUtil.crc16(b, 23, 0x8005, 0xffff) != 0) return emptyList()
    val id = (((b[8] shl 24) or (b[7] shl 16) or (b[6] shl 8) or b[5]).toLong()) and 0xFFFFFFFFL
    val flags1 = (b[9] shl 16) or (b[10] shl 8) or b[11]
    val leaking = (b[10] and 0x20) shr 5
    val readingRaw = (((b[15] shl 24) or (b[14] shl 16) or (b[13] shl 8) or b[12]).toLong()) and 0xFFFFFFFFL
    val dailyRaw = (((b[19] shl 24) or (b[18] shl 16) or (b[17] shl 8) or b[16]).toLong()) and 0xFFFFFFFFL
    val flags2 = b[20]
    val endpointModel = when {
        id in 30000000L..59999999L -> "ME or SE"
        id in 60000000L..69999999L -> "Mobile M"
        id in 70000000L..89999999L -> "Classic (CE)"
        id in 110000000L..119999999L -> "LTE"
        id in 120000000L..129999999L -> "LTE-M or LTE-MS"
        id in 130000000L..139999999L -> "C or CS"
        id in 140000000L..148999999L -> "HLA"
        id in 149000000L..149999999L -> "HLC"
        id in 150000000L..159999999L -> "HLB"
        id in 160000000L..169999999L -> "HLD"
        id in 170000000L..179999999L -> "HLFX"
        id in 180000000L..189999999L -> "HLG"
        else -> "Unknown Model"
    }
    val fields = linkedMapOf<String, Any?>(
        "endpoint_model" to endpointModel,
        "leaking" to leaking,
        "reading" to readingRaw,
    )
    if (dailyRaw != 0L) fields["daily_reading"] = dailyRaw
    fields["flags_1"] = flags1
    fields["flags_2"] = flags2
    fields["mic"] = "CRC"
    return listOf(Reading("Orion-Endpoint", id.toString(), fields))
}

// unverified: oil_standard.c:43-141 (oil_standard_decode, oil_standard_callback)
internal object OilStandard : Rtl433Decoder() {
    override val name = "Oil Ultrasonic STANDARD FSK"
    override val mod = Mod.FSK_PCM
    override val short = 500
    override val long = 500
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> = oilStandardCallback(bb)
}

// unverified: oil_standard.c:153-170 (shares oil_standard_callback with OilStandard)
internal object OilStandardAsk : Rtl433Decoder() {
    override val name = "Oil Ultrasonic STANDARD ASK"
    override val mod = Mod.OOK_PCM
    override val short = 500
    override val long = 500
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> = oilStandardCallback(bb)
}

// unverified: oil_watchman.c:21-99
internal object OilWatchman : Rtl433Decoder() {
    override val name = "Watchman Sonic / Apollo Ultrasonic / Beckett Rocket oil tank monitor"
    override val mod = Mod.FSK_PCM
    override val short = 1000
    override val long = 1000
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, intArrayOf(0xe0), 6)
            if (bitpos + 136 > bb.bitsPerRow[0]) break
            bitpos += 6
            val databits = BitBuffer()
            bitpos = bb.manchesterDecode(0, bitpos, databits, 64)
            if (databits.bitsPerRow[0] != 64) continue
            val b = databits.bb[0]
            val postamble = if ((b[7] and 1) == 0) 0x00 else 0xc0
            if (bb.search(0, bitpos, intArrayOf(postamble), 2) != bitpos) continue
            if (b[7] != Rtl433BitUtil.crc8le(b, 7, 0x31, 0)) continue
            val unitId = (b[0] shl 24) or (b[1] shl 16) or (b[2] shl 8) or b[3]
            val flags = b[4]
            val maybetemp = b[5] shr 2
            val temperature = (145.0 - 5.0 * maybetemp) / 3.0
            var depth = 0
            var bindingCountdown = 0
            if ((flags and 1) != 0) {
                bindingCountdown = b[6]
            } else {
                depth = ((b[5] and 3) shl 8) or b[6]
            }
            out.add(
                Reading(
                    "Oil-SonicSmart",
                    String.format("%06x", unitId),
                    mapOf(
                        "flags" to flags,
                        "maybetemp" to maybetemp,
                        "temperature_C" to temperature,
                        "binding_countdown" to bindingCountdown,
                        "depth_cm" to depth,
                    ),
                ),
            )
        }
        return out
    }
}

// unverified: oil_watchman_advanced.c:69-132
internal object OilWatchmanAdvanced : Rtl433Decoder() {
    override val name = "Watchman Sonic Advanced / Plus, Tekelek"
    override val mod = Mod.FSK_PCM
    override val short = 500
    override val long = 500
    override val reset = 12500

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        val preamble = intArrayOf(0xaa, 0xaa, 0xaa, 0x2d, 0xd4, 0x0e)
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, preamble, 48)
            if (bitpos + 128 + 1 > bb.bitsPerRow[0]) break
            bitpos += 40
            val b = IntArray(18)
            bb.extractBytes(0, bitpos, b, 128 + 8 + 1)
            bitpos += 128 + 8
            val crcMsg = (b[15] shl 8) or b[16]
            val crcCalc = Rtl433BitUtil.crc16(b, 15, 0x8005, 0)
            if (crcCalc != crcMsg) {
                val crcMsg2 = ((b[15] shl 9) or (b[16] shl 1) or (b[17] shr 7)) and 0xFFFF
                if (crcCalc != crcMsg2) return out
            }
            val mcode = (b[1] shl 8) or b[2]
            if (mcode != 0x0401 && mcode != 0x0106 && mcode != 0x0101) return out
            val serial = (b[3] shl 16) or (b[4] shl 8) or b[5]
            val status = b[6]
            val temperature = ((b[7] - 0x48) / 2).toDouble()
            val depth = ((b[9] and 0x0f) shl 8) or b[10]
            val version = "${b[11] and 0x0f}.${b[12] and 0x0f}.${b[13] and 0x0f}.${b[14] and 0x0f}"
            out.add(
                Reading(
                    "Oil-SonicAdv",
                    String.format("%08d", serial),
                    mapOf(
                        "version" to version,
                        "temperature_C" to temperature,
                        "depth_cm" to depth,
                        "status" to status,
                        "mic" to "CRC",
                    ),
                ),
            )
        }
        return out
    }
}

// unverified: olympia_9571.c:50-142
internal object Olympia9571 : Rtl433Decoder() {
    override val name = "Olympia Protect 9571 alarm system sensors"
    override val mod = Mod.FSK_PCM
    override val short = 366
    override val long = 366
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        var bitOffset = bb.search(0, 0, intArrayOf(0xAA, 0x2D, 0xD4), 24)
        if (bitOffset >= bb.bitsPerRow[0]) return emptyList()
        bitOffset += 24
        if (bitOffset + 48 > bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(6)
        bb.extractBytes(0, bitOffset, b, 48)
        val id = (b[0] shl 16) or (b[1] shl 8) or b[2]
        val markerA = (b[3] shr 4) and 0x0f
        val markerB = b[3] and 0x07
        val battWeak = (b[4] shr 7) and 0x01
        val deviceClass = (b[4] shr 4) and 0x07
        val sensorType = (b[4] shr 1) and 0x07
        val sensorState = b[4] and 0x01
        if (markerA != 0x8 || markerB != 0x6) return emptyList()
        if ((Rtl433BitUtil.addBytes(b, 5) and 0xff) != b[5]) return emptyList()
        var subtype: String? = null
        var state: String? = null
        var cmd: String? = null
        var hasState = false
        var hasCmd = false
        var cmdId = 0
        if (deviceClass == 0x0) {
            if (sensorType == 0x4) {
                subtype = "Contact"
                state = if (sensorState != 0) "open" else "closed"
                hasState = true
            } else if (sensorType == 0x7) {
                subtype = "PIR-Motion"
                state = if (sensorState != 0) "motion" else "idle"
                hasState = true
            }
        } else if (deviceClass == 0x1) {
            subtype = "Keyfob"
            hasCmd = true
            cmdId = sensorType
            cmd = when (cmdId) {
                0x3 -> "Disarm"
                0x4 -> "Arm Home + Siren"
                0x5 -> "Arm Siren Only"
                0x6 -> "Arm Home Only"
                0x7 -> "SOS"
                else -> "Unknown"
            }
        }
        if (subtype == null) return emptyList()
        val fields = linkedMapOf<String, Any?>(
            "subtype" to subtype,
            "battery_ok" to (if (battWeak != 0) 0 else 1),
            "mic" to "CHECKSUM",
        )
        if (hasState) fields["state"] = state
        if (hasCmd) {
            fields["cmd"] = cmd
            fields["cmd_id"] = cmdId
        }
        return listOf(Reading("Olympia-9571", String.format("%06x", id), fields))
    }
}

// unverified: omni.c:113-214
internal object Omni : Rtl433Decoder() {
    override val name = "Omni Multisensor"
    override val mod = Mod.OOK_PWM
    override val short = 200
    override val long = 400
    override val sync = 600
    override val gap = 500
    override val reset = 1250

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(2, 80)
        if (r < 0 || bb.bitsPerRow[r] > 82) return emptyList()
        val b = bb.bb[r]
        if (Rtl433BitUtil.crc8(b, 9, 0x97, 0xaa) != b[9]) return emptyList()
        val messageFmt = b[0] shr 4
        val id = b[0] and 0x0F
        val hexstring = (1..8).joinToString("") { String.format("%02x", b[it]) }
        val fields = linkedMapOf<String, Any?>()
        when (messageFmt) {
            0 -> {
                val itemp = ((s16((b[1] shl 8) or b[2]) shr 4).toDouble() * 0.10).toFloat().toDouble()
                val volts = (b[8].toDouble() * 0.01 + 3.00).toFloat().toDouble()
                fields["channel"] = messageFmt
                fields["temperature_C"] = itemp
                fields["voltage_V"] = volts
                fields["payload"] = hexstring
                fields["mic"] = "CRC"
            }
            1 -> {
                val itemp = ((s16((b[1] shl 8) or b[2]) shr 4).toDouble() * 0.10).toFloat().toDouble()
                val otemp = ((s16((b[2] shl 12) or (b[3] shl 4)) shr 4).toDouble() * 0.10).toFloat().toDouble()
                val ihum = b[4].toDouble()
                val light = b[5].toDouble()
                val press = (((b[6] shl 8) or b[7]).toDouble() * 0.10).toFloat().toDouble()
                val volts = (b[8].toDouble() * 0.01 + 3.00).toFloat().toDouble()
                fields["channel"] = messageFmt
                fields["temperature_C"] = itemp
                fields["temperature_2_C"] = otemp
                fields["humidity"] = ihum
                fields["light_pct"] = light
                fields["pressure_hPa"] = press
                fields["voltage_V"] = volts
                fields["mic"] = "CRC"
            }
            else -> {
                fields["channel"] = messageFmt
                fields["payload"] = hexstring
                fields["mic"] = "CRC"
            }
        }
        return listOf(Reading("Omni-Multisensor", id.toString(), fields))
    }
}

// unverified: opel_mokka.c:40-97
internal object OpelMokka : Rtl433Decoder() {
    override val name = "Opel Mokka Car Key"
    override val mod = Mod.FSK_MC_ZEROBIT
    override val short = 100
    override val long = 100
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (i in 0 until bb.numRows) {
            if (bb.bitsPerRow[i] != 268) continue
            val b = bb.bb[i]
            if ((0..10).any { b[it] != 0 }) continue
            val tempId = IntArray(2)
            bb.extractBytes(i, 90, tempId, 11)
            val keyId = (tempId[0] shl 3) or (tempId[1] shr 5)
            bb.extractBytes(i, 90 + 12 * 8 + 1, tempId, 11)
            val checkId = (tempId[0] shl 3) or (tempId[1] shr 5)
            if (keyId != checkId) continue
            if (keyId == 0) continue
            val eventType = ((b[12] and 0x07) shl 2) or ((b[13] and 0xc0) shr 6)
            val code = IntArray(8)
            bb.extractBytes(i, 90 + 17, code, 64)
            out.add(
                Reading(
                    "Opel-Mokka",
                    keyId.toString(),
                    mapOf("event" to eventType, "code" to bitrowSnprint(code, 64)),
                ),
            )
        }
        return out
    }
}

// unverified: opus_xt300.c:33-96
internal object OpusXt300 : Rtl433Decoder() {
    override val name = "Opus/Imagintronix XT300 Soil Moisture"
    override val mod = Mod.OOK_PWM
    override val short = 544
    override val long = 932
    override val gap = 10000
    override val reset = 31000

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            if (bb.bitsPerRow[row] != 48) continue
            val b = bb.bb[row]
            if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0) continue
            if (b[0] != 0xFF && ((b[1] or 0x1) and 0xFD) == 0x55) continue
            val chk = Rtl433BitUtil.addBytes(b.copyOfRange(1, 5), 4) and 0xFF
            if (chk != 0 && chk != b[5]) continue
            val channel = b[1] and 0x03
            val temp = b[3] - 40
            val moisture = b[2]
            if (temp > 100 || moisture > 101) continue
            out.add(
                Reading(
                    "Opus-XT300",
                    null,
                    mapOf(
                        "channel" to channel,
                        "temperature_C" to temp.toDouble(),
                        "moisture" to moisture,
                        "mic" to "CHECKSUM",
                    ),
                ),
            )
        }
        return out
    }
}

// unverified: oregon_scientific_sl109h.c:30-111
internal object OregonScientificSl109h : Rtl433Decoder() {
    override val name = "Oregon Scientific SL109H Remote Thermal Hygro Sensor"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 5000
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        val rowIndex = bb.findRepeatedRow(2, 38)
        if (rowIndex < 0 || bb.bitsPerRow[rowIndex] != 38) return emptyList()
        val msg = bb.bb[rowIndex]
        if (msg[0] == 0 && msg[1] == 0 && msg[2] == 0 && msg[3] == 0) return emptyList()
        val chk = msg[0] shr 4
        val b = IntArray(5)
        bb.extractBytes(rowIndex, 2, b, 36)
        b[0] = b[0] and 0x3f
        if (chk == 0 && b[0] == 0 && b[1] == 0 && b[2] == 0) return emptyList()
        val sum = Rtl433BitUtil.addNibbles(b, 5) and 0xf
        if (sum != chk) return emptyList()
        val channelCode = b[0] shr 4
        if (channelCode == 3) return emptyList()
        val channel = if (channelCode != 0) channelCode else 3
        val humTens = b[0] and 0x0f
        val humOnes = b[1] shr 4
        if (humTens > 9 || humOnes > 9) return emptyList()
        val humidity = 10 * humTens + humOnes
        val tempRaw = s16((b[1] and 0x0f) shl 12) or (b[2] shl 4)
        val tempC = (tempRaw shr 4) * 0.1f
        if (tempC < -20 || tempC > 60) return emptyList()
        val status = b[3] shr 4
        val id = ((b[3] and 0x0f) shl 4) or (b[4] shr 4)
        return listOf(
            Reading(
                "Oregon-SL109H",
                id.toString(),
                mapOf(
                    "channel" to channel,
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "status" to status,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: oregon_scientific_v1.c:27-94
internal object OregonScientificV1 : Rtl433Decoder() {
    override val name = "OSv1 Temperature Sensor"
    override val mod = Mod.OOK_PWM_OSV1
    override val short = 1465
    override val sync = 5780
    override val gap = 3500
    override val reset = 14000

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            if (bb.bitsPerRow[row] != 32) continue
            val raw = bb.bb[row]
            val nibble = IntArray(8)
            var rawCs = 0
            for (i in 0 until 4) {
                val byte = rv8(raw[i])
                nibble[i * 2] = byte and 0x0f
                nibble[i * 2 + 1] = byte shr 4
                if (i < 3) rawCs += nibble[i * 2] + 16 * nibble[i * 2 + 1]
            }
            if (raw[0] == 0xFF && raw[1] == 0xFF && raw[2] == 0xFF && raw[3] == 0xFF) continue
            val checksum = nibble[6] + (nibble[7] shl 4)
            val csFold = (rawCs and 0xFF) + (rawCs shr 8)
            val csAlt = (if (rawCs > 0x180) rawCs + 1 else rawCs) and 0xFF
            if (checksum == 0 || (checksum != csFold && checksum != csAlt)) continue
            val sid = nibble[0]
            val channel = ((nibble[1] shr 2) and 0x03) + 1
            var tempC = nibble[2] * 0.1f + nibble[3] + nibble[4] * 10.0f
            val battery = (nibble[5] shr 3) and 0x01
            val sign = (nibble[5] shr 1) and 0x01
            if (sign != 0) tempC = -tempC
            out.add(
                Reading(
                    "Oregon-v1",
                    sid.toString(),
                    mapOf(
                        "channel" to channel,
                        "battery_ok" to (if (battery != 0) 0 else 1),
                        "temperature_C" to tempC.toDouble(),
                        "mic" to "CHECKSUM",
                    ),
                ),
            )
        }
        return out
    }
}

// unverified: oregon_scientific_wmr500.c:81-158 (temperature fit is an estimate per the source header)
internal object OregonScientificWmr500 : Rtl433Decoder() {
    override val name = "Oregon Scientific WMR500 weather station"
    override val mod = Mod.FSK_PCM
    override val short = 26
    override val long = 26
    override val reset = 312

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0x55, 0x2c, 0x6e, 0x2c, 0x6e)
        if (bb.numRows != 1) return emptyList()
        bb.invert()
        val rowLen = bb.bitsPerRow[0]
        var pos = bb.search(0, 0, preamble, 40)
        if (pos >= rowLen) return emptyList()
        pos += 40
        if (pos + 8 > rowLen) return emptyList()
        val b = IntArray(28)
        var availBytes = (rowLen - pos) / 8
        if (availBytes > 28) availBytes = 28
        bb.extractBytes(0, pos, b, availBytes * 8)
        val len = b[0]
        val totalBytes: Int
        val crcInit: Int
        if (len == 14) {
            totalBytes = 17
            crcInit = 0x4ed0
        } else if (len == 25) {
            totalBytes = 28
            crcInit = 0x1a4c
        } else {
            return emptyList()
        }
        if (availBytes < totalBytes) return emptyList()
        val crcCalc = Rtl433BitUtil.crc16(b, totalBytes - 2, 0x8005, crcInit)
        val crcMsg = (b[totalBytes - 2] shl 8) or b[totalBytes - 1]
        if (crcCalc != crcMsg) return emptyList()
        if (len == 14) return emptyList()
        val deviceId = (b[8] shl 8) or b[9]
        val humidity = 208 - b[16]
        if (humidity < 0 || humidity > 100) return emptyList()
        val temperatureC = (b[14].toFloat() - 169.0f) * 0.7f
        return listOf(
            Reading(
                "Oregon-WMR500",
                String.format("%04x", deviceId),
                mapOf(
                    "temperature_C" to temperatureC.toDouble(),
                    "humidity" to humidity,
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: oria_wa150km.c:70-149 (priority 10 not represented in API)
internal object OriaWa150km : Rtl433Decoder() {
    override val name = "Oria WA150KM freezer and fridge thermometer"
    override val mod = Mod.OOK_PCM
    override val short = 490
    override val long = 490
    override val gap = 1500
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        var r = -1
        for (rr in 0 until bb.numRows) {
            if (bb.bitsPerRow[rr] == 227) {
                r = rr
                break
            }
        }
        if (r < 0) return emptyList()
        val raw = bb.bb[r]
        if (raw[0] != 0xAA || raw[1] != 0xAA || raw[2] != 0xAA) return emptyList()
        if (raw[bb.bitsPerRow[r] / 8 - 1] != 0x69) return emptyList()
        bb.invert()
        val manchester = BitBuffer()
        bb.manchesterDecode(r, 0, manchester, 227)
        val m = manchester.bb[0]
        var sum = 0
        for (i in 0 until 15) sum += oriaReflect4(oriaNibble(m, 7 + i))
        val chkCalc = sum and 0xff
        val chkRecv = oriaReflect4(oriaNibble(m, 22)) or (oriaReflect4(oriaNibble(m, 23)) shl 4)
        if (chkCalc != chkRecv) return emptyList()
        reflectBytes(manchester.bb[0], (manchester.bitsPerRow[0] + 7) / 8)
        val b = manchester.bb[0]
        val channel = ((b[5] shr 4) and 0x0F) + 1
        val deviceId = b[6]
        val temperature = (((b[8] shr 4) and 0x0F) * 10 + (b[8] and 0x0F)) + ((b[7] shr 4) and 0x0F) * 0.1f
        val tempSigned = if ((b[9] and 0x08) != 0) -temperature else temperature
        return listOf(
            Reading(
                "Oria-WA150KM",
                deviceId.toString(),
                mapOf(
                    "channel" to channel,
                    "temperature" to tempSigned.toDouble(),
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: badger_orion_endpoint.c:92-206 (shared decode, orion_endpoint variant)
internal object OrionEndpoint : Rtl433Decoder() {
    override val name = "Orion Endpoint from Badger Meter, GIF2014W-OSE, water meter, hopping from 904.4 Mhz to 924.6Mhz (-s 1600k)"
    override val mod = Mod.FSK_PCM
    override val short = 10
    override val long = 10
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> = orionEndpointDecode(bb)
}

// unverified: badger_orion_endpoint.c:92-206 (shared decode, orion_endpoint_2020 variant)
internal object OrionEndpoint2020 : Rtl433Decoder() {
    override val name = "Orion Endpoint from Badger Meter, GIF2020OCECNA, water meter, hopping from 904.4 Mhz to 924.6Mhz (-s 1600k)"
    override val mod = Mod.FSK_PCM
    override val short = 5
    override val long = 5
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> = orionEndpointDecode(bb)
}

// unverified: philips_aj3650.c:51-135
internal object PhilipsAj3650 : Rtl433Decoder() {
    override val name = "Philips outdoor temperature sensor (type AJ3650)"
    override val mod = Mod.OOK_PWM
    override val short = 2000
    override val long = 6000
    override val reset = 30000

    override fun decode(bb: BitBuffer): List<Reading> {
        val channelMap = intArrayOf(2, 0, 1, 0, 3)
        bb.invert()
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] != 112) return emptyList()
        val raw = bb.bb[0]
        if ((raw[0] shr 4) != 0x0) return emptyList()
        val packet = IntArray(4)
        for (i in 0 until 4) {
            val a = raw[i + 1]
            val b = ((raw[i + 5] shl 4) or ((raw[i + 6] shr 4) and 0xf)) and 0xff
            val c = raw[i + 10]
            packet[i] = (a and b) or (b and c) or (a and c)
        }
        val cCrc = crc4(packet, 4, 0x9, 1)
        if (cCrc != 0) return emptyList()
        var channel = packet[0] and 0x0f
        channel = if (channel >= channelMap.size) 0 else channelMap[channel]
        val tempRaw = (packet[1] shl 2) or (packet[2] shr 6)
        val temperature = (tempRaw - 500) * 0.1f
        val batteryLow = packet[3] and 0x40
        return listOf(
            Reading(
                "Philips-Temperature",
                null,
                mapOf(
                    "channel" to channel,
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "temperature_C" to temperature.toDouble(),
                ),
            ),
        )
    }
}

// unverified: philips_aj7010.c:41-113
internal object PhilipsAj7010 : Rtl433Decoder() {
    override val name = "Philips outdoor temperature sensor (type AJ7010)"
    override val mod = Mod.OOK_PWM
    override val short = 2000
    override val long = 6000
    override val sync = 1000
    override val reset = 30000

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] != 40) return emptyList()
        val b = bb.bb[0]
        if (b[0] == 0 && b[2] == 0 && b[3] == 0 && b[4] == 0) return emptyList()
        if (b[0] != 0x00) return emptyList()
        if (Rtl433BitUtil.xorBytes(b, 5) != 0 && (Rtl433BitUtil.xorBytes(b, 3) xor b[4]) != 0) return emptyList()
        val channel = when (b[1]) {
            0x36 -> 3
            0x45 -> 2
            0x5A -> 1
            else -> 0
        }
        val tempRaw = ((b[3] and 0x3f) shl 8) or b[2]
        val tempC = (tempRaw / 353.0f) - 9.2f
        return listOf(
            Reading(
                "Philips-AJ7010",
                null,
                mapOf(
                    "channel" to channel,
                    "temperature_C" to tempC.toDouble(),
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: proflame2.c:90-138
internal object Proflame2 : Rtl433Decoder() {
    override val name = "SmartFire Proflame 2 remote control"
    override val mod = Mod.OOK_PCM
    override val short = 417
    override val long = 417
    override val gap = 1000
    override val reset = 6000

    override fun decode(bb: BitBuffer): List<Reading> {
        for (row in 0 until bb.numRows) {
            val b = IntArray(64)
            val ret = proflame2Mc(bb, row, 0, b)
            if (ret != 7) continue
            val id = (b[0] shl 16) or (b[1] shl 8) or b[2]
            val cmd1 = b[3]
            val cmd2 = b[4]
            val err1 = b[5]
            val err2 = b[6]
            val pilot = b[3] shr 7
            val light = (b[3] and 0x70) shr 4
            val thermostat = (b[3] and 0x02) shr 1
            val power = b[3] and 0x01
            val front = b[4] shr 7
            val fan = (b[4] and 0x70) shr 4
            val aux = (b[4] and 0x08) shr 3
            val flame = b[4] and 0x07
            return listOf(
                Reading(
                    "Proflame2-Remote",
                    String.format("%06x", id),
                    mapOf(
                        "cmd1" to cmd1,
                        "cmd2" to cmd2,
                        "err1" to err1,
                        "err2" to err2,
                        "pilot" to pilot,
                        "light" to light,
                        "thermostat" to thermostat,
                        "power" to power,
                        "front" to front,
                        "fan" to fan,
                        "aux" to aux,
                        "flame" to flame,
                        "mic" to "CHECKSUM",
                    ),
                ),
            )
        }
        return emptyList()
    }
}

// unverified: prologue.c:35-88
internal object Prologue : Rtl433Decoder() {
    override val name = "Prologue, FreeTec NC-7104, NC-7159-675 temperature sensor"
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
            "battery_ok" to (if (battery != 0) 1 else 0),
            "temperature_C" to tempRaw * 0.1,
        )
        if (humidity != 0xcc) fields["humidity"] = humidity
        fields["button"] = button
        return listOf(Reading("Prologue-TH", id.toString(), fields))
    }
}

// unverified: proove.c:51-95
internal object Proove : Rtl433Decoder() {
    override val name = "Proove / Nexa / KlikAanKlikUit Wireless Switch"
    override val mod = Mod.OOK_PPM
    override val short = 270
    override val long = 1300
    override val sync = 2650
    override val tolerance = 200
    override val gap = 1500
    override val reset = 2800

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.syncsBeforeRow[0] != 1) return emptyList()
        if (bb.bitsPerRow[0] != 64) return emptyList()
        val databits = BitBuffer()
        bb.manchesterDecode(0, 0, databits, 80)
        if (databits.bitsPerRow[0] < 32) return emptyList()
        databits.invert()
        val b = databits.bb[0]
        val id = (b[0] shl 18) or (b[1] shl 10) or (b[2] shl 2) or (b[3] shr 6)
        val groupCmd = (b[3] shr 5) and 1
        val onBit = (b[3] shr 4) and 1
        val channel = ((b[3] shr 2) and 0x03) xor 0x03
        val unit = (b[3] and 0x03) xor 0x03
        return listOf(
            Reading(
                "Proove-Security",
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

// unverified: quhwa.c:21-56
internal object Quhwa : Rtl433Decoder() {
    override val name = "Quhwa"
    override val mod = Mod.OOK_PWM
    override val short = 360
    override val long = 1070
    override val gap = 1200
    override val sync = 0
    override val tolerance = 80
    override val reset = 6600

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(5, 18)
        if (r < 0) return emptyList()
        val b = bb.bb[r]
        if (b[0] == 0 && b[1] == 0 && b[2] == 0) return emptyList()
        b[0] = b[0].inv() and 0xFF
        b[1] = b[1].inv() and 0xFF
        b[2] = b[2].inv() and 0xFF
        if (bb.bitsPerRow[r] != 18 || (b[1] and 0x03) != 0x03 || (b[2] and 0xC0) != 0xC0) return emptyList()
        val id = (b[0] shl 8) or b[1]
        return listOf(Reading("Quhwa-Doorbell", id.toString(), emptyMap()))
    }
}

// unverified: quinetic.c:48-102 (upstream .disabled = 1, not represented in API)
internal object Quinetic : Rtl433Decoder() {
    override val name = "Quinetic"
    override val mod = Mod.FSK_PCM
    override val short = 10
    override val long = 10
    override val reset = 120
    override val tolerance = 1

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 110 || bb.bitsPerRow[0] > 140) return emptyList()
        val syncword = intArrayOf(0xA4, 0x23)
        val syncIdx = bb.search(0, 0, syncword, 16)
        if (syncIdx >= bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(5)
        bb.extractBytes(0, syncIdx + 16, b, 40)
        if (Rtl433BitUtil.crc16(b, 5, 0x1021, 0x1D0F) != 0) return emptyList()
        val switchChannel = b[2]
        if (switchChannel == 192) return emptyList()
        val id = (b[0] shl 8) or b[1]
        return listOf(
            Reading(
                "Quinetic",
                String.format("%04x", id),
                mapOf("channel" to switchChannel, "mic" to "CRC"),
            ),
        )
    }
}

// unverified: radiohead_ask.c:138-179 (rhAskExtract mirrors radiohead_ask.c:99-136)
internal object RadioheadAsk : Rtl433Decoder() {
    override val name = "Radiohead ASK"
    override val mod = Mod.OOK_PCM
    override val short = 500
    override val long = 500
    override val reset = 2500

    override fun decode(bb: BitBuffer): List<Reading> {
        val payload = IntArray(67)
        val msgLen = rhAskExtract(bb, 0, payload)
        if (msgLen <= 0) return emptyList()
        val dataLen = msgLen - 4 - 3
        if (dataLen <= 0) return emptyList()
        return listOf(
            Reading(
                "RadioHead-ASK",
                payload[3].toString(),
                mapOf(
                    "len" to dataLen,
                    "to" to payload[1],
                    "from" to payload[2],
                    "flags" to payload[4],
                    "payload" to (0 until dataLen).map { payload[5 + it] },
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: rainpoint.c:47-118
internal object Rainpoint : Rtl433Decoder() {
    override val name = "RainPoint soil temperature and moisture sensor"
    override val mod = Mod.OOK_PCM
    override val short = 500
    override val long = 500
    override val reset = 1500

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0xaa, 0xa9)
        if (bb.numRows != 1 || bb.bitsPerRow[0] < 232 || bb.bitsPerRow[0] > 3000) return emptyList()
        var startPos = bb.search(0, 0, preamble, 16)
        if (startPos >= bb.bitsPerRow[0]) return emptyList()
        startPos += 16 - 2
        val msg = BitBuffer()
        val len = bb.manchesterDecode(0, startPos, msg, 12 * 8)
        if (len - startPos != 12 * 2 * 8) return emptyList()
        msg.invert()
        val b = msg.bb[0]
        reflectBytes(b, 12)
        val sum = Rtl433BitUtil.addNibbles(b, 10)
        if ((sum and 0xff) != b[10]) return emptyList()
        val sync = (b[0] shl 8) or b[1]
        val id = (b[2] shl 8) or b[3]
        val flags = b[4]
        val status = (b[5] shl 8) or b[6]
        val tempC = b[7].toByte().toFloat()
        val moisture = b[8]
        val chan = when (flags) {
            0x9f -> 1
            0xb1 -> 2
            0xb7 -> 3
            else -> 0
        }
        return listOf(
            Reading(
                "RainPoint-Soil",
                String.format("%04x", id),
                mapOf(
                    "channel" to chan,
                    "sync" to sync,
                    "flags" to flags,
                    "status" to status,
                    "temperature_C" to tempC.toDouble(),
                    "moisture" to moisture,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: rainpoint_hcs012arf.c:57-109
internal object RainpointHcs012arf : Rtl433Decoder() {
    override val name = "RainPoint HCS012ARF Rain Gauge sensor"
    override val mod = Mod.OOK_PCM
    override val short = 320
    override val long = 320
    override val gap = 700
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(4, 163)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] > 163) return emptyList()
        val msg = BitBuffer()
        bb.manchesterDecode(row, 0, msg, 10 * 2 * 8)
        msg.invert()
        val b = msg.bb[0]
        reflectBytes(b, 10)
        if (b[0] != 0xa5) return emptyList()
        val sum = Rtl433BitUtil.addBytes(b.copyOfRange(1, 9), 8)
        if ((sum and 0xff) != b[9]) return emptyList()
        val id = (b[4] shl 24) or (b[3] shl 16) or (b[2] shl 8) or b[1]
        val flags1 = b[5]
        val batLow = (flags1 and 0x02) shr 1
        val flags2 = b[6]
        val rainRaw = (b[8] shl 8) or b[7]
        val rainMm = rainRaw * 0.1f
        return listOf(
            Reading(
                "RainPoint-HCS012ARF",
                id.toString(),
                mapOf(
                    "flags1" to (flags1 shr 2),
                    "flags2" to flags2,
                    "battery_ok" to (if (batLow != 0) 0 else 1),
                    "rain_mm" to rainMm.toDouble(),
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: regency_fan.c:69-177
internal object RegencyFan : Rtl433Decoder() {
    override val name = "Regency Ceiling Fan Remote (-f 303.75M to 303.96M)"
    override val mod = Mod.OOK_PWM
    override val short = 580
    override val long = 976
    override val gap = 8000
    override val reset = 14000

    override fun decode(bb: BitBuffer): List<Reading> {
        val commandNames = arrayOf(
            "invalid", "fan_speed", "fan_speed", "invalid",
            "light_intensity", "light_delay", "fan_direction", "invalid",
            "invalid", "invalid", "invalid", "invalid",
            "invalid", "invalid", "invalid", "invalid",
        )
        bb.invert()
        val row = bb.findRepeatedRow(4, 21)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] != 21) return emptyList()
        val bytes = IntArray(3)
        bb.extractBytes(row, 1, bytes, 20)
        reflectBytes(bytes, 3)
        val checksum = Rtl433BitUtil.addNibbles(bytes, 2) and 0x0f
        if (checksum != bytes[2]) return emptyList()
        val command = bytes[0] shr 4
        val channel = bytes[0].inv() and 0x0f
        val value = bytes[1]
        val valueString = when (command) {
            1 -> "stop"
            2 -> {
                if (value < 0x01 || value > 0x07) return emptyList()
                "speed $value"
            }
            4 -> {
                if (value > 0xc3) return emptyList()
                "$value %"
            }
            5 -> {
                if (value != 0x00 && value != 0x01) return emptyList()
                if (value == 0) "off" else "on"
            }
            6 -> {
                if (value != 0x07 && value != 0x83) return emptyList()
                if (value == 0x07) "clockwise" else "counter-clockwise"
            }
            else -> return emptyList()
        }
        return listOf(
            Reading(
                "Regency-Remote",
                null,
                mapOf(
                    "channel" to channel,
                    "command" to commandNames[command],
                    "value" to valueString,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: revolt_nc5462.c:54-102
internal object RevoltNc5462 : Rtl433Decoder() {
    override val name = "Revolt NC-5642 Energy Meter"
    override val mod = Mod.OOK_PWM
    override val short = 200
    override val long = 320
    override val sync = 10024
    override val reset = 272

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] != 104) return emptyList()
        val b = bb.bb[0]
        val sum = Rtl433BitUtil.addBytes(b, 11)
        if (sum == 0) return emptyList()
        val chk = b[11]
        if ((sum and 0xff) != chk) return emptyList()
        val button = b[0] shr 7
        val id = ((b[0] and 0x7f) shl 8) or b[1]
        val voltage = b[2]
        val current = b[4] or (b[3] shl 8)
        val frequency = b[5]
        val power = b[7] or (b[6] shl 8)
        val pf = b[8]
        val energy = b[10] or (b[9] shl 8)
        return listOf(
            Reading(
                "Revolt-NC5462",
                id.toString(),
                mapOf(
                    "voltage_V" to voltage,
                    "current_A" to current * 0.01,
                    "frequency_Hz" to frequency,
                    "power_W" to power * 0.1,
                    "power_factor_VA" to pf * 0.01,
                    "energy_kWh" to energy * 0.01,
                    "button" to button,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: revolt_zx7717.c:138-253
internal object RevoltZx7717 : Rtl433Decoder() {
    override val name = "Revolt ZX-7717 power meter"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 310
    override val long = 310
    override val reset = 900

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val rowLen = bb.bitsPerRow[0]
        if (rowLen < 15 * 8 || rowLen > 22 * 8) return emptyList()
        var pos = bb.search(0, 0, intArrayOf(0x2a), 8)
        pos += 8
        if (pos > 16) return emptyList()
        val len = bb.bitsPerRow[0] - pos
        val b = IntArray(32)
        bb.extractBytes(0, pos, b, len)
        reflectBytes(b, (len + 7) / 8)
        val msgLen = b[0]
        if (msgLen < 1) return emptyList()
        if (len < (msgLen + 1) * 8) return emptyList()
        val sum = Rtl433BitUtil.addBytes(b, msgLen)
        if (b[msgLen] != (sum and 0xff)) return emptyList()
        val id = (b[2] shl 8) or b[1]
        val version = b[3]
        var isPower = false
        var isEnergy = false
        var current = 0
        var voltage = 0
        var power = 0
        var energyKwh = 0
        when (msgLen) {
            13 -> {
                isPower = true
                current = (b[8] shl 8) or b[7]
                voltage = (b[10] shl 8) or b[9]
                power = (b[12] shl 8) or b[11]
            }
            14 -> {
                isEnergy = true
                energyKwh = (b[8] shl 16) or (b[7] shl 8) or b[6]
            }
            17 -> {
                isPower = true
                current = (b[12] shl 8) or b[11]
                voltage = (b[14] shl 8) or b[13]
                power = (b[16] shl 8) or b[15]
            }
            18 -> {
                isEnergy = true
                energyKwh = (b[12] shl 16) or (b[11] shl 8) or b[10]
            }
            else -> return emptyList()
        }
        val fields = linkedMapOf<String, Any?>("version" to version)
        if (isPower) {
            fields["current_A"] = current * 0.001
            fields["voltage_V"] = voltage * 0.1
            fields["power_W"] = power * 0.1
        }
        if (isEnergy) fields["energy_kWh"] = energyKwh * 0.01
        fields["mic"] = "CHECKSUM"
        return listOf(Reading("Revolt-ZX7717", id.toString(), fields))
    }
}

// unverified: rfm69_lowpowerlab_moteino.c:46-107 not ported - C passes int node/gateway ids to DATA_STRING (undefined behavior), no defined output to transcribe
internal object Rfm69LowpowerlabMoteino : Rtl433Decoder() {
    override val name = "RFM69 LowPowerLab Moteino board (-s 1000k)"
    override val mod = Mod.FSK_PCM
    override val short = 18
    override val long = 18
    override val reset = 400

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: rftech.c:42-70 (upstream .disabled = 1, not represented in API)
internal object Rftech : Rtl433Decoder() {
    override val name = "RF-tech"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 5000
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(3, 24)
        if (r < 0 || bb.bitsPerRow[r] != 24) return emptyList()
        val b = bb.bb[r]
        val sensorId = b[0]
        var tempC = (b[1] and 0x7f) + (b[2] and 0x0f) * 0.1f
        if ((b[1] and 0x80) != 0) tempC = -tempC
        val battery = if ((b[2] and 0x80) == 0x80) 1 else 0
        val button = if ((b[2] and 0x60) != 0) 1 else 0
        return listOf(
            Reading(
                "RF-tech",
                sensorId.toString(),
                mapOf(
                    "battery_ok" to battery,
                    "temperature_C" to tempC.toDouble(),
                    "button" to button,
                ),
            ),
        )
    }
}

// unverified: rfxmeter.c:76-120
internal object Rfxmeter : Rtl433Decoder() {
    override val name = "RfxMeter, RFXPwr"
    override val mod = Mod.OOK_PPM
    override val short = 500
    override val long = 1500
    override val gap = 2500
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1 && bb.numRows != 2) return emptyList()
        val last = bb.numRows - 1
        val b = bb.bb[last]
        if (bb.bitsPerRow[last] != 48) return emptyList()
        if ((b[0] xor 0xf0) != b[1]) return emptyList()
        val chk = Rtl433BitUtil.addNibbles(b, 6)
        if ((chk and 0x0f) != 0x0f) return emptyList()
        val address = b[0]
        val msgValue = (b[4] shl 16) or (b[2] shl 8) or b[3]
        val msgType = b[5] shr 4
        return listOf(
            Reading(
                "RfxMeter",
                address.toString(),
                mapOf(
                    "msg_type" to msgType,
                    "msg_value" to msgValue,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: risco_agility.c:94-172 (gray_decode at :94-98)
internal object RiscoAgility : Rtl433Decoder() {
    override val name = "Risco 2 Way Agility protocol, Risco PIR/PET Sensor RWX95P"
    override val mod = Mod.OOK_PCM
    override val short = 175
    override val long = 175
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val lenMsg = 16
        val pos = bb.search(0, 0, intArrayOf(0x55, 0x5a), 16)
        if (pos >= bb.bitsPerRow[0]) return emptyList()
        val decoded = BitBuffer()
        bb.differentialManchesterDecode(0, pos + 16, decoded, lenMsg * 8)
        if (decoded.bitsPerRow[0] < lenMsg * 8) return emptyList()
        val b = decoded.bb[0]
        if (Rtl433BitUtil.crc16(b, lenMsg, 0x8005, 0x8181) != 0) return emptyList()
        val messageType = (b[0] shl 8) or b[1]
        if (messageType != 0xFF60) return emptyList()
        val id = (b[6] shl 16) or (b[7] shl 8) or b[8]
        reflectBytes(b, 16)
        val state = grayDecode(b[12] and 0xF)
        val tamper = (state and 0x4) shr 2
        val motion = (state and 0x2) shr 1
        val lowBatt = (grayDecode((b[12] and 0xF0) shr 4) and 0x8) shr 3
        val counterRaw = (b[5] shl 8) or b[4]
        val counter = grayDecode(counterRaw)
        val fields = linkedMapOf<String, Any?>("counter" to counter)
        if (tamper != 0) fields["tamper"] = 1
        if (motion != 0) fields["motion"] = 1
        fields["battery_ok"] = if (lowBatt != 0) 0 else 1
        fields["mic"] = "CRC"
        return listOf(Reading("Risco-RWX95P", id.toString(), fields))
    }
}

// unverified: rojaflex.c:79-285 (signal-cloner block is compiled out, GENERATE_* defines are 0)
internal object Rojaflex : Rtl433Decoder() {
    override val name = "RojaFlex shutter and remote devices"
    override val mod = Mod.FSK_PCM
    override val short = 100
    override val long = 100
    override val reset = 102400

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val preamble = intArrayOf(0xaa, 0xaa, 0xd3, 0x91, 0xd3, 0x91)
        val startPos = bb.search(0, 0, preamble, 48)
        if (startPos >= bb.bitsPerRow[0]) return emptyList()
        val dataframeBitcount = ((bb.bitsPerRow[0] - startPos - 48) and 0xFE) and 0xFF
        if (dataframeBitcount < 72 || dataframeBitcount > 88) return emptyList()
        val msg = IntArray(11)
        bb.extractBytes(0, startPos + 48, msg, dataframeBitcount)
        val hasCrc = dataframeBitcount == 88
        if (hasCrc) {
            val crcMessage = (msg[9] shl 8) or msg[10]
            val crcCalc = Rtl433BitUtil.crc16(msg, 9, 0x8005, 0xffff)
            if (crcMessage != crcCalc) return emptyList()
        }
        val id = (msg[1] shl 20) or (msg[2] shl 12) or (msg[3] shl 4) or (msg[4] shr 4)
        val token = (msg[7] shl 8) or msg[8]
        var deviceType = 0x0
        if ((msg[5] and 0xF) == 0x5) {
            deviceType = 0x5
        } else if ((msg[5] and 0xF) == 0xa) {
            deviceType = if (hasCrc) 0xa else 0xb
        }
        val cmdStr = when (msg[5]) {
            0x0a -> "Stop"
            0x1a -> "Up"
            0x8a -> "Down"
            0x9a -> "Save/Unsave position"
            0xda -> "Go saved position"
            0xea -> "Request Status"
            0x85 -> "Pos. Status 0%"
            0x95 -> "Pos. Status 20%"
            0xA5 -> "Pos. Status 40%"
            0xB5 -> "Pos. Status 60%"
            0xC5 -> "Pos. Status 80%"
            0xD5 -> "Pos. Status 100%"
            else -> "unknown"
        }
        val model = when (deviceType) {
            0x5 -> "RojaFlex-Shutter"
            0xa -> "RojaFlex-Remote"
            0xb -> "RojaFlex-Bridge"
            else -> "RojaFlex-Other"
        }
        val fields = linkedMapOf<String, Any?>(
            "channel" to (msg[4] and 0xF),
            "token" to token,
            "cmd_id" to msg[5],
            "cmd_name" to cmdStr,
            "cmd_value" to msg[6],
        )
        if (hasCrc) fields["mic"] = "CRC"
        return listOf(Reading(model, String.format("%07x", id), fields))
    }
}

// unverified: rosstech_dcu706.c:37-101 (uart8o1 mirrors bit_util.c:147)
internal object RosstechDcu706 : Rtl433Decoder() {
    override val name = "Rosstech Digital Control Unit DCU-706/Sundance/Jacuzzi"
    override val mod = Mod.OOK_PCM
    override val short = 200
    override val long = 200
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> {
        val preambleData = intArrayOf(0xDD, 0x40)
        val preambleBond = intArrayOf(0xCD, 0x00)
        val preambleLength = 11
        if (bb.numRows != 1 || bb.bitsPerRow[0] < 55 || bb.bitsPerRow[0] > 300) return emptyList()
        var startPos = bb.search(0, 0, preambleData, preambleLength)
        if (startPos == bb.bitsPerRow[0]) {
            startPos = bb.search(0, 0, preambleBond, preambleLength)
            if (startPos == bb.bitsPerRow[0]) return emptyList()
        }
        if (startPos + 55 > bb.bitsPerRow[0]) return emptyList()
        val msg = IntArray(7)
        bb.extractBytes(0, startPos, msg, 56)
        val b = IntArray(5)
        val r = uart8o1(msg, 0, 55, b)
        if (r != 5) return emptyList()
        val msgType = b[0]
        val id = (b[1] shl 8) or b[2]
        val tempF = b[3]
        val checksum = b[4]
        val calculated = (0xff xor Rtl433BitUtil.xorBytes(b, 4)) and 0xFF
        if (calculated != checksum) return emptyList()
        return listOf(
            Reading(
                "Rosstech-Spa",
                String.format("%04x", id),
                mapOf(
                    "msg_type" to (if (msgType == 0xba) "Data" else "Bond"),
                    "temperature_F" to tempF,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: rubicson.c:40-91
internal object Rubicson : Rtl433Decoder() {
    override val name = "Rubicson, TFA 30.3197 or InFactory PT-310 Temperature Sensor"
    override val mod = Mod.OOK_PPM
    override val short = 1000
    override val long = 2000
    override val gap = 3000
    override val reset = 4800

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(3, 36)
        if (r < 0) return emptyList()
        val b = bb.bb[r]
        if (bb.bitsPerRow[r] < 36 || bb.bitsPerRow[r] > 38) return emptyList()
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
        val battery = b[1] and 0x80
        val channel = ((b[1] and 0x30) shr 4) + 1
        val tempRaw = s16((b[1] shl 12) or (b[2] shl 4))
        val tempC = (tempRaw shr 4) * 0.1f
        return listOf(
            Reading(
                "Rubicson-Temperature",
                id.toString(),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to (if (battery != 0) 1 else 0),
                    "temperature_C" to tempC.toDouble(),
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: rubicson_48659.c:151-183
internal object Rubicson48659 : Rtl433Decoder() {
    override val name = "Rubicson 48659 Thermometer"
    override val mod = Mod.OOK_PPM
    override val short = 940
    override val long = 1900
    override val gap = 2000
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(10, 32)
        if (row < 0) return emptyList()
        val b = bb.bb[row]
        if (bb.bitsPerRow[row] > 33 || bb.bitsPerRow[row] < 10) return emptyList()
        val checksum = (Rtl433BitUtil.addBytes(b, 3) - b[3]) and 0xff
        if (checksum != 0xa6) return emptyList()
        val id = b[0]
        val tempF = if (((b[1] and 0x04) shr 2) != 0) -1f else (1 * (((b[1] and 0x3) shl 8) or b[2])).toFloat()
        return listOf(
            Reading(
                "Rubicson-48659",
                id.toString(),
                mapOf(
                    "temperature_F" to tempF.toDouble(),
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
}

// unverified: rubicson_pool_48942.c:52-93
internal object RubicsonPool48942 : Rtl433Decoder() {
    override val name = "Rubicson Pool Thermometer 48942"
    override val mod = Mod.OOK_PWM
    override val short = 280
    override val long = 480
    override val reset = 6000
    override val gap = 5000
    override val sync = 730

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(2, 41)
        if (row < 0 || bb.bitsPerRow[row] != 41) return emptyList()
        val b = bb.bb[row]
        bb.invert()
        if ((b[3] and 0xF) != 0 || b[5] != 0) return emptyList()
        if (b[0] == 0 && b[2] == 0 && b[4] == 0) return emptyList()
        if (Rtl433BitUtil.crc8(b, 4, 0x31, 0x00) != b[4]) return emptyList()
        val channel = (b[0] shr 4) + 1
        val randomId = ((b[0] and 0x0F) shl 6) or ((b[1] and 0xFC) shr 2)
        val batteryLow = b[2] shr 7
        val tempC = ((((b[2] and 0x7F) shl 4) or (b[3] shr 4)) - 1024) * 0.1f
        return listOf(
            Reading(
                "Rubicson-48942",
                randomId.toString(),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "temperature_C" to tempC.toDouble(),
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

// unverified: s3318p.c:62-115
internal object S3318p : Rtl433Decoder() {
    override val name = "Conrad S3318P, FreeTec NC-5849-913 temperature humidity sensor, ORIA WA50 ST389 temperature sensor"
    override val mod = Mod.OOK_PPM
    override val short = 1900
    override val long = 3800
    override val gap = 4400
    override val reset = 9400

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] == 0 && bb.bitsPerRow[1] == 0) return emptyList()
        val r = bb.findRepeatedRow(4, 42)
        if (r < 0 || bb.bitsPerRow[r] != 42) return emptyList()
        val b = IntArray(5)
        bb.extractBytes(r, 2, b, 40)
        if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0) return emptyList()
        val crc = crc4(b, 4, 0x3, 0x0) xor (b[4] shr 4)
        if (crc != (b[4] and 0xf)) return emptyList()
        val id = b[0]
        val channel = ((b[1] and 0x30) shr 4) + 1
        val tempRaw = ((b[2] and 0x0f) shl 8) or (b[2] and 0xf0) or (b[1] and 0x0f)
        val tempF = (tempRaw - 900) * 0.1f
        val humidity = ((b[3] and 0x0f) shl 4) or ((b[3] and 0xf0) shr 4)
        val button = b[4] shr 7
        val batteryLow = (b[4] and 0x40) shr 6
        val fields = linkedMapOf<String, Any?>(
            "channel" to channel,
            "battery_ok" to (if (batteryLow != 0) 0 else 1),
            "temperature_F" to tempF.toDouble(),
        )
        if (humidity != 0) fields["humidity"] = humidity
        fields["button"] = button
        fields["mic"] = "CRC"
        return listOf(Reading("Conrad-S3318P", id.toString(), fields))
    }
}

// unverified: not ported - oregon_scientific.c:196-1043 (v2.1 and v3 multi-model decoders, ~830 lines), too large for this batch
internal object OregonScientific : Rtl433Decoder() {
    override val name = "Oregon Scientific Weather Sensor"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 440
    override val reset = 2400

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: not ported - RADIAN UART frame decoder lives in m_bus.c:1571-1868 and depends on m_bus helpers, not transcribed this batch
internal object Radian : Rtl433Decoder() {
    override val name = "RADIAN/RADIAN0 meter"
    override val mod = Mod.FSK_PCM
    override val short = 416
    override val long = 416
    override val reset = 20000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

internal val BATCH_06: List<Rtl433Decoder> = listOf(
    OilStandard,
    OilStandardAsk,
    OilWatchman,
    OilWatchmanAdvanced,
    Olympia9571,
    Omni,
    OpelMokka,
    OpusXt300,
    OregonScientific,
    OregonScientificSl109h,
    OregonScientificV1,
    OregonScientificWmr500,
    OriaWa150km,
    OrionEndpoint,
    OrionEndpoint2020,
    PhilipsAj3650,
    PhilipsAj7010,
    Proflame2,
    Prologue,
    Proove,
    Quhwa,
    Quinetic,
    Radian,
    RadioheadAsk,
    Rainpoint,
    RainpointHcs012arf,
    RegencyFan,
    RevoltNc5462,
    RevoltZx7717,
    Rfm69LowpowerlabMoteino,
    Rftech,
    Rfxmeter,
    RiscoAgility,
    Rojaflex,
    RosstechDcu706,
    Rubicson,
    Rubicson48659,
    RubicsonPool48942,
    S3318p,
)

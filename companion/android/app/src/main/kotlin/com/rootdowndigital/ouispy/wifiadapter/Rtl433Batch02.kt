// Kotlin transcription of rtl_433 device decoders (batch 02). GPL-3 reference; constants, bit offsets and CRC parameters transcribed as facts.
package com.rootdowndigital.ouispy.wifiadapter

// unverified: ecodhome.c:83-172, struct ecodhome.c:185
internal object Ecodhome : Rtl433Decoder() {
    override val name = "EcoDHOME Smart Socket and MCEE Solar monitor"
    override val mod = Mod.FSK_PCM
    override val short = 250
    override val long = 250
    override val reset = 6000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1 || bb.bitsPerRow[0] < 128) return emptyList()
        var startPos = bb.search(0, 0, intArrayOf(0xaa, 0xaa, 0x2d, 0xd4), 32)
        startPos += 32
        if (startPos >= bb.bitsPerRow[0]) return emptyList()
        if (startPos + 12 * 8 >= bb.bitsPerRow[0]) return emptyList()
        val msg = IntArray(13)
        bb.extractBytes(0, startPos, msg, 13 * 8)
        val id = (msg[0] shl 24) or (msg[1] shl 16) or (msg[2] shl 8) or msg[3]
        val mType = (msg[4] shl 8) or msg[5]
        val mSubtype = (msg[6] shl 8) or msg[7]
        val idStr = String.format("%08x", id)
        if (mType == 0x7700) {
            val sum = Rtl433BitUtil.addBytes(msg, 11)
            if ((sum and 0xff) != msg[11]) return emptyList()
            if (msg[10] != 0x53) return emptyList()
            val raw = (msg[8] shl 8) or msg[9]
            val powerW = (msg[9] shl 8) or msg[8]
            val fields = linkedMapOf<String, Any?>(
                "message_type" to mType,
                "message_subtype" to mSubtype,
            )
            if (mSubtype == 0x414b) fields["power_W"] = powerW.toDouble()
            fields["raw"] = raw
            return listOf(Reading("EcoDHOME-SmartSocket", idStr, fields))
        }
        val sum = Rtl433BitUtil.addBytes(msg, 9) + 0x35
        if ((sum and 0xff) != msg[9]) return emptyList()
        if (msg[10] != 0x55) return emptyList()
        if (msg[11] != 0x00) return emptyList()
        val raw = (msg[6] shl 16) or (msg[7] shl 8) or msg[8]
        val powerW = (((msg[7] - 0x33) and 0xFF) shl 8) or ((msg[6] - 0x33) and 0xFF)
        val fields = linkedMapOf<String, Any?>("message_type" to mType)
        if (mType == 0x3eb3) fields["power_W"] = powerW.toDouble()
        fields["raw"] = raw
        return listOf(Reading("EcoDHOME-Transmitter", idStr, fields))
    }
}

// unverified: ecoeye.c:53-99, struct ecoeye.c:109
internal object Ecoeye : Rtl433Decoder() {
    override val name = "Eco-Eye solar PV/grid current monitor"
    override val mod = Mod.FSK_PCM
    override val short = 200
    override val long = 200
    override val reset = 8100

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        var startPos = bb.search(0, 0, intArrayOf(0xaa, 0x2d, 0xd4), 24)
        startPos += 24
        if (startPos >= bb.bitsPerRow[0]) return emptyList()
        if (startPos + 5 * 8 > bb.bitsPerRow[0]) return emptyList()
        val msg = IntArray(5)
        bb.extractBytes(0, startPos, msg, 5 * 8)
        val sum = Rtl433BitUtil.addBytes(msg, 4)
        if ((sum and 0xff) != msg[4]) return emptyList()
        val pv = (msg[0] shl 8) or msg[1]
        val used = (msg[2] shl 8) or msg[3]
        return listOf(
            Reading(
                "EcoEye",
                null,
                mapOf(
                    "current_used_A" to (used * 0.01f).toDouble(),
                    "current_pv_A" to (pv * 0.01f).toDouble(),
                ),
            ),
        )
    }
}

// unverified: ecowitt.c:29-102, struct ecowitt.c:113
internal object Ecowitt : Rtl433Decoder() {
    override val name = "Ecowitt Wireless Outdoor Thermometer WH53/WH0280/WH0281A"
    override val mod = Mod.OOK_PWM
    override val short = 500
    override val long = 1480
    override val gap = 1500
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val pos = bb.search(0, 0, intArrayOf(0xf5, 0x30), 12)
        if (pos >= bb.bitsPerRow[0]) return emptyList()
        if (bb.bitsPerRow[0] - pos < 52) return emptyList()
        val b = IntArray(6)
        bb.extractBytes(0, pos + 4, b, 6 * 8)
        if (Rtl433BitUtil.crc8(b, 6, 0x31, 0) != 0) return emptyList()
        val sensorId = b[1]
        val channel = (b[2] shr 4) + 1
        if (channel > 3) return emptyList()
        if ((b[2] and (4 or 8)) != 0) return emptyList()
        val tempRaw = ((b[2] and 0x3) shl 8) or b[3]
        val tempC = (tempRaw - 400) * 0.1f
        if (b[4] != 0xFF) return emptyList()
        return listOf(
            Reading(
                "Ecowitt-WH53",
                sensorId.toString(),
                mapOf("channel" to channel, "temperature_C" to tempC.toDouble()),
            ),
        )
    }
}

// unverified: efergy_e2_classic.c:37-108, struct efergy_e2_classic.c:123
internal object EfergyE2Classic : Rtl433Decoder() {
    override val name = "Efergy e2 classic"
    override val mod = Mod.FSK_PWM
    override val short = 64
    override val long = 136
    override val sync = 500
    override val gap = 200
    override val reset = 400

    override fun decode(bb: BitBuffer): List<Reading> {
        val numBits = bb.bitsPerRow[0]
        val bytes = bb.bb[0]
        if (bb.numRows != 1) return emptyList()
        if (numBits < 64 || numBits > 65) return emptyList()
        if ((bytes[0] and 0xf0) != 0xf0 && (bytes[0] and 0xf0) != 0x00) return emptyList()
        if ((bytes[0] and 0xf0) != 0) {
            for (i in 0 until 8) bytes[i] = bytes[i].inv() and 0xFF
        }
        var zeroCount = 0
        for (i in 0 until 8) {
            if (bytes[i] == 0) zeroCount++
        }
        if (zeroCount > 5) return emptyList()
        val checksum = Rtl433BitUtil.addBytes(bytes, 7)
        if (checksum == 0) return emptyList()
        if ((checksum and 0xff) != bytes[7]) return emptyList()
        val address = (bytes[2] shl 8) or bytes[1]
        val learn = (bytes[3] and 0x80) shr 7
        val interval = (((bytes[3] and 0x30) shr 4) + 1) * 6
        val battery = (bytes[3] and 0x40) shr 6
        val fact = (-(bytes[6].toByte().toInt()) + 15) and 0xFF
        if (fact < 7 || fact > 23) return emptyList()
        val currentAdc = ((bytes[4] shl 8) or bytes[5]).toFloat() / (1 shl fact).toFloat()
        return listOf(
            Reading(
                "Efergy-e2CT",
                address.toString(),
                mapOf(
                    "battery_ok" to (if (battery != 0) 1 else 0),
                    "current" to currentAdc.toDouble(),
                    "interval" to interval,
                    "learn" to (if (learn != 0) "YES" else "NO"),
                ),
            ),
        )
    }
}

// unverified: efergy_optical.c:37-119, struct efergy_optical.c:127
internal object EfergyOptical : Rtl433Decoder() {
    override val name = "Efergy Optical"
    override val mod = Mod.FSK_PWM
    override val short = 64
    override val long = 136
    override val sync = 500
    override val reset = 400

    override fun decode(bb: BitBuffer): List<Reading> {
        var numBits = bb.bitsPerRow[0]
        val bytes = bb.bb[0]
        if (numBits < 96 || numBits > 100) return emptyList()
        while ((bytes[0] and 0xf0) != 0xf0 && (bytes[0] and 0xf0) != 0x00) {
            numBits -= 1
            if (numBits < 96) return emptyList()
            for (i in 0 until (numBits + 7) / 8) {
                bytes[i] = ((bytes[i] shl 1) or ((bytes[i + 1] and 0x80) shr 7)) and 0xFF
            }
        }
        if ((bytes[0] and 0xf0) != 0) {
            for (i in 0 until 12) bytes[i] = bytes[i].inv() and 0xFF
        }
        if (bytes[8] == 0 && bytes[9] == 0 && bytes[10] == 0 && bytes[11] == 0) return emptyList()
        val csum1 = (bytes[10] shl 8) or bytes[11]
        val crc = Rtl433BitUtil.crc16(bytes, 10, 0x1021, 0x0000)
        if (crc != csum1) return emptyList()
        val id = (bytes[0] shl 16) or (bytes[1] shl 8) or bytes[2]
        val seconds = (((bytes[3] and 0x30) shr 4) + 1) * 30.0f
        val pulsecount = bytes[8]
        val impKwh = intArrayOf(4000, 3200, 2000, 1000, 500)
        val out = ArrayList<Reading>()
        for (rate in impKwh) {
            val energy = (pulsecount.toFloat() / rate) * (3600 / seconds)
            out.add(
                Reading(
                    "Efergy-Optical",
                    id.toString(),
                    mapOf(
                        "pulses" to rate,
                        "pulsecount" to pulsecount,
                        "energy_kWh" to energy.toDouble(),
                    ),
                ),
            )
        }
        return out
    }
}

private val ELERO_NIBBLE = intArrayOf(0x0a, 0x03, 0x01, 0x0c, 0x0d, 0x07, 0x0f, 0x06, 0x00, 0x08, 0x0b, 0x0e, 0x09, 0x02, 0x05, 0x04)

private fun eleroDecodeCommand(msg: IntArray) {
    for (i in 0 until 8) {
        val nh = ELERO_NIBBLE[(msg[i] shr 4) and 0xf]
        val nl = ELERO_NIBBLE[msg[i] and 0xf]
        msg[i] = (nh shl 4) or nl
    }
    var key = 0xfe
    for (i in 0 until 2) {
        val ln = (msg[i] - key) and 0x0f
        val hn = (msg[i] and 0xf0) - (key and 0xf0)
        msg[i] = (hn or ln) and 0xFF
        key = (key - 0x22) and 0xFF
    }
    val xorB0 = msg[0]
    val xorB1 = msg[1]
    for (i in 0 until 8 step 2) {
        msg[i] = msg[i] xor xorB0
        msg[i + 1] = msg[i + 1] xor xorB1
    }
    key = 0xba
    for (i in 2 until 8) {
        val ln = (msg[i] - key) and 0x0f
        val hn = (msg[i] and 0xf0) - (key and 0xf0)
        msg[i] = (hn or ln) and 0xFF
        key = (key - 0x22) and 0xFF
    }
}

private fun eleroIbmWhitening(buf: IntArray, size: Int) {
    var keyMsb = 0x01
    var keyLsb = 0xff
    var keyMsbPrevious: Int
    for (pos in 0 until size) {
        buf[pos] = buf[pos] xor keyLsb
        for (rol in 0 until 8) {
            keyMsbPrevious = keyMsb
            keyMsb = (keyLsb and 0x01) xor ((keyLsb shr 5) and 0x01)
            keyLsb = ((keyLsb shr 1) and 0xff) or ((keyMsbPrevious shl 7) and 0x80)
        }
    }
}

// unverified: elero.c:92-177 (decode), elero.c:60-90 (command decode), bit_util.c:491 (ibm_whitening), struct elero.c:189
internal object Elero : Rtl433Decoder() {
    override val name = "Elero bidirectional blinds/awning remote (Silent Gliss and others)"
    override val mod = Mod.FSK_PCM
    override val short = 13
    override val long = 13
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val sync = intArrayOf(0xa7, 0x23, 0xa7, 0x23)
        var startPos = bb.search(0, 0, sync, 31)
        if (startPos == bb.bitsPerRow[0]) return emptyList()
        startPos += 31
        val availBits = bb.bitsPerRow[0] - startPos
        if (availBits < 8) return emptyList()
        val frame = IntArray(40)
        var availBytes = availBits / 8
        if (availBytes > 40) availBytes = 40
        bb.extractBytes(0, startPos, frame, availBytes * 8)
        eleroIbmWhitening(frame, availBytes)
        val length = frame[0]
        val total = length + 3
        if (total > 40 || availBytes < total) return emptyList()
        val crcCalc = Rtl433BitUtil.crc16(frame, total - 2, 0x8005, 0xffff)
        val crcRecv = (frame[total - 2] shl 8) or frame[total - 1]
        if (crcCalc != crcRecv) return emptyList()
        val ndst = frame[16]
        if (17 + ndst + 2 + 8 + 2 > total) return emptyList()
        val counter = frame[1]
        val src = (frame[7] shl 16) or (frame[8] shl 8) or frame[9]
        val channel = StringBuilder()
        for (i in 0 until ndst) channel.append(String.format("%02X", frame[17 + i]))
        val enc = IntArray(8) { frame[17 + ndst + 2 + it] }
        eleroDecodeCommand(enc)
        val command = when (enc[2]) {
            0x20 -> "Up"
            0x10 -> "Stop"
            0x40 -> "Down"
            else -> "?"
        }
        return listOf(
            Reading(
                "Elero",
                String.format("%06X", src),
                mapOf("channel" to channel.toString(), "command" to command, "counter" to counter),
            ),
        )
    }
}

// unverified: elro_db286a.c:27-44, struct elro_db286a.c:58 (upstream .disabled=1, ported enabled)
internal object ElroDb286a : Rtl433Decoder() {
    override val name = "Elro DB286A Doorbell"
    override val mod = Mod.OOK_PWM
    override val short = 456
    override val long = 1448
    override val gap = 2000
    override val reset = 8000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(5, 33)
        if (row < 0 || bb.bitsPerRow[row] != 33) return emptyList()
        val b = bb.bb[row]
        val idStr = String.format("%02x%02x%02x%02x", b[0], b[1], b[2], b[3])
        return listOf(Reading("Elro-DB286A", idStr, emptyMap()))
    }
}

private fun elsnerSpread(x: Int, k: Int): Int {
    var v = (x shl k) and 0xff
    if ((x and 1) != 0) v = v or ((1 shl k) - 1)
    return v
}

private fun elsnerStep(prev: Int, base: Int, old: Int, new: Int): Int =
    (elsnerSpread(prev, 1) + base + new - old) and 0xff

private fun elsnerDescramble(input: IntArray, out: IntArray, nbytes: Int) {
    val nbits = nbytes * 8
    for (i in 0 until nbytes) out[i] = 0
    for (n in 0 until nbits) {
        var bit = (input[n / 8] shr (7 - (n % 8))) and 1
        if (n - 5 >= 0) bit = bit xor ((input[(n - 5) / 8] shr (7 - ((n - 5) % 8))) and 1)
        if (n - 7 >= 0) bit = bit xor ((input[(n - 7) / 8] shr (7 - ((n - 7) % 8))) and 1)
        out[n / 8] = out[n / 8] or (bit shl (7 - (n % 8)))
    }
}

private fun elsnerLag7(input: IntArray, out: IntArray, nbytes: Int) {
    val nbits = nbytes * 8
    for (i in 0 until nbytes) out[i] = 0
    for (n in 0 until nbits) {
        var bit = (input[n / 8] shr (7 - (n % 8))) and 1
        if (n - 7 >= 0) bit = bit xor ((input[(n - 7) / 8] shr (7 - ((n - 7) % 8))) and 1)
        out[n / 8] = out[n / 8] or (bit shl (7 - (n % 8)))
    }
}

private fun elsnerCommandName(token: Int): String? = when (token) {
    0xcc00 -> "close"
    0xbb00 -> "open"
    0xbd00 -> "stop_or_release"
    0x00ef -> "automode_a"
    0x00e3 -> "automode_b"
    0xaac0 -> "filler"
    0xa9c0 -> "automode_companion"
    else -> null
}

// unverified: elsner_solexa.c:182-283 (decode), elsner_solexa.c:114-180 (helpers), struct elsner_solexa.c:296
internal object ElsnerSolexa : Rtl433Decoder() {
    override val name = "Elsner Solexa 230V"
    override val mod = Mod.FSK_MC_ZEROBIT
    override val short = 11
    override val long = 11
    override val reset = 25

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val pos = bb.search(0, 0, intArrayOf(0x0a), 8) + 8
        val len = bb.bitsPerRow[0]
        if (pos >= len || len - pos < 38 * 8) return emptyList()
        val b = IntArray(38)
        bb.extractBytes(0, pos, b, 38 * 8)
        val crcCalc = Rtl433BitUtil.crc16(b, 36, 0x1021, 0x68b3)
        val crcMsg = (b[36] shl 8) or b[37]
        if (crcCalc != crcMsg) return emptyList()
        val p = IntArray(36)
        elsnerDescramble(b, p, 36)
        val idStr = String.format("%02x%02x%02x%02x", p[0], p[1], p[2], p[3])
        val payloadStr = (0 until 32).joinToString("") { String.format("%02x", p[4 + it]) }
        val rp0 = b[4]
        val paramOk = b[7] == ((elsnerSpread(rp0, 3) + 0x48) and 0xff) &&
            b[8] == ((elsnerSpread(rp0, 4) + 0xd0) and 0xff) &&
            b[9] == ((elsnerSpread(rp0, 5) + 0xa0) and 0xff)
        val counter = (b[5] - elsnerSpread(rp0, 1)) and 0xff
        val rollingStr = String.format("%02x", rp0)
        val q = IntArray(36)
        elsnerLag7(b, q, 36)
        val family1 = (q[4 + 3] shr 4) and 1
        var command: String? = null
        if (paramOk && family1 != 0) {
            val branch1 = (q[4 + 17] shr 2) and 1
            val l12 = Rtl433BitUtil.parity8(rp0 and 0xf9)
            val l13 = Rtl433BitUtil.parity8(rp0 and 0xfd)
            val l14 = 1 xor Rtl433BitUtil.parity8(rp0 and 0xff)
            val l17 = Rtl433BitUtil.parity8(rp0 and 0xfe)
            val l18 = 1 xor Rtl433BitUtil.parity8(rp0 and 0xff)
            val l19 = Rtl433BitUtil.parity8(rp0 and 0xfe)
            val exp0: Int
            val exp1: Int
            val obs0: Int
            val obs1: Int
            if (branch1 == 0) {
                exp0 = elsnerStep(b[4 + 12], 0x6a, l12, l13)
                exp1 = elsnerStep(exp0, 0x30, l13, l14)
                obs0 = b[4 + 13]
                obs1 = b[4 + 14]
            } else {
                exp0 = elsnerStep(b[4 + 17], 0x30, l17, l18)
                exp1 = elsnerStep(exp0, 0x30, l18, l19)
                obs0 = b[4 + 18]
                obs1 = b[4 + 19]
            }
            val token = (((obs0 - exp0) and 0xff) shl 8) or ((obs1 - exp1) and 0xff)
            command = elsnerCommandName(token)
        }
        val fields = linkedMapOf<String, Any?>()
        if (paramOk) {
            fields["rolling"] = rollingStr
            fields["counter"] = counter
        }
        if (command != null) fields["command"] = command
        fields["data"] = payloadStr
        return listOf(Reading("Elsner-Solexa", idStr, fields))
    }
}

private const val ELSTER_MIN_LEN = 9
private const val ELSTER_MAX_LEN = 200
private const val ELSTER2_MIN_LEN = 12
private const val ELSTER2_MAX_LEN = 200
private const val ELSTER2_NBR_MAX = 8

// unverified: elster_power_meter.c:120-273 (decode), elster_power_meter.c:116-117 (length bounds), struct elster_power_meter.c:264
internal object ElsterPowerMeter : Rtl433Decoder() {
    override val name = "Elster/Honeywell R2S/REXU power meter"
    override val mod = Mod.FSK_MC_ZEROBIT
    override val short = 28
    override val long = 28
    override val reset = 3000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val rowBits = bb.bitsPerRow[0]
        if (rowBits < (ELSTER_MIN_LEN + 2) * 8) return emptyList()
        val row = bb.bb[0]
        val buf = IntArray(ELSTER_MAX_LEN + 2)
        var foundPos = -1
        var len = 0
        for (pos in 0..(rowBits - (ELSTER_MIN_LEN + 2) * 8)) {
            val candLen = bitrowGetByte(row, pos) xor 0x55
            if (candLen < ELSTER_MIN_LEN || candLen > ELSTER_MAX_LEN) continue
            if (pos + (candLen + 2) * 8 > rowBits) continue
            for (i in 0 until candLen + 2) buf[i] = bitrowGetByte(row, pos + i * 8) xor 0x55
            val chk = Rtl433BitUtil.crc16lsb(buf, candLen, 0x8408, 0xffff) xor 0xffff
            val chkRecv = buf[candLen] or (buf[candLen + 1] shl 8)
            if (chk == chkRecv) {
                foundPos = pos
                len = candLen
                break
            }
        }
        if (foundPos < 0) return emptyList()
        val flags = buf[1]
        val src = (buf[2] shl 24) or (buf[3] shl 16) or (buf[4] shl 8) or buf[5]
        val dst = (buf[6] shl 24) or (buf[7] shl 16) or (buf[8] shl 8) or buf[9]
        val srcStr = Integer.toUnsignedString(src)
        val dstStr = Integer.toUnsignedString(dst)
        val isBeacon = len == 40 && flags == 0x08 && dst == 0
        val dataRaw = (0 until len - 10).joinToString("") { String.format("%02x", buf[10 + it]) }
        var hasReading = false
        var meterKwh = 0f
        var hasHourly = false
        var ctr = 0
        var curHour = 0
        var lastHour = 0
        var hourlyStr = ""
        if (src >= 0 && len - 1 > 15) {
            val cmdStart = 15
            val cmdLen = buf[1 + cmdStart]
            if (cmdLen == 0x33 && len - 1 >= cmdStart + 1 + cmdLen) {
                val cmd = buf.copyOfRange(1 + cmdStart + 1, buf.size)
                val cmdId = cmd[1]
                if (cmdId == 0xce && cmdLen >= 10) {
                    ctr = cmd[2]
                    curHour = (cmd[5] shl 8) or cmd[6]
                    lastHour = (cmd[7] shl 8) or cmd[8]
                    var nHours = cmd[9]
                    if (nHours > 17) nHours = 17
                    hasHourly = true
                    val sb = StringBuilder()
                    var h = 0
                    while (h < nHours && cmdLen >= 10 + 2 * (h + 1)) {
                        val raw = (cmd[10 + 2 * h] shl 8) or cmd[10 + 2 * h + 1]
                        if (h > 0) sb.append(',')
                        sb.append(String.format(java.util.Locale.ROOT, "%.2f", (raw * 0.01f).toDouble()))
                        h++
                    }
                    hourlyStr = sb.toString()
                }
                if (cmdId == 0xce && cmdLen >= 47) {
                    val readingRaw = (cmd[44] shl 16) or (cmd[45] shl 8) or cmd[46]
                    meterKwh = readingRaw.toFloat()
                    hasReading = true
                }
            }
        }
        val fields = linkedMapOf<String, Any?>("dst" to dstStr, "flags" to flags)
        if (isBeacon) fields["frame_type"] = "beacon"
        if (hasHourly) {
            fields["ctr"] = ctr
            fields["cur_hour"] = curHour
            fields["last_hour"] = lastHour
            fields["hourly_kWh"] = hourlyStr
        }
        if (hasReading) fields["reading_kWh"] = meterKwh.toDouble()
        fields["data_raw"] = dataRaw
        return listOf(Reading("Elster-PowerMeter", srcStr, fields))
    }
}

// unverified: elster_power_meter.c:282-380 (decode), elster_power_meter.c:274-277 (length bounds), struct elster_power_meter.c:404
internal object ElsterPowerMeter2 : Rtl433Decoder() {
    override val name = "Elster/Honeywell R2S/REXU power meter, type-2 frames"
    override val mod = Mod.FSK_PCM
    override val short = 7
    override val long = 7
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val rowBits = bb.bitsPerRow[0]
        if (rowBits < (ELSTER2_MIN_LEN + 2) * 8) return emptyList()
        val row = bb.bb[0]
        val buf = IntArray(ELSTER2_MAX_LEN + 2)
        var foundPos = -1
        var len = 0
        for (pos in 0..(rowBits - (ELSTER2_MIN_LEN + 2) * 8)) {
            val lenHi = bitrowGetByte(row, pos) xor 0xaa
            val lenLo = bitrowGetByte(row, pos + 8) xor 0xaa
            val candLen = (lenHi shl 8) or lenLo
            if (candLen < ELSTER2_MIN_LEN || candLen > ELSTER2_MAX_LEN) continue
            if (pos + (candLen + 2) * 8 > rowBits) continue
            for (i in 0 until candLen + 2) buf[i] = bitrowGetByte(row, pos + i * 8) xor 0xaa
            val chk = Rtl433BitUtil.crc16lsb(buf, candLen, 0x8408, 0xffff) xor 0xffff
            val chkRecv = buf[candLen] or (buf[candLen + 1] shl 8)
            if (chk == chkRecv) {
                foundPos = pos
                len = candLen
                break
            }
        }
        if (foundPos < 0) return emptyList()
        val src = (buf[3] shl 24) or (buf[4] shl 16) or (buf[5] shl 8) or buf[6]
        val dst = (buf[7] shl 24) or (buf[8] shl 16) or (buf[9] shl 8) or buf[10]
        val srcStr = Integer.toUnsignedString(src)
        val dstStr = Integer.toUnsignedString(dst)
        val isMesh = src < 0
        var msg = -1
        if (!isMesh && len > 16) msg = buf[16]
        var nbrIds = ""
        if ((msg == 0x57 || msg == 0x7f) && len > 30) {
            val n = buf[28]
            val recStart = if (msg == 0x57) 30 else 29
            if (n > 0 && n <= ELSTER2_NBR_MAX && recStart + n * 20 <= len) {
                nbrIds = (0 until n).joinToString(",") { i ->
                    val base = recStart + i * 20
                    String.format("%02x%02x%02x%02x", buf[base], buf[base + 1], buf[base + 2], buf[base + 3])
                }
            }
        }
        val dataRaw = (0 until len - 12).joinToString("") { String.format("%02x", buf[12 + it]) }
        val fields = linkedMapOf<String, Any?>(
            "dst" to dstStr,
            "mesh" to (if (isMesh) 1 else 0),
        )
        if (msg >= 0) fields["msg"] = String.format("%02x", msg)
        if (nbrIds.isNotEmpty()) fields["nbr_ids"] = nbrIds
        fields["data_raw"] = dataRaw
        return listOf(Reading("Elster-PowerMeter2", srcStr, fields))
    }
}

private fun adPop(bytes: IntArray, bits: Int, bit: Int): Int {
    var v = 0
    for (i in 0 until bits) {
        val byteNo = (bit + i) / 8
        val bitNo = 7 - ((bit + i) % 8)
        if ((bytes[byteNo] and (1 shl bitNo)) != 0) v = v or (1 shl i)
    }
    return v
}

// unverified: elv.c:32-99 (em1000_callback), elv.c:14-25 (AD_POP), struct elv.c:108 (upstream .disabled=1, ported enabled)
internal object ElvEm1000 : Rtl433Decoder() {
    override val name = "ELV EM 1000"
    override val mod = Mod.OOK_PPM
    override val short = 500
    override val long = 1000
    override val gap = 7250
    override val reset = 30000

    override fun decode(bb: BitBuffer): List<Reading> {
        val rows = bb.bb
        val bbP = IntArray(14)
        for (i in 0 until 14) {
            bbP[i] = when {
                rows[0][i] == rows[1][i] || rows[0][i] == rows[2][i] -> rows[0][i]
                rows[1][i] == rows[2][i] -> rows[1][i]
                else -> return emptyList()
            }
        }
        var bit = 18
        val dec = IntArray(9)
        var checksumCalculated = 0
        for (i in 0 until 9) {
            dec[i] = adPop(bbP, 8, bit)
            bit += 8
            val stopbit = adPop(bbP, 1, bit)
            bit += 1
            if (stopbit == 0) return emptyList()
            checksumCalculated = checksumCalculated xor dec[i]
        }
        val checksumReceived = adPop(bbP, 8, bit)
        if (checksumReceived != checksumCalculated) return emptyList()
        val code = dec[1]
        val seqno = dec[2]
        val total = dec[3] or (dec[4] shl 8)
        val current = dec[5] or (dec[6] shl 8)
        val peak = dec[7] or (dec[8] shl 8)
        return listOf(
            Reading(
                "ELV-EM1000",
                code.toString(),
                mapOf("seq" to seqno, "total" to total, "current" to current, "peak" to peak),
            ),
        )
    }
}

private val WS2000_TYPES = arrayOf("!AS3", "AS2000/ASH2000/S2000/S2001A/S2001IA/ASH2200/S300IA", "!S2000R", "!S2000W", "S2001I/S2001ID", "!S2500H", "!Pyrano", "KS200/KS300")

private val WS2000_LENGTH = intArrayOf(5, 8, 5, 8, 12, 9, 8, 14, 8)

// unverified: elv.c:171-260 (ws2000_callback), elv.c:14-25 (AD_POP), struct elv.c:118 (upstream .disabled=1, ported enabled)
internal object ElvWs2000 : Rtl433Decoder() {
    override val name = "ELV WS 2000"
    override val mod = Mod.OOK_PWM
    override val short = 366
    override val long = 854
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.bb[0]
        val dec = IntArray(16)
        var bit = 11
        dec[0] = adPop(row, 4, bit)
        bit += 4
        var stopbit = adPop(row, 1, bit)
        bit += 1
        if (stopbit == 0) return emptyList()
        var checkCalculated = dec[0]
        var sumCalculated = dec[0]
        val len = if (dec[0] < WS2000_LENGTH.size) WS2000_LENGTH[dec[0]] else 0
        for (i in 1..len) {
            dec[i] = adPop(row, 4, bit)
            bit += 4
            stopbit = adPop(row, 1, bit)
            bit += 1
            if (stopbit == 0) return emptyList()
            checkCalculated = checkCalculated xor dec[i]
            sumCalculated = (sumCalculated + dec[i]) and 0xFF
        }
        if (checkCalculated != 0) return emptyList()
        val sumReceived = adPop(row, 4, bit)
        sumCalculated = ((sumCalculated + 5) and 0xFF) and 0xF
        if (sumReceived != sumCalculated) return emptyList()
        val subtype = if (dec[0] <= 7) WS2000_TYPES[dec[0]] else "?"
        val code = dec[1] and 7
        val temp = (if ((dec[1] and 8) != 0) -1.0f else 1.0f) * ((dec[4] * 10 + dec[3]) + dec[2] * 0.1f)
        var humidity = (dec[7] * 10 + dec[6]) + dec[5] * 0.1f
        var pressure = 0
        var isKsx00 = false
        var itRains = 0
        var wind = 0f
        var rainsum = 0
        var unknown = 0
        if (dec[0] == 4) {
            pressure = 200 + dec[10] * 100 + dec[9] * 10 + dec[8]
        }
        if (dec[0] == 7) {
            isKsx00 = true
            itRains = if ((dec[1] and 2) != 0) 1 else 0
            humidity = (dec[6] * 10 + dec[5]).toFloat()
            wind = (dec[9] * 10 + dec[8]) + dec[7] * 0.1f
            rainsum = (dec[12] shl 8) + (dec[11] shl 4) + dec[10]
            unknown = dec[13]
        }
        val fields = linkedMapOf<String, Any?>(
            "subtype" to subtype,
            "temperature_C" to temp.toDouble(),
            "humidity" to humidity.toDouble(),
        )
        if (pressure != 0) fields["pressure_hPa"] = pressure
        if (isKsx00) {
            fields["wind_avg_km_h"] = wind.toDouble()
            fields["rain_count"] = rainsum
            fields["rain_mm"] = rainsum.toDouble() * 0.295
            fields["is_raining"] = itRains
            fields["unknown"] = unknown
        }
        return listOf(Reading("ELV-WS2000", code.toString(), fields))
    }
}

private val EMAX_PREAMBLE = intArrayOf(0xaa, 0xaa, 0xca, 0xca, 0x54)

private const val EMAX_MESSAGE_BITLEN = 264

// unverified: emax.c:135-320 (decode), emax.c:133 (EMAX_MESSAGE_BITLEN), struct emax.c:341
internal object Emax : Rtl433Decoder() {
    override val name = "Emax W6, rebrand Altronics x7063/4/x7064A, Optex 990040/50/51, Orium 13093/13123, Infactory FWS-1200, Newentor Q9, Otio 810025, Protmex PT3390A, Jula Marquant 014331/32, TechniSat IMETEO X6 76-4924-00, Weather Station or temperature/humidity sensor"
    override val mod = Mod.FSK_PCM
    override val short = 90
    override val long = 90
    override val reset = 9000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        var pos = 0
        while (true) {
            pos = bb.search(0, pos, EMAX_PREAMBLE, 40)
            if (pos + EMAX_MESSAGE_BITLEN > bb.bitsPerRow[0]) break
            pos += 40
            if (pos + 32 * 8 > bb.bitsPerRow[0]) continue
            val b = IntArray(32)
            bb.extractBytes(0, pos, b, 32 * 8)
            val kind = (b[1] and 0xf0) shr 4
            val subtype = b[3] and 0x03
            var checksum = Rtl433BitUtil.addBytes(b, 31)
            if (kind != 0 && subtype == 0x3) checksum -= 0x9A
            if ((checksum and 0xff) != b[31]) continue
            val channel = b[1] and 0x0f
            val id = (b[2] shl 4) or (b[3] shr 4)
            val idStr = String.format("%03x", id)
            val batteryOk = if ((b[3] and 0x08) == 0) 1 else 0
            val pairing = b[3] and 0x04
            if (kind != 0) {
                val tempRaw = ((b[4] and 0x0f) shl 8) or (b[5] and 0xf0) or (b[6] and 0x0f)
                val model = when (subtype) {
                    0x1 -> "Altronics-X7064"
                    0x3 -> "Altronics-X7064A"
                    else -> return emptyList()
                }
                val fields = linkedMapOf<String, Any?>("channel" to channel, "battery_ok" to batteryOk)
                if (subtype == 0x1) {
                    fields["temperature_F"] = ((tempRaw - 900) * 0.1f).toDouble()
                } else {
                    fields["temperature_C"] = ((tempRaw - 500) * 0.1f).toDouble()
                }
                fields["humidity"] = b[7]
                if (pairing != 0) fields["pairing"] = 1
                return listOf(Reading(model, idStr, fields))
            }
            val tempRaw = ((b[4] and 0x0f) shl 8) or b[5]
            val tempF = (tempRaw - 900) * 0.1f
            val humidity = b[6]
            val windRaw = (((b[7] - 1) and 0xff) shl 8) or ((b[8] - 1) and 0xff)
            val speedKmh = windRaw * 0.2f
            val directionDeg = (((b[9] - 1) and 0x0f) shl 8) or ((b[10] - 1) and 0xff)
            val rainRaw = (((b[11] - 1) and 0xff) shl 8) or ((b[12] - 1) and 0xff)
            val rainMm = rainRaw * 0.2f
            if (b[29] == 0x17) {
                val uvIndex = (b[13] - 1) and 0x1f
                val lux14 = (b[14] - 1) and 0xFF
                val lux15 = (b[15] - 1) and 0xFF
                val luxMulti = (lux14 and 0x80) shr 7
                var lightLux = ((lux14 and 0x7f) shl 8) or lux15
                if (luxMulti == 1) lightLux *= 10
                val tag = ((b[13] - 1) and 0xC0) shr 6
                val fields = linkedMapOf<String, Any?>(
                    "channel" to channel,
                    "battery_ok" to batteryOk,
                    "temperature_F" to tempF.toDouble(),
                    "humidity" to humidity,
                    "wind_avg_km_h" to speedKmh.toDouble(),
                    "wind_dir_deg" to directionDeg,
                    "rain_mm" to rainMm.toDouble(),
                )
                if (tag != 3) {
                    fields["uvi"] = uvIndex.toDouble()
                    fields["light_lux"] = lightLux
                }
                if (pairing != 0) fields["pairing"] = 1
                return listOf(Reading(if (tag != 3) "Emax-W6" else "IMETEO-X6", idStr, fields))
            }
            if (b[29] == 0x16 && b[14] == 0x01 && b[15] == 0x01) {
                val gustKmh = b[16] / 1.5f
                val fields = linkedMapOf<String, Any?>(
                    "channel" to channel,
                    "battery_ok" to batteryOk,
                    "temperature_F" to tempF.toDouble(),
                    "humidity" to humidity,
                    "wind_avg_km_h" to speedKmh.toDouble(),
                    "wind_max_km_h" to gustKmh.toDouble(),
                    "wind_dir_deg" to directionDeg,
                    "rain_mm" to rainMm.toDouble(),
                )
                if (pairing != 0) fields["pairing"] = 1
                return listOf(Reading("Emax-EM3551H", idStr, fields))
            }
            if (b[29] == 0x16) {
                val tempC = (tempRaw - 500) * 0.1f
                val gustKmh = b[16] / 1.5f
                val uvIndex = (b[13] - 1) and 0x1f
                val lux14 = (b[14] - 1) and 0xff
                val lux15 = (b[15] - 1) and 0xff
                val luxMulti = (lux14 and 0x80) shr 7
                var lightLux = ((lux14 and 0x7f) shl 8) or lux15
                if (luxMulti == 1) lightLux *= 10
                val fields = linkedMapOf<String, Any?>(
                    "channel" to channel,
                    "battery_ok" to batteryOk,
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "wind_avg_km_h" to speedKmh.toDouble(),
                    "wind_max_km_h" to gustKmh.toDouble(),
                    "wind_dir_deg" to directionDeg,
                    "rain_mm" to rainMm.toDouble(),
                    "uvi" to uvIndex.toDouble(),
                    "light_lux" to lightLux,
                )
                if (pairing != 0) fields["pairing"] = 1
                return listOf(Reading("Lacrosse-WS6262", idStr, fields))
            }
            pos += EMAX_MESSAGE_BITLEN
        }
        return emptyList()
    }
}

private fun s16(x: Int): Int = x.toShort().toInt()

private val EMONTX_PREAMBLE = intArrayOf(0xaa, 0xaa, 0xaa)
private val EMONTX_PKT_HDR_INVERTED = intArrayOf(0xd2, 0x2d, 0xc0)
private val EMONTX_PKT_HDR = intArrayOf(0x2d, 0xd2, 0x00)

// unverified: emontx.c:45-127 (callback), emontx.c:19-30 (preamble and headers), struct emontx.c:160; float widths truncated to Int (short/long 20.30 -> 20)
internal object Emontx : Rtl433Decoder() {
    override val name = "emonTx OpenEnergyMonitor"
    override val mod = Mod.FSK_PCM
    override val short = 20
    override val long = 20
    override val reset = 1200

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        var bitpos = 0
        while (true) {
            bitpos = bb.search(0, bitpos, EMONTX_PREAMBLE, 22)
            if (bitpos >= bb.bitsPerRow[0]) break
            bitpos += 22
            while (bb.search(0, bitpos, EMONTX_PREAMBLE, 2) == bitpos) bitpos += 2
            bitpos--
            var pktPos = bb.search(0, bitpos, EMONTX_PKT_HDR, 11)
            var inverted = false
            if (pktPos > bitpos + 5) {
                pktPos = bb.search(0, bitpos, EMONTX_PKT_HDR_INVERTED, 11)
                if (pktPos > bitpos + 5) continue
                inverted = true
            }
            if (pktPos + 33 * 8 > bb.bitsPerRow[0]) break
            val pkt = IntArray(33)
            bb.extractBytes(0, pktPos, pkt, 33 * 8)
            if (inverted) {
                for (i in 0 until 33) pkt[i] = pkt[i] xor 0xff
            }
            if (pkt[3] != 0x1a || pkt[32] != 0xaa) continue
            val crc = Rtl433BitUtil.crc16lsb(pkt.copyOfRange(1, 30), 29, 0xa001, 0xffff)
            val words = IntArray(14) { pkt[4 + it * 2] or (pkt[5 + it * 2] shl 8) }
            if (crc != words[13]) continue
            val vrms = words[4].toFloat() / 100.0f
            val fields = linkedMapOf<String, Any?>(
                "node" to String.format("%02x", pkt[2] and 0x1f),
                "ct1" to s16(words[0]),
                "ct2" to s16(words[1]),
                "ct3" to s16(words[2]),
                "ct4" to s16(words[3]),
                "batt_Vrms" to vrms.toDouble(),
                "pulse" to ((words[11] or (words[12] shl 16)).toLong() and 0xFFFFFFFFL),
            )
            for (k in 0 until 6) {
                val t = words[5 + k]
                if (t != 3000) fields["temp${k + 1}_C"] = (t * 0.1f).toDouble()
            }
            out.add(Reading("emonTx-Energy", null, fields))
        }
        return out
    }
}

// unverified: emos_e6016.c:66-135 (decode), emos_e6016.c:156 (repeated-prefix search), struct emos_e6016.c:152
internal object EmosE6016 : Rtl433Decoder() {
    override val name = "EMOS E6016 weatherstation with DCF77, EMOS E6018 temperature/humidity sensor"
    override val mod = Mod.OOK_PWM
    override val short = 280
    override val long = 796
    override val gap = 3000
    override val reset = 850
    override val sync = 1836

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedPrefix(3, 120 - 8)
        if (row < 0) return emptyList()
        val b = bb.bb[row]
        if (bb.bitsPerRow[row] != 120) return emptyList()
        if (b[0] != 0x55 || b[1] != 0x5a || b[2] != 0x7c) return emptyList()
        bb.invert()
        if ((Rtl433BitUtil.addBytes(b, 13) and 0xff) != b[13]) return emptyList()
        val id = b[3]
        val variant = (b[4] shr 6) and 0x3
        val is2e6018 = variant != 2
        val battery = (b[12] shr 2) and 0x1
        val dcf77 = ((b[4] and 0x3f) shl 26) or (b[5] shl 18) or (b[6] shl 10) or (b[7] shl 2) or (b[8] shr 6)
        val dcf77Sec = (dcf77 shr 0) and 0x3f
        val dcf77Min = (dcf77 shr 6) and 0x3f
        val dcf77Hour = (dcf77 shr 12) and 0x1f
        val dcf77Day = (dcf77 shr 17) and 0x1f
        val dcf77Mth = (dcf77 shr 22) and 0x0f
        val dcf77Year = (dcf77 shr 26) and 0x3f
        val channel = ((b[8] shr 4) and 0x3) + 1
        val tempRaw = s16(((b[8] and 0x0f) shl 12) or (b[9] shl 4))
        val tempC = (tempRaw shr 4) * 0.1f
        val humidity = b[10]
        val speedMs = b[11] * 0.295f
        val dirRaw = (b[12] and 0xf0) shr 4
        val dirDeg = dirRaw * 22.5f
        val fields = linkedMapOf<String, Any?>(
            "channel" to channel,
            "battery_ok" to battery,
            "temperature_C" to tempC.toDouble(),
            "humidity" to humidity,
        )
        if (!is2e6018) {
            fields["wind_avg_m_s"] = speedMs.toDouble()
            fields["wind_dir_deg"] = dirDeg.toDouble()
            fields["radio_clock"] = String.format(
                "%4d-%02d-%02dT%02d:%02d:%02d",
                dcf77Year + 2000, dcf77Mth, dcf77Day, dcf77Hour, dcf77Min, dcf77Sec,
            )
        }
        return listOf(Reading(if (is2e6018) "EMOS-E6018" else "EMOS-E6016", id.toString(), fields))
    }
}

// unverified: emos_e6016_rain.c:52-83 (decode), emos_e6016_rain.c:112 (struct)
internal object EmosE6016Rain : Rtl433Decoder() {
    override val name = "EMOS E6016 rain gauge"
    override val mod = Mod.OOK_PWM
    override val short = 300
    override val long = 800
    override val gap = 1000
    override val reset = 2500

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(3, 72)
        if (r < 0) return emptyList()
        val b = bb.bb[r]
        if (bb.bitsPerRow[r] < 72 || bb.bitsPerRow[r] > 73) return emptyList()
        if (b[0] != 0x55 || b[1] != 0x5a || b[2] != 0x75) return emptyList()
        bb.invert()
        if ((Rtl433BitUtil.addBytes(b, 8) and 0xff) != b[8]) return emptyList()
        val id = b[3]
        val battery = b[4] shr 6
        val rainRaw = ((b[6] and 0x0f) shl 8) or b[7]
        val rainMm = rainRaw * 0.7f
        return listOf(
            Reading(
                "EMOS-E6016R",
                id.toString(),
                mapOf("battery_ok" to (if (battery != 0) 1 else 0), "rain_mm" to rainMm.toDouble()),
            ),
        )
    }
}

private fun extractU16(bb: BitBuffer, pos: Int): Int {
    val t = IntArray(2)
    bb.extractBytes(0, pos, t, 16)
    return (t[0] shl 8) or t[1]
}

// unverified: en2058.c:43-160 (decode; sanity checks for temp2-4 test temp1_F as in upstream), struct en2058.c:166
internal object En2058 : Rtl433Decoder() {
    override val name = "EN2058 four probe temperature sensor"
    override val mod = Mod.FSK_PCM
    override val short = 100
    override val long = 100
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1 || bb.bitsPerRow[0] < 174) return emptyList()
        var offset = 0
        for (i in 0 until 9) {
            offset = bb.search(0, offset, intArrayOf(0xff, 0xfe, 0, 0), 30)
            if (offset >= bb.bitsPerRow[0]) return emptyList()
            offset += 30
            if (offset + 56 + 24 + 16 + 8 + 8 + 144 > bb.bitsPerRow[0]) return emptyList()
            val idBytes = IntArray(3)
            bb.extractBytes(0, offset + 56, idBytes, 24)
            val id = (idBytes[0] shl 16) or (idBytes[1] shl 8) or idBytes[2]
            val dataBytes = IntArray(10)
            bb.extractBytes(0, offset + 80, dataBytes, 80)
            val checksum = (0x56 + Rtl433BitUtil.addBytes(idBytes, 3) + Rtl433BitUtil.addBytes(dataBytes, 8)) and 0xff
            if (checksum != dataBytes[9]) continue
            val temp1Raw = extractU16(bb, offset + 80)
            val temp1 = (temp1Raw - 900) * 0.1f
            val temp2Raw = extractU16(bb, offset + 80 + 16)
            val temp2 = (temp2Raw - 900) * 0.1f
            val temp3Raw = extractU16(bb, offset + 80 + 32)
            val temp3 = (temp3Raw - 900) * 0.1f
            val temp4Raw = extractU16(bb, offset + 80 + 48)
            val temp4 = (temp4Raw - 900) * 0.1f
            if (temp1Raw >= 0xff && (temp1 < -4.0f || temp1 > 572.0f)) return emptyList()
            if (temp2Raw >= 0xff && (temp2 < -4.0f || temp1 > 572.0f)) return emptyList()
            if (temp3Raw >= 0xff && (temp3 < -4.0f || temp1 > 572.0f)) return emptyList()
            if (temp4Raw >= 0xff && (temp4 < -4.0f || temp1 > 572.0f)) return emptyList()
            val hasSequence = offset + 320 <= bb.bitsPerRow[0]
            var sequence = 0
            if (hasSequence) {
                val seqBytes = IntArray(2)
                bb.extractBytes(0, offset + 304, seqBytes, 16)
                sequence = seqBytes[0]
            }
            val fields = linkedMapOf<String, Any?>()
            if (temp1Raw != 0x00c8) fields["temperature_1_F"] = temp1.toDouble()
            if (temp2Raw != 0x00c8) fields["temperature_2_F"] = temp2.toDouble()
            if (temp3Raw != 0x00c8) fields["temperature_3_F"] = temp3.toDouble()
            if (temp4Raw != 0x00c8) fields["temperature_4_F"] = temp4.toDouble()
            if (hasSequence) fields["sequence"] = sequence
            return listOf(Reading("EN2058", id.toString(), fields))
        }
        return emptyList()
    }
}

// unverified: ert_scm.c:48-94 (decode), struct ert_scm.c:109
internal object ErtScm : Rtl433Decoder() {
    override val name = "ERT Standard Consumption Message (SCM)"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 30
    override val reset = 64

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 96) return emptyList()
        val b = bb.bb[0]
        if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0) return emptyList()
        if (Rtl433BitUtil.crc16(b.copyOfRange(2, 12), 10, 0x6F63, 0) != 0) return emptyList()
        val physicalTamper = (b[3] and 0xC0) shr 6
        val ertType = (b[3] shr 2) and 0x0F
        val encoderTamper = b[3] and 0x03
        val consumptionData = (b[4] shl 16) or (b[5] shl 8) or b[6]
        val ertId = ((b[2] and 0x06) shl 23) or (b[7] shl 16) or (b[8] shl 8) or b[9]
        return listOf(
            Reading(
                "ERT-SCM",
                ertId.toString(),
                mapOf(
                    "physical_tamper" to physicalTamper,
                    "ert_type" to ertType,
                    "encoder_tamper" to encoderTamper,
                    "consumption_data" to consumptionData,
                ),
            ),
        )
    }
}

private fun enoceanDecode8of12(b: IntArray, pos: Int, end: Int, out: BitBuffer): Int {
    if (pos + 12 > end) return -1
    out.addBit(bitrowGetBit(b, pos + 0))
    out.addBit(bitrowGetBit(b, pos + 1))
    val b2 = bitrowGetBit(b, pos + 2)
    out.addBit(b2)
    if (b2 != (1 - bitrowGetBit(b, pos + 3))) return -1
    out.addBit(bitrowGetBit(b, pos + 4))
    out.addBit(bitrowGetBit(b, pos + 5))
    val b6 = bitrowGetBit(b, pos + 6)
    out.addBit(b6)
    if (b6 != (1 - bitrowGetBit(b, pos + 7))) return -1
    out.addBit(bitrowGetBit(b, pos + 8))
    out.addBit(bitrowGetBit(b, pos + 9))
    return (bitrowGetBit(b, pos + 10) shl 1) or bitrowGetBit(b, pos + 11)
}

// unverified: enocean_erp1.c:21-46 (decode_8of12), enocean_erp1.c:48-85 (decode), struct enocean_erp1.c:100 (upstream .disabled=1, ported enabled)
internal object EnoceanErp1 : Rtl433Decoder() {
    override val name = "EnOcean ERP1"
    override val mod = Mod.OOK_PCM
    override val short = 8
    override val long = 8
    override val tolerance = 1
    override val reset = 800

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        bb.invert()
        val start = bb.search(0, 0, intArrayOf(0x55, 0x20), 11)
        if (start >= bb.bitsPerRow[0]) return emptyList()
        var pos = start + 11
        val len = bb.bitsPerRow[0] - start
        val end = start + len
        val bytes = BitBuffer()
        var more: Int
        do {
            more = enoceanDecode8of12(bb.bb[0], pos, end, bytes)
            pos += 12
        } while (pos < end && more == 1)
        if (bytes.bitsPerRow[0] < 16) return emptyList()
        val chk = Rtl433BitUtil.crc8(bytes.bb[0], (bytes.bitsPerRow[0] - 1) / 8, 0x07, 0x00)
        if (chk != bitrowGetByte(bytes.bb[0], bytes.bitsPerRow[0] - 8)) return emptyList()
        val telegram = bitrowSnprint(bytes.bb[0], bytes.bitsPerRow[0])
        return listOf(Reading("EnOcean-ERP1", null, mapOf("telegram" to telegram)))
    }
}

// unverified: esic_emt7110.c:43-86 (decode), struct esic_emt7110.c:107
internal object EsicEmt7110 : Rtl433Decoder() {
    override val name = "ESIC EMT7110 power meter"
    override val mod = Mod.FSK_PCM
    override val short = 104
    override val long = 104
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        if (bb.bitsPerRow[0] < 120 || bb.bitsPerRow[0] > 140) return emptyList()
        var offset = bb.search(0, 0, intArrayOf(0xAA, 0x2D, 0xD4), 24)
        offset += 24
        if (offset > bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(12)
        bb.extractBytes(0, offset, b, 96)
        if ((Rtl433BitUtil.addBytes(b, 12) and 0xff) != 0) return emptyList()
        val id = (b[0] shl 24) or (b[1] shl 16) or (b[2] shl 8) or b[3]
        val pairing = (b[4] and 0x80) shr 7
        val connected = (b[4] and 0x40) shr 6
        val powerRaw = ((b[4] and 0x3f) shl 8) or b[5]
        val powerW = powerRaw * 0.5f
        val currentMa = (b[6] shl 8) or b[7]
        val currentA = currentMa * 0.001f
        val voltageV = (b[8] + 256) * 0.5f
        val energyRaw = ((b[9] and 0x3f) shl 8) or b[10]
        val energyKwh = energyRaw * 0.01f
        return listOf(
            Reading(
                "ESIC-EMT7110",
                String.format("%08x", id),
                mapOf(
                    "power_W" to powerW.toDouble(),
                    "current_A" to currentA.toDouble(),
                    "voltage_V" to voltageV.toDouble(),
                    "energy_kWh" to energyKwh.toDouble(),
                    "pairing" to pairing,
                    "connected" to connected,
                ),
            ),
        )
    }
}

private fun crc4(message: IntArray, nBytes: Int, polynomial: Int, init: Int): Int {
    var remainder = init shl 4
    val poly = polynomial shl 4
    for (n in 0 until nBytes) {
        remainder = remainder xor message[n]
        for (bit in 0 until 8) {
            remainder = if ((remainder and 0x80) != 0) (remainder shl 1) xor poly else remainder shl 1
        }
    }
    return (remainder shr 4) and 0x0f
}

// unverified: esperanza_ews.c:64-108 (callback), bit_util.c:240 (crc4), struct esperanza_ews.c:126
internal object EsperanzaEws : Rtl433Decoder() {
    override val name = "Esperanza EWS"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 4400
    override val reset = 9400

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 0 || bb.bitsPerRow[1] != 0) return emptyList()
        if (bb.numRows != 14) return emptyList()
        var row = 2
        while (row < bb.numRows - 3) {
            if (!bb.bb[row].contentEquals(bb.bb[row + 2]) || bb.bitsPerRow[row] != 42) return emptyList()
            row += 2
        }
        val b = IntArray(5)
        bb.extractBytes(2, 2, b, 40)
        val crc = crc4(b, 4, 0x3, 0x0) xor (b[4] shr 4)
        if (crc != (b[4] and 0xf)) return emptyList()
        val deviceId = b[0]
        val channel = ((b[1] and 0x30) shr 4) + 1
        val batteryLow = (b[4] and 0x40) == 0x40
        val tempRaw = ((b[2] and 0x0f) shl 8) or (b[2] and 0xf0) or (b[1] and 0x0f)
        val tempF = (tempRaw - 900) * 0.1f
        val humidity = ((b[3] and 0x0f) shl 4) or ((b[3] and 0xf0) shr 4)
        return listOf(
            Reading(
                "Esperanza-EWS",
                deviceId.toString(),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to (if (batteryLow) 0 else 1),
                    "temperature_F" to tempF.toDouble(),
                    "humidity" to humidity,
                ),
            ),
        )
    }
}

// unverified: esun_en2053.c:57-93 (decode), struct esun_en2053.c:109
internal object EsunEn2053 : Rtl433Decoder() {
    override val name = "Esun EN2053 two-channel BBQ thermometer"
    override val mod = Mod.OOK_PPM
    override val short = 1024
    override val long = 2000
    override val gap = 3000
    override val reset = 7500

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(2, 40)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] != 40) return emptyList()
        val b = bb.bb[row]
        if (b[0] != 0xc0) return emptyList()
        var chk = (b[0] + b[1] + b[2] + b[3]) and 0x07
        for (i in 0 until 4) {
            chk = chk or ((1 xor Rtl433BitUtil.parity8(b[i])) shl (4 + i))
        }
        if (chk != b[4]) return emptyList()
        val temp1Raw = (b[1] shl 4) or (b[2] shr 4)
        val temp2Raw = ((b[2] and 0x0f) shl 8) or b[3]
        val fields = linkedMapOf<String, Any?>()
        if (temp1Raw != 0xfd6) fields["temperature_1_F"] = temp1Raw
        if (temp2Raw != 0xfd6) fields["temperature_2_F"] = temp2Raw
        return listOf(Reading("Esun-EN2053", null, fields))
    }
}

// unverified: eurochron.c:37-75 (decode), struct eurochron.c:96 (upstream .disabled=1, ported enabled)
internal object Eurochron : Rtl433Decoder() {
    override val name = "Eurochron temperature and humidity sensor"
    override val mod = Mod.OOK_PPM
    override val short = 1016
    override val long = 2024
    override val gap = 2100
    override val reset = 8200

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(3, 36)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] > 36) return emptyList()
        val b = bb.bb[row]
        if ((b[1] and 0x0F) != 0) return emptyList()
        val device = b[0]
        val tempRaw = s16((b[3] shl 8) or (b[4] and 0xf0))
        val tempC = (tempRaw shr 4) * 0.1f
        val humidity = b[2]
        val batteryLow = b[1] shr 7
        val button = (b[1] and 0x10) shr 4
        return listOf(
            Reading(
                "Eurochron-TH",
                device.toString(),
                mapOf(
                    "battery_ok" to (if (batteryLow == 0) 1 else 0),
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "button" to button,
                ),
            ),
        )
    }
}

// unverified: efth800.c:46-124 (decode), struct efth800.c:137
internal object EurochronEfth800 : Rtl433Decoder() {
    override val name = "Eurochron EFTH-800 temperature and humidity sensor"
    override val mod = Mod.OOK_PWM
    override val short = 250
    override val long = 500
    override val sync = 750
    override val gap = 900
    override val reset = 5500

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        var radioClock: String? = null
        var row = bb.findRepeatedRow(2, 65)
        if (row > 0) {
            val c = bb.bb[row]
            val dcfHour = c[2] and 0x1f
            val dcfMin = c[3] and 0x3f
            val dcfSec = c[4] and 0x3f
            val dcfYear = c[5] shr 1
            val dcfDay = ((c[5] and 0x01) shl 4) or ((c[6] and 0xf0) shr 4)
            val dcfMth = c[6] and 0x0f
            if (Rtl433BitUtil.crc8(c, 8, 0x31, 0x00) == 0) {
                radioClock = String.format(
                    "%4d-%02d-%02dT%02d:%02d:%02d",
                    dcfYear + 2000, dcfMth, dcfDay, dcfHour, dcfMin, dcfSec,
                )
            }
        }
        for (r in 0 until bb.numRows) {
            if (bb.bitsPerRow[r] > 49) bb.bitsPerRow[r] = 0
        }
        row = bb.findRepeatedRow(2, 48)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] > 49) return emptyList()
        val b = bb.bb[row]
        if (b[0] == 0x00 && b[1] == 0x00 && b[2] == 0x00 && b[4] == 0x00) return emptyList()
        if (Rtl433BitUtil.crc8(b, 6, 0x31, 0x00) != 0) return emptyList()
        val channel = (b[0] and 0x70) shr 4
        val id = ((b[0] and 0x0f) shl 8) or b[1]
        val batteryLow = b[2] shr 7
        val tempRaw = s16((b[2] and 0x3f) shl 10) or ((b[3] and 0xf0) shl 2)
        val tempC = (tempRaw shr 6) * 0.1f
        val humidity = (b[4] shr 4) * 10 + (b[4] and 0xf)
        val fields = linkedMapOf<String, Any?>(
            "channel" to channel + 1,
            "battery_ok" to (if (batteryLow == 0) 1 else 0),
            "temperature_C" to tempC.toDouble(),
            "humidity" to humidity,
        )
        if (radioClock != null) fields["radio_clock"] = radioClock
        return listOf(Reading("Eurochron-EFTH800", id.toString(), fields))
    }
}

private fun decryptEsa(b: IntArray, blen: Int): Int {
    var pos = 0
    var salt = 0x89
    var crc = 0
    for (i in 0 until blen - 3) {
        val byte = b[pos]
        crc = (crc + byte) and 0xFFFF
        b[pos] = b[pos] xor salt
        pos++
        salt = (byte + 0x24) and 0xFF
    }
    crc = (crc + b[pos]) and 0xFFFF
    b[pos] = b[pos] xor 0xff
    pos++
    return (((b[blen - 2] shl 8) or b[blen - 1]) - crc) and 0xFFFF
}

// unverified: esa.c:72-194 (esa_cost_callback), esa.c:14-44 (decrypt_esa), struct esa.c:215 (upstream .disabled=1, ported enabled)
internal object EsaEnergy : Rtl433Decoder() {
    override val name = "ESA1000 / ESA2000 Energy Monitor, GIRA Wetterstation"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 260
    override val reset = 3000

    override fun decode(bb: BitBuffer): List<Reading> {
        val len = bb.bitsPerRow[0]
        if (!(len == 176 || len == 160) || bb.numRows != 1) return emptyList()
        val b = IntArray(40)
        bb.extractBytes(0, 16, b, len - 16)
        val crc = decryptEsa(b, len / 8 - 2)
        if (crc == 0xf00f) {
            val isRetry = b[0] shr 7
            val sequenceId = b[0] and 0x7f
            val deviceId = (b[1] shl 8) or b[2]
            val impulsesVal = (b[9] shl 8) or b[10]
            val impulsesTotal = ((b[5] shl 24) or (b[6] shl 16) or (b[7] shl 8) or b[8]).toLong() and 0xFFFFFFFFL
            val impulseConstant = ((b[14] shl 8) or b[15]) xor b[1]
            val energyTotal = 1.0f * impulsesTotal / impulseConstant
            val energyImpulse = 1.0f * impulsesVal / impulseConstant
            val model = when (b[3]) {
                0x01 -> "ESAx000WZ"
                0x03 -> "ESA1000Z"
                else -> "ESA-unknown"
            }
            return listOf(
                Reading(
                    model,
                    deviceId.toString(),
                    mapOf(
                        "impulses" to impulsesVal,
                        "impulses_total" to impulsesTotal,
                        "impulse_constant" to impulseConstant,
                        "total_kWh" to energyTotal.toDouble(),
                        "impulse_kWh" to energyImpulse.toDouble(),
                        "sequence_id" to sequenceId,
                        "is_retry" to isRetry,
                    ),
                ),
            )
        }
        if (crc == 0xee11) {
            val isRetry = (b[0] shr 6) and 0x01
            val sequenceId = b[0] and 0x3f
            val deviceId = (b[1] shl 8) or b[2]
            val status = (b[3] shl 8) or b[4]
            val impulsesVal = (b[11] shl 8) or b[12]
            val impulsesTotal = ((b[8] shl 16) or (b[9] shl 8) or b[10]).toLong() and 0xFFFFFFFFL
            val impulseConstant = (b[16] shl 8) or (b[17] xor b[1])
            val energyTotal = 1.0f * impulsesTotal / impulseConstant
            val energyImpulse = 1.0f * impulsesVal / impulseConstant
            val power = (b[6] shl 8) or b[7]
            return listOf(
                Reading(
                    "Gira-EHZ",
                    deviceId.toString(),
                    mapOf(
                        "impulses" to impulsesVal,
                        "impulses_total" to impulsesTotal,
                        "impulse_constant" to impulseConstant,
                        "total_kWh" to energyTotal.toDouble(),
                        "impulse_kWh" to energyImpulse.toDouble(),
                        "sequence_id" to sequenceId,
                        "is_retry" to isRetry,
                        "status" to status,
                        "power" to power,
                    ),
                ),
            )
        }
        return emptyList()
    }
}

// unverified: fineoffset_wh31l.c:88-140 (decode), struct fineoffset_wh31l.c:169
internal object FineoffsetWh31l : Rtl433Decoder() {
    override val name = "Ambient Weather WH31L (FineOffset WH57) Lightning-Strike sensor"
    override val mod = Mod.FSK_PCM
    override val short = 56
    override val long = 56
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> {
        val startPos = bb.search(0, 0, intArrayOf(0xaa, 0x2d, 0xd4), 24)
        if (startPos == bb.bitsPerRow[0]) return emptyList()
        val b = IntArray(9)
        bb.extractBytes(0, startPos + 24, b, 9 * 8)
        if (b[0] != 0x57) return emptyList()
        if (Rtl433BitUtil.crc8(b, 8, 0x31, 0x00) != 0) return emptyList()
        if (((Rtl433BitUtil.addBytes(b, 8) - b[8]) and 0xFF) != 0) return emptyList()
        val state = b[1] shr 4
        val id = ((b[1] and 0xf) shl 16) or (b[2] shl 8) or b[3]
        val flags = (state shl 12) or (b[4] shl 4) or (b[5] shr 4)
        val batteryOk = (b[4] and 0x06) shr 1
        val sDist = b[5] and 0x3f
        val sCount = b[6]
        val stateStr = when (state) {
            0 -> "reset"
            1 -> "interference"
            4 -> "noise"
            8 -> "strike"
            else -> "unknown"
        }
        val fields = linkedMapOf<String, Any?>(
            "battery_ok" to (batteryOk * 0.5f).toDouble(),
            "state" to stateStr,
            "flags" to flags,
        )
        if (sDist != 63) fields["storm_dist_km"] = sDist
        fields["strike_count"] = sCount
        return listOf(Reading("FineOffset-WH31L", id.toString(), fields))
    }
}

// unverified: fineoffset_wh43.c:85-130 (decode), struct fineoffset_wh43.c:149
internal object FineoffsetWh43 : Rtl433Decoder() {
    override val name = "Fine Offset Electronics WH43 air quality sensor"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 2500

    override fun decode(bb: BitBuffer): List<Reading> {
        val bitOffset = bb.search(0, 0, intArrayOf(0xAA, 0x2D, 0xD4), 24) + 24
        val b = IntArray(10)
        if (bitOffset + 10 * 8 > bb.bitsPerRow[0]) return emptyList()
        bb.extractBytes(0, bitOffset, b, 10 * 8)
        if (b[0] != 0x43) return emptyList()
        val crc = Rtl433BitUtil.crc8(b, 8, 0x31, 0x00)
        val sum = Rtl433BitUtil.addBytes(b, 9) and 0xff
        if (crc != b[8] || sum != b[9]) return emptyList()
        val id = (b[1] shl 16) or (b[2] shl 8) or b[3]
        val pm25 = ((b[4] and 0x3F) shl 8) or b[5]
        val pm100 = ((b[6] and 0x3F) shl 8) or b[7]
        val battBars = ((b[4] and 0x40) shr 4) or ((b[6] and 0xC0) shr 6)
        val extPower = if (battBars == 6) 1 else 0
        val battLvl = minOf(battBars * 0.2f, 1.0f)
        return listOf(
            Reading(
                "Fineoffset-WH43",
                String.format("%06x", id),
                mapOf(
                    "battery_ok" to (if (battBars > 1) 1 else 0),
                    "battery_pct" to (100 * battLvl).toInt(),
                    "ext_power" to extPower,
                    "pm2_5_ug_m3" to pm25 / 10,
                    "estimated_pm10_0_ug_m3" to pm100 / 10,
                ),
            ),
        )
    }
}

// unverified: fineoffset_wh45.c:64-125 (decode), struct fineoffset_wh45.c:145
internal object FineoffsetWh45 : Rtl433Decoder() {
    override val name = "Fine Offset Electronics WH45 air quality sensor"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 2500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 170 || bb.bitsPerRow[0] > 240) return emptyList()
        val bitOffset = bb.search(0, 0, intArrayOf(0xaa, 0x2d, 0xd4), 24) + 24
        val b = IntArray(15)
        if (bitOffset + 15 * 8 > bb.bitsPerRow[0]) return emptyList()
        bb.extractBytes(0, bitOffset, b, 15 * 8)
        if (b[0] != 0x45) return emptyList()
        val crc = Rtl433BitUtil.crc8(b, 13, 0x31, 0x00)
        val chk = Rtl433BitUtil.addBytes(b, 14) and 0xff
        if (crc != b[13] || chk != b[14]) return emptyList()
        val id = (b[1] shl 16) or (b[2] shl 8) or b[3]
        val tempRaw = ((b[4] and 0x7) shl 8) or b[5]
        val tempC = (tempRaw - 400) * 0.1f
        val humidity = b[6]
        val battBars = ((b[7] and 0x40) shr 4) or ((b[9] and 0xC0) shr 6)
        val extPower = if (battBars == 6) 1 else 0
        val batteryOk = minOf(battBars * 0.2f, 1.0f)
        val pm25Raw = ((b[7] and 0x3f) shl 8) or b[8]
        val pm25 = pm25Raw * 0.1f
        val pm10Raw = ((b[9] and 0x3f) shl 8) or b[10]
        val pm10 = pm10Raw * 0.1f
        val co2 = (b[11] shl 8) or b[12]
        return listOf(
            Reading(
                "Fineoffset-WH45",
                String.format("%06x", id),
                mapOf(
                    "battery_ok" to batteryOk.toDouble(),
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "pm2_5_ug_m3" to pm25.toDouble(),
                    "pm10_ug_m3" to pm10.toDouble(),
                    "co2_ppm" to co2,
                    "ext_power" to extPower,
                ),
            ),
        )
    }
}

// unverified: fineoffset_wh46.c:60-120 (decode), struct fineoffset_wh46.c:152
internal object FineoffsetWh46 : Rtl433Decoder() {
    override val name = "Fine Offset Electronics WH46 air quality sensor"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 2500

    override fun decode(bb: BitBuffer): List<Reading> {
        val bitOffset = bb.search(0, 0, intArrayOf(0xaa, 0x2d, 0xd4), 24) + 24
        val b = IntArray(21)
        if (bitOffset + 21 * 8 > bb.bitsPerRow[0]) return emptyList()
        bb.extractBytes(0, bitOffset, b, 21 * 8)
        if (b[0] != 0x46) return emptyList()
        val crc = Rtl433BitUtil.crc8(b, 19, 0x31, 0x00)
        val sum = Rtl433BitUtil.addBytes(b, 20) and 0xff
        if (crc != b[19] || sum != b[20]) return emptyList()
        val id = (b[1] shl 16) or (b[2] shl 8) or b[3]
        val tempRaw = ((b[4] and 0x7) shl 8) or b[5]
        val tempC = (tempRaw - 400) * 0.1f
        val humidity = b[6]
        val battBars = ((b[7] and 0x40) shr 4) or ((b[9] and 0xC0) shr 6)
        val extPower = if (battBars == 6) 1 else 0
        val battLvl = minOf(battBars * 0.2f, 1.0f)
        val pm25Raw = ((b[7] and 0x3f) shl 8) or b[8]
        val pm25 = pm25Raw * 0.1f
        val pm10Raw = ((b[9] and 0x3f) shl 8) or b[10]
        val pm10 = pm10Raw * 0.1f
        val co2 = (b[11] shl 8) or b[12]
        val pm1Raw = (b[13] shl 8) or b[14]
        val pm1 = pm1Raw * 0.1f
        val pm4Raw = (b[15] shl 8) or b[16]
        val pm4 = pm4Raw * 0.1f
        val unknown = (b[17] shl 8) or b[18]
        return listOf(
            Reading(
                "Fineoffset-WH46",
                String.format("%06x", id),
                mapOf(
                    "battery_ok" to (if (battBars > 1) 1 else 0),
                    "battery_pct" to (100 * battLvl).toDouble(),
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "pm1_ug_m3" to pm1.toDouble(),
                    "pm2_5_ug_m3" to pm25.toDouble(),
                    "pm4_ug_m3" to pm4.toDouble(),
                    "pm10_ug_m3" to pm10.toDouble(),
                    "co2_ppm" to co2,
                    "unknown" to unknown,
                    "ext_power" to extPower,
                ),
            ),
        )
    }
}

// unverified: fineoffset_wh52.c:61-125 (decode), struct fineoffset_wh52.c:146
internal object FineoffsetWh52 : Rtl433Decoder() {
    override val name = "Fine Offset Electronics / Ecowitt WH52 Soil Moisture/Temperature/EC Sensor"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 200) return emptyList()
        val bitOffset = bb.search(0, 0, intArrayOf(0xAA, 0x2D, 0xD4), 24) + 24
        val b = IntArray(24)
        if (bitOffset + 24 * 8 > bb.bitsPerRow[0]) return emptyList()
        bb.extractBytes(0, bitOffset, b, 24 * 8)
        if (b[0] != 0xa2) return emptyList()
        if ((Rtl433BitUtil.addBytes(b, 23) and 0xff) != b[23]) return emptyList()
        if (Rtl433BitUtil.crc8(b, 22, 0x31, 0) != b[22]) return emptyList()
        val id = String.format("%02x%02x%02x", b[1], b[2], b[3])
        val boost = (b[4] and 0xe0) shr 5
        val tempRaw = ((b[4] and 0x1f) shl 8) or b[5]
        val tempC = tempRaw * 0.1f - 40.0f
        val moisture = b[6]
        val ecRaw = ((b[8] and 0x0f) shl 16) or (b[9] shl 8) or b[10]
        val ecUscm = ecRaw / 25.6f
        val battMv = b[20] * 20
        var battLvl = (battMv - 1300) * (1.0f / 300.0f)
        if (battLvl < 0.0f) battLvl = 0.0f
        if (battLvl > 1.0f) battLvl = 1.0f
        return listOf(
            Reading(
                "Fineoffset-WH52",
                id,
                mapOf(
                    "temperature_C" to tempC.toDouble(),
                    "moisture" to moisture,
                    "conductivity_uS_cm" to ecUscm.toDouble(),
                    "battery_ok" to battLvl.toDouble(),
                    "battery_mV" to battMv,
                    "boost" to boost,
                ),
            ),
        )
    }
}

// unverified: fineoffset.c:57-181 (WH2/WH2A/WH5/Telldus/TFA-303225 decode), struct fineoffset.c:313
internal object FineoffsetWH2 : Rtl433Decoder() {
    override val name = "Fine Offset Electronics, WH2, WH5, Telldus Temperature/Humidity/Rain Sensor"
    override val mod = Mod.OOK_PWM
    override val short = 500
    override val long = 1500
    override val reset = 1200
    override val tolerance = 160

    override fun decode(bb: BitBuffer): List<Reading> {
        val row0 = bb.bb[0]
        val b = IntArray(6)
        val model: String
        if (bb.bitsPerRow[0] == 48 && row0[0] == 0xFF) {
            bb.extractBytes(0, 8, b, 40)
            model = "WH2"
        } else if (bb.bitsPerRow[0] == 55 && row0[0] == 0xFE) {
            bb.extractBytes(0, 7, b, 48)
            model = if (b[3] == 0xff) "TFA303225" else "WH2A"
        } else if (bb.bitsPerRow[0] == 47 && row0[0] == 0xFE) {
            bb.extractBytes(0, 7, b, 40)
            model = "WH5"
        } else if (bb.bitsPerRow[0] == 49 && row0[0] == 0xFF && (row0[1] and 0x80) == 0x80) {
            bb.extractBytes(0, 9, b, 40)
            model = "TP"
        } else {
            return emptyList()
        }
        if (b[4] != Rtl433BitUtil.crc8(b, 4, 0x31, 0)) return emptyList()
        if (model == "TFA303225" && (Rtl433BitUtil.addBytes(b, 5) and 0xff) != b[5]) return emptyList()
        val type = b[0] shr 4
        if (type != 4) return emptyList()
        val id = ((b[0] and 0x0F) shl 4) or ((b[1] and 0xF0) shr 4)
        var temp = ((b[1] and 0x0F) shl 8) or b[2]
        var lowBattery = 0
        if (model == "TFA303225") {
            lowBattery = if ((temp and 0x800) != 0) 1 else 0
            temp = temp and 0x7FF
            temp -= 400
        } else if (model == "WH5") {
            temp -= 400
        } else {
            if ((temp and 0x800) != 0) {
                temp = temp and 0x7FF
                temp = -temp
            }
        }
        val temperature = temp * 0.1f
        if (model == "WH5" && (temperature < -40.0f || temperature > 60.0f)) return emptyList()
        val humidity = b[3]
        val modelName = when (model) {
            "WH2" -> "Fineoffset-WH2"
            "WH2A" -> "Fineoffset-WH2A"
            "WH5" -> "Fineoffset-WH5"
            "TP" -> "Fineoffset-TelldusProove"
            else -> "TFA-303225"
        }
        val fields = linkedMapOf<String, Any?>()
        if (model == "TFA303225") fields["battery_ok"] = if (lowBattery != 0) 0 else 1
        fields["temperature_C"] = temperature.toDouble()
        if (humidity != 0xff) fields["humidity"] = humidity
        return listOf(Reading(modelName, id.toString(), fields))
    }
}

private fun wh1050Decode(bb: BitBuffer, bitpos: Int, ook: Boolean): Reading? {
    val br = IntArray(9)
    bb.extractBytes(0, bitpos, br, 9 * 8)
    if (Rtl433BitUtil.crc8(br, 9, 0x31, 0x00) != 0) return null
    val msgType = br[0] shr 4
    val model = if (ook) "Fineoffset-WH1050" else "TFA-303151"
    val deviceId = ((br[0] shl 4) and 0xf0) or (br[1] shr 4)
    val batteryOk = if ((br[1] and 0x04) != 0) 0 else 1
    if (msgType == 5) {
        val tempSign = (br[1] and 0x08) shr 3
        val tempRaw = ((br[1] and 0x03) shl 8) or br[2]
        val rainRaw = (br[6] shl 8) or br[7]
        val temperature: Float
        val rain: Float
        if (ook) {
            temperature = (tempRaw - 400) * 0.1f
            rain = rainRaw * 0.3f
        } else {
            temperature = if (tempSign != 0) -(tempRaw * 0.1f) else tempRaw * 0.1f
            rain = rainRaw * 0.5f
        }
        val humidity = br[3]
        val speed = (br[4] * 0.34f) * 3.6f
        val gust = (br[5] * 0.34f) * 3.6f
        return Reading(
            model,
            String.format("%02X", deviceId),
            mapOf(
                "msg_type" to msgType,
                "battery_ok" to batteryOk,
                "temperature_C" to temperature.toDouble(),
                "humidity" to humidity,
                "wind_avg_km_h" to speed.toDouble(),
                "wind_max_km_h" to gust.toDouble(),
                "rain_mm" to rain.toDouble(),
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
        val clockStr = String.format("%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hours, minutes, seconds)
        return Reading(
            model,
            String.format("%02X", deviceId),
            mapOf("msg_type" to msgType, "battery_ok" to batteryOk, "radio_clock" to clockStr),
        )
    }
    return null
}

// unverified: fineoffset_wh1050.c:108-200 (decode), fineoffset_wh1050.c:201-236 (callback), struct fineoffset_wh1050.c:258
internal object FineoffsetWh1050 : Rtl433Decoder() {
    override val name = "Fine Offset WH1050 Weather Station"
    override val mod = Mod.OOK_PWM
    override val short = 544
    override val long = 1524
    override val reset = 10520

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val bits = bb.bitsPerRow[0]
        val preambleByte = bb.bb[0][0]
        val out = ArrayList<Reading>()
        if (bits == 79 && preambleByte == 0xfe) {
            wh1050Decode(bb, 7, true)?.let { out.add(it) }
        } else if (bits == 80 && preambleByte == 0xff) {
            wh1050Decode(bb, 8, true)?.let { out.add(it) }
        } else if (bits > 112 && bits < 760) {
            var bitpos = 0
            while (true) {
                bitpos = bb.search(0, bitpos, intArrayOf(0xAA, 0x2D, 0xD4), 24)
                if (bitpos + 72 > bb.bitsPerRow[0]) break
                wh1050Decode(bb, bitpos + 24, false)?.let { out.add(it) }
                bitpos += 123
            }
        } else {
            return emptyList()
        }
        return out
    }
}

// unverified: fineoffset.c:736-800 (WH51 callback), struct fineoffset.c:368
internal object FineoffsetWH51 : Rtl433Decoder() {
    override val name = "Fine Offset Electronics/Ecowitt WH51, WN31, SwitchDoc Labs SM23 Soil Moisture Sensor"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 120) return emptyList()
        val bitOffset = bb.search(0, 0, intArrayOf(0xAA, 0x2D, 0xD4), 24) + 24
        val b = IntArray(14)
        if (bitOffset + 14 * 8 > bb.bitsPerRow[0]) return emptyList()
        bb.extractBytes(0, bitOffset, b, 14 * 8)
        if (b[0] != 0x51) return emptyList()
        if ((Rtl433BitUtil.addBytes(b, 13) and 0xff) != b[13]) return emptyList()
        if (Rtl433BitUtil.crc8(b, 12, 0x31, 0) != b[12]) return emptyList()
        val id = String.format("%02x%02x%02x", b[1], b[2], b[3])
        val boost = (b[4] and 0xe0) shr 5
        val batteryMvBits = b[4] and 0x1f
        val batteryMv = batteryMvBits * 100
        val adRaw = ((b[7] and 0x01) shl 8) or b[8]
        val moisture = b[6]
        val batteryLevel: Float = when {
            batteryMvBits >= 16 -> 1.0f
            batteryMvBits == 15 -> 0.9f
            batteryMvBits == 14 -> 0.5f
            batteryMvBits == 13 -> 0.1f
            else -> 0.0f
        }
        return listOf(
            Reading(
                "Fineoffset-WH51",
                id,
                mapOf(
                    "battery_ok" to batteryLevel.toDouble(),
                    "battery_mV" to batteryMv,
                    "moisture" to moisture,
                    "boost" to boost,
                    "ad_raw" to adRaw,
                ),
            ),
        )
    }
}

// unverified: WH24/WH65/WS69/HP1000 (fineoffset_WH24_callback) and WH0290 delegations (rows <160 or 190..439 bits) not ported; only the WH25/WH32/WH32B/WN32B path
internal object FineoffsetWH25 : Rtl433Decoder() {
    override val name = "Fine Offset Electronics, WH25, WH32, WH32B, WN32B, WH24, WH65, WS69, HP1000, Misol WS2320 Temperature/Humidity/Pressure Sensor"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 20000

    private val PREAMBLE = intArrayOf(0xAA, 0x2D, 0xD4)

    override fun decode(bb: BitBuffer): List<Reading> {
        val bits = bb.bitsPerRow[0]
        var type = 25
        if (bits < 160) return emptyList()
        else if (bits < 190) type = 32
        else if (bits < 440) return emptyList()
        if (bits > 510) type = 32
        val bitOffset = bb.search(0, 0, PREAMBLE, 24) + 24
        if (bitOffset + 64 > bits) return emptyList()
        val b = IntArray(9)
        bb.extractBytes(0, bitOffset, b, 64)
        val msgType = b[0] and 0xf0
        if (type == 32 && msgType == 0xd0) type = 31
        else if (msgType != 0xe0) return emptyList()
        val sum = (Rtl433BitUtil.addBytes(b, 6) and 0xff) - b[6]
        if (sum != 0) return emptyList()
        var bitsum = Rtl433BitUtil.xorBytes(b, 6)
        bitsum = ((bitsum and 0x0f) shl 4) or (bitsum shr 4)
        if (type == 25 && bitsum != b[7]) return emptyList()
        val id = ((b[0] and 0x0f) shl 4) or (b[1] shr 4)
        val lowBattery = (b[1] and 0x08) shr 3
        val tempRaw = ((b[1] and 0x03) shl 8) or b[2]
        val temperature = (tempRaw - 400) * 0.1f
        val humidity = b[3]
        val pressureRaw = (b[4] shl 8) or b[5]
        val pressure = pressureRaw * 0.1f
        val model = when (type) {
            31 -> "Fineoffset-WH32"
            32 -> "Fineoffset-WH32B"
            else -> "Fineoffset-WH25"
        }
        val fields = linkedMapOf<String, Any?>()
        fields["battery_ok"] = if (lowBattery == 0) 1 else 0
        fields["temperature_C"] = temperature.toDouble()
        fields["humidity"] = humidity
        if (pressureRaw != 0xffff) fields["pressure_hPa"] = pressure.toDouble()
        fields["mic"] = "CRC"
        return listOf(Reading(model, id.toString(), fields))
    }
}

internal object FineoffsetWH0530 : Rtl433Decoder() {
    override val name = "Fine Offset Electronics, WH0530 Temperature/Rain Sensor"
    override val mod = Mod.OOK_PWM
    override val short = 504
    override val long = 1480
    override val reset = 1200
    override val tolerance = 160

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 71) return emptyList()
        val r = bb.bb[0]
        if ((r[0] shr 1) != 0x7F || (r[1] shr 5) != 0x3) return emptyList()
        val b = IntArray(9)
        bb.extractBytes(0, 7, b, 64)
        val crc = Rtl433BitUtil.crc8(b, 7, 0x31, 0)
        val sum = (Rtl433BitUtil.addBytes(b, 7) and 0xff) - b[7]
        if (crc != 0 || sum != 0) return emptyList()
        val id = ((b[0] and 0x0f) shl 4) or (b[1] shr 4)
        val batteryLow = (b[1] shr 3) and 0x1
        val tempRaw = ((b[1] and 0x7) shl 8) or b[2]
        val temperature = (tempRaw - 400) * 0.1f
        val rainRaw = (b[4] shl 8) or b[3]
        val rainfall = rainRaw * 0.3f
        return listOf(Reading("Fineoffset-WH0530", id.toString(), mapOf(
            "battery_ok" to (if (batteryLow == 0) 1 else 0),
            "temperature_C" to temperature.toDouble(),
            "rain_mm" to rainfall.toDouble(),
            "mic" to "CRC",
        )))
    }
}

private const val IDM_PACKET_BYTES = 92
private const val IDM_PACKET_BITLEN = 720
private val IDM_FRAME_SYNC = intArrayOf(0x16, 0xA3, 0x1C)

private fun idmMeterTypeName(ertType: Int): String = when (ertType and 0x0f) {
    4, 5, 7, 8 -> "Electric"
    0, 1, 2, 9, 12 -> "Gas"
    3, 11, 13 -> "Water"
    else -> "unknown"
}

private fun idmHex(b: IntArray, from: Int, count: Int): String {
    val sb = StringBuilder("0x")
    for (j in 0 until count) sb.append("%02X".format(b[from + j]))
    return sb.toString()
}

private fun idmFrame(bb: BitBuffer): Pair<Int, IntArray>? {
    if (bb.bitsPerRow[0] < IDM_PACKET_BITLEN) return null
    val syncIndex = bb.search(0, 0, IDM_FRAME_SYNC, 24)
    if (syncIndex >= bb.bitsPerRow[0]) return null
    if (bb.bitsPerRow[0] - syncIndex < IDM_PACKET_BITLEN) return null
    val b = IntArray(IDM_PACKET_BYTES)
    bb.extractBytes(0, syncIndex, b, IDM_PACKET_BITLEN)
    val packetCrc = (b[88] shl 8) or b[89]
    if (Rtl433BitUtil.crc16(b.copyOfRange(2, 88), 86, 0x1021, 0xD895) != packetCrc) return null
    return Pair(syncIndex, b)
}

private fun idmIntervals(bb: BitBuffer, startPos: Int, count: Int, width: Int): List<Int> {
    var pos = startPos
    val out = ArrayList<Int>(count)
    for (j in 0 until count) {
        val buffy = IntArray(4)
        bb.extractBytes(0, pos, buffy, width)
        out.add(if (width == 9) (buffy[0] shl 1) or (buffy[1] shr 7) else (buffy[0] shl 6) or (buffy[1] shr 2))
        pos += width
    }
    return out
}

internal object ErtIdm : Rtl433Decoder() {
    override val name = "ERT Interval Data Message (IDM)"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 30
    override val gap = 20000
    override val reset = 20000

    override fun decode(bb: BitBuffer): List<Reading> {
        val (syncIndex, b) = idmFrame(bb) ?: return emptyList()
        val serial = ((b[7].toLong() shl 24) or (b[8].toLong() shl 16) or (b[9].toLong() shl 8) or b[10].toLong())
        val lastConsumption = ((b[27].toLong() shl 24) or (b[28].toLong() shl 16) or (b[29].toLong() shl 8) or b[30].toLong())
        return listOf(
            Reading(
                "IDM",
                serial.toString(),
                mapOf(
                    "PacketTypeID" to "0x%02X".format(b[2]),
                    "PacketLength" to b[3],
                    "ApplicationVersion" to b[5],
                    "ERTType" to "0x%02X".format(b[6]),
                    "ERTSerialNumber" to serial,
                    "ConsumptionIntervalCount" to b[11],
                    "ModuleProgrammingState" to "0x%02X".format(b[12]),
                    "TamperCounters" to idmHex(b, 13, 6),
                    "AsynchronousCounters" to "0x%02X".format((b[19] shl 8) or b[20]),
                    "PowerOutageFlags" to idmHex(b, 21, 6),
                    "LastConsumptionCount" to lastConsumption,
                    "DifferentialConsumptionIntervals" to idmIntervals(bb, syncIndex + 31 * 8, 47, 9),
                    "TransmitTimeOffset" to ((b[84] shl 8) or b[85]),
                    "MeterIdCRC" to "0x%04X".format((b[86] shl 8) or b[87]),
                    "PacketCRC" to "0x%04X".format((b[88] shl 8) or b[89]),
                    "MeterType" to idmMeterTypeName(b[6]),
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

internal object ErtNetidm : Rtl433Decoder() {
    override val name = "ERT Interval Data Message (IDM) for Net Meters"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 30
    override val gap = 20000
    override val reset = 20000

    override fun decode(bb: BitBuffer): List<Reading> {
        val (syncIndex, b) = idmFrame(bb) ?: return emptyList()
        val serial = ((b[7].toLong() shl 24) or (b[8].toLong() shl 16) or (b[9].toLong() shl 8) or b[10].toLong())
        val lastGeneration = (b[26] shl 16) or (b[27] shl 8) or b[28]
        val lastConsumption = ((b[32].toLong() shl 24) or (b[33].toLong() shl 16) or (b[34].toLong() shl 8) or b[35].toLong())
        return listOf(
            Reading(
                "NETIDM",
                serial.toString(),
                mapOf(
                    "PacketTypeID" to "0x%02X".format(b[2]),
                    "PacketLength" to b[3],
                    "ApplicationVersion" to b[5],
                    "ERTType" to "0x%02X".format(b[6]),
                    "ERTSerialNumber" to serial,
                    "ConsumptionIntervalCount" to b[11],
                    "ModuleProgrammingState" to "0x%02X".format(b[12]),
                    "TamperCounters" to idmHex(b, 13, 6),
                    "Unknown_field_1" to idmHex(b, 19, 7),
                    "LastGenerationCount" to lastGeneration,
                    "Unknown_field_2" to idmHex(b, 29, 3),
                    "LastConsumptionCount" to lastConsumption,
                    "DifferentialConsumptionIntervals" to idmIntervals(bb, syncIndex + 36 * 8, 27, 14),
                    "TransmitTimeOffset" to ((b[84] shl 8) or b[85]),
                    "MeterIdCRC" to "0x%04X".format((b[86] shl 8) or b[87]),
                    "PacketCRC" to "0x%04X".format((b[88] shl 8) or b[89]),
                    "MeterType" to idmMeterTypeName(b[6]),
                    "mic" to "CRC",
                ),
            ),
        )
    }
}

private val WH1080_WIND_DIR_DEGR = intArrayOf(0, 23, 45, 68, 90, 113, 135, 158, 180, 203, 225, 248, 270, 293, 315, 338)

private fun wh1080Decode(bb: BitBuffer, ook: Boolean): List<Reading> {
    if (bb.numRows != 1) return emptyList()
    val row0 = bb.bb[0]
    val bits = bb.bitsPerRow[0]
    val bbuf = IntArray(11)
    val br: IntArray
    val spb: Boolean
    val sensMsg: Int
    if (!ook) {
        val bitOffset = bb.search(0, 0, intArrayOf(0xAA, 0x2D, 0xD4), 24) + 24
        if (bitOffset + 11 * 8 > bits) return emptyList()
        bb.extractBytes(0, bitOffset - 8, bbuf, 11 * 8)
        bbuf[0] = 0xFF
        br = bbuf
        spb = false
        sensMsg = 10
    } else if (bits >= 88 && bits < 100) {
        br = row0
        spb = false
        sensMsg = 10
    } else if (bits == 87) {
        val tmp = IntArray(10)
        bb.extractBytes(0, 7, tmp, 10 * 8)
        for (i in 0 until 10) bbuf[i + 1] = tmp[i]
        bbuf[0] = (row0[0] shr 1) or 0x80
        br = bbuf
        spb = true
        sensMsg = 10
    } else if (bits == 64) {
        br = row0
        spb = false
        sensMsg = 7
    } else if (bits == 63) {
        val tmp = IntArray(7)
        bb.extractBytes(0, 7, tmp, 7 * 8)
        for (i in 0 until 7) bbuf[i + 1] = tmp[i]
        bbuf[0] = (row0[0] shr 1) or 0x80
        br = bbuf
        spb = true
        sensMsg = 7
    } else {
        return emptyList()
    }
    if (br[0] != 0xff) return emptyList()
    if (sensMsg == 10) {
        if (Rtl433BitUtil.crc8(br, 11, 0x31, 0xff) != 0) return emptyList()
    } else {
        if (Rtl433BitUtil.crc8(br, 8, 0x31, 0xff) != 0) return emptyList()
    }
    val msgType = when (br[1] shr 4) {
        0x0a -> 0
        0x0b -> 1
        0x07 -> 2
        else -> return emptyList()
    }
    val temperature: Float
    if (ook) {
        val tempRaw = ((br[2] and 0x03) shl 8) or br[3]
        temperature = (tempRaw - 400) * 0.1f
    } else {
        var tempRaw = ((br[2] and 0x0F) shl 8) or br[3]
        if ((tempRaw and 0x800) != 0) {
            tempRaw = tempRaw and 0x7FF
            tempRaw = -tempRaw
        }
        temperature = tempRaw * 0.1f
    }
    val humidity = br[4]
    val directionDeg = WH1080_WIND_DIR_DEGR[br[9] and 0x0f]
    val speed = (br[5] * 0.34f) * 3.6f
    val gust = (br[6] * 0.34f) * 3.6f
    val rainRaw = ((br[7] and 0x0f) shl 8) or br[8]
    val rain = rainRaw * 0.3f
    val deviceId = ((br[1] shl 4) and 0xf0) or (br[2] shr 4)
    val batteryLow = (br[9] shr 4) == 1
    val uvSensorId = ((br[1] shl 4) and 0xf0) or (br[2] shr 4)
    val uvStatusOk = br[3] == 85
    val uvIndex = br[2] and 0x0F
    val light = (br[4] shl 16) or (br[5] shl 8) or br[6]
    val lux = light * 0.1
    val wm = if (spb) light / 1265.8f else light / 6830.0f
    val signalType = (br[2] and 0x0F) == 10
    val signalTypeStr = if (signalType) "DCF77" else "WWVB/MSF"
    val hours = ((br[3] and 0x30) shr 4) * 10 + (br[3] and 0x0F)
    val minutes = ((br[4] and 0xF0) shr 4) * 10 + (br[4] and 0x0F)
    val seconds = ((br[5] and 0xF0) shr 4) * 10 + (br[5] and 0x0F)
    val year = ((br[6] and 0xF0) shr 4) * 10 + (br[6] and 0x0F) + 2000
    val month = ((br[7] and 0x10) shr 4) * 10 + (br[7] and 0x0F)
    val day = ((br[8] and 0xF0) shr 4) * 10 + (br[8] and 0x0F)
    return when (msgType) {
        0 -> listOf(
            Reading(
                "Fineoffset-WHx080",
                deviceId.toString(),
                mapOf(
                    "subtype" to msgType,
                    "battery_ok" to (if (batteryLow) 0 else 1),
                    "temperature_C" to temperature.toDouble(),
                    "humidity" to humidity,
                    "wind_dir_deg" to directionDeg,
                    "wind_avg_km_h" to speed.toDouble(),
                    "wind_max_km_h" to gust.toDouble(),
                    "rain_mm" to rain.toDouble(),
                ),
            ),
        )
        1 -> listOf(
            Reading(
                "Fineoffset-WHx080",
                deviceId.toString(),
                mapOf(
                    "subtype" to msgType,
                    "signal" to signalTypeStr,
                    "radio_clock" to String.format("%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hours, minutes, seconds),
                ),
            ),
        )
        else -> listOf(
            Reading(
                "Fineoffset-WHx080",
                null,
                mapOf(
                    "subtype" to msgType,
                    "uv_sensor_id" to uvSensorId,
                    "uv_status" to (if (uvStatusOk) "OK" else "ERROR"),
                    "uv_index" to uvIndex,
                    "lux" to lux,
                    "wm" to wm.toDouble(),
                ),
            ),
        )
    }
}

// unverified: fineoffset_wh1080.c:123-313 (callback, OOK type), fineoffset_wh1080.c:315-317 (callback_ook), struct fineoffset_wh1080.c:352
internal object FineoffsetWh1080 : Rtl433Decoder() {
    override val name = "Fine Offset Electronics WH1080/WH3080 Weather Station"
    override val mod = Mod.OOK_PWM
    override val short = 544
    override val long = 1524
    override val reset = 2800

    override fun decode(bb: BitBuffer): List<Reading> = wh1080Decode(bb, true)
}

// unverified: fineoffset_wh1080.c:123-313 (callback, FSK type), fineoffset_wh1080.c:324-326 (callback_fsk), struct fineoffset_wh1080.c:362
internal object FineoffsetWh1080Fsk : Rtl433Decoder() {
    override val name = "Fine Offset Electronics WH1080/WH3080 Weather Station (FSK)"
    override val mod = Mod.FSK_PCM
    override val short = 58
    override val long = 58
    override val reset = 5800

    override fun decode(bb: BitBuffer): List<Reading> = wh1080Decode(bb, false)
}

internal val BATCH_02: List<Rtl433Decoder> = listOf(
    Ecodhome,
    Ecoeye,
    Ecowitt,
    EfergyE2Classic,
    EfergyOptical,
    Elero,
    ElroDb286a,
    ElsnerSolexa,
    ElsterPowerMeter,
    ElsterPowerMeter2,
    ElvEm1000,
    ElvWs2000,
    Emax,
    Emontx,
    EmosE6016,
    EmosE6016Rain,
    En2058,
    EnoceanErp1,
    ErtIdm,
    ErtNetidm,
    ErtScm,
    EsaEnergy,
    EsicEmt7110,
    EsperanzaEws,
    EsunEn2053,
    Eurochron,
    EurochronEfth800,
    FineoffsetWH0530,
    FineoffsetWh1050,
    FineoffsetWh1080,
    FineoffsetWh1080Fsk,
    FineoffsetWH2,
    FineoffsetWH25,
    FineoffsetWh31l,
    FineoffsetWh43,
    FineoffsetWh45,
    FineoffsetWh46,
    FineoffsetWH51,
    FineoffsetWh52,
)

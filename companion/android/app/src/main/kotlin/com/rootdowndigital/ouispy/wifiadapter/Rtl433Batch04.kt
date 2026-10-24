// Kotlin transcription of rtl_433 device decoders (batch 04). GPL-3 reference; constants, bit offsets and CRC parameters transcribed as facts.
package com.rootdowndigital.ouispy.wifiadapter

private fun rv8(x: Int): Int {
    var v = x and 0xFF
    v = ((v and 0xF0) shr 4) or ((v and 0x0F) shl 4)
    v = ((v and 0xCC) shr 2) or ((v and 0x33) shl 2)
    v = ((v and 0xAA) shr 1) or ((v and 0x55) shl 1)
    return v and 0xFF
}

private fun s16(x: Int): Int = x.toShort().toInt()

private fun hcs361Decode(bb: BitBuffer): List<Reading> {
    if (bb.numRows < 2 || bb.bitsPerRow[1] != 67) return emptyList()
    if (bb.bitsPerRow[0] == 6 && bb.bb[0][0] != 0xfc) return emptyList()
    if (bb.bitsPerRow[0] == 7 && bb.bb[0][0] != 0xfe) return emptyList()
    if (bb.bitsPerRow[0] == 12) {
        val preamble = (bb.bb[0][0] shl 8) or bb.bb[0][1]
        if (preamble != 0xaaa0 && preamble != 0xfff0) return emptyList()
    }
    val b = bb.bb[1]
    if (b[0] == 0xff && b[1] == 0xff && b[2] == 0xff && b[3] == 0xff && b[4] == 0xff && b[5] == 0xff && b[6] == 0xff && b[7] == 0xff) return emptyList()
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
    val encrypted = (rv8(b[3]) shl 24) or (rv8(b[2]) shl 16) or (rv8(b[1]) shl 8) or rv8(b[0])
    val serial = (rv8(b[7] and 0xf0) shl 24) or (rv8(b[6]) shl 16) or (rv8(b[5]) shl 8) or rv8(b[4])
    val btn = b[7] and 0x0f
    val btnNum = (btn and 0x08) or ((btn and 0x01) shl 2) or (btn and 0x02) or ((btn and 0x04) shr 2)
    val batteryOk = if ((b[8] and 0x80) == 0x80) 1 else 0
    if (serial == 0) return emptyList()
    return listOf(
        Reading(
            "Microchip-HCS361",
            String.format("%08X", serial),
            linkedMapOf(
                "battery_ok" to batteryOk,
                "button" to btnNum,
                "encrypted" to String.format("%08X", encrypted),
                "mic" to "CRC",
            ),
        ),
    )
}

private fun hcs362Crc(b: IntArray): Int {
    var crc0 = 0
    var crc1 = 0
    for (n in 0 until 65) {
        val d = (b[n / 8] shr (7 - (n % 8))) and 1
        val nextCrc1 = crc0 xor d
        val nextCrc0 = crc0 xor d xor crc1
        crc0 = nextCrc0
        crc1 = nextCrc1
    }
    return (crc1 shl 1) or crc0
}

private fun hcs362Decode(bb: BitBuffer, pcm: Boolean): List<Reading> {
    val b: IntArray
    val msg = BitBuffer()
    if (pcm) {
        if (bb.bitsPerRow[0] < 12 * 2 - 8 || bb.bitsPerRow[0] > 12 * 2 + 8) return emptyList()
        val pre = bb.bb[0]
        if (pre[0] != 0xaa || pre[1] != 0xaa || pre[2] != 0xaa) return emptyList()
        if (bb.bitsPerRow[1] < 71 * 2 || bb.bitsPerRow[1] > 72 * 2 + 4) return emptyList()
        if ((bb.bb[1][0] and 0xc0) != 0x80) return emptyList()
        val len = bb.manchesterDecode(1, 2, msg, 72)
        if (len < 69 + 1) return emptyList()
        msg.invert()
        b = msg.bb[0]
    } else {
        if (bb.bitsPerRow[0] != 12 || bb.bitsPerRow[1] != 69) return emptyList()
        val pre = bb.bb[0]
        if (pre[0] != 0xff || (pre[1] and 0xf0) != 0xf0) return emptyList()
        b = bb.bb[1]
    }
    if (b[1] == 0xff && b[2] == 0xff && b[3] == 0xff && b[4] == 0xff && b[5] == 0xff && b[6] == 0xff && b[7] == 0xff) return emptyList()
    val actualCrc = ((b[8] shr 6) and 1) or (((b[8] shr 5) and 1) shl 1)
    if (actualCrc != hcs362Crc(b)) return emptyList()
    val encrypted = (rv8(b[3]) shl 24) or (rv8(b[2]) shl 16) or (rv8(b[1]) shl 8) or rv8(b[0])
    val serial = (rv8(b[7] and 0xf0) shl 24) or (rv8(b[6]) shl 16) or (rv8(b[5]) shl 8) or rv8(b[4])
    val btn = b[7] and 0x0f
    val btnNum = (btn and 0x08) or ((btn and 0x01) shl 2) or (btn and 0x02) or ((btn and 0x04) shr 2)
    val batteryLow = if ((b[8] and 0x80) == 0x80) 1 else 0
    val queue = ((b[8] shr 4) and 1) or (((b[8] shr 3) and 1) shl 1)
    return listOf(
        Reading(
            "Microchip-HCS362",
            String.format("%07X", serial),
            linkedMapOf(
                "battery_ok" to (if (batteryLow == 0) 1 else 0),
                "button" to btnNum,
                "repeat" to queue,
                "encrypted" to String.format("%08X", encrypted),
                "mic" to "CRC",
            ),
        ),
    )
}

// unverified: hcs361.c:193-204 (struct), hcs361.c:65-166 (decode)
internal object Hcs361Txwak0Bsel1 : Rtl433Decoder() {
    override val name = "Microchip HCS361 KeeLoq Hopping Encoder based remotes (-f 315.1M) (Sync, 1667 bit/s)"
    override val mod = Mod.OOK_PWM
    override val short = 200
    override val long = 400
    override val gap = 600
    override val reset = 13600
    override val tolerance = 70
    override val sync = 2000

    override fun decode(bb: BitBuffer): List<Reading> = hcs361Decode(bb)
}

// unverified: hcs361.c:212-222 (struct), hcs361.c:65-166 (decode)
internal object Hcs361Txwak1Bsel0 : Rtl433Decoder() {
    override val name = "Microchip HCS361 KeeLoq Hopping Encoder based remotes (-f 315.1M) (No Sync, 833 bit/s)"
    override val mod = Mod.OOK_PWM
    override val short = 200
    override val long = 400
    override val gap = 1200
    override val reset = 6800
    override val tolerance = 140

    override fun decode(bb: BitBuffer): List<Reading> = hcs361Decode(bb)
}

// unverified: hcs361.c:230-240 (struct), hcs361.c:65-166 (decode)
internal object Hcs361Txwak1Bsel1 : Rtl433Decoder() {
    override val name = "Microchip HCS361 KeeLoq Hopping Encoder based remotes (-f 315.1M) (No Sync, 1667 bit/s)"
    override val mod = Mod.OOK_PWM
    override val short = 100
    override val long = 200
    override val gap = 600
    override val reset = 6600
    override val tolerance = 70

    override fun decode(bb: BitBuffer): List<Reading> = hcs361Decode(bb)
}

// unverified: hcs361.c:247-258 (struct), hcs361.c:65-166 (decode)
internal object Hcs361Vpwm1Bsel0 : Rtl433Decoder() {
    override val name = "Microchip HCS361 KeeLoq Hopping Encoder based remotes (-f 315.1M) (PIWM, 2500 bit/s)"
    override val mod = Mod.OOK_PIWM_DC
    override val short = 400
    override val long = 800
    override val gap = 4000
    override val reset = 45600
    override val tolerance = 140
    override val sync = 4000

    override fun decode(bb: BitBuffer): List<Reading> = hcs361Decode(bb)
}

// unverified: hcs361.c:265-276 (struct), hcs361.c:65-166 (decode)
internal object Hcs361Vpwm1Bsel1 : Rtl433Decoder() {
    override val name = "Microchip HCS361 KeeLoq Hopping Encoder based remotes (-f 315.1M) (PIWM, 5000 bit/s)"
    override val mod = Mod.OOK_PIWM_DC
    override val short = 200
    override val long = 400
    override val gap = 2000
    override val reset = 45200
    override val tolerance = 70
    override val sync = 2000

    override fun decode(bb: BitBuffer): List<Reading> = hcs361Decode(bb)
}

// unverified: hcs362.c:199-209 (struct), hcs362.c:85-197 (decode, PWM branch)
internal object Hcs362Pwm : Rtl433Decoder() {
    override val name = "Microchip HCS362 KeeLoq PWM"
    override val mod = Mod.OOK_PWM
    override val short = 200
    override val long = 400
    override val gap = 550
    override val reset = 900
    override val tolerance = 50

    override fun decode(bb: BitBuffer): List<Reading> = hcs362Decode(bb, false)
}

// unverified: hcs362.c:211-221 (struct), hcs362.c:85-197 (decode, MC branch)
internal object Hcs362Mc : Rtl433Decoder() {
    override val name = "Microchip HCS362 KeeLoq MC"
    override val mod = Mod.OOK_PCM
    override val short = 214
    override val long = 214
    override val gap = 600
    override val reset = 900
    override val tolerance = 50

    override fun decode(bb: BitBuffer): List<Reading> = hcs362Decode(bb, true)
}

private fun hidekiDecode(bb: BitBuffer): List<Reading> {
    for (row in 0 until bb.numRows) {
        var unstuffedLen = (bb.bitsPerRow[row] + 4) / 9
        val sensortype = when (unstuffedLen) {
            14 -> "WIND"
            10 -> "TS04"
            9 -> "RAIN"
            8 -> "TEMP"
            else -> continue
        }
        unstuffedLen -= 1
        val b = bb.bb[row]
        var sync = (b[0] shl 1) or (b[1] shr 7)
        var startpos = -1
        for (i in 0 until 4) {
            if (sync == 0x0d) {
                startpos = 9 - i
                break
            }
            sync = sync shr 1
        }
        if (startpos < 0) continue
        bb.invert()
        val packet = IntArray(unstuffedLen)
        var unstuffError = false
        for (i in 0 until unstuffedLen) {
            val offset = startpos + i * 9
            packet[i] = ((b[offset / 8] shl (offset % 8)) or (b[offset / 8 + 1] shr (8 - offset % 8))) and 0xFF
            val parity = (b[offset / 8 + 1] shr (7 - offset % 8)) and 1
            if (parity != Rtl433BitUtil.parity8(packet[i])) {
                unstuffError = true
                break
            }
        }
        if (unstuffError) continue
        if (Rtl433BitUtil.xorBytes(packet, unstuffedLen - 1) != 0) continue
        if (Rtl433BitUtil.crc8(packet, unstuffedLen, 0x07, 0x00) != 0) continue
        for (i in 0 until unstuffedLen) packet[i] = rv8(packet[i])
        val pktLen = (packet[1] shr 1) and 0x1f
        if (pktLen + 2 != unstuffedLen) continue
        var channel = (packet[0] shr 5) and 0x0F
        if (channel >= 5) channel -= 1
        val rc = packet[0] and 0x0F
        var temp = (packet[4] and 0x0F) * 100 + ((packet[3] and 0xF0) shr 4) * 10 + (packet[3] and 0x0F)
        if (((packet[4] shr 7) and 1) == 0) temp = -temp
        var batteryOk = (packet[4] shr 6) and 1
        when (sensortype) {
            "TS04" -> {
                val humidity = ((packet[5] and 0xF0) shr 4) * 10 + (packet[5] and 0x0F)
                return listOf(
                    Reading(
                        "Hideki-TS04",
                        rc.toString(),
                        linkedMapOf(
                            "channel" to channel,
                            "battery_ok" to batteryOk,
                            "temperature_C" to (temp / 10.0f).toDouble(),
                            "humidity" to humidity,
                        ),
                    ),
                )
            }
            "WIND" -> {
                val wd = intArrayOf(0, 15, 13, 14, 9, 10, 12, 11, 1, 2, 4, 3, 8, 7, 5, 6)
                val windDirection = wd[(packet[10] and 0xF0) shr 4] * 225
                val windSpeed = (packet[8] and 0x0F) * 100 + (packet[7] shr 4) * 10 + (packet[7] and 0x0F)
                val gustSpeed = (packet[9] shr 4) * 100 + (packet[9] and 0x0F) * 10 + (packet[8] shr 4)
                val ad = intArrayOf(0, 1, -1, 2)
                val windApproach = ad[(packet[10] shr 2) and 0x03]
                return listOf(
                    Reading(
                        "Hideki-Wind",
                        rc.toString(),
                        linkedMapOf(
                            "channel" to channel,
                            "battery_ok" to batteryOk,
                            "temperature_C" to (temp * 0.1f).toDouble(),
                            "wind_avg_mi_h" to (windSpeed * 0.1f).toDouble(),
                            "wind_max_mi_h" to (gustSpeed * 0.1f).toDouble(),
                            "wind_approach" to windApproach,
                            "wind_dir_deg" to (windDirection * 0.1f).toDouble(),
                        ),
                    ),
                )
            }
            "TEMP" -> {
                return listOf(
                    Reading(
                        "Hideki-Temperature",
                        rc.toString(),
                        linkedMapOf(
                            "channel" to channel,
                            "battery_ok" to batteryOk,
                            "temperature_C" to (temp * 0.1f).toDouble(),
                        ),
                    ),
                )
            }
            "RAIN" -> {
                val rainUnits = (packet[4] shl 8) or packet[3]
                batteryOk = (packet[1] shr 6) and 1
                return listOf(
                    Reading(
                        "Hideki-Rain",
                        rc.toString(),
                        linkedMapOf(
                            "channel" to channel,
                            "battery_ok" to batteryOk,
                            "rain_mm" to (rainUnits * 0.7f).toDouble(),
                        ),
                    ),
                )
            }
        }
        return emptyList()
    }
    return emptyList()
}

// unverified: hideki.c:245-254 (struct), hideki.c:50-243 (decode)
internal object HidekiTs04 : Rtl433Decoder() {
    override val name = "HIDEKI TS04 Temperature, Humidity, Wind and Rain Sensor"
    override val mod = Mod.OOK_DMC
    override val short = 520
    override val long = 1040
    override val reset = 4000
    override val tolerance = 240

    override fun decode(bb: BitBuffer): List<Reading> = hidekiDecode(bb)
}

private fun holmanXorShiftBytes(msg: IntArray, numBytes: Int, shiftUp: Int): Int {
    var result0 = 0
    var i = 0
    while (i < numBytes) {
        result0 = result0 xor msg[i]
        i += 2
    }
    var result1 = 0
    i = 1
    while (i < numBytes) {
        result1 = result1 xor msg[i]
        i += 2
    }
    var resultx = 0
    for (j in 0 until 7) {
        if ((shiftUp and (1 shl j)) != 0) resultx = (resultx xor (result0 shl (j + 1))) and 0xFF
    }
    return (result0 xor result1 xor resultx) and 0xFF
}

private fun holmanPcmDecode(bb: BitBuffer): List<Reading> {
    val windDirDegr = intArrayOf(0, 23, 45, 68, 90, 113, 135, 158, 180, 203, 225, 248, 270, 293, 315, 338)
    val preamble = intArrayOf(0xAA, 0xAA, 0xAA, 0x98, 0xF3, 0xA5)
    if (bb.numRows != 1) return emptyList()
    val bits = bb.bitsPerRow[0]
    if (bits < 192) return emptyList()
    var pos = bb.search(0, 0, preamble, preamble.size * 8)
    if (pos >= bits) return emptyList()
    pos += preamble.size * 8
    val b = IntArray(18)
    bb.extractBytes(0, pos, b, b.size * 8)
    val chkDigest = b[12]
    val chkCalc = Rtl433BitUtil.xorBytes(b, 12) and 0xFF
    val chkExpected = Rtl433BitUtil.lfsrDigest8Reflect(intArrayOf(chkCalc), 1, 0x00, 0x31)
    if (chkExpected != chkDigest) return emptyList()
    val deviceId = (b[0] shl 8) or b[1]
    val tempRaw = s16((b[2] shl 8) or (b[3] and 0xf0))
    val tempC = (tempRaw shr 4) * 0.1f
    val humidity = ((b[3] and 0x0f) shl 4) or ((b[4] and 0xf0) shr 4)
    val rainRaw = ((b[4] and 0x0f) shl 8) or b[5]
    val speedKmh = b[6].toFloat()
    val directionDeg = windDirDegr[(b[7] and 0xf0) shr 4]
    val lightLux = ((b[8] and 0x7F) shl 10) or (b[9] shl 2) or ((b[10] and 0xC0) shr 6)
    if (bits < 200 && lightLux == 0) {
        val rainMm = rainRaw * 0.79f
        return listOf(
            Reading(
                "Holman-WS5029",
                String.format("%04X", deviceId),
                linkedMapOf(
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "rain_mm" to rainMm.toDouble(),
                    "wind_avg_km_h" to speedKmh.toDouble(),
                    "wind_dir_deg" to directionDeg,
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    } else if (bits < 221) {
        val rainMm = rainRaw * 1.0f
        val uvIndex = ((b[7] and 0x07) shl 1) or ((b[8] and 0x80) shr 7)
        val batteryLow = (b[10] and 0x30) shr 4
        val counter = ((b[10] and 0x0f) shl 8) or b[11]
        return listOf(
            Reading(
                "AOK-5056",
                String.format("%04X", deviceId),
                linkedMapOf(
                    "temperature_C" to tempC.toDouble(),
                    "humidity" to humidity,
                    "rain_mm" to rainMm.toDouble(),
                    "wind_avg_km_h" to speedKmh.toDouble(),
                    "wind_dir_deg" to directionDeg,
                    "uvi" to uvIndex.toDouble(),
                    "light_lux" to lightLux,
                    "counter" to counter,
                    "battery_ok" to (if (batteryLow == 0) 1 else 0),
                    "mic" to "CHECKSUM",
                ),
            ),
        )
    }
    return emptyList()
}

// unverified: holman_ws5029.c:202-210 (struct), holman_ws5029.c:90-200 (decode)
internal object HolmanWs5029pcm : Rtl433Decoder() {
    override val name = "AOK Weather Station rebrand Holman Industries iWeather WS5029, Conrad AOK-5056, Optex 990018"
    override val mod = Mod.FSK_PCM
    override val short = 100
    override val long = 100
    override val reset = 19200

    override fun decode(bb: BitBuffer): List<Reading> = holmanPcmDecode(bb)
}

private fun holmanPwmDecode(bb: BitBuffer): List<Reading> {
    val preamble = intArrayOf(0x55, 0x5a, 0x67)
    val r = bb.findRepeatedRow(3, 96)
    if (r < 0 || bb.bitsPerRow[r] != 96) return emptyList()
    val b = bb.bb[r]
    for (i in 0 until 3) {
        if (b[i] != preamble[i]) return emptyList()
    }
    bb.invert()
    val chkDigest = b[10]
    val chkCalc = holmanXorShiftBytes(b, 10, 0x18)
    if (chkCalc != chkDigest) return emptyList()
    val id = b[3]
    val batteryLow = b[4] and 0x80
    val tempRaw = s16(((b[4] and 0x0f) shl 12) or (b[5] shl 4))
    val tempC = (tempRaw shr 4) * 0.1f
    val humidity = b[6]
    val rainMm = ((b[7] shl 4) + (b[8] shr 4)) * 0.79f
    val speedKmh = (((b[8] and 0xF) shl 4) + (b[9] shr 4)).toFloat()
    val windDir = b[9] and 0xF
    return listOf(
        Reading(
            "Holman-WS5029",
            id.toString(),
            linkedMapOf(
                "battery_ok" to (if (batteryLow == 0) 1 else 0),
                "temperature_C" to tempC.toDouble(),
                "humidity" to humidity,
                "rain_mm" to rainMm.toDouble(),
                "wind_avg_km_h" to speedKmh.toDouble(),
                "wind_dir_deg" to (windDir * 22.5).toInt(),
                "mic" to "CHECKSUM",
            ),
        ),
    )
}

// unverified: holman_ws5029.c:320-329 (struct), holman_ws5029.c:258-318 (decode)
internal object HolmanWs5029pwm : Rtl433Decoder() {
    override val name = "Holman Industries iWeather WS5029 weather station (older PWM)"
    override val mod = Mod.FSK_PWM
    override val short = 488
    override val long = 976
    override val reset = 6000
    override val gap = 2000

    override fun decode(bb: BitBuffer): List<Reading> = holmanPwmDecode(bb)
}

// unverified: holman_ws5029.c:340-349 (struct), holman_ws5029.c:258-318 (decode)
internal object HolmanWs5029pwmOok : Rtl433Decoder() {
    override val name = "Holman Industries iWeather WS5029 weather station (older PWM, OOK), BIOWIN 270208"
    override val mod = Mod.OOK_PWM
    override val short = 488
    override val long = 976
    override val reset = 6000
    override val gap = 2000

    override fun decode(bb: BitBuffer): List<Reading> = holmanPwmDecode(bb)
}

private fun homeleadDecode(bb: BitBuffer): List<Reading> {
    val preamble = intArrayOf(0x55, 0xaa)
    val luxEstimate = intArrayOf(60, 200, 400, 600, 1000, 1500, 2800, 4500, 10000, -1, -1, -1, -1, -1, -1, -1)
    val row = bb.findRepeatedRow(1, 65)
    if (row < 0) return emptyList()
    val rowLen = bb.bitsPerRow[row]
    if (rowLen > 65 + 8) return emptyList()
    val pos = bb.search(row, 0, preamble, 16)
    if (pos + 65 > rowLen) return emptyList()
    bb.invert()
    val b = bb.bb[row]
    val chk = (b[7] and 0xf0) shr 4
    val sum = Rtl433BitUtil.addNibbles(b, 7) and 0x0f
    if (sum != chk) return emptyList()
    val id = (b[2] shl 8) or b[3]
    val moisture = b[4]
    val tSign = (b[5] and 0x80) shr 7
    var temperature = b[5] and 0x7f
    val sequence = (b[6] and 0xc0) shr 6
    val battLvl = (b[6] and 0x30) shr 4
    val lightLvl = b[6] and 0x0f
    val lightLux = luxEstimate[lightLvl]
    if (tSign != 0) temperature = 0 - temperature
    val out = listOf(
        Reading(
            "Homelead-HG9901",
            String.format("%04X", id),
            linkedMapOf(
                "battery_ok" to (if (battLvl > 1) 1 else 0),
                "battery_pct" to 100 * battLvl / 3,
                "temperature_C" to temperature.toDouble(),
                "moisture" to moisture,
                "light_lvl" to lightLvl,
                "light_lux" to lightLux,
                "sequence" to sequence,
                "mic" to "CHECKSUM",
            ),
        ),
    )
    bb.invert()
    return out
}

// unverified: homelead_hg9901.c:167-176 (struct), homelead_hg9901.c:84-165 (decode)
internal object HomeleadHg9901 : Rtl433Decoder() {
    override val name = "Homelead HG9901 (Geevon, Dr.Meter, Royal Gardineer) soil moisture/temp/light level sensor"
    override val mod = Mod.OOK_PWM
    override val short = 432
    override val long = 1228
    override val gap = 2000
    override val reset = 4500

    override fun decode(bb: BitBuffer): List<Reading> = homeleadDecode(bb)
}

private fun hondaremoteDecode(bb: BitBuffer): List<Reading> {
    val commandCode = arrayOf("boot", "unlock", "lock")
    for (row in 0 until bb.numRows) {
        val b = bb.bb[row]
        if (bb.bitsPerRow[row] < 385 || bb.bitsPerRow[row] > 394) continue
        if (b[0] != 0xFF || b[38] != 0xFF) continue
        val command = (b[46] - 0xAA) and 0xFF
        val code = if (command < commandCode.size) commandCode[command] else "unknown"
        val deviceId = (b[44] shl 8) or b[45]
        return listOf(Reading("Honda-CarRemote", deviceId.toString(), mapOf("code" to code)))
    }
    return emptyList()
}

// unverified: hondaremote.c:71-80 (struct; upstream disabled=1, no MIC, not gated here), hondaremote.c:33-69 (decode)
internal object Hondaremote : Rtl433Decoder() {
    override val name = "Honda Car Key"
    override val mod = Mod.FSK_PWM
    override val short = 250
    override val long = 500
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> = hondaremoteDecode(bb)
}

private fun ht680Decode(bb: BitBuffer): List<Reading> {
    for (row in 0 until bb.numRows) {
        if (bb.bitsPerRow[row] != 41 || (bb.bb[row][0] and 0xf8) != 0xa8) continue
        val b = IntArray(5)
        bb.extractBytes(row, 5, b, 36)
        if ((b[1] and 0xf0) != 0xa0 || (b[2] and 0x0c) != 0x08 || (b[3] and 0x30) != 0x20 || (b[4] and 0xf0) != 0xa0) continue
        val tristate = StringBuilder()
        for (byte in 0 until 5) {
            var bit = 7
            while (bit > 0) {
                tristate.append(
                    when ((b[byte] shr (bit - 1)) and 0x03) {
                        0x00 -> '0'
                        0x01 -> 'X'
                        0x02 -> 'Z'
                        0x03 -> '1'
                        else -> '?'
                    },
                )
                bit -= 2
            }
        }
        val tri = tristate.substring(0, tristate.length - 2)
        val address = (b[0] shl 12) or (b[1] shl 4) or (b[2] shr 4)
        val button1 = (b[3] shr 0) and 0x03
        val button2 = (b[3] shr 2) and 0x03
        val button3 = (b[3] shr 6) and 0x03
        val button4 = (b[2] shr 0) and 0x03
        return listOf(
            Reading(
                "HT680-Remote",
                String.format("0x%06X", address),
                linkedMapOf(
                    "button1" to (if (button1 == 3) "PRESSED" else ""),
                    "button2" to (if (button2 == 3) "PRESSED" else ""),
                    "button3" to (if (button3 == 3) "PRESSED" else ""),
                    "button4" to (if (button4 == 3) "PRESSED" else ""),
                    "tristate" to tri,
                ),
            ),
        )
    }
    return emptyList()
}

// unverified: ht680.c:96-105 (struct), ht680.c:21-94 (decode)
internal object Ht680 : Rtl433Decoder() {
    override val name = "HT680 Remote control"
    override val mod = Mod.OOK_PWM
    override val short = 200
    override val long = 600
    override val gap = 1200
    override val reset = 14000

    override fun decode(bb: BitBuffer): List<Reading> = ht680Decode(bb)
}

private fun ibisBeaconDecode(bb: BitBuffer): List<Reading> {
    if (bb.numRows != 1 || bb.bitsPerRow[0] < 232 || bb.bitsPerRow[0] > 250) return emptyList()
    var pos = bb.search(0, 0, intArrayOf(0xAB), 8)
    if (pos > 26) return emptyList()
    pos += 8
    var len = bb.bitsPerRow[0] - pos
    if (len < 224) return emptyList()
    len = 224
    val msg = IntArray(32)
    bb.extractBytes(0, pos, msg, len)
    val crcCalculated = Rtl433BitUtil.crc16(msg, 26, 0x8005, 0x0000)
    val crc = (msg[26] shl 8) or msg[27]
    if (crc != crcCalculated) return emptyList()
    val id = ((msg[5] and 0x0f) shl 12) or (msg[6] shl 4) or ((msg[7] and 0xf0) shr 4)
    val counter = (msg[20] shl 24) or (msg[21] shl 16) or (msg[22] shl 8) or msg[23]
    val codeStr = StringBuilder()
    for (i in 0 until (len + 7) / 8) codeStr.append(String.format("%02x", msg[i]))
    return listOf(
        Reading(
            "IBIS-Beacon",
            id.toString(),
            linkedMapOf(
                "counter" to counter,
                "code" to codeStr.toString(),
                "mic" to "CRC",
            ),
        ),
    )
}

// unverified: ibis_beacon.c:92-100 (struct), ibis_beacon.c:23-90 (decode)
internal object IbisBeacon : Rtl433Decoder() {
    override val name = "IBIS beacon"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 30
    override val reset = 100

    override fun decode(bb: BitBuffer): List<Reading> = ibisBeaconDecode(bb)
}

private fun hondaKeyfobDecode(bb: BitBuffer): List<Reading> {
    if (bb.numRows > 1) return emptyList()
    if (bb.bitsPerRow[0] < 150 || bb.bitsPerRow[0] > 184) return emptyList()
    val preamble = intArrayOf(0xec, 0x0f, 0x62)
    val bitOffset = bb.search(0, 0, preamble, preamble.size * 8)
    if (bitOffset + 16 + 120 > bb.bitsPerRow[0]) return emptyList()
    val b = IntArray(15)
    bb.extractBytes(0, bitOffset + 16, b, 120)
    val crc = Rtl433BitUtil.crc8(b, 14, 0x2f, 0x00)
    if (crc != b[14]) return emptyList()
    val deviceId = (b[2] shl 24) or (b[3] shl 16) or (b[4] shl 8) or b[5]
    val deviceCounter = (b[7] shl 16) or (b[8] shl 8) or b[9]
    val rollingCode = (b[10] shl 24) or (b[11] shl 16) or (b[12] shl 8) or b[13]
    val event = when (b[6]) {
        0x21 -> "Lock"
        0x22 -> "Unlock"
        0x24 -> "Trunk"
        0x27 -> "Emergency"
        0x2d -> "RemoteStart"
        else -> "?"
    }
    return listOf(
        Reading(
            "Honda-KR5V2X1X",
            String.format("%08x", deviceId),
            linkedMapOf(
                "event" to event,
                "counter" to deviceCounter,
                "code" to rollingCode,
                "mic" to "CRC",
            ),
        ),
    )
}

// unverified: continental_car_remote.c:241-249 (struct), continental_car_remote.c:174-239 (decode)
internal object HondaKeyfob : Rtl433Decoder() {
    override val name = "Honda Keyfob KR5V2X/1X (-f 433.6M -s 1024k)"
    override val mod = Mod.FSK_MC_ZEROBIT
    override val short = 60
    override val long = 120
    override val reset = 1500

    override fun decode(bb: BitBuffer): List<Reading> = hondaKeyfobDecode(bb)
}

private fun honeywellDecode(bb: BitBuffer): List<Reading> {
    val preamblePattern = intArrayOf(0x55, 0x55, 0x56)
    val row = 0
    if (bb.numRows != 1 || bb.bitsPerRow[row] < 120) return emptyList()
    val rawLen = bb.bitsPerRow[row]
    val b = IntArray(10)
    var channel = 0
    var deviceId = 0
    var len = 0
    var rawPos = 0
    var found = false
    while (true) {
        rawPos = bb.search(row, rawPos, preamblePattern, 24)
        if (rawPos + 24 >= rawLen) break
        val decoded = BitBuffer()
        bb.manchesterDecode(row, rawPos + 24, decoded, 96)
        rawPos += 1
        len = decoded.bitsPerRow[0]
        if (len < 48) continue
        for (i in 0 until 10) b[i] = decoded.bb[0][i]
        channel = b[0] shr 4
        deviceId = ((b[0] and 0xf) shl 16) or (b[1] shl 8) or b[2]
        val crc = (b[4] shl 8) or b[5]
        if (deviceId == 0 && crc == 0) continue
        val crcCalculated = if (channel == 0x2 || channel == 0x4 || channel == 0x9 || channel == 0xA || channel == 0xC) {
            Rtl433BitUtil.crc16(b, 4, 0x8050, 0)
        } else {
            Rtl433BitUtil.crc16(b, 4, 0x8005, 0)
        }
        if (crc == crcCalculated) {
            found = true
            break
        }
    }
    if (!found) return emptyList()
    val event = b[3]
    val contact = (event and 0x80) shr 7
    val tamper = (event and 0x40) shr 6
    val reed = (event and 0x20) shr 5
    val alarm = (event and 0x10) shr 4
    val batteryLow = (event and 0x08) shr 3
    val heartbeat = (event and 0x04) shr 2
    return listOf(
        Reading(
            "Honeywell-Security",
            String.format("%05x", deviceId),
            linkedMapOf(
                "channel" to channel,
                "event" to event,
                "state" to (if (contact != 0) "open" else "closed"),
                "contact_open" to contact,
                "reed_open" to reed,
                "alarm" to alarm,
                "tamper" to tamper,
                "battery_ok" to (if (batteryLow == 0) 1 else 0),
                "heartbeat" to heartbeat,
                "mic" to "CRC",
            ),
        ),
    )
}

// unverified: honeywell.c:164-172 (struct), honeywell.c:53-162 (decode)
internal object Honeywell : Rtl433Decoder() {
    override val name = "Honeywell Door/Window Sensor, 2Gig DW10/DW11, RE208 repeater"
    override val mod = Mod.OOK_PCM
    override val short = 136
    override val long = 136
    override val reset = 408

    override fun decode(bb: BitBuffer): List<Reading> = honeywellDecode(bb)
}

private fun honeywellWdbDecode(bb: BitBuffer): List<Reading> {
    val row = bb.findRepeatedRow(4, 48)
    if (row < 0) return emptyList()
    val bytes = bb.bb[row]
    if (bb.bitsPerRow[row] != 48) return emptyList()
    bb.invert()
    val parity = Rtl433BitUtil.parityBytes(bytes, 6)
    if ((bytes[0] == 0 && bytes[2] == 0 && bytes[4] == 0 && bytes[5] == 0) ||
        (bytes[0] == 0xff && bytes[2] == 0xff && bytes[4] == 0xff && bytes[5] == 0xff)
    ) return emptyList()
    if (parity != 0) return emptyList()
    val device = (bytes[0] shl 12) or (bytes[1] shl 4) or (bytes[2] shr 4)
    val type = (bytes[3] and 0x70) shr 4
    val klass = when (type) {
        0x1 -> "PIR-Motion"
        0x2 -> "Doorbell"
        0x5 -> "Contact"
        else -> "Unknown"
    }
    val tmp = bytes[4] and 0x3
    val alert = when (tmp) {
        0x0 -> "Normal"
        0x1, 0x2 -> "High"
        0x3 -> "Full"
        else -> "Unknown"
    }
    var secretKnock = (bytes[5] and 0x10) shr 4
    var tampered = secretKnock
    if (type == 0x5) {
        secretKnock = 0
    } else {
        tampered = 0
    }
    val relay = (bytes[5] and 0x8) shr 3
    val battery = (bytes[5] and 0x2) shr 1
    val opened = (bytes[5] and 0x20) shr 5
    val closed = (bytes[5] and 0x40) shr 6
    val open = if (opened != 0 && closed == 0) 1 else if (opened == 0 && closed != 0) 0 else -1
    return listOf(
        Reading(
            "Honeywell-ActivLink",
            String.format("%x", device),
            linkedMapOf(
                "subtype" to klass,
                "battery_ok" to (if (battery == 0) 1 else 0),
                "alert" to alert,
                "secret_knock" to secretKnock,
                "open" to open,
                "tampered" to tampered,
                "relay" to relay,
                "mic" to "PARITY",
            ),
        ),
    )
}

// unverified: honeywell_wdb.c:156-166 (struct), honeywell_wdb.c:48-154 (decode)
internal object HoneywellWdb : Rtl433Decoder() {
    override val name = "Honeywell ActivLink, Wireless Doorbell"
    override val mod = Mod.OOK_PWM
    override val short = 175
    override val long = 340
    override val gap = 0
    override val reset = 5000
    override val sync = 500

    override fun decode(bb: BitBuffer): List<Reading> = honeywellWdbDecode(bb)
}

// unverified: honeywell_wdb.c:168-178 (struct), honeywell_wdb.c:48-154 (decode)
internal object HoneywellWdbFsk : Rtl433Decoder() {
    override val name = "Honeywell ActivLink, Wireless Doorbell (FSK)"
    override val mod = Mod.FSK_PWM
    override val short = 160
    override val long = 320
    override val gap = 0
    override val reset = 560
    override val sync = 500

    override fun decode(bb: BitBuffer): List<Reading> = honeywellWdbDecode(bb)
}

private fun intertechnoDecode(bb: BitBuffer): List<Reading> {
    if (bb.bb[0][0] != 0 || (bb.bb[1][0] != 0x56 && bb.bb[1][0] != 0x69)) return emptyList()
    val b = bb.bb[1]
    val idStr = String.format("%02x%02x%02x%02x%02x", b[0], b[1], b[2], b[3], b[4])
    val slave = b[7] and 0x0f
    val master = (b[7] and 0xf0) shr 4
    val command = b[6] and 0x07
    return listOf(
        Reading(
            "Intertechno-Remote",
            idStr,
            mapOf("slave" to slave, "master" to master, "command" to command),
        ),
    )
}

// unverified: intertechno.c:59-69 (struct; upstream disabled=1, not gated here), intertechno.c:1-57 (decode)
internal object Intertechno : Rtl433Decoder() {
    override val name = "Intertechno 433"
    override val mod = Mod.OOK_PPM
    override val short = 330
    override val long = 1400
    override val gap = 1700
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> = intertechnoDecode(bb)
}

private fun crc4(msg: IntArray, nBytes: Int, polynomial: Int, init: Int): Int {
    var remainder = init shl 4
    val poly = polynomial shl 4
    for (n in 0 until nBytes) {
        remainder = remainder xor msg[n]
        for (bit in 0 until 8) {
            remainder = if ((remainder and 0x80) != 0) (remainder shl 1) xor poly else remainder shl 1
        }
    }
    return (remainder shr 4) and 0x0f
}

private fun jascoDecode(bb: BitBuffer): List<Reading> {
    val preamble = intArrayOf(0xfc, 0x0c)
    if (bb.bitsPerRow[0] < 80 || bb.bitsPerRow[0] > 87) return emptyList()
    val startPos = bb.search(0, 0, preamble, 16) + 16
    if (startPos + 64 > bb.bitsPerRow[0]) return emptyList()
    val packetBits = BitBuffer()
    bb.manchesterDecode(0, startPos, packetBits, 32)
    if (packetBits.bitsPerRow[0] < 32) return emptyList()
    val b = packetBits.bb[0]
    val chk = b[0] xor b[1] xor b[2] xor b[3]
    if (chk != 0) return emptyList()
    val sensorId = (b[0] shl 8) or b[1]
    val sClosed = if ((b[2] and 0xef) == 0xef) 1 else 0
    return listOf(
        Reading(
            "Jasco-Security",
            sensorId.toString(),
            mapOf("status" to sClosed, "mic" to "CHECKSUM"),
        ),
    )
}

// unverified: jasco.c:80-88 (struct), jasco.c:22-78 (decode)
internal object Jasco : Rtl433Decoder() {
    override val name = "Jasco/GE Choice Alert Security Devices"
    override val mod = Mod.OOK_PCM
    override val short = 250
    override val long = 250
    override val reset = 1800

    override fun decode(bb: BitBuffer): List<Reading> = jascoDecode(bb)
}

private fun kedsumDecode(bb: BitBuffer): List<Reading> {
    if (bb.numRows < 5 ||
        bb.bitsPerRow[0] != 0 || bb.bitsPerRow[1] != 0 || bb.bitsPerRow[2] != 0 || bb.bitsPerRow[3] != 0 || bb.bitsPerRow[4] != 0
    ) return emptyList()
    val r = bb.findRepeatedRow(4, 42)
    if (r < 0 || bb.bitsPerRow[r] != 42) return emptyList()
    val b = IntArray(5)
    bb.extractBytes(r, 2, b, 40)
    val crc = crc4(b, 4, 0x3, 0x0) xor (b[4] shr 4)
    if (crc != (b[4] and 0xf)) return emptyList()
    val id = b[0]
    var battery = b[1] shr 6
    val channel = ((b[1] and 0x30) shr 4) + 1
    val tempRaw = ((b[2] and 0x0f) shl 8) or (b[2] and 0xf0) or (b[1] and 0x0f)
    val humidity = ((b[3] and 0x0f) shl 4) or ((b[3] and 0xf0) shr 4)
    val tempF = (tempRaw - 900) * 0.1f
    val flags = (b[1] and 0xc0) or (b[4] shr 4)
    battery = if (battery == 2) 100 else battery * 10
    return listOf(
        Reading(
            "Kedsum-TH",
            id.toString(),
            linkedMapOf(
                "channel" to channel,
                "battery_ok" to (battery * 0.01f).toDouble(),
                "flags" to flags,
                "temperature_F" to tempF.toDouble(),
                "humidity" to humidity,
                "mic" to "CRC",
            ),
        ),
    )
}

// unverified: kedsum.c:108-117 (struct), kedsum.c:39-106 (decode), crc4 at bit_util.c:240
internal object Kedsum : Rtl433Decoder() {
    override val name = "Kedsum Temperature & Humidity Sensor, Pearl NC-7415"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 4400
    override val reset = 9400

    override fun decode(bb: BitBuffer): List<Reading> = kedsumDecode(bb)
}

private fun keruiDecode(bb: BitBuffer): List<Reading> {
    val r = bb.findRepeatedRow(9, 25)
    if (r < 0) return emptyList()
    if (bb.bitsPerRow[r] != 25) return emptyList()
    val b = bb.bb[r]
    if (b[0] == 0 && b[1] == 0 && b[2] == 0) return emptyList()
    b[0] = b[0].inv() and 0xFF
    b[1] = b[1].inv() and 0xFF
    b[2] = b[2].inv() and 0xFF
    val id = (b[0] shl 12) or (b[1] shl 4) or (b[2] shr 4)
    val cmd = b[2] and 0x0F
    val cmdStr = when (cmd) {
        0xa -> "motion"
        0xe -> "open"
        0x7 -> "close"
        0xb -> "tamper"
        0x5 -> "water"
        0xf -> "battery"
        else -> return emptyList()
    }
    val fields = linkedMapOf<String, Any?>("cmd" to cmd)
    if (cmd == 0xa) fields["motion"] = 1
    if (cmd == 0xe) fields["opened"] = 1
    if (cmd == 0x7) fields["opened"] = 0
    if (cmd == 0xb) fields["tamper"] = 1
    if (cmd == 0x5) fields["water"] = 1
    if (cmd == 0xf) fields["battery_ok"] = 0
    fields["state"] = cmdStr
    return listOf(Reading("Kerui-Security", String.format("0x%x", id), fields))
}

// unverified: kerui.c:106-116 (struct), kerui.c:32-104 (decode)
internal object Kerui : Rtl433Decoder() {
    override val name = "Kerui PIR / Contact Sensor"
    override val mod = Mod.OOK_PWM
    override val short = 420
    override val long = 960
    override val gap = 1100
    override val reset = 9900
    override val tolerance = 160

    override fun decode(bb: BitBuffer): List<Reading> = keruiDecode(bb)
}

private fun kiddeSmokeDecode(bb: BitBuffer): List<Reading> {
    val row = 0
    if (bb.numRows != 1 || bb.bitsPerRow[row] < 25 * 2) return emptyList()
    val rowLen = bb.bitsPerRow[row]
    var start = 0
    while (start < rowLen) {
        val decoded = BitBuffer()
        val next = bb.differentialManchesterDecode(row, start, decoded, 0)
        val len = decoded.bitsPerRow[0]
        start = if (next > start) next else start + 1
        if (len < 25) continue
        val b = decoded.bb[0]
        var searchStart = 9
        while (searchStart + 16 <= len) {
            val pos = decoded.search(0, searchStart, intArrayOf(0x7f), 8)
            if (pos + 16 > len) break
            searchStart = pos + 1
            if (pos < 9) continue
            if (bitrowGetBit(b, pos - 9) != 0) continue
            var idRefl = 0
            for (i in 0 until 8) idRefl = (idRefl shl 1) or bitrowGetBit(b, pos - 8 + i)
            var id2Refl = 0
            for (i in 0 until 8) id2Refl = (id2Refl shl 1) or bitrowGetBit(b, pos + 8 + i)
            if (id2Refl != (idRefl xor 0x80)) continue
            val id = rv8(idRefl and 0xFF)
            return listOf(Reading("Kidde-Smoke", String.format("%02x", id), emptyMap()))
        }
    }
    return emptyList()
}

// unverified: kidde_smoke.c:150-159 (struct; upstream disabled=1, no checksum, not gated here), kidde_smoke.c:78-148 (decode)
internal object KiddeSmoke : Rtl433Decoder() {
    override val name = "Kidde RF-SM-DC wireless-interconnect smoke alarm"
    override val mod = Mod.OOK_PCM
    override val short = 400
    override val long = 400
    override val reset = 3000

    override fun decode(bb: BitBuffer): List<Reading> = kiddeSmokeDecode(bb)
}

private fun klimaloggDecode(bb: BitBuffer): List<Reading> {
    val preamble = intArrayOf(0xB4, 0x2B)
    if (bb.bitsPerRow[0] < 11 * 8) return emptyList()
    val bitOffset = bb.search(0, 0, preamble, 16) + 16
    if (bitOffset + 9 * 8 > bb.bitsPerRow[0]) return emptyList()
    val b = IntArray(9)
    bb.extractBytes(0, bitOffset, b, 9 * 8)
    if (b[7] != 0x6a) return emptyList()
    for (i in 0 until 9) b[i] = rv8(b[i])
    if (Rtl433BitUtil.crc8(b, 9, 0x31, 0) != 0) return emptyList()
    val id = ((b[0] and 0x7f) shl 8) or b[1]
    val tempRaw = (b[2] and 0x0f) * 100 + (b[3] shr 4) * 10 + (b[3] and 0x0f)
    val temperature = (tempRaw - 400) * 0.1f
    var humidity = b[4] and 0x7f
    val batteryLow = (b[5] and 0x80) shr 7
    val sequenceNr = (b[6] and 0xf0) shr 4
    if (humidity == 0x6a) humidity = 100
    return listOf(
        Reading(
            "Klimalogg-Pro",
            String.format("%04x", id),
            linkedMapOf(
                "battery_ok" to (if (batteryLow == 0) 1 else 0),
                "temperature_C" to temperature.toDouble(),
                "humidity" to humidity,
                "sequence_nr" to sequenceNr,
                "mic" to "CRC",
            ),
        ),
    )
}

// unverified: klimalogg.c:113-123 (struct; upstream disabled=1, not gated here), klimalogg.c:46-111 (decode)
internal object Klimalogg : Rtl433Decoder() {
    override val name = "Klimalogg"
    override val mod = Mod.OOK_NRZS
    override val short = 26
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> = klimaloggDecode(bb)
}

private fun kw9015bDecode(bb: BitBuffer): List<Reading> {
    val row = bb.findRepeatedRow(3, 36)
    if (row < 0) return emptyList()
    if (bb.bitsPerRow[row] > 36) return emptyList()
    val b = bb.bb[row]
    val device = rv8(b[0]) and 0x0f
    val tempRaw = s16((rv8(b[2]) shl 8) or (rv8(b[1]) and 0xf0))
    val tempC = (tempRaw shr 4) * 0.1f
    val rain = ((rv8(b[0]) and 0xc0) shl 4) or ((rv8(b[1]) and 0x06) shl 7) or rv8(b[3])
    val chksum = ((rv8(b[0]) shr 4) + (rv8(b[0]) and 0x0f) +
        (rv8(b[1]) shr 4) + (rv8(b[1]) and 0x0f) +
        (rv8(b[2]) shr 4) + (rv8(b[2]) and 0x0f) +
        (rv8(b[3]) shr 4) + (rv8(b[3]) and 0x0f)) and 0xFF
    val batteryLow = b[1] shr 7
    if ((chksum and 0x0f) != (rv8(b[4]) and 0x0f)) return emptyList()
    return listOf(
        Reading(
            "Inovalley-kw9015b",
            device.toString(),
            linkedMapOf(
                "battery_ok" to (if (batteryLow == 0) 1 else 0),
                "temperature_C" to tempC.toDouble(),
                "rain" to rain,
                "rain_mm" to (rain * 0.45f).toDouble(),
            ),
        ),
    )
}

// unverified: inovalley-kw9015b.c:87-97 (struct; upstream disabled=1, not gated here), inovalley-kw9015b.c:31-85 (decode)
internal object Kw9015b : Rtl433Decoder() {
    override val name = "Inovalley kw9015b, TFA Dostmann 30.3161 (Rain and temperature sensor)"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val gap = 4800
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> = kw9015bDecode(bb)
}

private fun lacrosseBreezeproDecode(bb: BitBuffer): List<Reading> {
    val preamble = intArrayOf(0xd2, 0xaa, 0x2d, 0xd4)
    if (bb.bitsPerRow[0] < 264) return emptyList()
    var offset = bb.search(0, 0, preamble, preamble.size * 8)
    if (offset >= bb.bitsPerRow[0]) return emptyList()
    offset += preamble.size * 8
    val b = IntArray(11)
    bb.extractBytes(0, offset, b, 11 * 8)
    if (Rtl433BitUtil.crc8(b, 11, 0x31, 0x00) != 0) return emptyList()
    val id = (b[0] shl 16) or (b[1] shl 8) or b[2]
    val flags = b[3] and 0xf1
    val seq = (b[3] and 0x0e) shr 1
    val rawTemp = (b[4] shl 4) or ((b[5] and 0xf0) shr 4)
    val humidity = ((b[5] and 0x0f) shl 8) or b[6]
    val rawSpeed = (b[7] shl 4) or ((b[8] and 0xf0) shr 4)
    val direction = ((b[8] and 0x0f) shl 8) or b[9]
    val tempC = (rawTemp - 400) * 0.1f
    val speedKmh = rawSpeed * 0.1f
    if (humidity < 0 || humidity > 100 || tempC < -40 || tempC > 70 ||
        direction < 0 || direction > 360 || speedKmh < 0 || speedKmh > 200
    ) return emptyList()
    return listOf(
        Reading(
            "LaCrosse-BreezePro",
            String.format("%06x", id),
            linkedMapOf(
                "seq" to seq,
                "flags" to flags,
                "temperature_C" to tempC.toDouble(),
                "humidity" to humidity,
                "wind_avg_km_h" to speedKmh.toDouble(),
                "wind_dir_deg" to direction,
                "mic" to "CRC",
            ),
        ),
    )
}

// unverified: lacrosse_breezepro.c:169-177 (struct), lacrosse_breezepro.c:84-153 (decode)
internal object LacrosseBreezepro : Rtl433Decoder() {
    override val name = "LaCrosse Technology View LTV-WSDTH01 Breeze Pro Wind Sensor"
    override val mod = Mod.FSK_PCM
    override val short = 107
    override val long = 107
    override val reset = 5900

    override fun decode(bb: BitBuffer): List<Reading> = lacrosseBreezeproDecode(bb)
}

private fun lacrosseThDecode(bb: BitBuffer): List<Reading> {
    val preamble = intArrayOf(0xd2, 0xaa, 0x2d, 0xd4)
    if (bb.bitsPerRow[0] < 156) return emptyList()
    if (bb.bitsPerRow[0] > 290) return emptyList()
    val modelNum = if (bb.bitsPerRow[0] < 280) 3 else 2
    var offset = bb.search(0, 0, preamble, preamble.size * 8)
    if (offset >= bb.bitsPerRow[0]) return emptyList()
    offset += preamble.size * 8
    val b = IntArray(11)
    bb.extractBytes(0, offset, b, 8 * 8)
    val chk3 = Rtl433BitUtil.crc8(b, 8, 0x31, 0x00)
    val chk2 = Rtl433BitUtil.crc8(b, 8, 0x31, 0xac)
    val chk2i = Rtl433BitUtil.crc8(b, 8, 0x31, 0xb2)
    if (chk3 != 0 && chk2 != 0 && chk2i != 0) return emptyList()
    val id = (b[0] shl 16) or (b[1] shl 8) or b[2]
    val flags = b[3] and 0x31
    val battLow = (b[3] and 0x80) shr 7
    val retrans = (b[3] and 0x40) shr 6
    val seq = (b[3] and 0x0e) shr 1
    val rawTemp = (b[4] shl 4) or ((b[5] and 0xf0) shr 4)
    val humidity = ((b[5] and 0x0f) shl 8) or b[6]
    val tempC = (rawTemp - 400) * 0.1f
    if (humidity < 0 || humidity > 100 || tempC < -50 || tempC > 70) return emptyList()
    val fields = linkedMapOf<String, Any?>(
        "battery_ok" to (if (battLow == 0) 1 else 0),
        "seq" to seq,
        "temperature_C" to tempC.toDouble(),
        "humidity" to humidity,
        "mic" to "CRC",
    )
    if (retrans != 0) fields["retransmit"] = retrans
    if (flags != 0) fields["flags"] = flags
    val model = if (modelNum == 3) "LaCrosse-TH3" else "LaCrosse-TH2"
    return listOf(Reading(model, String.format("%06x", id), fields))
}

// unverified: lacrosse_th3.c:175-183 (struct), lacrosse_th3.c:79-157 (decode)
internal object LacrosseTh3 : Rtl433Decoder() {
    override val name = "LaCrosse Technology View LTV-TH Thermo/Hygro Sensor"
    override val mod = Mod.FSK_PCM
    override val short = 104
    override val long = 104
    override val reset = 9600

    override fun decode(bb: BitBuffer): List<Reading> = lacrosseThDecode(bb)
}

private fun lacrosseItDecode(bb: BitBuffer, device29or35: Int): List<Reading> {
    val preamble = intArrayOf(0xa2, 0xdd, 0x49)
    val out = ArrayList<Reading>()
    for (row in 0 until bb.numRows) {
        val startPos = bb.search(row, 0, preamble, 24)
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
        val model = if (device29or35 == 29) "LaCrosse-TX29IT" else "LaCrosse-TX35DTHIT"
        val fields = linkedMapOf<String, Any?>(
            "battery_ok" to (if (batteryLow == 0) 1 else 0),
            "newbattery" to newBatt,
            "temperature_C" to tempC.toDouble(),
        )
        if (humidity == 0x6a || humidity == 0x7d) {
            if (humidity == 0x7d) sensorId += 0x40
        } else {
            fields["humidity"] = humidity
        }
        fields["mic"] = "CRC"
        out.add(Reading(model, sensorId.toString(), fields))
    }
    return out
}

// unverified: lacrosse_tx35.c:186-194 (struct, TX29 variant), lacrosse_tx35.c:85-158 (lacrosse_it), constants lacrosse_tx35.c:80-82
internal object LacrosseTx29 : Rtl433Decoder() {
    override val name = "LaCrosse TX29IT, TFA Dostmann 30.3159.IT Temperature sensor"
    override val mod = Mod.FSK_PCM
    override val short = 55
    override val long = 55
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> = lacrosseItDecode(bb, 29)
}

private fun tx22Bcd3(b: IntArray, p: Int): Int = ((b[p] and 0x0f) * 100) + ((b[p + 1] shr 4) * 10) + (b[p + 1] and 0x0f)

private fun tx22Nybble3(b: IntArray, p: Int): Int = ((b[p] and 0x0f) shl 8) or b[p + 1]

private fun lacrosseTx22uitDecode(bb: BitBuffer): List<Reading> {
    val preamble = intArrayOf(0xaa, 0xaa, 0x2d, 0xd4)
    var offset = bb.search(0, 0, preamble, preamble.size * 8)
    if (offset >= bb.bitsPerRow[0]) return emptyList()
    offset += preamble.size * 8
    var size = bb.bitsPerRow[0] - offset
    if (size > 64 * 8) size = 64 * 8
    val b = IntArray(64)
    bb.extractBytes(0, offset, b, size)
    size /= 8
    var quartets = 0
    for (n in 5 downTo 1) {
        if (n == 4) continue
        val dataLen = 2 + 2 * n
        if (dataLen + 2 <= size && Rtl433BitUtil.crc8(b, dataLen, 0x31, 0x00) == b[dataLen]) {
            quartets = n
            break
        }
    }
    if (quartets == 0) return emptyList()
    size = 2 + 2 * quartets + 2
    val id = b[0]
    val flags = b[1]
    var rawTemp = -1
    var humidity = -1
    var rawSpeed = -1
    var direction = -1
    var rainMm = -1.0f
    var windGustKmh = -1.0f
    var recognized = 0
    var p = 2
    while (p < size - 2) {
        when (b[p] shr 4) {
            0 -> {
                rawTemp = tx22Bcd3(b, p)
                recognized++
            }
            1 -> {
                humidity = tx22Bcd3(b, p)
                recognized++
            }
            2 -> {
                rainMm = (0.5180 * tx22Nybble3(b, p)).toFloat()
                recognized++
            }
            3 -> {
                direction = ((b[p] and 0x0f) * 22.5).toInt()
                rawSpeed = b[p + 1]
                recognized++
            }
            4 -> {
                windGustKmh = (tx22Nybble3(b, p) * 0.1).toFloat()
                recognized++
            }
        }
        p += 2
    }
    if (recognized == 0) return emptyList()
    val tempC = (rawTemp - 400) * 0.1f
    val speedKmh = rawSpeed * 0.1f
    val fields = linkedMapOf<String, Any?>("flags" to flags)
    if (-40.0 < tempC && tempC <= 70.0) fields["temperature_C"] = tempC.toDouble()
    if (0 < humidity && humidity <= 100) fields["humidity"] = humidity
    if (0.0 <= rainMm && rainMm <= 0xfff * 0.5180) fields["rain_mm"] = rainMm.toDouble()
    if (0.0 <= speedKmh && speedKmh <= 200.0) fields["wind_avg_km_h"] = speedKmh.toDouble()
    if (0.0 <= windGustKmh && windGustKmh <= 200.0) fields["wind_gust_km_h"] = windGustKmh.toDouble()
    if (0 <= direction && direction <= 360) fields["wind_dir_deg"] = direction
    fields["mic"] = "CRC"
    return listOf(Reading("LaCrosse-TX22UIT", String.format("%02x", id), fields))
}

// unverified: lacrosse_tx22uit.c:248-256 (struct, FSK), lacrosse_tx22uit.c:100-218 (decode)
internal object LacrosseTx22uit : Rtl433Decoder() {
    override val name = "LaCrosse Technology TX22U-IT"
    override val mod = Mod.FSK_PCM
    override val short = 116
    override val long = 116
    override val reset = 5900

    override fun decode(bb: BitBuffer): List<Reading> = lacrosseTx22uitDecode(bb)
}

// unverified: lacrosse_tx22uit.c:258-266 (struct, OOK), lacrosse_tx22uit.c:228-232 (invert wrapper), lacrosse_tx22uit.c:100-218 (decode)
internal object LacrosseTx22uitOok : Rtl433Decoder() {
    override val name = "LaCrosse Technology TX22U-IT (OOK)"
    override val mod = Mod.OOK_PCM
    override val short = 120
    override val long = 120
    override val reset = 5000

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        return lacrosseTx22uitDecode(bb)
    }
}

private fun infactoryCrcCheck(b: IntArray): Boolean {
    val msg = IntArray(5)
    for (i in 0 until 5) msg[i] = b[i]
    val msgCrc = msg[1] shr 4
    msg[1] = (msg[1] and 0x0F) or ((msg[4] and 0x0F) shl 4)
    var crc = crc4(msg, 4, 0x13, 0)
    crc = crc xor (msg[4] shr 4)
    return crc == msgCrc
}

private fun infactoryDecode(bb: BitBuffer): List<Reading> {
    if (bb.bitsPerRow[0] != 40 && bb.bitsPerRow[0] != 41 && bb.bitsPerRow[0] != 42) return emptyList()
    val b = bb.bb[0]
    val channel = b[4] and 0x03
    if (channel == 0) return emptyList()
    if (!infactoryCrcCheck(b)) return emptyList()
    val id = b[0]
    val button = (b[1] shr 3) and 1
    val batteryLow = (b[1] shr 2) and 1
    val tempRaw = (b[2] shl 4) or (b[3] shr 4)
    val humidity = (b[3] and 0x0F) * 10 + (b[4] shr 4)
    val tempF = (tempRaw - 900) * 0.1f
    if (humidity > 100) return emptyList()
    if (tempF < -40.0f || tempF > 158.0f) return emptyList()
    return listOf(
        Reading(
            "inFactory-TH",
            id.toString(),
            linkedMapOf(
                "channel" to channel,
                "battery_ok" to (if (batteryLow == 0) 1 else 0),
                "button" to button,
                "temperature_F" to tempF.toDouble(),
                "humidity" to humidity,
                "mic" to "CRC",
            ),
        ),
    )
}

// unverified: infactory.c:154-164 (struct), infactory.c:57-119 (decode + crc check)
internal object Infactory : Rtl433Decoder() {
    override val name = "inFactory, nor-tec, FreeTec NC-3982-913 temperature humidity sensor"
    override val mod = Mod.OOK_PPM
    override val short = 2000
    override val long = 4000
    override val sync = 500
    override val reset = 5000
    override val tolerance = 750

    override fun decode(bb: BitBuffer): List<Reading> = infactoryDecode(bb)
}

private fun inkbirdIth20rDecode(bb: BitBuffer): List<Reading> {
    val preamble = intArrayOf(0xaa, 0xaa, 0xaa, 0x2d, 0xd4)
    if (bb.numRows != 1 || bb.bitsPerRow[0] < 187) return emptyList()
    var startPos = bb.search(0, 0, preamble, preamble.size * 8)
    if (startPos == bb.bitsPerRow[0]) return emptyList()
    startPos += preamble.size * 8
    var len = bb.bitsPerRow[0] - startPos
    if ((len + 7) / 8 < 19) return emptyList()
    len = minOf(len, 19 * 8)
    val msg = IntArray(19)
    bb.extractBytes(0, startPos, msg, len)
    val crcCalculated = Rtl433BitUtil.crc16lsb(msg, 16, 0xA001, 0x86F4)
    val crcReceived = (msg[17] shl 8) or msg[16]
    if (crcReceived != crcCalculated) return emptyList()
    val sensorNum = msg[4]
    val batteryOk = msg[7] * 0.01f
    val sensorId = (msg[9] shl 8) or msg[8]
    val temperature = s16((msg[11] shl 8) or msg[10]) * 0.1f
    val temperatureExt = s16((msg[13] shl 8) or msg[12]) * 0.1f
    val humidity = ((msg[15] shl 8) or msg[14]) * 0.1f
    return listOf(
        Reading(
            "Inkbird-ITH20R",
            sensorId.toString(),
            linkedMapOf(
                "battery_ok" to batteryOk.toDouble(),
                "sensor_num" to sensorNum,
                "temperature_C" to temperature.toDouble(),
                "temperature_2_C" to temperatureExt.toDouble(),
                "humidity" to humidity.toDouble(),
                "mic" to "CRC",
            ),
        ),
    )
}

// unverified: inkbird_ith20r.c:143-151 (struct), inkbird_ith20r.c:56-129 (decode); crc constants inkbird_ith20r.c:52-53; subtype/word56/word18 are computed upstream but not emitted, omitted here
internal object InkbirdIth20r : Rtl433Decoder() {
    override val name = "Inkbird ITH-20R temperature humidity sensor"
    override val mod = Mod.FSK_PCM
    override val short = 100
    override val long = 100
    override val reset = 4000

    override fun decode(bb: BitBuffer): List<Reading> = inkbirdIth20rDecode(bb)
}

private fun lacrosseR1Decode(bb: BitBuffer): List<Reading> {
    val preamble = intArrayOf(0xd2, 0xaa, 0x2d, 0xd4)
    if (bb.numRows > 1) return emptyList()
    val msgLen = bb.bitsPerRow[0]
    if (msgLen < 170) return emptyList()
    if (msgLen > 272) return emptyList()
    var offset = bb.search(0, 0, preamble, preamble.size * 8)
    if (offset >= msgLen) return emptyList()
    offset += preamble.size * 8
    val b = IntArray(20)
    bb.extractBytes(0, offset, b, 20 * 8)
    var rev = 1
    var chk = Rtl433BitUtil.crc8(b, 11, 0x31, 0x00)
    if (chk == 0 && b[4] == 0xaa && b[5] == 0xaa && b[6] == 0xaa && (b[8] and 0x0f) == 0x0a && b[9] == 0xaa) {
        rev = 9
    } else if (chk == 0 && b[10] != 0) {
        rev = 3
    } else {
        chk = Rtl433BitUtil.crc8(b, 8, 0x31, 0x00)
        if (b[10] != 0 || chk != 0) return emptyList()
    }
    val id = (b[0] shl 16) or (b[1] shl 8) or b[2]
    val flags = b[3] and 0x31
    val battLow = (b[3] and 0x80) shr 7
    val startup = (b[3] and 0x40) shr 6
    val seq = (b[3] and 0x0e) shr 1
    val rawRain1 = ((b[5] xor 0xaa) shl 16) or (b[4] shl 8) or b[6]
    val rawRain2 = ((b[8] xor 0xaa) shl 16) or (b[7] shl 8) or b[9]
    val rawWind = (b[7] shl 4) or (b[8] shr 4)
    val rainMm = rawRain1 * 0.25f
    val rain2Mm = rawRain2 * 0.25f
    val wspeedKmh = rawWind * 0.1f
    val model = when (rev) {
        1 -> "LaCrosse-R1"
        3 -> "LaCrosse-R3"
        else -> "LaCrosse-W1"
    }
    val fields = linkedMapOf<String, Any?>("battery_ok" to (if (battLow == 0) 1 else 0), "seq" to seq)
    if (startup != 0) fields["startup"] = startup
    if (flags != 0) fields["flags"] = flags
    if (rev != 9) fields["rain_mm"] = rainMm.toDouble()
    if (rev == 3) fields["rain2_mm"] = rain2Mm.toDouble()
    if (rev == 9) fields["wind_avg_km_h"] = wspeedKmh.toDouble()
    fields["mic"] = "CRC"
    return listOf(Reading(model, String.format("%06x", id), fields))
}

// unverified: lacrosse_r1.c:215-223 (struct), lacrosse_r1.c:108-210 (decode)
internal object LacrosseR1 : Rtl433Decoder() {
    override val name = "LaCrosse Technology View LTV-R1, LTV-R3 Rainfall Gauge, LTV-W1/W2 Wind Sensor"
    override val mod = Mod.FSK_PCM
    override val short = 104
    override val long = 104
    override val reset = 9600

    override fun decode(bb: BitBuffer): List<Reading> = lacrosseR1Decode(bb)
}

private fun interlogixDecode(bb: BitBuffer): List<Reading> {
    val preamble = intArrayOf(0x01)
    val row = 0
    if (bb.numRows != 1) return emptyList()
    if (bb.bitsPerRow[row] < 57 || bb.bitsPerRow[row] > 64) return emptyList()
    var bitOffset = bb.search(row, 0, preamble, 8)
    if (bitOffset == bb.bitsPerRow[row]) return emptyList()
    bitOffset += 8
    val msgBitLen = 46
    val message = IntArray((msgBitLen + 7) / 8)
    bb.extractBytes(row, bitOffset, message, msgBitLen)
    if (message[0] == 0x00 && message[1] == 0x00 && message[2] == 0x00) return emptyList()
    if (message[0] == 0xff && message[1] == 0xff && message[2] == 0xff) return emptyList()
    if (message[3] == 0x00 && message[4] == 0x00 && message[5] == 0x00) return emptyList()
    if (message[3] == 0xff && message[4] == 0xff && message[5] == 0xff) return emptyList()
    var parity = message[0] xor message[1] xor message[2] xor message[3] xor message[4]
    parity = (parity shr 4) xor (parity and 0xF)
    parity = (parity shr 2) xor (parity and 0x3)
    parity = parity xor (message[5] shr 6)
    val parityError = parity xor 0x3
    if (parityError != 0) return emptyList()
    val typeNib = rv8(message[2]) shr 4
    val deviceType = when (typeNib) {
        0xa -> "contact"
        0xf -> "keyfob"
        0x4 -> "motion"
        0x6 -> "heat"
        0x9 -> "glass"
        0xd -> "glass"
        0xe -> "freeze"
        0x2 -> "smoke"
        0x3 -> "panic"
        else -> "unknown"
    }
    if (deviceType == "unknown") return emptyList()
    val deviceSerial = String.format("%02x%02x%02x", rv8(message[2]), rv8(message[1]), rv8(message[0]))
    val rawMessage = String.format("%02x%02x%02x", message[3], message[4], message[5])
    val lowBattery: Int
    val f1: String
    val f2: String
    val f3: String
    val f4: String
    val f5: String
    if (typeNib == 0xf) {
        lowBattery = 0
        f1 = if ((message[3] and 0xe) == 0x4) "CLOSED" else "OPEN"
        f2 = if ((message[3] and 0xe) == 0x8) "CLOSED" else "OPEN"
        f3 = if ((message[3] and 0xe) == 0xc) "CLOSED" else "OPEN"
        f4 = if ((message[3] and 0xe) == 0x2) "CLOSED" else "OPEN"
        f5 = if ((message[3] and 0xe) == 0xa) "CLOSED" else "OPEN"
    } else {
        lowBattery = if ((message[3] and 0x10) != 0) 1 else 0
        f1 = if ((message[3] and 0x04) != 0) "OPEN" else "CLOSED"
        f2 = if ((message[3] and 0x01) != 0) "OPEN" else "CLOSED"
        f3 = if ((message[4] and 0x40) != 0) "OPEN" else "CLOSED"
        f4 = if ((message[4] and 0x10) != 0) "OPEN" else "CLOSED"
        f5 = if ((message[4] and 0x04) != 0) "OPEN" else "CLOSED"
    }
    return listOf(
        Reading(
            "Interlogix-Security",
            deviceSerial,
            linkedMapOf(
                "subtype" to deviceType,
                "battery_ok" to (if (lowBattery == 0) 1 else 0),
                "switch1" to f1,
                "switch2" to f2,
                "switch3" to f3,
                "switch4" to f4,
                "switch5" to f5,
                "raw_message" to rawMessage,
            ),
        ),
    )
}

// unverified: interlogix.c:245-253 (struct), interlogix.c:98-243 (decode), INTERLOGIX_MSG_BIT_LEN interlogix.c:96
internal object Interlogix : Rtl433Decoder() {
    override val name = "Interlogix GE UTC Security Devices"
    override val mod = Mod.OOK_PPM
    override val short = 122
    override val long = 244
    override val reset = 500

    override fun decode(bb: BitBuffer): List<Reading> = interlogixDecode(bb)
}

private fun lacrosseTx141xDecode(bb: BitBuffer): List<Reading> {
    bb.invert()
    var r = bb.findRepeatedRow(if (bb.numRows > 5) 5 else 3, 32)
    if (r < 0) r = bb.findRepeatedRow(2, 64)
    if (r < 0 && bb.numRows <= 4) {
        for (row in 0 until bb.numRows) {
            if ((bb.bitsPerRow[row] == 40 || bb.bitsPerRow[row] == 41) &&
                Rtl433BitUtil.lfsrDigest8Reflect(bb.bb[row], 4, 0x31, 0xf4) == bb.bb[row][4]
            ) {
                r = row
                break
            }
        }
    }
    if (r < 0) return emptyList()
    val rowBits = bb.bitsPerRow[r]
    val device = when {
        rowBits >= 64 -> 65
        rowBits > 41 -> return emptyList()
        rowBits >= 41 -> {
            if (bb.numRows > 12) return emptyList()
            40
        }
        rowBits >= 40 -> 40
        rowBits >= 37 -> 37
        rowBits == 32 -> 32
        else -> 33
    }
    val b = bb.bb[r]
    if (device == 65) {
        val pre = b[0] shr 3
        if (pre != 0x01) return emptyList()
        if (Rtl433BitUtil.crc8(b, 8, 0x31, 0x00) != 0) return emptyList()
        val id = ((b[0] and 0x07) shl 16) or (b[1] shl 8) or b[2]
        val batteryLow = b[3] shr 7
        val test = (b[3] and 0x40) shr 6
        val channel = (b[3] and 0x30) shr 4
        val type = b[3] and 0x0f
        val tempRaw = (b[4] shl 4) or (b[5] shr 4)
        val humidity = ((b[5] and 0x0f) shl 8) or b[6]
        return when (type) {
            1 -> listOf(
                Reading(
                    "LaCrosse-TX141W",
                    String.format("%05x", id),
                    linkedMapOf(
                        "channel" to channel,
                        "battery_ok" to (if (batteryLow == 0) 1 else 0),
                        "temperature_C" to ((tempRaw - 500) * 0.1f).toDouble(),
                        "humidity" to humidity,
                        "test" to test,
                        "mic" to "CRC",
                    ),
                ),
            )
            2 -> listOf(
                Reading(
                    "LaCrosse-TX141W",
                    String.format("%05x", id),
                    linkedMapOf(
                        "channel" to channel,
                        "battery_ok" to (if (batteryLow == 0) 1 else 0),
                        "wind_avg_km_h" to (tempRaw * 0.1f).toDouble(),
                        "wind_dir_deg" to humidity,
                        "test" to test,
                        "mic" to "CRC",
                    ),
                ),
            )
            else -> emptyList()
        }
    }
    val id = b[0]
    val batteryLow = if (device == 40) (b[1] shr 7) else (if ((b[1] shr 7) == 0) 1 else 0)
    val test = (b[1] and 0x40) shr 6
    val channel = (b[1] and 0x30) shr 4
    val tempRaw = ((b[1] and 0x0F) shl 8) or b[2]
    val tempC = (tempRaw - 500) * 0.1f
    var humidity = 0
    if (device == 40) humidity = b[3]
    if (id == 0 || (device == 40 && (humidity == 0 || humidity > 100)) || tempC < -40.0f || tempC > 140.0f) return emptyList()
    val testStr = if (test != 0) "Yes" else "No"
    val batteryOk = if (batteryLow == 0) 1 else 0
    val idStr = String.format("%02x", id)
    return when (device) {
        32 -> listOf(
            Reading(
                "LaCrosse-TX141B",
                idStr,
                linkedMapOf(
                    "temperature_C" to tempC.toDouble(),
                    "battery_ok" to batteryOk,
                    "test" to testStr,
                ),
            ),
        )
        37 -> listOf(
            Reading(
                "LaCrosse-TX141Bv2",
                idStr,
                linkedMapOf(
                    "channel" to channel,
                    "temperature_C" to tempC.toDouble(),
                    "battery_ok" to batteryOk,
                    "test" to testStr,
                ),
            ),
        )
        33 -> listOf(
            Reading(
                "LaCrosse-TX141Bv3",
                idStr,
                linkedMapOf(
                    "channel" to channel,
                    "battery_ok" to batteryOk,
                    "temperature_C" to tempC.toDouble(),
                    "test" to testStr,
                ),
            ),
        )
        else -> {
            if (Rtl433BitUtil.lfsrDigest8Reflect(b, 4, 0x31, 0xf4) != b[4]) return emptyList()
            listOf(
                Reading(
                    "LaCrosse-TX141THBv2",
                    idStr,
                    linkedMapOf(
                        "channel" to channel,
                        "battery_ok" to batteryOk,
                        "temperature_C" to tempC.toDouble(),
                        "humidity" to humidity,
                        "test" to testStr,
                        "mic" to "CRC",
                    ),
                ),
            )
        }
    }
}

// unverified: lacrosse_tx141x.c:317-327 (struct), lacrosse_tx141x.c:102-312 (decode); device codes lacrosse_tx141x.c:96-100
internal object LacrosseTx141x : Rtl433Decoder() {
    override val name = "LaCrosse TX141-Bv2, TX141TH-Bv2, TX141-Bv3, TX141W, TX145wsdth, (TFA, ORIA) sensor"
    override val mod = Mod.OOK_PWM
    override val short = 208
    override val long = 417
    override val sync = 833
    override val gap = 625
    override val reset = 1700

    override fun decode(bb: BitBuffer): List<Reading> = lacrosseTx141xDecode(bb)
}

// unverified: not ported - honeywell_cm921.c:146-467 is a multi-row message reassembler (parse_msg, decode_10to8, device map) with cross-row state; not transcribed this batch
internal object HoneywellCm921 : Rtl433Decoder() {
    override val name = "Honeywell CM921 Wireless Programmable Room Thermostat"
    override val mod = Mod.FSK_PCM
    override val short = 26
    override val long = 26
    override val tolerance = 5
    override val reset = 2000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: not ported - ikea_sparsnas.c:94-137 brute-force encryption keyed by a file-static sensor id (ikea_sparsnas.c:92) and the pulse-level decode at ikea_sparsnas.c:139-284; stateful, not transcribed this batch
internal object IkeaSparsnas : Rtl433Decoder() {
    override val name = "IKEA Sparsnas Energy Meter Monitor"
    override val mod = Mod.FSK_PCM
    override val short = 27
    override val long = 27
    override val gap = 1000
    override val reset = 3000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

// unverified: not ported - insteon.c:114-376 parse_insteon_pkt plus CRC helpers (insteon.c:80-112) and callback (insteon.c:378-481); multi-packet parser, not transcribed this batch
internal object Insteon : Rtl433Decoder() {
    override val name = "Insteon"
    override val mod = Mod.FSK_PCM
    override val short = 110
    override val long = 110
    override val gap = 500
    override val tolerance = 15
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> = emptyList()
}

internal val BATCH_04: List<Rtl433Decoder> = listOf(
    Hcs361Txwak0Bsel1,
    Hcs361Txwak1Bsel0,
    Hcs361Txwak1Bsel1,
    Hcs361Vpwm1Bsel0,
    Hcs361Vpwm1Bsel1,
    Hcs362Mc,
    Hcs362Pwm,
    HidekiTs04,
    HolmanWs5029pcm,
    HolmanWs5029pwm,
    HolmanWs5029pwmOok,
    HomeleadHg9901,
    HondaKeyfob,
    Hondaremote,
    Honeywell,
    HoneywellCm921,
    HoneywellWdb,
    HoneywellWdbFsk,
    Ht680,
    IbisBeacon,
    IkeaSparsnas,
    Infactory,
    InkbirdIth20r,
    Insteon,
    Interlogix,
    Intertechno,
    Jasco,
    Kedsum,
    Kerui,
    KiddeSmoke,
    Klimalogg,
    Kw9015b,
    LacrosseBreezepro,
    LacrosseR1,
    LacrosseTh3,
    LacrosseTx141x,
    LacrosseTx22uit,
    LacrosseTx22uitOok,
    LacrosseTx29,
)

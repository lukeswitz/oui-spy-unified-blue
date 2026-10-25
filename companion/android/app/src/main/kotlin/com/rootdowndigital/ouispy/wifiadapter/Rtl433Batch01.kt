// Kotlin transcription of rtl_433 device decoders (batch 01). GPL-3 reference; constants, bit offsets and CRC parameters transcribed as facts.
package com.rootdowndigital.ouispy.wifiadapter

private fun s16(x: Int): Int = x.toShort().toInt()

private fun rv8(x: Int): Int {
    var v = x and 0xFF
    v = ((v and 0xF0) shr 4) or ((v and 0x0F) shl 4)
    v = ((v and 0xCC) shr 2) or ((v and 0x33) shl 2)
    v = ((v and 0xAA) shr 1) or ((v and 0x55) shl 1)
    return v and 0xFF
}

private fun reflect4(x: Int): Int {
    var v = ((x and 0xCC) shr 2) or ((x and 0x33) shl 2)
    v = ((v and 0xAA) shr 1) or ((v and 0x55) shl 1)
    return v
}

private fun reflectBytes(b: IntArray, n: Int) {
    for (i in 0 until n) b[i] = rv8(b[i])
}

private fun reflectNibbles(b: IntArray, n: Int) {
    for (i in 0 until n) b[i] = reflect4(b[i])
}

// unverified: bresser_3ch.c:41-98, struct bresser_3ch.c:111
internal object Bresser3ch : Rtl433Decoder() {
    override val name = "Bresser Thermo-/Hygro-Sensor 3CH"
    override val mod = Mod.OOK_PWM
    override val short = 250
    override val long = 500
    override val sync = 750
    override val gap = 625
    override val reset = 1250

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(3, 40)
        if (r < 0 || bb.bitsPerRow[r] > 42) return emptyList()
        val b = bb.bb[r]
        b[0] = b[0].inv() and 0xFF
        b[1] = b[1].inv() and 0xFF
        b[2] = b[2].inv() and 0xFF
        b[3] = b[3].inv() and 0xFF
        b[4] = b[4].inv() and 0xFF
        if (((b[0] + b[1] + b[2] + b[3] - b[4]) and 0xFF) != 0) return emptyList()
        val id = b[0]
        val batteryLow = (b[1] and 0x80) shr 7
        val channel = (b[1] and 0x30) shr 4
        val tempRaw = ((b[1] and 0x0F) shl 8) + b[2]
        val tempF = (tempRaw - 900) * 0.1f
        val humidity = b[3]
        if (channel == 0 || humidity > 100 || tempF < -20.0f || tempF > 160.0f) return emptyList()
        return listOf(
            Reading(
                "Bresser-3CH",
                id.toString(),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "temperature_F" to tempF.toDouble(),
                    "humidity" to humidity,
                ),
            ),
        )
    }
}

// unverified: bt_rain.c:33-85, struct bt_rain.c:99
internal object BtRain : Rtl433Decoder() {
    override val name = "Biltema rain gauge"
    override val mod = Mod.OOK_PPM
    override val short = 1940
    override val long = 3900
    override val gap = 4100
    override val reset = 8800

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(4, 36)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] != 36 && bb.bitsPerRow[row] != 37) return emptyList()
        val b = bb.bb[row]
        if (b[0] == 0xff && b[1] == 0xff && b[2] == 0xff && b[3] == 0xff) return emptyList()
        val id = b[0]
        val battery = b[1] shr 7
        val channel = ((b[1] and 0x30) shr 4) + 1
        val button = (b[1] and 0x08) shr 3
        val tempRaw = s16(((b[1] and 0x07) shl 13) or (b[2] shl 5))
        val tempC = (tempRaw shr 5) * 0.1f
        var rain = ((b[1] and 0x07) shl 4) or b[3]
        val rest = rain % 25
        if (rest % 2 != 0) {
            rain += (rest / 2) * 2048
        } else {
            rain += ((rest + 1) / 2) * 2048 + 12 * 2048
        }
        val rainrate = rain * 0.052f
        return listOf(
            Reading(
                "Biltema-Rain",
                id.toString(),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to (if (battery != 0) 0 else 1),
                    "transmit" to (if (button != 0) "MANUAL" else "AUTO"),
                    "temperature_C" to tempC.toDouble(),
                    "rain_rate_mm_h" to rainrate.toDouble(),
                    "button" to button,
                ),
            ),
        )
    }
}

// unverified: burnhardbbq.c:34-120, struct burnhardbbq.c:137
internal object BurnhardBbq : Rtl433Decoder() {
    override val name = "Burnhard BBQ thermometer"
    override val mod = Mod.OOK_PWM
    override val short = 240
    override val long = 484
    override val sync = 840
    override val reset = 848

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        for (i in 0 until bb.numRows) {
            if (bb.bitsPerRow[i] < 80 || bb.bitsPerRow[i] > 81) continue
            val b = bb.bb[i]
            if (b[0] == 0 && b[9] == 0) continue
            if (Rtl433BitUtil.lfsrDigest8Reflect(b, 9, 0x31, 0xf4) != b[9]) continue
            val id = b[0]
            val channel = b[1] and 0x07
            val tempAlarm = if ((b[1] and 0x80) > 7) 1 else 0
            val timerAlarm = if ((b[1] and 0x40) > 6) 1 else 0
            val timerActive = if ((b[1] and 0x10) > 4) 1 else 0
            val setpointRaw = ((b[7] and 0x0f) shl 8) or b[6]
            val tempRaw = ((b[7] and 0xf0) shl 4) or b[8]
            val setpointC = (setpointRaw - 500) * 0.1f
            val tempC = (tempRaw - 500) * 0.1f
            val timerStr = String.format("%02x:%02x", b[3], b[4] and 0x7f)
            val meat = when (b[5] shr 4) {
                0 -> "free"
                1 -> "beef"
                2 -> "veal"
                3 -> "pork"
                4 -> "chicken"
                5 -> "lamb"
                6 -> "fish"
                7 -> "ham"
                else -> ""
            }
            val taste = when (b[5] and 0x0f) {
                0 -> "rare"
                1 -> "medium rare"
                2 -> "medium"
                3 -> "medium well"
                4 -> "well done"
                else -> ""
            }
            val fields = linkedMapOf<String, Any?>(
                "channel" to channel,
                "setpoint_C" to setpointC.toDouble(),
                "temperature_alarm" to tempAlarm,
                "timer" to timerStr,
                "timer_active" to timerActive,
                "timer_alarm" to timerAlarm,
            )
            if (tempRaw != 0) fields["temperature_C"] = tempC.toDouble()
            if (meat.isNotEmpty()) fields["meat"] = meat
            if (taste.isNotEmpty()) fields["taste"] = taste
            return listOf(Reading("BurnhardBBQ", id.toString(), fields))
        }
        return emptyList()
    }
}

// unverified: calibeur.c:51-117, struct calibeur.c:128
internal object CalibeurRf104 : Rtl433Decoder() {
    override val name = "Calibeur RF-104 Sensor"
    override val mod = Mod.OOK_PWM
    override val short = 760
    override val long = 2240
    override val reset = 3200
    override val sync = 1560

    override fun decode(bb: BitBuffer): List<Reading> {
        val b = bb.bb[1]
        val b2 = bb.bb[2]
        if ((b[0] == 0 && b[1] == 0 && b[2] == 0) || (b[0] == 0xff && b[1] == 0xff && b[2] == 0xff)) return emptyList()
        bb.invert()
        if (bb.bitsPerRow[1] != 21) return emptyList()
        if (Rtl433BitUtil.crc8(b, 3, 0x80, 0) == 0) return emptyList()
        if (b[0] != b2[0] || b[1] != b2[1] || b[2] != b2[2]) return emptyList()

        var bits = ((b[0] and 0x80) shr 7)
        bits = bits or ((b[0] and 0x40) shr 5)
        bits = bits or ((b[0] and 0x20) shr 3)
        bits = bits or ((b[0] and 0x10) shr 1)
        bits = bits or ((b[0] and 0x08) shl 1)
        bits = bits or ((b[0] and 0x04) shl 3)
        val id = bits / 10
        var temperature = (bits % 10).toFloat() * 0.1f

        bits = ((b[0] and 0x02) shl 3)
        bits = bits or ((b[0] and 0x01) shl 5)
        bits = bits or ((b[1] and 0x80) shr 7)
        bits = bits or ((b[1] and 0x40) shr 5)
        bits = bits or ((b[1] and 0x20) shr 3)
        bits = bits or ((b[1] and 0x10) shr 1)
        bits = bits or ((b[1] and 0x08) shl 3)
        temperature += bits.toFloat() - 41.0f

        bits = ((b[1] and 0x02) shl 4)
        bits = bits or ((b[1] and 0x01) shl 6)
        bits = bits or ((b[2] and 0x80) shr 7)
        bits = bits or ((b[2] and 0x40) shr 5)
        bits = bits or ((b[2] and 0x20) shr 3)
        bits = bits or ((b[2] and 0x10) shr 1)
        bits = bits or ((b[2] and 0x08) shl 1)
        val humidity = bits

        return listOf(
            Reading(
                "Calibeur-RF104",
                id.toString(),
                mapOf(
                    "temperature_C" to temperature.toDouble(),
                    "humidity" to humidity.toDouble(),
                ),
            ),
        )
    }
}

// unverified: cardin.c:29-130, struct cardin.c:139
internal object Cardin : Rtl433Decoder() {
    override val name = "Cardin S466-TX2"
    override val mod = Mod.OOK_PWM
    override val short = 730
    override val long = 1400
    override val gap = 1600
    override val reset = 32000
    override val sync = 6150

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 24) return emptyList()
        val b = bb.bb[0]
        if ((b[2] and 0x3f) != 0x03 && (b[2] and 0x3f) != 0x09 && (b[2] and 0x3f) != 0x0c && (b[2] and 0x3f) != 0x06) return emptyList()
        if (((b[0] and 8) == 0 && (b[1] and 8) != 0) ||
            ((b[0] and 16) == 0 && (b[1] and 16) != 0) ||
            ((b[0] and 32) == 0 && (b[1] and 32) != 0) ||
            ((b[0] and 64) == 0 && (b[1] and 64) != 0) ||
            ((b[0] and 128) == 0 && (b[1] and 128) != 0) ||
            ((b[2] and 128) == 0 && (b[2] and 64) != 0) ||
            ((b[0] and 1) == 0 && (b[1] and 1) != 0) ||
            ((b[0] and 2) == 0 && (b[1] and 2) != 0) ||
            ((b[0] and 4) == 0 && (b[1] and 4) != 0)
        ) return emptyList()
        val rbutton = arrayOf("11R", "10R", "01R", "00L?")
        val button = rbutton[((b[2] and 0x0f) / 3) - 1]
        val dip = CharArray(9) { '-' }
        if ((b[0] and 8) != 0) {
            dip[0] = 'o'
            if ((b[1] and 8) != 0) dip[0] = '+'
        }
        if ((b[0] and 16) != 0) {
            dip[1] = 'o'
            if ((b[1] and 16) != 0) dip[1] = '+'
        }
        if ((b[0] and 32) != 0) {
            dip[2] = 'o'
            if ((b[1] and 32) != 0) dip[2] = '+'
        }
        if ((b[0] and 64) != 0) {
            dip[3] = 'o'
            if ((b[1] and 64) != 0) dip[3] = '+'
        }
        if ((b[0] and 128) != 0) {
            dip[4] = 'o'
            if ((b[1] and 128) != 0) dip[4] = '+'
        }
        if ((b[2] and 128) != 0) {
            dip[5] = 'o'
            if ((b[2] and 64) != 0) dip[5] = '+'
        }
        if ((b[0] and 1) != 0) {
            dip[6] = 'o'
            if ((b[1] and 1) != 0) dip[6] = '+'
        }
        if ((b[0] and 2) != 0) {
            dip[7] = 'o'
            if ((b[1] and 2) != 0) dip[7] = '+'
        }
        if ((b[0] and 4) != 0) {
            dip[8] = 'o'
            if ((b[1] and 4) != 0) dip[8] = '+'
        }
        return listOf(
            Reading(
                "Cardin-S466",
                null,
                mapOf("dipswitch" to String(dip), "rbutton" to button),
            ),
        )
    }
}

// unverified: ced7000.c:37-94, struct ced7000.c:105
internal object Ced7000 : Rtl433Decoder() {
    override val name = "CED7000 Shot Timer"
    override val mod = Mod.FSK_PCM
    override val short = 1300
    override val long = 1300
    override val gap = 3500
    override val reset = 9000

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(2, 6 * 16 + 3 * 8)
        if (row < 0) return emptyList()
        val syncPattern = intArrayOf(0xaa, 0x4d, 0x5e)
        val bitpos = bb.search(row, 0, syncPattern, 24) + 24
        if (bitpos >= bb.bitsPerRow[row]) return emptyList()
        bb.invert()
        val decoded = BitBuffer()
        val ret = bb.manchesterDecode(row, bitpos, decoded, 169)
        if (ret != 201 + 1) return emptyList()
        val b = decoded.bb[0]
        reflectNibbles(b, ret / 8)
        val id = (b[1] and 0xF) * 1000 + (b[1] shr 4) * 100 + (b[0] and 0xF) * 10 + (b[0] shr 4)
        val count = (b[2] and 0xF) * 10 + (b[2] shr 4)
        val finalT = (((b[5] shr 4) * 100 + (b[4] and 0xF) * 10 + (b[4] shr 4)).toDouble() + (b[3] and 0xF) * 0.1 + (b[3] shr 4) * 0.01f).toFloat()
        val split = (((b[7] and 0xF) * 100 + (b[7] shr 4) * 10 + (b[6] and 0xF)).toDouble() + (b[6] shr 4) * 0.1 + (b[5] and 0xF) * 0.01f).toFloat()
        return listOf(
            Reading(
                "CED7000",
                String.format("%04d", id),
                mapOf("count" to count, "final" to finalT.toDouble(), "split" to split.toDouble()),
            ),
        )
    }
}

// unverified: chuango.c:36-91, struct chuango.c:101
internal object Chuango : Rtl433Decoder() {
    override val name = "Chuango Security Technology"
    override val mod = Mod.OOK_PWM
    override val short = 568
    override val long = 1704
    override val reset = 1800
    override val sync = 0
    override val tolerance = 160

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 25) return emptyList()
        val b = bb.bb[0]
        b[0] = b[0].inv() and 0xFF
        b[1] = b[1].inv() and 0xFF
        b[2] = b[2].inv() and 0xFF
        if ((b[3] and 0x80) == 0 || (b[0] == 0 && b[1] == 0 && (b[2] and 0xF0) == 0)) return emptyList()
        val id = (b[0] shl 12) or (b[1] shl 4) or (b[2] shr 4)
        val cmd = b[2] and 0x0F
        val cmdStr = when (cmd) {
            0xF -> "?"
            0xE -> "?"
            0xD -> "Low Battery"
            0xC -> "Closing"
            0xB -> "24H Zone"
            0xA -> "Single Delay Zone"
            0x9 -> "?"
            0x8 -> "Arm"
            0x7 -> "Normal Zone"
            0x6 -> "Home Mode Zone"
            0x5 -> "On"
            0x4 -> "Home Mode"
            0x3 -> "Tamper"
            0x2 -> "Alarm"
            0x1 -> "Disarm"
            0x0 -> "Test"
            else -> ""
        }
        return listOf(
            Reading(
                "Chuango-Security",
                id.toString(),
                mapOf("cmd" to cmdStr, "cmd_id" to cmd),
            ),
        )
    }
}

// unverified: cmr113.c:48-110, struct cmr113.c:121
internal object Cmr113 : Rtl433Decoder() {
    override val name = "Clipsal CMR113 Cent-a-meter power meter"
    override val mod = Mod.OOK_PIWM_DC
    override val short = 480
    override val long = 976
    override val reset = 2069
    override val sync = 2028
    override val tolerance = 200

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 350 || bb.bitsPerRow[0] > 450) return emptyList()
        val buf = IntArray(4)
        bb.extractBytes(0, 0, buf, 32)
        if (buf[0] != 0xb0 || buf[1] != 0x00 || buf[2] != 0x00) return emptyList()
        var start = 0
        var bit = 0
        val b = BitBuffer()
        while (start + 3 < bb.bitsPerRow[0]) {
            bb.extractBytes(0, start, buf, 3)
            if ((buf[0] shr 6) == 0x00) {
                start += 2
                b.addBit(bit)
            } else if ((buf[0] shr 5) == 0x03) {
                start += 3
                bit = 1 - bit
                b.addBit(bit)
            } else if (start == 0) {
                start += 1
            } else {
                return emptyList()
            }
        }
        if (b.bitsPerRow[0] < 2 * 83 + 2) return emptyList()
        val b1 = IntArray(11)
        val b2 = IntArray(11)
        b.extractBytes(0, 0, b1, 83)
        b.extractBytes(0, 83 + 2, b2, 83)
        if (!b1.contentEquals(b2)) return emptyList()
        val current = DoubleArray(3)
        for (i in 0 until 3) {
            b.extractBytes(0, 36 + i * 10, buf, 10)
            reflectBytes(buf, 2)
            current[i] = (buf[0].toFloat() + ((buf[1] and 0x3) shl 8)) * 0.1
        }
        return listOf(
            Reading(
                "Clipsal-CMR113",
                null,
                mapOf(
                    "current_1_A" to current[0],
                    "current_2_A" to current[1],
                    "current_3_A" to current[2],
                ),
            ),
        )
    }
}

// unverified: celsia_czc1.c:50-133, struct celsia_czc1.c:145
internal object CelsiaCzc1 : Rtl433Decoder() {
    override val name = "Celsia CZC1 Thermostat"
    override val mod = Mod.OOK_PCM
    override val short = 1220
    override val long = 1220
    override val reset = 4880
    override val tolerance = 20

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0xcc, 0xcc, 0xcc, 0xcc, 0x55, 0x55, 0x55, 0x55)
        if (bb.numRows > 1 || bb.bitsPerRow[0] < 144) return emptyList()
        val preambleEnd = bb.search(0, 0, preamble, 64) + 64
        val firstByte = preambleEnd shr 3
        if (preambleEnd >= bb.bitsPerRow[0]) return emptyList()
        if (preambleEnd + 132 > bb.bitsPerRow[0]) return emptyList()
        val decoded = BitBuffer()
        val bits = bb.bb[0]
        val nBytes = bb.bitsPerRow[0] shr 3
        var ipos = firstByte
        while (ipos < nBytes) {
            if (bits[ipos] == 0xf0) break
            when (bits[ipos]) {
                0x55 -> {
                    decoded.addBit(0)
                    decoded.addBit(0)
                }
                0x5a -> {
                    decoded.addBit(0)
                    decoded.addBit(1)
                }
                0xa5 -> {
                    decoded.addBit(1)
                    decoded.addBit(0)
                }
                0xaa -> {
                    decoded.addBit(1)
                    decoded.addBit(1)
                }
            }
            ipos++
        }
        val b = decoded.bb[0]
        if (Rtl433BitUtil.crc8(b, 8, 0x31, 0xd7) != 0) return emptyList()
        if (b[2] != 0x00 && b[2] != 0xf0) return emptyList()
        val id = (b[0] shl 8) or b[1]
        val heatOk = b[2] == 0xf0
        val heat = rv8(b[3])
        val fields = linkedMapOf<String, Any?>()
        if (heatOk) fields["heat"] = heat
        return listOf(Reading("Celsia-CZC1", String.format("%x", id), fields))
    }
}

// unverified: chrysler_car_remote.c:58-140, struct chrysler_car_remote.c:151
internal object ChryslerCarRemote : Rtl433Decoder() {
    override val name = "Chrysler Car Remote (-f 315.1M -s 920k)"
    override val mod = Mod.OOK_PWM
    override val short = 350
    override val long = 700
    override val gap = 4200
    override val reset = 17500
    override val sync = 7350
    override val tolerance = 100

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        bb.invert()
        for (row in 0 until bb.numRows) {
            val offset = when {
                bb.bitsPerRow[row] >= 49 -> 49
                bb.bitsPerRow[row] == 48 -> 48
                else -> continue
            }
            val bytes = IntArray(6)
            bb.extractBytes(row, bb.bitsPerRow[row] - offset, bytes, 48)
            reflectBytes(bytes, 6)
            val sum = Rtl433BitUtil.addBytes(bytes, 5)
            if ((sum and 0xff) != bytes[5]) continue
            if (sum == 0 || sum == 0xff * 5) continue
            val id = (bytes[0] shl 24) or (bytes[1] shl 16) or (bytes[2] shl 8) or bytes[3]
            val idStr = String.format("%08X", id)
            val button = bytes[4] shr 4
            val multiPress = (bytes[4] and 0x4) != 0
            val buttonStrings = arrayOf("Unlock", "Lock", "Panic")
            val matched = ArrayList<String>()
            var mask = 0x01
            for (i in 0 until 3) {
                if ((button and mask) != 0) matched.add(buttonStrings[i])
                mask = mask shl 1
            }
            val matches = matched.size
            if (matches == 0 || (matches > 1 && !multiPress) || (matches == 1 && multiPress)) continue
            out.add(
                Reading(
                    "Chrysler-CarRemote",
                    idStr,
                    mapOf(
                        "button_code" to button,
                        "button_str" to matched.joinToString("; "),
                    ),
                ),
            )
        }
        return out
    }
}

// unverified: code_alarm_car_remote.c:45-126, struct code_alarm_car_remote.c:137
internal object CodeAlarmFrdpc2000CarRemote : Rtl433Decoder() {
    override val name = "Code Alarm FRDPC2002 Car Remote"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 550
    override val long = 1100
    override val reset = 1600
    override val tolerance = 100

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] != 60) return emptyList()
        if (bb.bb[0][0] != 0x00 || bb.bb[0][1] != 0x00) return emptyList()
        val bytes = IntArray(5)
        bb.extractBytes(0, 19, bytes, 40)
        val bytesSum = Rtl433BitUtil.addBytes(bytes, 5)
        if (bytesSum == 0 || bytesSum >= 0xff * 5) return emptyList()
        val code = IntArray(5)
        bb.extractBytes(0, 23, code, 36)
        val dataStr = String.format("%02X%02X%02X%02X%02X", bytes[0], bytes[1], bytes[2], bytes[3], bytes[4])
        val id = ((code[0] xor code[1]) shl 16) or ((code[1] xor code[2]) shl 8) or (code[2] xor code[3])
        val idStr = String.format("%06X", id)
        val button = bytes[0] shr 4
        val buttonMap = listOf(
            "Multiple" to intArrayOf(0x7),
            "Lock" to intArrayOf(0x6, 0x4),
            "Panic" to intArrayOf(0x1, 0x3),
            "Start" to intArrayOf(0x0, 0x3),
            "Unlock" to intArrayOf(0x5, 0x4),
        )
        val matched = ArrayList<String>()
        for ((name, vals) in buttonMap) {
            if (vals.contains(button)) matched.add(name)
        }
        val buttonStr = if (matched.isEmpty()) "?" else matched.joinToString("; ")
        return listOf(
            Reading(
                "CodeAlarm-FRDPC2002",
                idStr,
                mapOf(
                    "button_code" to button,
                    "button_str" to buttonStr,
                    "data" to dataStr,
                ),
            ),
        )
    }
}

// unverified: companion_wtr001.c:49-128, struct companion_wtr001.c:137
internal object CompanionWtr001 : Rtl433Decoder() {
    override val name = "Companion WTR001 Temperature Sensor"
    override val mod = Mod.OOK_PWM
    override val short = 732
    override val long = 2196
    override val gap = 4000
    override val reset = 8000
    override val sync = 1464

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(3, 14)
        if (r < 0 || bb.bitsPerRow[r] != 14) return emptyList()
        val b = IntArray(2)
        bb.extractBytes(r, 0, b, 14)
        b[0] = b[0].inv() and 0xFF
        b[1] = b[1].inv() and 0xfc
        if ((b[0] and 0x04) == 0x04) return emptyList()
        if (Rtl433BitUtil.parityBytes(b, 2) == 0) return emptyList()
        var tempTenthRaw = rv8(b[0] and 0xf8)
        if (tempTenthRaw < 0x0a) return emptyList()
        if (tempTenthRaw > 0x13) return emptyList()
        tempTenthRaw -= 0x0a
        val tempWholeRaw = rv8(b[1] and 0xf0) or (rv8(b[0] and 0x03) shr 2) or ((b[1] and 0x08) shl 3)
        if (tempWholeRaw < 11) return emptyList()
        if (tempWholeRaw > 111) return emptyList()
        val temperature = (tempWholeRaw + tempTenthRaw * 0.1f) - 41.0f
        return listOf(
            Reading(
                "Companion-WTR001",
                null,
                mapOf("temperature_C" to temperature.toDouble()),
            ),
        )
    }
}

// unverified: compustar_1wg3r.c:61-172, struct compustar_1wg3r.c:183
internal object Compustar1wg3r : Rtl433Decoder() {
    override val name = "Compustar 1WG3R Car Remote"
    override val mod = Mod.OOK_PWM
    override val short = 708
    override val long = 1076
    override val reset = 1532
    override val sync = 1448

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        var previousRow = -1
        for (currentRow in 0 until bb.numRows) {
            val b = bb.bb[currentRow]
            if (bb.bitsPerRow[currentRow] == 5 && (b[0] and 0xf8) == 0xf8) {
                previousRow = -1
                continue
            }
            if (bb.bitsPerRow[currentRow] < 35) continue
            if ((b[2] and 0xe0) != 0xe0 || (b[4] and 1) != 0x0) continue
            if ((b[0] == 0xff && b[1] == 0xff) || (b[0] == 0x00 && b[1] == 0x00)) continue
            val id = (b[0] shl 8) or b[1]
            val idStr = String.format("%04X", id)
            val buttonInverse = ((b[2] shl 3) and 0xff) or (b[3] shr 5)
            val button = ((b[3] shl 3) and 0xff) or (b[4] shr 5)
            if (((buttonInverse.inv()) and 0xff) != button) continue
            val buttonMap = listOf(
                "Lock" to intArrayOf(0x03, 0x05, 0x09, 0x0b, 0x0d, 0x0f, 0x1f, 0x17, 0x13, 0x15, 0x19, 0x1b, 0x1d),
                "Panic" to intArrayOf(0x18),
                "Start" to intArrayOf(0x09, 0x0a, 0x0c, 0x0b, 0x0e, 0x0d, 0x04, 0x1f, 0x08, 0x19, 0x1a, 0x1c, 0x1b, 0x1e, 0x1d, 0x12),
                "Trunk" to intArrayOf(0x05, 0x06, 0x0c, 0x0e, 0x0d, 0x1f, 0x17, 0x02, 0x15, 0x16, 0x1c, 0x1e, 0x1d, 0x08, 0x14),
                "Unlock" to intArrayOf(0x03, 0x06, 0x0a, 0x0b, 0x0e, 0x1f, 0x07, 0x17, 0x13, 0x16, 0x1a, 0x1b, 0x1e),
                "Long Press" to intArrayOf(
                    0x23, 0x31, 0x13, 0x16, 0x17, 0x1a, 0x1b, 0x1e, 0x15, 0x16, 0x1c, 0x1e, 0x1d, 0x08, 0x14,
                    0x08, 0x19, 0x1a, 0x1c, 0x1b, 0x1e, 0x1d, 0x12, 0x13, 0x15, 0x19, 0x1b, 0x1d,
                ),
            )
            val sb = StringBuilder()
            var matches = 0
            for ((name, vals) in buttonMap) {
                if (vals.contains(button and 0x7f)) {
                    if (matches > 0) sb.append("; ")
                    sb.append(name)
                    matches++
                }
            }
            if (matches == 0) sb.append("?")
            if ((button and 0x80) != 0) {
                if (matches > 0) sb.append("; ")
                sb.append("Secondary Mode")
            }
            if (previousRow >= 0 && bb.compareRows(previousRow, currentRow, 35)) continue
            previousRow = currentRow
            out.add(
                Reading(
                    "Compustar-1WG3R",
                    idStr,
                    mapOf("button_code" to button, "button_str" to sb.toString()),
                ),
            )
        }
        return out
    }
}

// unverified: continental_car_remote.c:53-119, struct continental_car_remote.c:132
internal object ContinentalCarRemote : Rtl433Decoder() {
    override val name = "Continental KR5V2X Car Remote (-f 313.8M -s 1024k)"
    override val mod = Mod.FSK_MC_ZEROBIT
    override val short = 100
    override val long = 200
    override val reset = 1500

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.bitsPerRow[0] < 132) return emptyList()
        val pattern = intArrayOf(0xf0, 0xf0, 0x60)
        val offset = bb.search(0, 0, pattern, 20) + 20
        if (bb.bitsPerRow[0] - offset < 112) return emptyList()
        val bytes = IntArray(14)
        bb.extractBytes(0, offset, bytes, 112)
        val id = (bytes[0] shl 24) or (bytes[1] shl 16) or (bytes[2] shl 8) or bytes[3]
        val button = bytes[5] shr 4
        val sequence = (bytes[6] shl 16) or (bytes[7] shl 8) or bytes[8]
        val encrypted = (bytes[9] shl 24) or (bytes[10] shl 16) or (bytes[11] shl 8) or bytes[12]
        if (id == 0 || button == 0 || sequence == 0 || id == 0xfffffff || encrypted == 0xfffffff || sequence == 0xffffff) return emptyList()
        if (Rtl433BitUtil.xorBytes(bytes, 14) != 0) return emptyList()
        val idStr = String.format("%08X", id)
        val encryptedStr = String.format("%08X", encrypted)
        val buttonStr = when (button) {
            0x1 -> "Lock"
            0x3 -> "Unlock"
            0x9 -> "Trunk Long Press"
            0xa -> "Trunk/Panic Short Press"
            0xb -> "Panic Long Press"
            else -> "?"
        }
        return listOf(
            Reading(
                "Continental-KR5V2X",
                idStr,
                mapOf(
                    "encrypted" to encryptedStr,
                    "sequence" to sequence,
                    "button_code" to button,
                    "button_str" to buttonStr,
                ),
            ),
        )
    }
}

// unverified: cotech_36_7900.c:45-87, struct cotech_36_7900.c:97
internal object Cotech367900 : Rtl433Decoder() {
    override val name = "Cotech 36-7900 rain gauge"
    override val mod = Mod.OOK_PPM
    override val short = 1000
    override val long = 2000
    override val gap = 3500
    override val reset = 4500

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = bb.findRepeatedRow(8, 60)
        if (row < 0) return emptyList()
        if (bb.bitsPerRow[row] != 60) return emptyList()
        val b = IntArray(8)
        bb.extractBytes(row, 0, b, 60)
        if (b[0] != 0xab || (b[1] shr 4) != 0x8) return emptyList()
        if (b[3] != 0x00 || b[4] != 0x00 || b[5] != 0x00) return emptyList()
        val id = (b[0] shl 8) or b[1]
        var tempRaw = ((b[1] and 0x0f) shl 8) or b[2]
        if ((tempRaw and 0x800) != 0) tempRaw -= 0x1000
        val temperatureC = tempRaw * 0.1f
        val rainRaw = (b[6] shl 4) or (b[7] shr 4)
        return listOf(
            Reading(
                "Cotech-367900",
                String.format("%04x", id),
                mapOf(
                    "temperature_C" to temperatureC.toDouble(),
                    "rain_raw" to rainRaw,
                ),
            ),
        )
    }
}

// unverified: cotech_36_7959.c:57-138, struct cotech_36_7959.c:157
internal object Cotech367959 : Rtl433Decoder() {
    override val name = "Cotech 36-7959, SwitchDocLabs FT020T wireless weather station with USB"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 500
    override val gap = 1200
    override val reset = 1200

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0x01, 0x40)
        var r = -1
        val b = IntArray(14)
        if (bb.numRows > 2) return emptyList()
        if (bb.bitsPerRow[0] < 112 && bb.bitsPerRow[1] < 112) return emptyList()
        for (i in 0 until bb.numRows) {
            val pos = bb.search(i, 0, preamble, 12) + 12
            if (pos + 112 > bb.bitsPerRow[i]) continue
            r = i
            bb.extractBytes(i, pos, b, 112)
            break
        }
        if (r < 0) return emptyList()
        if (Rtl433BitUtil.crc8(b, 14, 0x31, 0xc0) != 0) return emptyList()
        val id = ((b[0] and 0x0f) shl 4) or (b[1] shr 4)
        val battLow = (b[1] and 0x08) shr 3
        val degMsb = (b[1] and 0x04) shr 2
        val gustMsb = (b[1] and 0x02) shr 1
        val windMsb = b[1] and 0x01
        val wind = (windMsb shl 8) or b[2]
        val gust = (gustMsb shl 8) or b[3]
        val windDir = (degMsb shl 8) or b[4]
        val rain = ((b[5] and 0x0f) shl 8) or b[6]
        val tempRaw = ((b[7] and 0x0f) shl 8) or b[8]
        val humidity = b[9]
        val lightLux = (b[10] shl 8) or b[11] or ((b[7] and 0x80) shl 9)
        val uvi = b[12]
        val tempC = (tempRaw - 400) * 0.1f
        val lightIsValid = uvi <= 150
        val fields = linkedMapOf<String, Any?>(
            "battery_ok" to (if (battLow != 0) 0 else 1),
            "temperature_F" to tempC.toDouble(),
            "humidity" to humidity,
            "rain_mm" to (rain * 0.1f).toDouble(),
            "wind_dir_deg" to windDir,
            "wind_avg_m_s" to (wind * 0.1f).toDouble(),
            "wind_max_m_s" to (gust * 0.1f).toDouble(),
        )
        if (lightIsValid) {
            fields["light_lux"] = lightLux
            fields["uvi"] = (uvi * 0.1f).toDouble()
        }
        return listOf(Reading("Cotech-367959", id.toString(), fields))
    }
}

// unverified: cotech_ft0203.c:40-81, struct cotech_ft0203.c:94
internal object CotechFt0203 : Rtl433Decoder() {
    override val name = "Cotech FT0203/18-3676 anemometer"
    override val mod = Mod.OOK_MC_ZEROBIT
    override val short = 500
    override val gap = 1200
    override val reset = 1200

    override fun decode(bb: BitBuffer): List<Reading> {
        for (row in 0 until bb.numRows) {
            val rowBits = bb.bitsPerRow[row]
            val b = IntArray(9)
            var pos = 0
            while (pos + 9 * 8 <= rowBits) {
                bb.extractBytes(row, pos, b, 9 * 8)
                if (b[0] != 0x14 || b[6] != 0xff || b[7] != 0xff) {
                    pos++
                    continue
                }
                if (Rtl433BitUtil.crc8(b, 9, 0x31, 0xc0) != 0) {
                    pos++
                    continue
                }
                val id = (b[1] shl 3) or (b[2] shr 5)
                val batteryOk = (b[2] shr 4) and 0x1
                val dirMsb = (b[2] shr 2) and 0x1
                val gustMsb = (b[2] shr 1) and 0x1
                val avgMsb = b[2] and 0x1
                val avgRaw = (avgMsb shl 8) or b[3]
                val gustRaw = (gustMsb shl 8) or b[4]
                val dirDeg = (dirMsb shl 8) or b[5]
                return listOf(
                    Reading(
                        "Cotech-FT0203",
                        id.toString(),
                        mapOf(
                            "battery_ok" to batteryOk,
                            "wind_dir_deg" to dirDeg,
                            "wind_avg_m_s" to avgRaw * 0.1,
                            "wind_max_m_s" to gustRaw * 0.1,
                        ),
                    ),
                )
            }
        }
        return emptyList()
    }
}

// unverified: ctt_life_power_hybrid.c:42-124, struct ctt_life_power_hybrid.c:134
internal object CttLifePowerHybrid : Rtl433Decoder() {
    override val name = "Cellular Tracking Technologies LifeTag/PowerTag/HybridTag"
    override val mod = Mod.FSK_PCM
    override val short = 40
    override val long = 40
    override val reset = 500

    private val syncWord = intArrayOf(0xD3, 0x91)
    private val motusCode = intArrayOf(
        0x00, 0x07, 0x19, 0x1E, 0x2A, 0x2D, 0x33, 0x34,
        0x4B, 0x4C, 0x52, 0x55, 0x61, 0x66, 0x78, 0x7F,
        0x80, 0x87, 0x99, 0x9E, 0xAA, 0xAD, 0xB3, 0xB4,
        0xCB, 0xCC, 0xD2, 0xD5, 0xE1, 0xE6, 0xF8, 0xFF,
    )

    private fun byteInMotusCode(b: Int): Boolean = motusCode.contains(b)

    override fun decode(bb: BitBuffer): List<Reading> {
        val out = ArrayList<Reading>()
        for (row in 0 until bb.numRows) {
            if (bb.bitsPerRow[row] < 56) continue
            val syncPos = bb.search(row, 0, syncWord, 16)
            if (syncPos >= bb.bitsPerRow[row]) continue
            if (syncPos + 16 + 40 > bb.bitsPerRow[row]) continue
            val payload = IntArray(5)
            bb.extractBytes(row, syncPos + 16, payload, 40)
            val calcCrc = Rtl433BitUtil.crc8(payload, 4, 0x07, 0x00)
            if (calcCrc != payload[4]) continue
            val id = (payload[0] shl 24) or (payload[1] shl 16) or (payload[2] shl 8) or payload[3]
            val motusTag = byteInMotusCode(payload[0]) &&
                byteInMotusCode(payload[1]) &&
                byteInMotusCode(payload[2]) &&
                byteInMotusCode(payload[3])
            out.add(
                Reading(
                    "CTT-Tag",
                    String.format("0x%08X", id),
                    mapOf("valid_motus" to (if (motusTag) 1 else 0)),
                ),
            )
        }
        return out
    }
}

// unverified: current_cost.c:20-117, struct current_cost.c:130
internal object CurrentCost : Rtl433Decoder() {
    override val name = "CurrentCost Current Sensor"
    override val mod = Mod.FSK_PCM
    override val short = 250
    override val long = 250
    override val reset = 8000

    override fun decode(bb: BitBuffer): List<Reading> {
        bb.invert()
        val initPatternClassic = intArrayOf(0xcc, 0xcc, 0xcc, 0xce, 0x91, 0x5d)
        val initPatternEnvir = intArrayOf(0x55, 0x55, 0x55, 0x55, 0xa4, 0x57)
        var startPos = bb.search(0, 0, initPatternEnvir, 48)
        val isEnvir: Boolean
        if (startPos + 47 + 112 <= bb.bitsPerRow[0]) {
            isEnvir = true
            startPos += 47
        } else {
            isEnvir = false
            startPos = bb.search(0, 0, initPatternClassic, 45)
            if (startPos + 45 + 112 > bb.bitsPerRow[0]) return emptyList()
            startPos += 45
        }
        val packet = BitBuffer()
        bb.manchesterDecode(0, startPos, packet, 0)
        if (packet.bitsPerRow[0] < 64) return emptyList()
        val b = packet.bb[0]
        if ((b[0] and 0xf0) == 0) {
            val deviceId = ((b[0] and 0x0f) shl 8) or b[1]
            var watt0 = 0
            var watt1 = 0
            var watt2 = 0
            if ((b[2] and 0x80) == 128) watt0 = ((b[2] and 0x7F) shl 8) or b[3]
            if ((b[4] and 0x80) == 128) watt1 = ((b[4] and 0x7F) shl 8) or b[5]
            if ((b[6] and 0x80) == 128) watt2 = ((b[6] and 0x7F) shl 8) or b[7]
            return listOf(
                Reading(
                    if (isEnvir) "CurrentCost-EnviR" else "CurrentCost-TX",
                    deviceId.toString(),
                    mapOf("power0_W" to watt0, "power1_W" to watt1, "power2_W" to watt2),
                ),
            )
        }
        if ((b[0] and 0xf0) == 64) {
            val deviceId = ((b[0] and 0x0f) shl 8) or b[1]
            val sensorType = b[3]
            val cImpulse = (b[4] shl 24) or (b[5] shl 16) or (b[6] shl 8) or b[7]
            return listOf(
                Reading(
                    if (isEnvir) "CurrentCost-EnviRCounter" else "CurrentCost-Counter",
                    deviceId.toString(),
                    mapOf("subtype" to sensorType, "power0" to cImpulse),
                ),
            )
        }
        return emptyList()
    }
}

// unverified: dickert_mahs.c:41-92, struct dickert_mahs.c:102
internal object DickertPwm : Rtl433Decoder() {
    override val name = "Dickert MAHS433-01 garage door remote control"
    override val mod = Mod.OOK_PWM
    override val short = 362
    override val long = 770
    override val gap = 1064
    override val reset = 12000

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val numBits = 36
        val msgLen = numBits + 1
        if (bb.bitsPerRow[0] != msgLen) return emptyList()
        val b = IntArray(5)
        bb.extractBytes(0, 1, b, numBits)
        val trinary = charArrayOf('-', '0', '?', '+')
        val dip = CharArray(10)
        val fac = CharArray(8)
        for (field in 0 until 18) {
            val byteIdx = field / 4
            val nib = 3 - (field % 4)
            val v = (b[byteIdx] shr (2 * nib)) and 0x3
            val c = trinary[v]
            if (field < 10) dip[field] = c else fac[field - 10] = c
        }
        val id = (b[0] shl 12) or (b[1] shl 4) or (b[2] shr 4)
        return listOf(
            Reading(
                "Dickert-MAHS433",
                id.toString(),
                mapOf("dipswitch" to String(dip), "facswitch" to String(fac)),
            ),
        )
    }
}

// unverified: dish_remote_6_3.c:100-134, table dish_remote_6_3.c:33-98, struct dish_remote_6_3.c:142 (upstream .disabled = 1)
internal object DishRemote63 : Rtl433Decoder() {
    override val name = "Dish remote 6.3"
    override val mod = Mod.OOK_PPM
    override val short = 1692
    override val long = 2812
    override val gap = 4500
    override val reset = 9000

    private val buttonMap = arrayOf(
        "Undefined", "Undefined", "Swap", "Undefined", "Position", "PIP", "DVR", "Undefined",
        "Skip Forward", "Skip Backward", "Undefined", "Dish Button", "Undefined", "Forward", "Backward", "TV Power",
        "Reset", "Undefined", "Undefined", "Undefined", "Undefined", "Undefined", "SAT", "Mute/Volume Up/Volume Down",
        "Undefined", "#/Search", "*/Format", "Undefined", "Undefined", "Undefined", "Stop", "Pause",
        "Record", "Channel Down", "Undefined", "Left", "Recall", "Channel Up", "Undefined", "Right",
        "TV/Video", "View/Live TV", "Undefined", "Guide", "Undefined", "Cancel", "Digit 0", "Select",
        "Page Up", "Digit 9", "Digit 8", "Digit 7", "Menu", "Digit 6", "Digit 5", "Digit 4",
        "Page Down", "Digit 3", "Digit 2", "Digit 1", "Play", "Dish Power", "Undefined", "Info",
    )

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(3, 16)
        if (r < 0 || bb.bitsPerRow[r] > 16) return emptyList()
        val b = bb.bb[r]
        if ((b[0] and 0x03) != 0x02 || (b[1] and 0xe8) != 0xa8) return emptyList()
        val button = b[0] shr 2
        return listOf(Reading("Dish-RC63", null, mapOf("button" to buttonMap[button])))
    }
}

// unverified: digitech_xc0324.c:76-175, struct digitech_xc0324.c:187
internal object DigitechXc0324 : Rtl433Decoder() {
    override val name = "Digitech XC-0324 / AmbientWeather FT005TH temp/hum sensor"
    override val mod = Mod.OOK_PPM
    override val short = 520
    override val long = 1000
    override val reset = 3000

    private fun decodeMessage(bb: BitBuffer, row: Int, bitpos: Int): Reading? {
        val b = IntArray(6)
        bb.extractBytes(row, bitpos, b, 48)
        if (Rtl433BitUtil.xorBytes(b, 6) != 0x00) return null
        val id = String.format("%02X", b[1])
        val temp = ((rv8(b[3]) and 0x0f) shl 8) or rv8(b[2])
        val temperature = (temp - 400) * 0.1f
        val humidity = rv8(b[4])
        return Reading(
            "Digitech-XC0324",
            id,
            mapOf("temperature_C" to temperature.toDouble(), "humidity" to humidity),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0x5F)
        var events = 0
        var first: Reading? = null
        for (r in 0 until bb.numRows) {
            if (bb.bitsPerRow[r] < 48) continue
            var bitpos = 0
            while (true) {
                bitpos = bb.search(r, bitpos, preamble, 8)
                if (bitpos + 48 > bb.bitsPerRow[r]) break
                val msg = decodeMessage(bb, r, bitpos)
                if (msg != null) {
                    events++
                    if (first == null) first = msg
                }
                bitpos += 48
            }
        }
        val m = first ?: return emptyList()
        return listOf(Reading(m.model, m.id, m.fields + ("message_num" to events)))
    }
}

// unverified: eberle_instat868r1.c:84-185, struct eberle_instat868r1.c:197
internal object EberleInstat868r1 : Rtl433Decoder() {
    override val name = "Eberle Instat 868r1 floor heating thermostat remote"
    override val mod = Mod.FSK_PCM
    override val short = 400
    override val long = 400
    override val reset = 8000

    private val preamblePattern = intArrayOf(0x00, 0x0f, 0xe0, 0x30)

    private fun nibbleLsbFirst(bitrow: IntArray, bitOffset: Int): Int {
        var v = 0
        for (i in 0 until 4) {
            if (bitrowGetBit(bitrow, bitOffset + i) != 0) v = v or (1 shl i)
        }
        return v
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val row = 0
        if (bb.numRows != 1 || bb.bitsPerRow[row] < 30 + 50) return emptyList()
        val rowLen = bb.bitsPerRow[row]
        var searchStart = 0
        val decoded = BitBuffer()
        var micOk = false
        while (searchStart + 30 + 50 <= rowLen) {
            val pos = bb.search(row, searchStart, preamblePattern, 30)
            if (pos + 30 + 50 > rowLen) break
            bb.differentialManchesterDecode(row, pos + 30, decoded, 25)
            if (decoded.bitsPerRow[0] < 25) {
                searchStart = pos + 30 + 1
                continue
            }
            val bd = decoded.bb[0]
            var checksum = 0
            for (n in 0 until 6) checksum += nibbleLsbFirst(bd, 1 + n * 4)
            if ((checksum and 0xf) != 0xb) {
                searchStart = pos + 30 + 1
                continue
            }
            micOk = true
            break
        }
        if (!micOk) return emptyList()
        val b = decoded.bb[0]
        val grayBits = IntArray(24)
        var prev = bitrowGetBit(b, 1)
        grayBits[0] = if (prev == 0) 1 else 0
        for (i in 1 until 24) {
            prev = prev xor bitrowGetBit(b, 1 + i)
            grayBits[i] = if (prev == 0) 1 else 0
        }
        val nibble = IntArray(6)
        for (n in 0 until 6) {
            var v = 0
            for (i in 0 until 4) v = (v shl 1) or grayBits[n * 4 + i]
            nibble[n] = v
        }
        val id = (nibble[0] shl 8) or (nibble[1] shl 4) or nibble[2]
        val action = nibble[3]
        val data = nibble[4]
        val idOdd = id and 1
        val command = when {
            action == (if (idOdd != 0) 0x3 else 0xc) -> "Learn"
            action == (if (idOdd != 0) 0xb else 0x4) -> "Reset"
            action == (if (idOdd != 0) 0xe else 0x1) -> "On"
            action == (if (idOdd != 0) 0x5 else 0xa) -> "Off"
            else -> "Unknown"
        }
        return listOf(
            Reading(
                "Eberle-Instat868r1",
                String.format("%03x", id),
                mapOf(
                    "command" to command,
                    "action_code" to action,
                    "data" to data,
                ),
            ),
        )
    }
}

// unverified: ec3k.c:141-262 (decode, extract_fields), struct ec3k.c:303
internal object Ec3k : Rtl433Decoder() {
    override val name = "Voltcraft EnergyCount 3000 (ec3k)"
    override val mod = Mod.FSK_PCM
    override val short = 50
    override val long = 50
    override val gap = 3000
    override val reset = 5000
    override val tolerance = 5

    private fun bitAt(bytes: IntArray, bit: Int): Int = (bytes[bit shr 3] shr (7 - (bit and 7))) and 1

    private fun symbolAt(bytes: IntArray, bit: Int): Int {
        val bit0 = if (bit > 0) bitAt(bytes, bit - 1) else 0
        val bit1 = bitAt(bytes, bit)
        return if (bit0 == bit1) 1 else 0
    }

    private fun descrambledSymbolAt(bytes: IntArray, bit: Int): Int {
        var out = symbolAt(bytes, bit)
        if (bit > 17) out = out xor symbolAt(bytes, bit - 17)
        if (bit > 12) out = out xor symbolAt(bytes, bit - 12)
        return out
    }

    private fun unpackNibbles(buf: IntArray, startNibble: Int, numNibbles: Int): Int {
        var v = 0
        for (i in 0 until numNibbles) {
            v = (v shl 4) or ((buf[(startNibble + i) / 2] shr ((1 - ((startNibble + i) and 1)) * 4)) and 0x0F)
        }
        return v
    }

    private fun extractFields(p: IntArray): Reading? {
        val id = unpackNibbles(p, 1, 4)
        val timeTotalLow = unpackNibbles(p, 5, 4)
        val pad1 = unpackNibbles(p, 9, 4)
        val timeOnLow = unpackNibbles(p, 13, 4)
        val pad2 = unpackNibbles(p, 17, 7)
        val energyLow = unpackNibbles(p, 24, 7)
        val powerCurrent = unpackNibbles(p, 31, 4) / 10.0
        val powerMax = unpackNibbles(p, 35, 4) / 10.0
        val energy2 = unpackNibbles(p, 39, 6)
        val timeTotalHigh = unpackNibbles(p, 59, 3)
        val pad3 = unpackNibbles(p, 62, 5)
        val energyHigh = unpackNibbles(p, 67, 4).toLong() shl 28
        val timeOnHigh = unpackNibbles(p, 71, 3)
        val resetCounter = unpackNibbles(p, 74, 2)
        val flags = unpackNibbles(p, 76, 1)
        val pad4 = unpackNibbles(p, 77, 1)
        val receivedCrc = 0xffff xor (unpackNibbles(p, 78, 2) or (unpackNibbles(p, 80, 2) shl 8))
        val calculatedCrc = Rtl433BitUtil.crc16lsb(p, 41 - 2, 0x8408, 0xffff)
        val energyWs = energyHigh or energyLow.toLong()
        val energyKwh = energyWs.toDouble() / (1000.0 * 3600.0)
        val energy2Kwh = energy2.toDouble() / (1000.0 * 3600.0)
        val timeTotal = timeTotalLow or (timeTotalHigh shl 16)
        val timeOn = timeOnLow or (timeOnHigh shl 16)
        if (pad1 != 0 || pad2 != 0 || pad3 != 0 || pad4 != 0) return null
        if (calculatedCrc != receivedCrc) return null
        return Reading(
            "Voltcraft-EC3k",
            String.format("%04x", id),
            mapOf(
                "power" to powerCurrent,
                "energy" to energyKwh,
                "energy2" to energy2Kwh,
                "time_total" to timeTotal,
                "time_on" to timeOn,
                "power_max" to powerMax,
                "reset_counter" to resetCounter,
                "flags" to flags,
            ),
        )
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1 || bb.bitsPerRow[0] < 90) return emptyList()
        val bytes = bb.bb[0]
        val packetbuffer = IntArray(41)
        var packetpos = 0
        var packet = 0
        var onecount = 0
        var recbyte = 0
        var recpos = 0
        fun resync() {
            packetpos = 0
            packet = 0
            onecount = 0
            recbyte = 0
            recpos = 0
        }
        for (bufferpos in 17 until bb.bitsPerRow[0]) {
            val out = descrambledSymbolAt(bytes, bufferpos)
            if (out != 0) {
                if (onecount < 6 && packetpos < 41) {
                    onecount++
                    recbyte = (recbyte shr 1) or 0x80
                    recpos++
                    if (recpos == 8 && packet != 0) {
                        recpos = 0
                        packetbuffer[packetpos++] = recbyte
                    }
                } else {
                    resync()
                }
            } else {
                if (onecount < 5 && packetpos < 41) {
                    recbyte = recbyte shr 1
                    recpos++
                    if (recpos == 8 && packet != 0) {
                        recpos = 0
                        packetbuffer[packetpos++] = recbyte
                    }
                } else if (onecount == 5) {
                } else if (onecount == 6) {
                    packet = if (packet != 0) 0 else 1
                    packetpos = 0
                    recpos = 0
                } else {
                    resync()
                }
                onecount = 0
            }
            if (packetpos >= 41) {
                val reading = extractFields(packetbuffer)
                resync()
                if (reading != null) return listOf(reading)
            }
        }
        return emptyList()
    }
}

// unverified: bresser_5in1.c:67-170, struct bresser_5in1.c:186
internal object Bresser5in1 : Rtl433Decoder() {
    override val name = "Bresser Weather Center 5-in-1"
    override val mod = Mod.FSK_PCM
    override val short = 124
    override val long = 124
    override val reset = 25000

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0xaa, 0xaa, 0xaa, 0x2d, 0xd4)
        if (bb.numRows != 1 || bb.bitsPerRow[0] < 248 || bb.bitsPerRow[0] > 440) return emptyList()
        var startPos = bb.search(0, 0, preamble, preamble.size * 8)
        if (startPos == bb.bitsPerRow[0]) return emptyList()
        startPos += preamble.size * 8
        var len = bb.bitsPerRow[0] - startPos
        if ((len + 7) / 8 < 26) return emptyList()
        len = minOf(len, 26 * 8)
        val msg = IntArray(26)
        bb.extractBytes(0, startPos, msg, len)
        for (col in 0 until 13) {
            if ((msg[col] xor msg[col + 13]) != 0xff) return emptyList()
        }
        val sensorId = msg[14]
        val tempOk = (msg[20] and 0x0f) <= 9
        var tempRaw = (msg[20] and 0x0f) + ((msg[20] and 0xf0) shr 4) * 10 + (msg[21] and 0x0f) * 100
        if ((msg[25] and 0x0f) != 0) tempRaw = -tempRaw
        val temperature = tempRaw * 0.1f
        val humidityOk = (msg[22] and 0x0f) <= 9
        val humidity = (msg[22] and 0x0f) + ((msg[22] and 0xf0) shr 4) * 10
        val windDirectionDeg = ((msg[17] and 0xf0) shr 4) * 22.5f
        val gustRaw = ((msg[17] and 0x0f) shl 8) + msg[16]
        val windGust = gustRaw * 0.1f
        val windRaw = (msg[18] and 0x0f) + ((msg[18] and 0xf0) shr 4) * 10 + (msg[19] and 0x0f) * 100
        val windAvg = windRaw * 0.1f
        val rainRaw = (msg[23] and 0x0f) + ((msg[23] and 0xf0) shr 4) * 10 + (msg[24] and 0x0f) * 100 + ((msg[24] and 0xf0) shr 4) * 1000
        var rain = rainRaw * 0.1f
        val batteryLow = msg[25] and 0x80
        val sensorType = msg[15] and 0x7f
        if (sensorType in 0x39..0x3b) {
            rain = rain * 2.5f
            return listOf(
                Reading(
                    "Bresser-ProRainGauge",
                    sensorId.toString(),
                    buildMap {
                        put("battery_ok", if (batteryLow != 0) 0 else 1)
                        if (tempOk) put("temperature_C", temperature.toDouble())
                        put("rain_mm", rain.toDouble())
                    },
                ),
            )
        }
        return listOf(
            Reading(
                "Bresser-5in1",
                sensorId.toString(),
                buildMap {
                    put("battery_ok", if (batteryLow != 0) 0 else 1)
                    if (tempOk) put("temperature_C", temperature.toDouble())
                    if (humidityOk) put("humidity", humidity)
                    put("wind_max_m_s", windGust.toDouble())
                    put("wind_avg_m_s", windAvg.toDouble())
                    put("wind_dir_deg", windDirectionDeg.toDouble())
                    put("rain_mm", rain.toDouble())
                },
            ),
        )
    }
}

// unverified: bresser_6in1.c:97-233, struct bresser_6in1.c:255
internal object Bresser6in1 : Rtl433Decoder() {
    override val name = "Bresser Weather Center 6-in-1, 7-in-1 indoor, soil, new 5-in-1, 3-in-1 wind gauge, Froggit WH6000, Ventus C8488A"
    override val mod = Mod.FSK_PCM
    override val short = 124
    override val long = 124
    override val reset = 25000

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0xaa, 0xaa, 0x2d, 0xd4)
        val moistureMap = intArrayOf(0, 7, 13, 20, 27, 33, 40, 47, 53, 60, 67, 73, 80, 87, 93, 99)
        if (bb.numRows != 1 || bb.bitsPerRow[0] < 160 || bb.bitsPerRow[0] > 440) return emptyList()
        val startPos = bb.search(0, 0, preamble, preamble.size * 8) + preamble.size * 8
        if (startPos >= bb.bitsPerRow[0]) return emptyList()
        val len = bb.bitsPerRow[0] - startPos
        if (len < 18 * 8) return emptyList()
        val msg = IntArray(18)
        bb.extractBytes(0, startPos, msg, 18 * 8)
        val chkdgst = (msg[0] shl 8) or msg[1]
        val digest = Rtl433BitUtil.lfsrDigest16(msg.copyOfRange(2, 17), 15, 0x8810, 0x5412)
        if (chkdgst != digest) return emptyList()
        val sum = Rtl433BitUtil.addBytes(msg.copyOfRange(2, 18), 16)
        if ((sum and 0xff) != 0xff) return emptyList()

        val id = (msg[2] shl 24) or (msg[3] shl 16) or (msg[4] shl 8) or msg[5]
        val sType = msg[6] shr 4
        val startup = (msg[6] shr 3) and 1
        val chan = msg[6] and 0x7
        val battery = (msg[13] shr 1) and 1

        val tempOk = msg[12] <= 0x99 && (msg[13] and 0xf0) <= 0x90
        val tempRaw = (msg[12] shr 4) * 100 + (msg[12] and 0x0f) * 10 + (msg[13] shr 4)
        val tempSign = (msg[13] shr 3) and 1
        var tempC = tempRaw * 0.1f
        if (tempSign != 0) tempC = (tempRaw - 1000) * 0.1f
        if (tempC < -50.0f) tempC = -tempRaw * 0.1f

        val humidity = (msg[14] shr 4) * 10 + (msg[14] and 0x0f)

        var uvOk = (msg[16] and 0x0f) == 0 && (msg[15].inv() and 0xff) <= 0x99 && (msg[16].inv() and 0xf0) <= 0x90
        val uvRaw = (((msg[15].inv() and 0xf0) shr 4) * 100) + ((msg[15].inv() and 0x0f) * 10) + ((msg[16].inv() and 0xf0) shr 4)
        val uvi = uvRaw * 0.1f
        val flags = msg[16] and 0x0f

        msg[7] = msg[7] xor 0xff
        msg[8] = msg[8] xor 0xff
        msg[9] = msg[9] xor 0xff
        var windOk = msg[7] <= 0x99 && msg[8] <= 0x99 && msg[9] <= 0x99
        val gustRaw = (msg[7] shr 4) * 100 + (msg[7] and 0x0f) * 10 + (msg[8] shr 4)
        val windGust = gustRaw * 0.1f
        val wavgRaw = (msg[9] shr 4) * 100 + (msg[9] and 0x0f) * 10 + (msg[8] and 0x0f)
        val windAvg = wavgRaw * 0.1f
        val windDir = ((msg[10] and 0xf0) shr 4) * 100 + (msg[10] and 0x0f) * 10 + ((msg[11] and 0xf0) shr 4)

        msg[12] = msg[12] xor 0xff
        msg[13] = msg[13] xor 0xff
        msg[14] = msg[14] xor 0xff
        val rainOk = msg[16] and 1
        val rainRaw = (msg[12] shr 4) * 100000 + (msg[12] and 0x0f) * 10000 +
            (msg[13] shr 4) * 1000 + (msg[13] and 0x0f) * 100 +
            (msg[14] shr 4) * 10 + (msg[14] and 0x0f)
        val rainMm = rainRaw * 0.1f

        if (sType == 2 || sType == 4) {
            windOk = false
            uvOk = false
        }

        var moisture = -1
        if (sType == 4 && tempOk && humidity in 1..16) moisture = moistureMap[humidity - 1]

        return listOf(
            Reading(
                "Bresser-6in1",
                String.format("%08x", id),
                buildMap {
                    put("channel", chan)
                    if (rainOk == 0) put("battery_ok", battery)
                    if (tempOk) put("temperature_C", tempC.toDouble())
                    if (tempOk && moisture < 0) put("humidity", humidity)
                    put("sensor_type", sType)
                    if (moisture >= 0) put("moisture", moisture)
                    if (windOk) {
                        put("wind_max_m_s", windGust.toDouble())
                        put("wind_avg_m_s", windAvg.toDouble())
                        put("wind_dir_deg", windDir)
                    }
                    if (rainOk != 0) put("rain_mm", rainMm.toDouble())
                    if (uvOk) put("uvi", uvi.toDouble())
                    if (startup != 0) put("startup", startup)
                    put("flags", flags)
                },
            ),
        )
    }
}

// unverified: bresser_leakage.c:71-138, struct bresser_leakage.c:150
internal object BresserLeakage : Rtl433Decoder() {
    override val name = "Bresser water leakage"
    override val mod = Mod.FSK_PCM
    override val short = 124
    override val long = 124
    override val reset = 25000

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0xaa, 0xaa, 0x2d, 0xd4)
        if (bb.numRows != 1 || bb.bitsPerRow[0] < 160 || bb.bitsPerRow[0] > 440) return emptyList()
        var startPos = bb.search(0, 0, preamble, preamble.size * 8)
        if (startPos >= bb.bitsPerRow[0]) return emptyList()
        startPos += preamble.size * 8
        val len = bb.bitsPerRow[0] - startPos
        if (len < 18 * 8) return emptyList()
        val msg = IntArray(18)
        bb.extractBytes(0, startPos, msg, 18 * 8)
        val crcCalculated = Rtl433BitUtil.crc16(msg.copyOfRange(2, 7), 5, 0x1021, 0x0000)
        val crcReceived = (msg[0] shl 8) or msg[1]
        if (crcReceived != crcCalculated) return emptyList()
        val sensorId = (msg[2] shl 24) or (msg[3] shl 16) or (msg[4] shl 8) or msg[5]
        val sType = msg[6] shr 4
        val chan = msg[6] and 0x7
        val batteryOk = if ((msg[7] and 0x30) != 0x00) 1 else 0
        val nstartup = (msg[6] and 0x08) shr 3
        val alarm = (msg[7] and 0x80) shr 7
        val noAlarm = (msg[7] and 0x40) shr 6
        if (sType != 5 || alarm == noAlarm || chan == 0) return emptyList()
        return listOf(
            Reading(
                "Bresser-Leakage",
                String.format("%08x", sensorId),
                buildMap {
                    put("channel", chan)
                    put("battery_ok", batteryOk)
                    put("alarm", alarm)
                    if (nstartup == 0) put("startup", 1)
                },
            ),
        )
    }
}

// unverified: bresser_lightning.c:36-115, struct bresser_lightning.c:129
internal object BresserLightning : Rtl433Decoder() {
    override val name = "Bresser lightning"
    override val mod = Mod.FSK_PCM
    override val short = 124
    override val long = 124
    override val reset = 25000

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0xaa, 0xaa, 0x2d, 0xd4)
        if (bb.numRows != 1 || bb.bitsPerRow[0] < 112 || bb.bitsPerRow[0] > 440) return emptyList()
        var startPos = bb.search(0, 0, preamble, preamble.size * 8)
        if (startPos >= bb.bitsPerRow[0]) return emptyList()
        startPos += preamble.size * 8
        val len = bb.bitsPerRow[0] - startPos
        if (len < 10 * 8) return emptyList()
        val msg = IntArray(10)
        bb.extractBytes(0, startPos, msg, 10 * 8)
        val sType = msg[6] shr 4
        val chan = msg[6] and 0x07
        val batteryLow = (msg[5] and 0x08) shr 3
        val nstartup = (msg[6] and 0x08) shr 3
        for (i in 0 until 10) msg[i] = msg[i] xor 0xaa
        val chk = (msg[0] shl 8) or msg[1]
        val digest = Rtl433BitUtil.lfsrDigest16(msg.copyOfRange(2, 10), 8, 0x8810, 0xabf9)
        if ((chk xor digest) != 0x899e) return emptyList()
        val sensorId = (msg[2] shl 8) or msg[3]
        val distanceKm = msg[7]
        val count = (msg[4] shr 4) * 100 + (msg[4] and 0xf) * 10 + (msg[5] shr 4)
        val unknown1 = ((msg[5] and 0x0f) shl 8) or msg[6]
        val unknown2 = (msg[8] shl 8) or msg[9]
        if (sType != 9 || chan != 0) return emptyList()
        return listOf(
            Reading(
                "Bresser-Lightning",
                String.format("%08x", sensorId),
                buildMap {
                    if (nstartup == 0) put("startup", 1)
                    put("battery_ok", if (batteryLow != 0) 0 else 1)
                    put("storm_dist_km", distanceKm)
                    put("strike_count", count)
                    put("unknown1", unknown1)
                    put("unknown2", unknown2)
                },
            ),
        )
    }
}

// unverified: bresser_st1005h.c:90-147, struct bresser_st1005h.c:161
internal object BresserSt1005h : Rtl433Decoder() {
    override val name = "Bresser Thermo-/Hygro-Sensor Explore Scientific ST1005H"
    override val mod = Mod.OOK_PPM
    override val short = 2500
    override val long = 4500
    override val gap = 4500
    override val reset = 10000

    override fun decode(bb: BitBuffer): List<Reading> {
        val r = bb.findRepeatedRow(3, 38)
        if (r < 0 || bb.bitsPerRow[r] > 38) return emptyList()
        val b = bb.bb[r]
        if (bitrowGetBit(b, 0) != 0) return emptyList()
        val msg = IntArray(4)
        bb.extractBytes(r, 1, msg, 4 * 8)
        msg[3] = msg[3] and 0xfe
        val chk = b[4] shr 2
        val sum = Rtl433BitUtil.addNibbles(msg, 4)
        if (sum == 0) return emptyList()
        if (chk != (sum and 0x3f)) return emptyList()
        val id = msg[0]
        val batteryLow = msg[1] shr 7
        val button = (msg[1] shr 6) and 0x1
        val channel = ((msg[1] shr 4) and 0x3) + 1
        val tempRaw = s16(((msg[1] and 0xf) shl 12) or (msg[2] shl 4))
        val tempC = (tempRaw shr 4) * 0.1
        val humidity = msg[3] shr 1
        if (channel >= 4 || humidity > 110 || tempC < -30.0 || tempC > 160.0) return emptyList()
        return listOf(
            Reading(
                "Bresser-ST1005H",
                id.toString(),
                mapOf(
                    "channel" to channel,
                    "battery_ok" to (if (batteryLow != 0) 0 else 1),
                    "button" to button,
                    "temperature_C" to tempC,
                    "humidity" to humidity,
                ),
            ),
        )
    }
}

// unverified: bresser_7in1.c:141-323, struct bresser_7in1.c:350
internal object Bresser7in1 : Rtl433Decoder() {
    override val name = "Bresser Weather Center 7-in-1, Air Quality PM2.5/PM10 7009970, CO2 7009977, HCHO/VOC 7009978 sensors"
    override val mod = Mod.FSK_PCM
    override val short = 124
    override val long = 124
    override val reset = 25000

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0xaa, 0xaa, 0xaa, 0x2d, 0xd4)
        if (bb.numRows != 1 || bb.bitsPerRow[0] < 240 - 80) return emptyList()
        var startPos = bb.search(0, 0, preamble, preamble.size * 8)
        startPos += preamble.size * 8
        if (startPos >= bb.bitsPerRow[0]) return emptyList()
        if (startPos + 21 * 8 >= bb.bitsPerRow[0]) return emptyList()
        val msg = IntArray(25)
        bb.extractBytes(0, startPos, msg, 25 * 8)
        if (msg[21] == 0x00) return emptyList()
        val sType = msg[6] shr 4
        val nstartup = (msg[6] and 0x08) shr 3
        val chan = msg[6] and 0x07
        for (i in 0 until 25) msg[i] = msg[i] xor 0xaa
        val chk = (msg[0] shl 8) or msg[1]
        val digest = Rtl433BitUtil.lfsrDigest16(msg.copyOfRange(2, 25), 23, 0x8810, 0xba95)
        if ((chk xor digest) != 0x6df1) return emptyList()
        val id = (msg[2] shl 8) or msg[3]
        val flags = msg[15] and 0x0f
        val batteryLow = if ((flags and 0x06) == 0x06) 1 else 0
        val batteryOk = if (batteryLow != 0) 0 else 1

        if (sType == 1 || sType == 12 || sType == 13) {
            val wdir = (msg[4] shr 4) * 100 + (msg[4] and 0x0f) * 10 + (msg[5] shr 4)
            val wgstRaw = (msg[7] shr 4) * 100 + (msg[7] and 0x0f) * 10 + (msg[8] shr 4)
            val wavgRaw = (msg[8] and 0x0f) * 100 + (msg[9] shr 4) * 10 + (msg[9] and 0x0f)
            val rainRaw = (msg[10] shr 4) * 100000 + (msg[10] and 0x0f) * 10000 + (msg[11] shr 4) * 1000 +
                (msg[11] and 0x0f) * 100 + (msg[12] shr 4) * 10 + (msg[12] and 0x0f) * 1
            val rainMm = rainRaw * 0.1f
            val tempRaw = (msg[14] shr 4) * 100 + (msg[14] and 0x0f) * 10 + (msg[15] shr 4)
            var tempC = tempRaw * 0.1f
            if (tempRaw > 600) tempC = (tempRaw - 1000) * 0.1f
            val humidity = (msg[16] shr 4) * 10 + (msg[16] and 0x0f)
            val lghtRaw = (msg[17] shr 4) * 100000 + (msg[17] and 0x0f) * 10000 + (msg[18] shr 4) * 1000 +
                (msg[18] and 0x0f) * 100 + (msg[19] shr 4) * 10 + (msg[19] and 0x0f)
            val uvRaw = (msg[20] shr 4) * 100 + (msg[20] and 0x0f) * 10 + (msg[21] shr 4)
            val lightKlx = lghtRaw * 0.001f
            val lightLux = lghtRaw.toFloat()
            val uvIndex = uvRaw * 0.1f
            val windLightOk = sType != 12
            var tglobeOk = false
            var tglobeC = 0.0f
            if (sType == 13) {
                if ((msg[23] shr 4) < 10) {
                    tglobeOk = true
                    tglobeC = (msg[22] shr 4) * 10 + (msg[22] and 0x0f) + (msg[23] shr 4) * 0.1f
                }
            }
            return listOf(
                Reading(
                    "Bresser-7in1",
                    id.toString(),
                    buildMap {
                        if (nstartup == 0) put("startup", 1)
                        put("temperature_C", tempC.toDouble())
                        put("humidity", humidity)
                        if (windLightOk) {
                            put("wind_max_m_s", (wgstRaw * 0.1f).toDouble())
                            put("wind_avg_m_s", (wavgRaw * 0.1f).toDouble())
                            put("wind_dir_deg", wdir)
                        }
                        put("rain_mm", rainMm.toDouble())
                        if (windLightOk) {
                            put("light_klx", lightKlx.toDouble())
                            put("light_lux", lightLux.toDouble())
                            put("uvi", uvIndex.toDouble())
                        }
                        if (tglobeOk) put("temperature_1_C", tglobeC.toDouble())
                        put("battery_ok", batteryOk)
                    },
                ),
            )
        }
        if (sType == 8) {
            val pm25 = (msg[10] and 0x0f) * 1000 + (msg[11] shr 4) * 100 + (msg[11] and 0x0f) * 10 + (msg[12] shr 4)
            val pm10 = (msg[12] and 0x0f) * 1000 + (msg[13] shr 4) * 100 + (msg[13] and 0x0f) * 10 + (msg[14] shr 4)
            val pm25Init = (msg[10] and 0x0f) == 0x0f
            val pm10Init = (msg[12] and 0x0f) == 0x0f
            return listOf(
                Reading(
                    "Bresser-7in1",
                    id.toString(),
                    buildMap {
                        put("channel", chan)
                        if (nstartup == 0) put("startup", 1)
                        put("battery_ok", batteryOk)
                        if (!pm25Init) put("pm2_5_ug_m3", pm25)
                        if (!pm10Init) put("pm10_0_ug_m3", pm10)
                    },
                ),
            )
        }
        if (sType == 10) {
            val co2 = ((msg[4] and 0xf0) shr 4) * 1000 + (msg[4] and 0x0f) * 100 + ((msg[5] and 0xf0) shr 4) * 10 + (msg[5] and 0x0f)
            val co2Init = (msg[5] and 0x0f) == 0x0f
            return listOf(
                Reading(
                    "Bresser-CO2",
                    id.toString(),
                    buildMap {
                        put("channel", chan)
                        if (nstartup == 0) put("startup", 1)
                        put("battery_ok", batteryOk)
                        if (!co2Init) put("co2_ppm", co2)
                    },
                ),
            )
        }
        if (sType == 11) {
            val hcho = ((msg[4] and 0xf0) shr 4) * 1000 + (msg[4] and 0x0f) * 100 + ((msg[5] and 0xf0) shr 4) * 10 + (msg[5] and 0x0f)
            val voc = msg[22] and 0x0f
            val hchoInit = (msg[5] and 0x0f) == 0x0f
            val vocInit = voc == 0x0f
            return listOf(
                Reading(
                    "Bresser-HCHOVOC",
                    id.toString(),
                    buildMap {
                        put("channel", chan)
                        if (nstartup == 0) put("startup", 1)
                        put("battery_ok", batteryOk)
                        if (!hchoInit) put("hcho_ppb", hcho)
                        if (!vocInit) put("voc_level", voc)
                    },
                ),
            )
        }
        return emptyList()
    }
}

// unverified: cavius.c:40-119, struct cavius.c:132
internal object Cavius : Rtl433Decoder() {
    override val name = "Cavius smoke, heat and water detector"
    override val mod = Mod.FSK_PCM
    override val short = 206
    override val long = 206
    override val sync = 2700
    override val gap = 1000
    override val reset = 1000

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0x43, 0x61, 0x76, 0x69)
        var bitOffset = bb.search(0, 0, preamble, preamble.size * 8)
        if (bitOffset + 22 * 8 >= bb.bitsPerRow[0]) return emptyList()
        bitOffset += preamble.size * 8
        val databits = BitBuffer()
        bb.manchesterDecode(0, bitOffset, databits, 11 * 8)
        databits.invert()
        if (databits.bitsPerRow[0] < 11 * 8) return emptyList()
        val b = databits.bb[0]
        if (Rtl433BitUtil.crc8le(b, 7, 0x31, 0x0) != 0) return emptyList()
        val netId = (b[0] shl 24) or (b[1] shl 16) or (b[2] shl 8) or b[3]
        val senderId = (b[7] shl 24) or (b[8] shl 16) or (b[9] shl 8) or b[10]
        val battLow = (b[4] and 0x08) != 0
        val message = b[4] and 0x08.inv()
        val text = when (message) {
            0x20 -> "Fire alarm"
            0x04 -> "Alarm muted"
            0x80 -> "Pairing"
            0x40 -> "Test alarm"
            0x10 -> "Warning/Water detected"
            else -> if (battLow) "Battery low" else "Unknown"
        }
        return listOf(
            Reading(
                "Cavius-Security",
                senderId.toString(),
                mapOf(
                    "battery_ok" to (if (battLow) 0 else 1),
                    "net_id" to netId,
                    "message" to message,
                    "text" to text,
                ),
            ),
        )
    }
}

// unverified: cavius.c:163-218, struct cavius.c:229
internal object CaviusDoor : Rtl433Decoder() {
    override val name = "Cavius Door/Window sensor (-f 868.7M)"
    override val mod = Mod.FSK_PCM
    override val short = 415
    override val long = 415
    override val reset = 3000

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0xaa, 0xaa, 0xaa, 0xd3, 0x15, 0x27)
        if (bb.numRows != 1) return emptyList()
        val rowLen = bb.bitsPerRow[0]
        var bitOffset = bb.search(0, 0, preamble, preamble.size * 8)
        if (bitOffset >= rowLen) return emptyList()
        bitOffset += preamble.size * 8
        if (bitOffset + 9 * 8 > rowLen) return emptyList()
        val b = IntArray(9)
        bb.extractBytes(0, bitOffset, b, 9 * 8)
        if (Rtl433BitUtil.crc8(b, 8, 0x07, 0x00) != b[8]) return emptyList()
        val state = when (b[7]) {
            0x25 -> "open"
            0x24 -> "closed"
            else -> return emptyList()
        }
        val idStr = String.format("%02x%02x%02x%02x%02x%02x", b[1], b[2], b[3], b[4], b[5], b[6])
        return listOf(
            Reading(
                "Cavius-Door",
                idStr,
                mapOf("state" to state, "counter" to b[0]),
            ),
        )
    }
}

// unverified: danfoss.c:54-148, struct danfoss.c:160
internal object DanfossCfr : Rtl433Decoder() {
    override val name = "Danfoss CFR Thermostat"
    override val mod = Mod.FSK_PCM
    override val short = 100
    override val long = 100
    override val reset = 500

    private val header = intArrayOf(0x36, 0x5c)

    private fun decodeNibble(byte: Int): Int = when (byte) {
        0x0B -> 0xD
        0x0D -> 0xE
        0x0E -> 0x3
        0x13 -> 0x4
        0x15 -> 0xA
        0x16 -> 0xF
        0x19 -> 0x9
        0x1A -> 0x6
        0x25 -> 0x0
        0x26 -> 0x7
        0x29 -> 0x1
        0x2A -> 0x5
        0x2C -> 0xC
        0x31 -> 0xB
        0x32 -> 0x2
        0x34 -> 0x8
        else -> 0xFF
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        val bits = bb.bitsPerRow[0]
        if (bits < 246 || bits > 260) return emptyList()
        var bitOffset = bb.search(0, 112, header, 16)
        if (bits - bitOffset < 126) return emptyList()
        bitOffset += 6
        val bytes = IntArray(10)
        for (n in 0 until 10) {
            val nibbleH = decodeNibble((bitrowGetByte(bb.bb[0], n * 12 + bitOffset) and 0xFF) shr 2)
            val nibbleL = decodeNibble((bitrowGetByte(bb.bb[0], n * 12 + bitOffset + 6) and 0xFF) shr 2)
            if (nibbleH > 0xF || nibbleL > 0xF) return emptyList()
            bytes[n] = (nibbleH shl 4) or nibbleL
        }
        val crcCalc = Rtl433BitUtil.crc16(bytes, 8, 0x1021, 0x0000)
        if (bytes[0] != 0x02 || crcCalc != ((bytes[8] shl 8) or bytes[9])) return emptyList()
        val id = (bytes[1] shl 8) or bytes[2]
        val strSw = when (bytes[3] and 0x0F) {
            2 -> "DAY"
            4 -> "TIMER"
            8 -> "NIGHT"
            else -> "ERROR"
        }
        val tempMeas = bytes[5] + bytes[4] / 256.0f
        val tempSetp = bytes[7] + bytes[6] / 256.0f
        return listOf(
            Reading(
                "Danfoss-CFR",
                id.toString(),
                mapOf(
                    "temperature_C" to tempMeas.toDouble(),
                    "setpoint_C" to tempSetp.toDouble(),
                    "switch" to strSw,
                ),
            ),
        )
    }
}

private class DirectvDpwm(val len: Int, val syncPos: Int, val syncLen: Int)

private fun directvSetBit(bitrow: IntArray, bitIdx: Int, bitVal: Int) {
    if (bitVal == 0) {
        bitrow[bitIdx shr 3] = bitrow[bitIdx shr 3] and (1 shl (7 - (bitIdx and 7))).inv()
    } else {
        bitrow[bitIdx shr 3] = bitrow[bitIdx shr 3] or (1 shl (7 - (bitIdx and 7)))
    }
}

private fun directvDpwmDecode(bitrow: IntArray, bitLen: Int, start: Int, bitrowBuf: IntArray): DirectvDpwm {
    var bitrowBufPos = -1
    var curSymbolLen = -1
    var syncPos = start
    var syncLen = 0
    var syncInProgress = true
    var prevBit = 0xff
    for (bitrowPos in start until bitLen) {
        val thisBit = bitrowGetBit(bitrow, bitrowPos)
        if (thisBit == prevBit) {
            curSymbolLen++
            if (curSymbolLen > 1) syncInProgress = true
        } else {
            if (syncInProgress) {
                syncLen = curSymbolLen + 1
                syncPos = bitrowPos - curSymbolLen - 1
                bitrowBufPos = -1
                syncInProgress = false
            } else {
                if (bitrowBufPos >= 0) directvSetBit(bitrowBuf, bitrowBufPos, curSymbolLen)
                bitrowBufPos++
            }
            curSymbolLen = 0
        }
        prevBit = thisBit
    }
    if (syncInProgress) bitrowBufPos -= 1
    if (bitrowBufPos < 0) bitrowBufPos = 0
    return DirectvDpwm(bitrowBufPos, syncPos, syncLen)
}

// unverified: directv.c:93-361 (label table, bitrow_dpwm_decode, directv_decode), struct directv.c:373
internal object Directv : Rtl433Decoder() {
    override val name = "DirecTV RC66RX Remote Control"
    override val mod = Mod.FSK_PCM
    override val short = 600
    override val long = 600
    override val gap = 30000
    override val reset = 50000

    private val buttonLabels = mapOf(
        0x01 to "1", 0x02 to "2", 0x03 to "3", 0x04 to "4", 0x05 to "5", 0x06 to "6", 0x07 to "7", 0x08 to "8", 0x09 to "9",
        0x0D to "CH UP", 0x0E to "CH DOWN", 0x0F to "CH PREV", 0x10 to "PWR", 0x11 to "0", 0x12 to "DASH",
        0x13 to "ENTER", 0x14 to "DASH REPEAT", 0x15 to "ENTER REPEAT",
        0x20 to "MENU", 0x21 to "UP", 0x22 to "DOWN", 0x23 to "LEFT", 0x24 to "RIGHT", 0x25 to "SELECT", 0x26 to "EXIT",
        0x27 to "BACK", 0x28 to "GUIDE", 0x29 to "ACTIVE", 0x2A to "LIST", 0x2B to "LIST REPEAT", 0x2C to "INFO REPEAT",
        0x2D to "GUIDE REPEAT", 0x2E to "INFO",
        0x30 to "VCR PLAY", 0x31 to "VCR STOP", 0x32 to "VCR PAUSE", 0x33 to "VCR RWD", 0x34 to "VCR FFD", 0x35 to "VCR REC",
        0x36 to "VCR BACK", 0x37 to "VCR SKIP", 0x38 to "VCR SKIP REPEAT", 0x3A to "VCR PLAY REPEAT",
        0x3B to "VCR PAUSE REPEAT", 0x3C to "VCR RWD REPEAT", 0x3D to "VCR FFD REPEAT", 0x3E to "VCR REC REPEAT",
        0x3F to "VCR BACK REPEAT",
        0x41 to "RED", 0x42 to "YELLOW", 0x43 to "GREEN", 0x44 to "BLUE", 0x45 to "MENU REPEAT", 0x46 to "ACTIVE REPEAT",
        0x4A to "RED REPEAT", 0x4B to "YELLOW REPEAT", 0x4C to "GREEN REPEAT", 0x4D to "BLUE REPEAT",
        0x51 to "TV: VCR ALERT", 0x59 to "VOLUME ALERT", 0x5A to "AV1/AV2/TV: IR ALERT 1", 0x5B to "DTV: IR ALERT",
        0x5C to "AV1/AV2/TV: IR ALERT 2", 0x5D to "TV: DTV ALERT", 0x5E to "AV1: DTV ALERT", 0x5F to "AV2: DTV ALERT",
        0x60 to "0 REPEAT", 0x61 to "1 REPEAT", 0x62 to "2 REPEAT", 0x63 to "3 REPEAT", 0x64 to "4 REPEAT",
        0x65 to "5 REPEAT", 0x66 to "6 REPEAT", 0x67 to "7 REPEAT", 0x68 to "8 REPEAT", 0x69 to "9 REPEAT",
        0x73 to "FORMAT", 0x75 to "FORMAT REPEAT",
        0x80 to "DTV: DTV&TV POWER ON", 0x81 to "DTV: DTV&TV POWER OFF",
        0xD6 to "SELECT RELEASE",
    )

    override fun decode(bb: BitBuffer): List<Reading> {
        val bitLen = bb.bitsPerRow[0]
        if (bitLen < 44 || bitLen > 99) return emptyList()
        val bitrow = IntArray(13)
        bb.extractBytes(0, 0, bitrow, bitLen)
        val dtvBuf = IntArray(13)
        val res = directvDpwmDecode(bitrow, bitLen, 0, dtvBuf)
        if (res.len != 40) return emptyList()
        if (dtvBuf[0] != 0x10) return emptyList()
        val checksum1 = ((dtvBuf[0] shr 4) + (dtvBuf[0] and 0x0F) + (dtvBuf[1] shr 4) + (dtvBuf[1] and 0x0F) +
            (dtvBuf[2] shr 4) + (dtvBuf[2] and 0x0F) + (dtvBuf[3] shr 4) + (dtvBuf[3] and 0x0F) +
            (dtvBuf[4] shr 4)) and 0x0F
        val checksum2 = dtvBuf[4] and 0x0F
        if (checksum1 != checksum2) return emptyList()
        val deviceId = (dtvBuf[1] shl 12) or (dtvBuf[2] shl 4) or (dtvBuf[3] shr 4)
        if (deviceId > 999999) return emptyList()
        val buttonId = ((dtvBuf[3] shl 4) or (dtvBuf[4] shr 4)) and 0xFF
        val event = if (res.syncLen > 5) "INITIAL" else "REPEAT"
        return listOf(
            Reading(
                "DirecTV-RC66RX",
                String.format("%06d", deviceId),
                mapOf(
                    "button_id" to buttonId,
                    "button_name" to (buttonLabels[buttonId] ?: "unknown"),
                    "event" to event,
                ),
            ),
        )
    }
}

private fun ccittWhitening(buf: IntArray, size: Int) {
    var keyMsb = 0x01
    var keyLsb = 0xff
    for (pos in 0 until size) {
        var r = ((keyLsb and 0xf0) shr 4) or ((keyLsb and 0x0f) shl 4)
        r = ((r and 0xcc) shr 2) or ((r and 0x33) shl 2)
        r = ((r and 0xaa) shr 1) or ((r and 0x55) shl 1)
        buf[pos] = buf[pos] xor r
        for (c in 0 until 8) {
            val prev = keyMsb
            keyMsb = (keyLsb and 0x01) xor ((keyLsb shr 5) and 0x01)
            keyLsb = ((prev shl 7) and 0x80) or ((keyLsb shr 1) and 0xff)
        }
    }
}

private fun le16(f: IntArray, p: Int): Int = f[p] or (f[p + 1] shl 8)

private class DeltadoreHeader {
    var number = 0
    var type = 0
    var headerFlags = 0
    var deviceId = 0
    var network = 0
    var flags2 = 0
    var flags3 = 0
    var tempType = 0
    var temperature = 0
    var messageId = 0
}

private fun deltadoreParseHeader(f: IntArray, start: Int, out: DeltadoreHeader): Int {
    var p = start
    var bytesRead = 14
    out.number = f[p++]
    out.type = f[p++]
    out.headerFlags = f[p++] and 0xe0
    out.deviceId = f[p] or (f[p + 1] shl 8) or (f[p + 2] shl 16)
    p += 3
    out.network = f[p++]
    p++
    out.flags2 = f[p++]
    out.flags3 = f[p++]
    if (out.flags3 == 0x01) {
        p++
        bytesRead++
    } else if (out.flags3 == 0x08) {
        out.tempType = f[p++]
        out.temperature = s16(le16(f, p))
        p += 2
        bytesRead += 3
    }
    out.messageId = le16(f, p)
    return bytesRead
}

// unverified: deltadore_x3d.c:190-397, struct deltadore_x3d.c:422; ccitt_whitening from bit_util.c:463
internal object DeltadoreX3d : Rtl433Decoder() {
    override val name = "DeltaDore X3D devices"
    override val mod = Mod.FSK_PCM
    override val short = 25
    override val long = 25
    override val reset = 800

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val preamble = intArrayOf(0xaa, 0xaa, 0x81, 0x69, 0x96, 0x7e)
        var startPos = bb.search(0, 0, preamble, preamble.size * 8)
        if (startPos >= bb.bitsPerRow[0]) return emptyList()
        startPos += preamble.size * 8
        if (bb.bitsPerRow[0] < 10 * 8) return emptyList()
        val lenBuf = IntArray(1)
        bb.extractBytes(0, startPos, lenBuf, 8)
        ccittWhitening(lenBuf, 1)
        val len = lenBuf[0]
        if (len < 2 || len > 64) return emptyList()
        val frame = IntArray(65)
        bb.extractBytes(0, startPos, frame, len * 8)
        ccittWhitening(frame, len)
        val crc = Rtl433BitUtil.crc16(frame, len - 2, 0x1021, 0x0000)
        val actualCrc = (frame[len - 2] shl 8) or frame[len - 1]
        if (actualCrc != crc) return emptyList()

        val head = DeltadoreHeader()
        var bytesRead = 2
        bytesRead += deltadoreParseHeader(frame, bytesRead, head)
        if (head.type == 1 && (head.headerFlags and 0x20) == 0 && len < bytesRead + 12 + 2) return emptyList()

        val cls = when (head.type) {
            0 -> "Sensor"
            1 -> "Standard"
            2 -> "Pairing"
            3 -> "Beacon"
            else -> "Unknown"
        }
        val wndStat = when (head.flags2) {
            0x01 -> "Closed"
            0x41 -> "Opened"
            else -> ""
        }
        val tempType = when (head.tempType) {
            0 -> "indoor"
            1 -> "outdoor"
            else -> ""
        }
        val fields = linkedMapOf<String, Any?>(
            "network" to head.network,
            "subtype" to cls,
            "msg_id" to head.messageId,
            "msg_no" to head.number,
        )
        if (head.flags3 == 0x08) {
            fields["temperature_C"] = (head.temperature.toFloat() / 100.0f).toDouble()
            fields["temperature_type"] = tempType
        }
        if ((head.headerFlags and 0x20) != 0) {
            if (wndStat.isNotEmpty()) fields["wnd_stat"] = wndStat
        } else if (head.type == 1) {
            val p = bytesRead
            fields["retry"] = frame[p]
            fields["transfer"] = le16(frame, p + 1)
            fields["transfer_ack"] = le16(frame, p + 3)
            fields["target"] = le16(frame, p + 5)
            fields["action"] = frame[p + 7]
            fields["register_high"] = frame[p + 8]
            fields["register_low"] = frame[p + 9]
            fields["target_ack"] = le16(frame, p + 10)
            bytesRead += 12
            fields["raw_msg"] = (bytesRead until len - 2).joinToString("") { String.format("%02x", frame[it]) }
        }
        return listOf(Reading("DeltaDore-X3D", head.deviceId.toString(), fields))
    }
}

private fun cwpircInvert(v: Int): IntArray? = when (v) {
    0x00 -> intArrayOf(1, 1, 0)
    0x01 -> intArrayOf(0, 1, 0)
    0x02 -> intArrayOf(0, 0, 1)
    0x04 -> intArrayOf(1, 1, 1)
    0x05, 0x0a -> intArrayOf(1, 0, 1)
    0x06 -> intArrayOf(0, 1, 1)
    0x08 -> intArrayOf(1, 0, 0)
    0x09 -> intArrayOf(0, 0, 0)
    else -> null
}

private fun cwpircOrder(v: Int): IntArray? = when (v) {
    0x06, 0x09 -> intArrayOf(2, 1, 0)
    0x08, 0x04 -> intArrayOf(1, 2, 0)
    0x01 -> intArrayOf(2, 0, 1)
    0x00 -> intArrayOf(0, 2, 1)
    0x05 -> intArrayOf(1, 0, 2)
    0x02, 0x0a -> intArrayOf(0, 1, 2)
    else -> null
}

private class CwpircHalf(val roll: IntArray, val fixed20: Int)

private fun cwpircHalfDecode(h: IntArray): CwpircHalf? {
    val h40 = (h[0].toLong() shl 32) or (h[1].toLong() shl 24) or (h[2].toLong() shl 16) or (h[3].toLong() shl 8) or h[4].toLong()
    val orderInvert = ((h40 shr 30) and 0xff).toInt()
    val order = orderInvert shr 4
    val invert = orderInvert and 0x0f
    var x = (h40 and 0x3fffffffL).toInt()
    var p0 = 0
    var p1 = 0
    var p2 = 0
    for (i in 0 until 10) {
        p2 = p2 xor ((x and 1) shl i)
        x = x shr 1
        p1 = p1 xor ((x and 1) shl i)
        x = x shr 1
        p0 = p0 xor ((x and 1) shl i)
        x = x shr 1
    }
    val inv = cwpircInvert(invert) ?: return null
    if (inv[0] != 0) p0 = p0.inv() and 0x3ff
    if (inv[1] != 0) p1 = p1.inv() and 0x3ff
    if (inv[2] != 0) p2 = p2.inv() and 0x3ff
    val vals = intArrayOf(p0, p1, p2)
    val o = cwpircOrder(order) ?: return null
    p0 = vals[o[0]]
    p1 = vals[o[1]]
    p2 = vals[o[2]]
    val roll = IntArray(9)
    for (i in 0 until 4) {
        roll[i] = (orderInvert shr (6 - 2 * i)) and 0x03
        if (roll[i] == 3) return null
    }
    for (i in 0 until 5) {
        roll[4 + i] = (p2 shr (8 - 2 * i)) and 0x03
        if (roll[4 + i] == 3) return null
    }
    return CwpircHalf(roll, (p0 shl 10) or p1)
}

// unverified: chamberlain_cwpirc.c:49-232, struct chamberlain_cwpirc.c:243
internal object ChamberlainCwpirc : Rtl433Decoder() {
    override val name = "Chamberlain CWPIRC PIR Sensor"
    override val mod = Mod.FSK_PCM
    override val short = 25
    override val long = 25
    override val reset = 500

    override fun decode(bb: BitBuffer): List<Reading> {
        val preamble = intArrayOf(0x55, 0x2D, 0xD4)
        if (bb.numRows != 1) return emptyList()
        val bits = bb.bitsPerRow[0]
        if (bits < 136) return emptyList()
        val searchPos = bb.search(0, 0, preamble, preamble.size * 8)
        if (searchPos >= bits) return emptyList()
        val b = IntArray(14)
        var gotFrame = false
        for (shift in 0..4) {
            val pos = searchPos + preamble.size * 8 + shift
            if (pos + 14 * 8 > bits) break
            bb.extractBytes(0, pos, b, 14 * 8)
            if (b[0] != 0 || b[6] != 1) continue
            if (Rtl433BitUtil.crc16(b, 14, 0x1021, 0x0000) != 0) continue
            gotFrame = true
            break
        }
        if (!gotFrame) return emptyList()
        val half0 = cwpircHalfDecode(b.copyOfRange(1, 6)) ?: return emptyList()
        val half1 = cwpircHalfDecode(b.copyOfRange(7, 12)) ?: return emptyList()
        val roll0 = half0.roll
        val roll1 = half1.roll
        val fixed = (half0.fixed20.toLong() shl 20) or half1.fixed20.toLong()
        val batteryLow = (fixed and 0x20L) != 0L
        val canonicalId = fixed and 0x20L.inv()
        val rollingDigits = IntArray(18)
        rollingDigits[0] = roll1[8]
        rollingDigits[1] = roll0[8]
        for (i in 0 until 4) rollingDigits[2 + i] = roll1[4 + i]
        for (i in 0 until 4) rollingDigits[6 + i] = roll0[4 + i]
        for (i in 0 until 4) rollingDigits[10 + i] = roll1[i]
        for (i in 0 until 4) rollingDigits[14 + i] = roll0[i]
        var rollingTemp = 0
        for (i in 0 until 18) rollingTemp = rollingTemp * 3 + rollingDigits[i]
        val rolling = Integer.reverse(rollingTemp) ushr 4
        return listOf(
            Reading(
                "Chamberlain-CWPIRC",
                String.format("%010x", canonicalId),
                mapOf(
                    "battery_ok" to (if (batteryLow) 0 else 1),
                    "rolling" to rolling,
                ),
            ),
        )
    }
}

internal object BresserGarden : Rtl433Decoder() {
    override val name = "Bresser SmartHome Garden soil moisture and water timer valve (Baldr Homgar, RainPoint)"
    override val mod = Mod.FSK_PCM
    override val short = 50
    override val long = 50
    override val reset = 10000

    private fun modelOf(sourceId: Long): String = when ((sourceId shr 24).toInt()) {
        0x47 -> "Bresser-SoilMoisture"
        0x1f -> "Bresser-WaterTimer"
        0x01 -> "Bresser-Gateway"
        else -> "Bresser-Garden"
    }

    private fun le32(b: IntArray, o: Int): Long =
        (b[o + 3].toLong() shl 24) or (b[o + 2].toLong() shl 16) or (b[o + 1].toLong() shl 8) or b[o].toLong()

    private fun payloadHex(b: IntArray, len: Int): String {
        val s = StringBuilder()
        for (i in 0 until minOf(len, 20)) s.append(String.format("%02x", b[11 + i]))
        return s.toString()
    }

    override fun decode(bb: BitBuffer): List<Reading> {
        if (bb.numRows != 1) return emptyList()
        val msgLen = bb.bitsPerRow[0]
        if (msgLen > 2000) return emptyList()
        val pre = intArrayOf(0xaa, 0xf3, 0xe9, 0x10, 0x5e, 0x51)
        var offset = bb.search(0, 0, pre, pre.size * 8)
        if (offset >= msgLen) return emptyList()
        offset += pre.size * 8
        if (msgLen - offset < 33 * 8) return emptyList()
        val b = IntArray(33)
        bb.extractBytes(0, offset, b, 33 * 8)
        if (Rtl433BitUtil.crc16(b, 33, 0x1021, 0xd636) != 0) return emptyList()

        val targetId = le32(b, 0)
        val sourceId = le32(b, 4)
        val counter = b[8]
        val msgType = b[9]
        val msgLength = b[10]
        val ack = msgType shr 7
        if (msgLength > 20) return emptyList()
        val model = modelOf(sourceId)
        val id = sourceId.toString()

        when {
            msgType == 0x01 && (msgLength == 0x07 || msgLength == 0x08) -> return listOf(Reading(model, id, mapOf(
                "msg_name" to "Init Pairing",
                "target_id" to targetId,
                "msg_counter" to counter,
                "device_type" to b[11],
                "firmware" to b[17],
                "msg_type" to msgType,
                "msg_length" to msgLength,
                "msg" to payloadHex(b, msgLength),
            )))
            msgType == 0x03 && msgLength == 0x07 -> return listOf(Reading(model, id, mapOf(
                "msg_name" to "Soil telemetry",
                "device_type" to b[11],
                "station_id" to targetId,
                "msg_counter" to counter,
                "msg_type" to msgType,
                "temperature_F" to (s16((b[17] shl 8) or b[16]) * 0.1f).toDouble(),
                "moisture" to b[14],
                "battery_ok" to (if (((b[12] and 0x10) shr 4) != 0) 0 else 1),
                "battery_level" to (b[12] and 0x0f),
            )))
            (msgType == 0x83 || msgType == 0x84 || msgType == 0x89 || msgType == 0x8a) && msgLength == 0x01 -> return listOf(Reading(model, id, mapOf(
                "msg_name" to "Acknowledgement",
                "target_id" to targetId,
                "msg_counter" to counter,
                "acknowledgement" to ack,
                "msg_type" to msgType,
                "msg_length" to msgLength,
            )))
            msgType == 0x0a && msgLength == 0x09 -> return listOf(Reading(model, id, mapOf(
                "msg_name" to "Relay telemetry",
                "device_type" to b[11],
                "sensor_number" to b[12],
                "station_id" to targetId,
                "msg_counter" to counter,
                "msg_type" to msgType,
                "temperature_F" to (s16((b[19] shl 8) or b[18]) * 0.1f).toDouble(),
                "moisture" to b[16],
                "soil_rssi" to b[13],
                "battery_ok" to (if (((b[14] and 0x10) shr 4) != 0) 0 else 1),
                "battery_level" to (b[14] and 0x0f),
            )))
            msgType == 0x09 && msgLength == 0x09 -> return listOf(Reading(model, id, mapOf(
                "msg_name" to "Soil telemetry",
                "device_type" to b[11],
                "sensor_number" to b[12],
                "station_id" to targetId,
                "msg_counter" to counter,
                "msg_type" to msgType,
                "temperature_F" to (s16((b[19] shl 8) or b[18]) * 0.1f).toDouble(),
                "moisture" to b[16],
                "battery_ok" to (if (((b[14] and 0x10) shr 4) != 0) 0 else 1),
                "battery_level" to (b[14] and 0x0f),
            )))
            msgType == 0x04 && msgLength == 0x0e -> return listOf(Reading(model, id, mapOf(
                "msg_name" to "Watering",
                "sensor_number" to b[11],
                "station_id" to targetId,
                "msg_counter" to counter,
                "msg_type" to msgType,
                "program" to String.format("%04x", (b[14] shl 8) or b[15]),
                "cycle_counter" to (b[16] or (b[17] shl 8)),
                "trigger" to String.format("%02x", b[18]),
                "water_usage_l" to ((b[19] or (b[20] shl 8)) * 0.1f).toDouble(),
                "duration_s" to (b[23] or (b[24] shl 8)),
            )))
            msgType == 0x85 && msgLength == 0x0f -> return listOf(Reading(model, id, mapOf(
                "msg_name" to "Schedule config",
                "target_id" to targetId,
                "sensor_number" to b[18],
                "msg_counter" to counter,
                "msg_type" to msgType,
                "default_duration_s" to (b[12] or (b[13] shl 8)),
                "mist_run_s" to (b[14] or (b[15] shl 8)),
                "mist_interval_s" to (b[16] or (b[17] shl 8)),
                "stop_moisture" to b[19],
                "flow_rate" to b[24].toByte().toInt(),
                "unknown" to String.format("%02x", b[22]),
            )))
            msgType == 0x20 && (msgLength == 0x02 || msgLength == 0x03) -> {
                val f = linkedMapOf<String, Any?>(
                    "msg_name" to "Config change",
                    "target_id" to targetId,
                    "msg_counter" to counter,
                    "msg_type" to msgType,
                    "config_counter" to b[11],
                )
                if (msgLength == 0x03 && b[12] == 0x04) f["rf_channel"] = b[13]
                return listOf(Reading(model, id, f))
            }
        }
        return emptyList()
    }
}

internal val BATCH_01: List<Rtl433Decoder> = listOf(
    Bresser3ch,
    Bresser5in1,
    Bresser6in1,
    Bresser7in1,
    BresserGarden,
    BresserLeakage,
    BresserLightning,
    BresserSt1005h,
    BtRain,
    BurnhardBbq,
    CalibeurRf104,
    Cardin,
    Cavius,
    CaviusDoor,
    Ced7000,
    CelsiaCzc1,
    ChamberlainCwpirc,
    ChryslerCarRemote,
    Chuango,
    Cmr113,
    CodeAlarmFrdpc2000CarRemote,
    CompanionWtr001,
    Compustar1wg3r,
    ContinentalCarRemote,
    Cotech367900,
    Cotech367959,
    CotechFt0203,
    CttLifePowerHybrid,
    CurrentCost,
    DanfossCfr,
    DeltadoreX3d,
    DickertPwm,
    DigitechXc0324,
    Directv,
    DishRemote63,
    EberleInstat868r1,
    Ec3k,
)

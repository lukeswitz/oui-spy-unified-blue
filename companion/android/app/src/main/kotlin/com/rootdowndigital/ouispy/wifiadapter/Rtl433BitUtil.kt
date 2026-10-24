package com.rootdowndigital.ouispy.wifiadapter

internal object Rtl433BitUtil {

    private fun reverse8(x: Int): Int {
        var v = x and 0xFF
        v = ((v and 0xF0) shr 4) or ((v and 0x0F) shl 4)
        v = ((v and 0xCC) shr 2) or ((v and 0x33) shl 2)
        v = ((v and 0xAA) shr 1) or ((v and 0x55) shl 1)
        return v
    }

    fun crc8(msg: IntArray, nBytes: Int, poly: Int, init: Int): Int {
        var rem = init and 0xFF
        val p = poly and 0xFF
        for (i in 0 until nBytes) {
            rem = rem xor (msg[i] and 0xFF)
            for (b in 0 until 8) {
                rem = if (rem and 0x80 != 0) ((rem shl 1) xor p) and 0xFF else (rem shl 1) and 0xFF
            }
        }
        return rem
    }

    fun crc8le(msg: IntArray, nBytes: Int, poly: Int, init: Int): Int {
        var rem = reverse8(init)
        val p = reverse8(poly)
        for (i in 0 until nBytes) {
            rem = rem xor (msg[i] and 0xFF)
            for (b in 0 until 8) {
                rem = if (rem and 1 != 0) (rem shr 1) xor p else rem shr 1
            }
        }
        return rem and 0xFF
    }

    fun crc16lsb(msg: IntArray, nBytes: Int, poly: Int, init: Int): Int {
        var rem = init and 0xFFFF
        val p = poly and 0xFFFF
        for (i in 0 until nBytes) {
            rem = rem xor (msg[i] and 0xFF)
            for (b in 0 until 8) {
                rem = if (rem and 1 != 0) (rem shr 1) xor p else rem shr 1
            }
        }
        return rem and 0xFFFF
    }

    fun crc16(msg: IntArray, nBytes: Int, poly: Int, init: Int): Int {
        var rem = init and 0xFFFF
        val p = poly and 0xFFFF
        for (i in 0 until nBytes) {
            rem = rem xor ((msg[i] and 0xFF) shl 8)
            for (b in 0 until 8) {
                rem = if (rem and 0x8000 != 0) ((rem shl 1) xor p) and 0xFFFF else (rem shl 1) and 0xFFFF
            }
        }
        return rem
    }

    fun lfsrDigest8(msg: IntArray, bytes: Int, gen: Int, key: Int): Int {
        var sum = 0
        var k = key and 0xFF
        val g = gen and 0xFF
        for (j in 0 until bytes) {
            val data = msg[j] and 0xFF
            for (i in 7 downTo 0) {
                if ((data shr i) and 1 != 0) sum = sum xor k
                k = if (k and 1 != 0) (k shr 1) xor g else k shr 1
            }
        }
        return sum and 0xFF
    }

    fun lfsrDigest8Reverse(msg: IntArray, bytes: Int, gen: Int, key: Int): Int {
        var sum = 0
        var k = key and 0xFF
        val g = gen and 0xFF
        for (j in bytes - 1 downTo 0) {
            val data = msg[j] and 0xFF
            for (i in 7 downTo 0) {
                if ((data shr i) and 1 != 0) sum = sum xor k
                k = if (k and 1 != 0) (k shr 1) xor g else k shr 1
            }
        }
        return sum and 0xFF
    }

    fun lfsrDigest8Reflect(msg: IntArray, bytes: Int, gen: Int, key: Int): Int {
        var sum = 0
        var k = key and 0xFF
        val g = gen and 0xFF
        for (j in bytes - 1 downTo 0) {
            val data = msg[j] and 0xFF
            for (i in 0 until 8) {
                if ((data shr i) and 1 != 0) sum = sum xor k
                k = if (k and 0x80 != 0) ((k shl 1) xor g) and 0xFF else (k shl 1) and 0xFF
            }
        }
        return sum and 0xFF
    }

    fun lfsrDigest16(msg: IntArray, bytes: Int, gen: Int, key: Int): Int {
        var sum = 0
        var k = key and 0xFFFF
        val g = gen and 0xFFFF
        for (j in 0 until bytes) {
            val data = msg[j] and 0xFF
            for (i in 7 downTo 0) {
                if ((data shr i) and 1 != 0) sum = sum xor k
                k = if (k and 1 != 0) (k shr 1) xor g else k shr 1
            }
        }
        return sum and 0xFFFF
    }

    fun xorBytes(msg: IntArray, nBytes: Int): Int {
        var r = 0
        for (i in 0 until nBytes) r = r xor (msg[i] and 0xFF)
        return r
    }

    fun addBytes(msg: IntArray, nBytes: Int): Int {
        var r = 0
        for (i in 0 until nBytes) r += msg[i] and 0xFF
        return r
    }

    fun addNibbles(msg: IntArray, nBytes: Int): Int {
        var r = 0
        for (i in 0 until nBytes) r += ((msg[i] and 0xFF) shr 4) + (msg[i] and 0x0F)
        return r
    }

    fun parity8(b: Int): Int {
        var v = (b and 0xFF)
        v = (v xor (v shr 4)) and 0xF
        return (0x6996 shr v) and 1
    }

    fun parityBytes(msg: IntArray, nBytes: Int): Int {
        var r = 0
        for (i in 0 until nBytes) r = r xor parity8(msg[i])
        return r
    }

    fun demo() {
        val msg = intArrayOf(0x08, 0x0a, 0xe8, 0x80)
        check(crc8(msg, 3, 0x80, 0x00) == 0x80)
        check(crc8(msg, 4, 0x80, 0x00) == 0x00)
        check(lfsrDigest8(intArrayOf(0x80), 1, 0x8C, 0x37) == 0x37)
    }
}

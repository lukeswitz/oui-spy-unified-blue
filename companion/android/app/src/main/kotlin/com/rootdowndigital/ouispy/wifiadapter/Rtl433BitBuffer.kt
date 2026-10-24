// Kotlin reimplementation of the bit buffer API from rtl_433 (include/bitbuffer.h, src/bitbuffer.c; GPL-3 reference, algorithm transcribed as facts).
package com.rootdowndigital.ouispy.wifiadapter

const val BITBUF_COLS = 128
const val BITBUF_ROWS = 50
const val BITBUF_MAX_ROW_BITS = BITBUF_ROWS * BITBUF_COLS * 8
const val BITBUF_MAX_PRINT_BITS = 50
const val BITBUF_UINT16_MAX = 65535

fun bitrowGetBit(bitrow: IntArray, bitIdx: Int): Int =
    (bitrow[bitIdx shr 3] shr (7 - (bitIdx and 7))) and 1

fun bitrowGetByte(bitrow: IntArray, bitIdx: Int): Int {
    val i = bitIdx shr 3
    val hi = bitrow[i] shl (bitIdx and 7)
    val lo = if (i + 1 < bitrow.size) bitrow[i + 1] shr (8 - (bitIdx and 7)) else 0
    return (hi or lo) and 0xFF
}

fun bitrowSnprint(bitrow: IntArray, bitLen: Int): String {
    val sb = StringBuilder()
    for (i in 0 until (bitLen + 7) / 8) sb.append("%02x".format(bitrow[i]))
    return sb.toString()
}

private fun bitrowPrint(bitrow: IntArray, bitLen: Int, highestIndent: Int, alwaysBinary: Boolean): String {
    val sb = StringBuilder()
    sb.append("{%2d} ".format(bitLen))
    var rowLen = 0
    for (col in 0 until (bitLen + 7) / 8) {
        sb.append("%02x ".format(bitrow[col]))
        rowLen += 3
    }
    if (alwaysBinary || bitLen <= BITBUF_MAX_PRINT_BITS) {
        val pad = if (highestIndent > rowLen) highestIndent - rowLen else 0
        sb.append(" ".repeat(pad)).append(": ")
        for (bit in 0 until bitLen) {
            sb.append(if ((bitrow[bit / 8] and (0x80 shr (bit % 8))) != 0) '1' else '0')
            if (bit % 8 == 7) sb.append(' ')
        }
    }
    return sb.toString()
}

class BitBuffer {
    var numRows = 0
    var freeRow = 0
    val bitsPerRow = IntArray(BITBUF_ROWS)
    val syncsBeforeRow = IntArray(BITBUF_ROWS)
    val bb = Array(BITBUF_ROWS) { IntArray(BITBUF_COLS) }

    private fun getByte(row: Int, col: Int): Int {
        val r = row + col / BITBUF_COLS
        return if (r < BITBUF_ROWS) bb[r][col % BITBUF_COLS] else 0
    }

    private fun setByte(row: Int, col: Int, v: Int) {
        val r = row + col / BITBUF_COLS
        if (r < BITBUF_ROWS) bb[r][col % BITBUF_COLS] = v and 0xFF
    }

    private fun bitAt(row: Int, bit: Int): Int = (getByte(row, bit shr 3) shr (7 - (bit and 7))) and 1

    fun clear() {
        numRows = 0
        freeRow = 0
        bitsPerRow.fill(0)
        syncsBeforeRow.fill(0)
        for (r in bb) r.fill(0)
    }

    fun addBit(bit: Int) {
        if (numRows == 0) {
            numRows = 1
            freeRow = 1
        }
        val last = numRows - 1
        val n = bitsPerRow[last]
        if (n == BITBUF_UINT16_MAX) return
        val colIndex = n / 8
        val bitIndex = n % 8
        if (n > 0 && n % (BITBUF_COLS * 8) == 0) {
            if (freeRow < BITBUF_ROWS) freeRow++ else return
        }
        setByte(last, colIndex, getByte(last, colIndex) or (bit shl (7 - bitIndex)))
        bitsPerRow[last] = n + 1
    }

    private fun setWidth(widthIn: Int) {
        var width = widthIn
        if (numRows == 0) {
            numRows = 1
            freeRow = 1
        }
        val remainingRows = BITBUF_ROWS - numRows + 1
        val remainingBits = remainingRows * BITBUF_COLS * 8
        if (width > remainingBits) width = remainingBits
        val last = numRows - 1
        if (bitsPerRow[last] > width) {
            val clrFrom = (width + 7) / 8
            val clrEnd = (bitsPerRow[last] + 7) / 8
            for (c in clrFrom until clrEnd) setByte(last, c, 0)
            setByte(last, width / 8, getByte(last, width / 8) and ((0xff00 shr (width % 8)) and 0xFF))
        }
        bitsPerRow[last] = width
        val extraRows = if (width == 0) 0 else (width - 1) / (BITBUF_COLS * 8)
        freeRow = numRows + extraRows
    }

    fun addRow() {
        if (numRows == 0) {
            numRows = 1
            freeRow = 1
        }
        if (freeRow < BITBUF_ROWS) {
            freeRow++
            numRows = freeRow
        } else {
            bitsPerRow[numRows - 1] = 0
        }
    }

    fun addSync() {
        if (numRows == 0) {
            numRows = 1
            freeRow = 1
        }
        if (bitsPerRow[numRows - 1] != 0) addRow()
        syncsBeforeRow[numRows - 1]++
    }

    fun invert() {
        for (row in 0 until numRows) {
            if (bitsPerRow[row] > 0) {
                val lastCol = (bitsPerRow[row] - 1) / 8
                val lastBits = ((bitsPerRow[row] - 1) % 8) + 1
                for (col in 0..lastCol) setByte(row, col, getByte(row, col).inv())
                setByte(row, lastCol, getByte(row, lastCol) xor (0xFF shr lastBits))
            }
        }
    }

    fun nrzsDecode() {
        for (row in 0 until numRows) {
            if (bitsPerRow[row] > 0) {
                val lastCol = (bitsPerRow[row] - 1) / 8
                val lastBits = ((bitsPerRow[row] - 1) % 8) + 1
                var prev = 0
                for (col in 0..lastCol) {
                    val cur = getByte(row, col)
                    val mask = (prev shl 7) or (cur shr 1)
                    prev = cur
                    setByte(row, col, cur xor mask.inv())
                }
                setByte(row, lastCol, getByte(row, lastCol) and (0xFF shl (8 - lastBits)))
            }
        }
    }

    fun nrzmDecode() {
        for (row in 0 until numRows) {
            if (bitsPerRow[row] > 0) {
                val lastCol = (bitsPerRow[row] - 1) / 8
                val lastBits = ((bitsPerRow[row] - 1) % 8) + 1
                var prev = 0
                for (col in 0..lastCol) {
                    val cur = getByte(row, col)
                    val mask = (prev shl 7) or (cur shr 1)
                    prev = cur
                    setByte(row, col, cur xor mask)
                }
                setByte(row, lastCol, getByte(row, lastCol) and (0xFF shl (8 - lastBits)))
            }
        }
    }

    fun extractBytes(row: Int, posIn: Int, out: IntArray, len: Int) {
        if (len == 0) return
        var pos = posIn
        if ((pos and 7) == 0) {
            val base = pos / 8
            for (i in 0 until (len + 7) / 8) out[i] = getByte(row, base + i)
        } else {
            val shift = 8 - (pos and 7)
            var bytes = (len + 7) shr 3
            var p = 0
            pos = pos shr 3
            var word = getByte(row, pos)
            while (bytes-- > 0) {
                word = ((word shl 8) or getByte(row, ++pos)) and 0xFFFF
                out[p++] = (word shr shift) and 0xFF
            }
        }
        if ((len and 7) != 0) {
            val i = (len - 1) / 8
            out[i] = out[i] and ((0xff00 shr (len and 7)) and 0xFF)
        }
    }

    fun search(row: Int, start: Int, pattern: IntArray, patternBitsLen: Int): Int {
        val len = bitsPerRow[row]
        var ipos = start
        var ppos = 0
        while (ipos < len && ppos < patternBitsLen) {
            if (bitAt(row, ipos) == bitrowGetBit(pattern, ppos)) {
                ppos++
                ipos++
                if (ppos == patternBitsLen) return ipos - patternBitsLen
            } else {
                ipos -= ppos
                ipos++
                ppos = 0
            }
        }
        return len
    }

    fun manchesterDecode(row: Int, start: Int, outbuf: BitBuffer, max: Int): Int {
        var len = bitsPerRow[row]
        var ipos = start
        if (max != 0 && len > start + max * 2) len = start + max * 2
        while (ipos < len) {
            val bit1 = bitAt(row, ipos++)
            val bit2 = bitAt(row, ipos++)
            if (bit1 == bit2) break
            outbuf.addBit(bit2)
        }
        return ipos
    }

    fun differentialManchesterDecode(row: Int, start: Int, outbuf: BitBuffer, max: Int): Int {
        var len = bitsPerRow[row]
        var ipos = start
        var bit1: Int
        var bit2 = 0
        if (max != 0 && len > start + max * 2) len = start + max * 2
        while (ipos < len) {
            bit1 = bitAt(row, ipos++)
            bit2 = bitAt(row, ipos++)
            val bit3 = bitAt(row, ipos)
            if (bit1 != bit2) {
                if (bit2 != bit3) {
                    outbuf.addBit(0)
                } else {
                    bit2 = bit1
                    ipos -= 1
                    break
                }
            } else {
                bit2 = 1 - bit1
                ipos -= 2
                break
            }
        }
        while (ipos < len) {
            bit1 = bitAt(row, ipos++)
            if (bit1 == bit2) break
            bit2 = bitAt(row, ipos++)
            if (bit1 == bit2) outbuf.addBit(1) else outbuf.addBit(0)
        }
        return ipos
    }

    fun compareRows(rowA: Int, rowB: Int, maxBits: Int): Boolean {
        if (maxBits == 0 || bitsPerRow[rowA] < maxBits || bitsPerRow[rowB] < maxBits) {
            if (bitsPerRow[rowA] != bitsPerRow[rowB]) return false
            for (i in 0 until (bitsPerRow[rowA] + 7) / 8) if (getByte(rowA, i) != getByte(rowB, i)) return false
            return true
        }
        val last = (maxBits - 1) / 8
        val mask = 0xff00 shr (maxBits and 7)
        for (i in 0 until maxBits / 8) if (getByte(rowA, i) != getByte(rowB, i)) return false
        return (getByte(rowA, last) and mask) == (getByte(rowB, last) and mask)
    }

    fun countRepeats(row: Int, maxBits: Int): Int {
        var cnt = 0
        for (i in 0 until numRows) if (compareRows(row, i, maxBits)) cnt++
        return cnt
    }

    fun findRepeatedRow(minRepeats: Int, minBits: Int): Int {
        for (i in 0 until numRows) {
            if (bitsPerRow[i] >= minBits && countRepeats(i, 0) >= minRepeats) return i
        }
        return -1
    }

    fun findRepeatedPrefix(minRepeats: Int, minBits: Int): Int {
        for (i in 0 until numRows) {
            if (bitsPerRow[i] >= minBits && countRepeats(i, minBits) >= minRepeats) return i
        }
        return -1
    }

    fun printHex(): String {
        var highestIndent = "[dd] {dd} ".length
        for (row in 0 until numRows) {
            val indent = 3 * ((bitsPerRow[row] + 7) / 8)
            if (indent > highestIndent) highestIndent = indent
        }
        val sb = StringBuilder("bitbuffer:: Number of rows: $numRows \n")
        for (row in 0 until numRows) {
            sb.append("[%02d] ".format(row))
            sb.append(bitrowPrint(bb[row], bitsPerRow[row], highestIndent, false)).append('\n')
        }
        if (numRows >= BITBUF_ROWS) sb.append("... Maximum number of rows reached. Message is likely truncated.\n")
        return sb.toString()
    }

    companion object {
        fun parse(code: String): BitBuffer {
            val bits = BitBuffer()
            var data = 0
            var width = -1
            var i = 0
            while (i < code.length) {
                val c = code[i]
                if (c == ' ') {
                    i++
                    continue
                } else if (c == '0' && i + 1 < code.length && (code[i + 1] == 'x' || code[i + 1] == 'X')) {
                    i += 2
                    continue
                } else if (c == '{') {
                    if (width >= 0) bits.setWidth(width)
                    if (bits.numRows > 0) bits.addRow()
                    var j = i + 1
                    while (j < code.length && code[j].isWhitespace()) j++
                    var radix = 10
                    if (j + 1 < code.length && code[j] == '0' && (code[j + 1] == 'x' || code[j + 1] == 'X')) {
                        radix = 16
                        j += 2
                    }
                    var v = 0
                    while (j < code.length && Character.digit(code[j], radix) >= 0) {
                        v = v * radix + Character.digit(code[j], radix)
                        j++
                    }
                    width = v
                    while (j < code.length && (code[j] == ' ' || code[j] == '\t' || code[j] == '\r' || code[j] == '\n')) j++
                    if (width > BITBUF_MAX_ROW_BITS) width = BITBUF_MAX_ROW_BITS
                    if (j >= code.length) break
                    i = j + 1
                    continue
                } else if (c == '/') {
                    if (width >= 0) {
                        bits.setWidth(width)
                        width = -1
                    }
                    bits.addRow()
                    i++
                    continue
                } else if (c in '0'..'9') {
                    data = c - '0'
                } else if (c in 'A'..'F') {
                    data = c - 'A' + 10
                } else if (c in 'a'..'f') {
                    data = c - 'a' + 10
                }
                bits.addBit((data shr 3) and 1)
                bits.addBit((data shr 2) and 1)
                bits.addBit((data shr 1) and 1)
                bits.addBit(data and 1)
                i++
            }
            if (width >= 0) bits.setWidth(width)
            return bits
        }
    }
}

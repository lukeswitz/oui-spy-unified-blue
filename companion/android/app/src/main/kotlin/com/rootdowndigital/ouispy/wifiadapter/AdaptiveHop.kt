package com.rootdowndigital.ouispy.wifiadapter

class AdaptiveHop(private val channels: IntArray) {
    private var sweepLeft = 0
    private var sweepAt = Long.MIN_VALUE / 2

    fun next(cur: Int, active: Set<Int>, now: Long): Int {
        val n = channels.size
        val every = sweepEveryMs
        if (every <= 0 || active.isEmpty()) return step(channels, cur)
        if (now - sweepAt > every) {
            sweepLeft = channels.count { enabled(it) }
            sweepAt = now
        }
        if (sweepLeft > 0) {
            sweepLeft--
            return step(channels, cur)
        }
        var nx = step(channels, cur)
        var s = 0
        while (s < n && channels[nx] !in active) {
            nx = step(channels, nx)
            s++
        }
        return nx
    }

    companion object {
        @Volatile
        var sweepEveryMs = 0L

        @Volatile
        var priDwellMs = 0L

        @Volatile
        var otherDwellMs = 0L

        @Volatile
        var bandMask = 0x03

        fun dwellMs(ch: Int, fallback: Long): Long {
            val v = if (ch == 1 || ch == 6 || ch == 11) priDwellMs else otherDwellMs
            return if (v > 0) v else fallback
        }

        fun waitMs(hopAt: Long, dwellMs: Long): Long =
            (dwellMs - (System.currentTimeMillis() - hopAt)).coerceIn(1L, 100L)

        fun enabled(ch: Int): Boolean = (bandMask and (if (ch <= 14) 0x01 else 0x02)) != 0

        fun step(channels: IntArray, cur: Int): Int {
            val n = channels.size
            var nx = (cur + 1) % n
            var s = 0
            while (s < n && !enabled(channels[nx])) {
                nx = (nx + 1) % n
                s++
            }
            return nx
        }
    }
}

package com.rootdowndigital.ouispy.wifiadapter

class AdaptiveHop(private val channels: IntArray) {
    private var sweepLeft = 0
    private var sweepAt = Long.MIN_VALUE / 2

    fun next(cur: Int, active: Set<Int>, now: Long): Int {
        val n = channels.size
        val every = sweepEveryMs
        if (every <= 0 || active.isEmpty()) return (cur + 1) % n
        if (now - sweepAt > every) {
            sweepLeft = n
            sweepAt = now
        }
        if (sweepLeft > 0) {
            sweepLeft--
            return (cur + 1) % n
        }
        var nx = (cur + 1) % n
        var s = 0
        while (s < n && channels[nx] !in active) {
            nx = (nx + 1) % n
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

        fun dwellMs(ch: Int, fallback: Long): Long {
            val v = if (ch == 1 || ch == 6 || ch == 11) priDwellMs else otherDwellMs
            return if (v > 0) v else fallback
        }
    }
}

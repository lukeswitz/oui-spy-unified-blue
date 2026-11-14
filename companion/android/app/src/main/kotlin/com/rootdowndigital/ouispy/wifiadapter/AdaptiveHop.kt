package com.rootdowndigital.ouispy.wifiadapter

class AdaptiveHop(private val channels: IntArray, private val sweepEveryMs: Long = SWEEP_EVERY_MS) {
    private var sweepLeft = 0
    private var sweepAt = Long.MIN_VALUE / 2

    fun next(cur: Int, active: Set<Int>, now: Long): Int {
        val n = channels.size
        if (now - sweepAt > sweepEveryMs) {
            sweepLeft = n
            sweepAt = now
        }
        if (sweepLeft > 0 || active.isEmpty()) {
            if (sweepLeft > 0) sweepLeft--
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
        const val SWEEP_EVERY_MS = 15000L
    }
}

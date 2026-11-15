package com.rootdowndigital.ouispy.wifiadapter

class AdaptiveHop(private val channels: IntArray) {
    private var sweepLeft = 0
    private var sweepAt = Long.MIN_VALUE / 2
    private var exploreAt = 0L
    private var explorePtr = -1

    fun next(cur: Int, active: Set<Int>, now: Long): Int {
        val n = channels.size
        val every = sweepEveryMs
        if (every > 0) {
            if (now - sweepAt > every) {
                sweepLeft = n
                sweepAt = now
            }
            if (sweepLeft > 0) {
                sweepLeft--
                return (cur + 1) % n
            }
        }
        if (active.isEmpty()) return (cur + 1) % n
        if (every <= 0 && now - exploreAt >= EXPLORE_MS) {
            exploreAt = now
            var s = 0
            do {
                explorePtr = (explorePtr + 1) % n
                s++
            } while (s < n && channels[explorePtr] in active)
            return explorePtr
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
        const val EXPLORE_MS = 2000L

        @Volatile
        var sweepEveryMs = 0L
    }
}

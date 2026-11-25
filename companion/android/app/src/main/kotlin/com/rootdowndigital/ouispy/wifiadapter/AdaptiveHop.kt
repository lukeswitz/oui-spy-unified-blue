// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

package com.rootdowndigital.ouispy.wifiadapter

class AdaptiveHop(private val channels: IntArray) {
    private var sweepLeft = 0
    private var sweepAt = Long.MIN_VALUE / 2
    private var pos = 0
    private val key = Any()

    fun next(cur: Int, active: Set<Int>, now: Long): Int {
        val (unit, units) = join(key, now)
        if (units > 1) return splitNext(unit, units)
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

    private fun splitNext(unit: Int, units: Int): Int {
        val list = channels.indices.filter { enabled(channels[it]) }
        if (list.isEmpty()) return 0
        val sz = list.size
        val offset = (sz / units) * unit
        val idx = chanhopIndex(pos + offset, sz, shuffleSpacing(sz))
        pos = (pos + 1) % sz
        return list[idx]
    }

    companion object {
        private val live = LinkedHashMap<Any, Long>()

        private fun join(key: Any, now: Long): Pair<Int, Int> = synchronized(live) {
            val staleMs = maxOf(10_000L, 3 * maxOf(priDwellMs, otherDwellMs))
            live.entries.removeAll { it.key !== key && now - it.value > staleMs }
            live[key] = now
            Pair(live.keys.indexOf(key), live.size)
        }

        fun shuffleSpacing(sz: Int): Int {
            var spacing = 4
            if (spacing >= sz) return 1
            while (sz % (sz / spacing) == 0) {
                if (spacing >= sz - 1) return 1
                spacing++
            }
            return spacing
        }

        fun chanhopIndex(posIn: Int, sz: Int, spacing: Int): Int {
            var pos = posIn % sz
            if (spacing <= 1 || spacing >= sz) return pos
            for (pass in 0 until spacing) {
                val passSz = (sz - pass + spacing - 1) / spacing
                if (pos < passSz) return pass + pos * spacing
                pos -= passSz
            }
            return 0
        }

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

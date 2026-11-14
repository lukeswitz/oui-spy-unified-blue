package com.rootdowndigital.ouispy.wifiadapter

class AdaptiveHop(private val channels: IntArray) {
    private var cursor = 0

    fun next(cur: Int, active: Set<Int>, explore: Boolean): Int {
        val n = channels.size
        if (active.isEmpty()) return (cur + 1) % n
        if (explore) {
            var s = 0
            do {
                cursor = (cursor + 1) % n
                s++
            } while (s < n && channels[cursor] in active)
            return cursor
        }
        var nx = (cur + 1) % n
        var s = 0
        while (s < n && channels[nx] !in active) {
            nx = (nx + 1) % n
            s++
        }
        return nx
    }
}

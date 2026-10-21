package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbRequest
import com.rootdowndigital.ouispy.wifiadapter.UsbIo.Companion.le32
import java.nio.ByteBuffer
import java.util.concurrent.TimeoutException

// Receive-only bulk-in pump and rtw88 24-byte RX descriptor parser (Linux rtw88 rx.c/usb.c, GPL-2.0 OR BSD-3-Clause): beacons and probe responses only.
internal class RtlRx(
    private val conn: UsbDeviceConnection,
    private val epRx: UsbEndpoint,
    private val phyPower: (ByteArray, Int, Int) -> Int,
    private val retune: (Int) -> Unit,
    private val stopped: () -> Boolean,
) {
    private class Entry(var ssid: String?, var rssi: Int, var channel: Int, var lastSeen: Long)

    private class Table {
        val map = LinkedHashMap<String, Entry>()
    }

    private inner class Hopper(
        val channels: IntArray,
        val onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit,
    ) {
        val table = Table()
        var idx = 0
        var hopAt = System.currentTimeMillis()
        var emitAt = hopAt

        fun tick() {
            val now = System.currentTimeMillis()
            if (now - emitAt > EMIT_MS) {
                emit(table, onBatch)
                emitAt = now
            }
            if (now - hopAt > DWELL_MS) {
                idx = (idx + 1) % channels.size
                retune(channels[idx])
                hopAt = System.currentTimeMillis()
            }
        }
    }

    fun run(channels: IntArray, onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val hop = Hopper(channels, onBatch)
        val buffers = Array(NBUF) { ByteBuffer.allocateDirect(BUF_SZ) }
        val reqs = ArrayList<UsbRequest>(NBUF)
        var ok = true
        for (i in 0 until NBUF) {
            val r = UsbRequest()
            if (!r.initialize(conn, epRx)) {
                ok = false
                break
            }
            r.clientData = i
            buffers[i].clear()
            if (!r.queue(buffers[i])) {
                ok = false
                break
            }
            reqs.add(r)
        }
        if (!ok) {
            reqs.forEach { runCatching { it.cancel() }; runCatching { it.close() } }
            runSync(hop)
            return
        }
        val scratch = ByteArray(BUF_SZ)
        try {
            while (!stopped()) {
                val req = try { conn.requestWait(100L) } catch (e: TimeoutException) { null }
                if (req != null) {
                    val idx = req.clientData as? Int ?: -1
                    if (idx in 0 until NBUF) {
                        val b = buffers[idx]
                        val nbytes = b.position()
                        if (nbytes in 1..BUF_SZ) {
                            b.rewind()
                            b.get(scratch, 0, nbytes)
                            parse(scratch, nbytes, hop.channels[hop.idx], hop.table)
                        }
                        b.clear()
                        if (!runCatching { req.queue(b) }.getOrDefault(false)) {
                            runCatching { req.close() }
                        }
                    }
                }
                hop.tick()
            }
        } finally {
            reqs.forEach { runCatching { it.cancel() }; runCatching { it.close() } }
        }
        emit(hop.table, onBatch)
    }

    private fun runSync(hop: Hopper) {
        val buf = ByteArray(BUF_SZ)
        while (!stopped()) {
            val n = conn.bulkTransfer(epRx, buf, buf.size, 500)
            if (n > 0) parse(buf, n, hop.channels[hop.idx], hop.table)
            hop.tick()
        }
        emit(hop.table, hop.onBatch)
    }

    private fun parse(b: ByteArray, n: Int, hopCh: Int, t: Table) {
        val desc = Rtl88Regs.RX_DESC_SIZE
        var p = 0
        while (p + desc <= n) {
            val w0 = le32(b, p)
            val w2 = le32(b, p + 8)
            val w3 = le32(b, p + 12)
            val pktLen = w0 and 0x3fff
            val drvRaw = (w0 ushr 16) and 0xf
            val shift = (w0 ushr 24) and 3
            val rate = w3 and 0x7f
            val c2h = ((w2 ushr 28) and 1) != 0
            if (rate >= RATE_MAX || (drvRaw != 0 && drvRaw != Rtl88Regs.PHY_STATUS_SIZE) || pktLen > MAX_MPDU) return
            val total = desc + drvRaw * 8 + shift + pktLen
            if (p + total > n || (!c2h && pktLen <= FCS_LEN)) return
            val bad = (w0 and ((1 shl 14) or (1 shl 15))) != 0
            if (!c2h && !bad) frame(b, p, w0, drvRaw * 8, shift, pktLen - FCS_LEN, rate, hopCh, t)
            p += (total + 7) and 7.inv()
        }
    }

    private fun frame(
        b: ByteArray,
        p: Int,
        w0: Int,
        drvInfo: Int,
        shift: Int,
        len: Int,
        rate: Int,
        hopCh: Int,
        t: Table,
    ) {
        val hdr = p + Rtl88Regs.RX_DESC_SIZE + drvInfo + shift
        if (len < 36) return
        val fc = b[hdr].toInt() and 0xff
        if (((fc shr 2) and 3) != 0) return
        val sub = (fc shr 4) and 0xf
        if (sub != 8 && sub != 5) return
        val bssid = (0 until 6).joinToString(":") { "%02x".format(b[hdr + 16 + it].toInt() and 0xff) }
        if (bssid == "ff:ff:ff:ff:ff:ff" || bssid == "00:00:00:00:00:00") return
        var ssid: String? = null
        var ch = 0
        var i = hdr + 36
        val end = hdr + len
        while (i + 2 <= end) {
            val tag = b[i].toInt() and 0xff
            val tl = b[i + 1].toInt() and 0xff
            if (i + 2 + tl > end) break
            if (tag == 0) {
                ssid = if (tl == 0) "" else String(b, i + 2, tl, Charsets.UTF_8)
                if (ssid.length > 32 || ssid.any { it.code == 0xFFFD || it.isISOControl() }) ssid = null
            } else if ((tag == 3 || tag == 61) && tl >= 1) {
                if (ch == 0) ch = b[i + 2].toInt() and 0xff
            }
            i += 2 + tl
        }
        val channel = if (ch in 1..196) ch else hopCh
        val physt = ((w0 ushr 26) and 1) != 0 && drvInfo >= PHY_STATUS_BYTES
        val rssi = if (physt) phyPower(b, p + Rtl88Regs.RX_DESC_SIZE + shift, rate).coerceIn(-120, -10) else -100
        val e = t.map.getOrPut(bssid) { Entry(null, rssi, channel, 0) }
        if (!ssid.isNullOrEmpty()) e.ssid = ssid
        if (rssi > e.rssi) e.rssi = rssi
        e.channel = channel
        e.lastSeen = System.currentTimeMillis()
    }

    private fun emit(table: Table, onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val now = System.currentTimeMillis()
        val batch = table.map.entries
            .filter { now - it.value.lastSeen < FRESH_MS }
            .map { (mac, e) -> Mt7612uAdapter.ApSighting(mac, e.ssid, e.rssi, e.channel, Mt76Regs.freqOf(e.channel)) }
        table.map.entries.removeAll { now - it.value.lastSeen > EXPIRE_MS }
        if (batch.isNotEmpty()) onBatch(batch)
    }

    companion object {
        const val DWELL_MS = 150L
        private const val EMIT_MS = 2000L
        private const val FRESH_MS = 8000L
        private const val EXPIRE_MS = 60_000L
        private const val NBUF = 8
        private const val BUF_SZ = 16384
        private const val RATE_MAX = 0x54
        private const val MAX_MPDU = 11454
        private const val FCS_LEN = 4
        private const val PHY_STATUS_BYTES = 28
    }
}

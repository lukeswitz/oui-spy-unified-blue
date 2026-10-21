package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbInterface
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import java.io.ByteArrayOutputStream
import java.io.IOException

// Line-oriented 115200 8N1 text console shared by the GhostESP, Marauder and FreeWili scanners.
internal class SerialLines(private val port: UsbSerialPort) {
    private val buf = ByteArray(4096)
    private val acc = ByteArrayOutputStream()
    private val pending = ArrayDeque<String>()

    fun send(s: String) {
        port.write(s.toByteArray(Charsets.UTF_8), 1000)
    }

    fun readLine(timeoutMs: Int): String? {
        pending.removeFirstOrNull()?.let { return it }
        val end = System.currentTimeMillis() + timeoutMs
        while (true) {
            val left = (end - System.currentTimeMillis()).toInt()
            if (left <= 0) return null
            val n = port.read(buf, minOf(left, 200))
            for (i in 0 until n) {
                if (buf[i] == NL) {
                    pending.addLast(clean(acc.toByteArray()))
                    acc.reset()
                } else {
                    acc.write(buf[i].toInt())
                }
            }
            pending.removeFirstOrNull()?.let { return it }
        }
    }

    // onLine returns true when the line counts as activity; ends at totalMs, idleMs after last activity, or stop().
    fun pump(totalMs: Int, idleMs: Int, stop: () -> Boolean, onLine: (String) -> Boolean) {
        val start = System.currentTimeMillis()
        var last = start
        while (!stop()) {
            val now = System.currentTimeMillis()
            if (now - start >= totalMs || now - last >= idleMs) return
            val line = readLine(200) ?: continue
            if (line.isNotEmpty() && onLine(line)) last = System.currentTimeMillis()
        }
    }

    private fun clean(b: ByteArray): String = String(b, Charsets.UTF_8).replace(ANSI, "").trim()

    companion object {
        private const val NL = '\n'.code.toByte()
        private val ANSI = Regex("\u001B\\[[0-9;]*[A-Za-z]")
        val MAC = Regex("(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}")

        fun open(device: UsbDevice, conn: UsbDeviceConnection): UsbSerialPort {
            val driver = UsbSerialProber.getDefaultProber().probeDevice(device)
                ?: throw IllegalStateException("no USB serial driver for %04x:%04x".format(device.vendorId, device.productId))
            val p = driver.ports[0]
            p.open(conn)
            p.setParameters(115200, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE)
            // unverified: native-USB CDC (303a:1001) needs DTR asserted to emit output; RTS left low to avoid resetting the chip.
            p.dtr = true
            return p
        }

        fun freqOf(ch: Int, sixGhz: Boolean = false): Int = when {
            sixGhz -> 5950 + ch * 5
            ch == 14 -> 2484
            ch <= 14 -> 2407 + ch * 5
            else -> 5000 + ch * 5
        }
    }
}

internal class ApTable {
    private val map = LinkedHashMap<String, Mt7612uAdapter.ApSighting>()
    private val dirty = LinkedHashSet<String>()

    fun put(s: Mt7612uAdapter.ApSighting) {
        val old = map[s.bssid]
        map[s.bssid] = if (s.ssid.isNullOrEmpty() && old != null) s.copy(ssid = old.ssid) else s
        dirty.add(s.bssid)
    }

    fun flush(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        if (dirty.isEmpty()) return
        val batch = dirty.mapNotNull { map[it] }
        dirty.clear()
        if (batch.isNotEmpty()) onBatch(batch)
    }
}

// Passive GhostESP scan: scanap + list -a only; stopscan on exit.
internal class GhostEspScanner(
    private val port: UsbSerialPort,
    @Suppress("unused") private val intf: UsbInterface,
    private val log: (String) -> Unit,
) {
    @Volatile private var stop = false

    fun abort() { stop = true }

    private class Rec {
        var ssid: String? = null
        var bssid: String? = null
        var rssi: Int? = null
        var channel: Int? = null
        var band: String? = null
    }

    private var cur: Rec? = null
    private val table = ApTable()

    fun run(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val io = SerialLines(port)
        try {
            io.send("\n")
            io.pump(400, 400, { stop }) { false }
            log("GhostESP: scanning")
            while (!stop) {
                io.send("scanap\n")
                io.pump(30_000, 5_000, { stop }) { feed(it) }
                commit()
                table.flush(onBatch)
                if (stop) break
                io.send("list -a\n")
                io.pump(6_000, 2_000, { stop }) { feed(it) }
                commit()
                table.flush(onBatch)
            }
        } finally {
            try {
                io.send("stopscan\n")
            } catch (e: IOException) {
                log("GhostESP: stopscan not sent, port closed")
            }
        }
    }

    private fun feed(line: String): Boolean {
        HEAD.matchEntire(line)?.let {
            commit()
            cur = Rec().also { r -> r.ssid = it.groupValues[1].let { s -> if (s == "(Hidden)") null else s } }
            return true
        }
        val r = cur ?: return false
        FIELD.matchEntire(line)?.let {
            val v = it.groupValues[2].trimEnd(',').trim()
            when (it.groupValues[1]) {
                "BSSID" -> r.bssid = v.takeIf { m -> SerialLines.MAC.matches(m) }?.lowercase()
                "RSSI" -> r.rssi = v.toIntOrNull()
                "Channel" -> r.channel = v.toIntOrNull()
                "Band" -> r.band = v
            }
            return true
        }
        return false
    }

    private fun commit() {
        val r = cur ?: return
        cur = null
        val b = r.bssid ?: return
        val rssi = r.rssi ?: return
        val ch = r.channel ?: return
        val six = r.band?.startsWith("6") == true
        table.put(Mt7612uAdapter.ApSighting(b, r.ssid, rssi, ch, SerialLines.freqOf(ch, six)))
    }

    companion object {
        // "[0] SSID: name," -- the firmware appends one trailing comma; sources: GhostESP main/managers/wifi_manager.c and main/scans/wifi/ap_scan.c
        private val HEAD = Regex("""\[\d+]\s+SSID:\s?(.*?),?""")
        private val FIELD = Regex("""(BSSID|RSSI|Channel|Band):\s*(.*)""")
    }
}

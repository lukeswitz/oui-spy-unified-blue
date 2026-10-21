package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbInterface
import com.hoho.android.usbserial.driver.UsbSerialPort
import java.io.IOException

// Passive ESP32 Marauder scan: wardrive CSV stream when GPS is present, else sniffbeacon with manual channel hop.
internal class MarauderScanner(
    private val port: UsbSerialPort,
    @Suppress("unused") private val intf: UsbInterface,
    private val log: (String) -> Unit,
) {
    @Volatile private var stop = false

    fun abort() { stop = true }

    private val table = ApTable()

    fun run(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val io = SerialLines(port)
        try {
            io.send("\n")
            io.send("help\n")
            var ghost = false
            var marauder = false
            io.pump(2_500, 1_000, { stop }) { line ->
                val l = line.lowercase()
                if (l.contains("ghostesp")) ghost = true
                // unverified: "CLI Ready" is not in the Marauder source; banner is "ESP32 Marauder", help lists sniffbeacon.
                if (l.contains("cli ready") || l.contains("marauder") || l.contains("sniffbeacon")) marauder = true
                true
            }
            if (ghost) throw IllegalStateException("Marauder: GhostESP firmware detected, use the GhostESP scanner")
            log(if (marauder) "Marauder: CLI ready" else "Marauder: no banner seen, trying anyway")
            if (!stop && tryWardrive(io, onBatch)) return
            sniffBeacons(io, onBatch)
        } finally {
            try {
                io.send("stopscan\n")
            } catch (e: IOException) {
                log("Marauder: stopscan not sent, port closed")
            }
        }
    }

    private fun tryWardrive(io: SerialLines, onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit): Boolean {
        io.send("wardrive\n")
        var rows = 0
        io.pump(20_000, 20_000, { stop || rows > 0 }) { line -> parseWardrive(line)?.also { table.put(it); rows++ } != null }
        if (rows == 0) {
            io.send("stopscan\n")
            io.pump(800, 800, { stop }) { false }
            return false
        }
        log("Marauder: wardrive stream")
        table.flush(onBatch)
        while (!stop) {
            io.pump(2_000, 2_000, { stop }) { line -> parseWardrive(line)?.also { table.put(it) } != null }
            table.flush(onBatch)
        }
        return true
    }

    private fun sniffBeacons(io: SerialLines, onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        log("Marauder: sniffbeacon")
        val hop = intArrayOf(1, 6, 11, 2, 7, 12, 3, 8, 13, 4, 9, 5, 10)
        while (!stop) {
            io.send("clearlist -a\n")
            io.send("sniffbeacon\n")
            val cycleEnd = System.currentTimeMillis() + CYCLE_MS
            var i = 0
            while (!stop && System.currentTimeMillis() < cycleEnd) {
                io.send("channel -s ${hop[i++ % hop.size]}\n")
                io.pump(HOP_MS, HOP_MS, { stop }) { line -> parseBeacon(line)?.also { table.put(it) } != null }
                table.flush(onBatch)
            }
            io.send("stopscan\n")
            io.pump(500, 500, { stop }) { false }
        }
    }

    // "<rssi> Ch: <ch> <bssid> ESSID: <name>" from WiFiScan::apSnifferCallbackFull in justcallmekoko/ESP32Marauder
    private fun parseBeacon(line: String): Mt7612uAdapter.ApSighting? {
        val m = BEACON.matchEntire(line) ?: return null
        val ch = m.groupValues[2].toInt()
        return Mt7612uAdapter.ApSighting(
            m.groupValues[3].lowercase(), m.groupValues[4].ifEmpty { null }, m.groupValues[1].toInt(), ch, SerialLines.freqOf(ch),
        )
    }

    // "[<n> | ]BSSID,SSID,[AUTH],datetime,ch,freqMHz,rssi,lat,lon,alt,acc,,0,WIFI" from WiFiScan::executeWarDrive
    private fun parseWardrive(line: String): Mt7612uAdapter.ApSighting? {
        val body = line.substringAfter(" | ", line)
        val f = body.split(",")
        if (f.size < 14 || f.last() != "WIFI" || !SerialLines.MAC.matches(f[0])) return null
        val ch = f[4].toIntOrNull() ?: return null
        val rssi = f[6].toIntOrNull() ?: return null
        val freq = f[5].toIntOrNull() ?: SerialLines.freqOf(ch)
        return Mt7612uAdapter.ApSighting(f[0].lowercase(), f[1].ifEmpty { null }, rssi, ch, freq)
    }

    companion object {
        private const val CYCLE_MS = 20_000L
        private const val HOP_MS = 300
        private val BEACON = Regex("""(-?\d+) Ch: (\d+) ((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}) ESSID:\s?(.*)""")
    }
}

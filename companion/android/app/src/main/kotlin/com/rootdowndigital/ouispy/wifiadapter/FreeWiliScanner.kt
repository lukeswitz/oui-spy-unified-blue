package com.rootdowndigital.ouispy.wifiadapter

import android.hardware.usb.UsbInterface
import com.hoho.android.usbserial.driver.UsbSerialPort

// Passive FreeWili scan: menu path w\w\s (Scan for Access Points) and [*wifiscan ...] event lines only.
internal class FreeWiliScanner(
    private val port: UsbSerialPort,
    @Suppress("unused") private val intf: UsbInterface,
    private val log: (String) -> Unit,
) {
    @Volatile private var stop = false

    fun abort() { stop = true }

    private val table = ApTable()

    fun run(onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit) {
        val io = SerialLines(port)
        io.send(RESET)
        io.send("\n")
        io.pump(500, 500, { stop }) { false }
        var toggled = false
        var anyRecord = false
        log("FreeWili: scanning")
        while (!stop) {
            io.send(RESET + "w\\w\\s\n")
            var records = 0
            io.pump(20_000, 4_000, { stop }) { line ->
                val s = parse(line)
                if (s != null) {
                    table.put(s)
                    records++
                } else if (line.startsWith("[w\\w\\s ") && line.endsWith(" 0]")) {
                    log("FreeWili: scan rejected (ESP32 power zone off?) $line")
                }
                true
            }
            table.flush(onBatch)
            if (records > 0) anyRecord = true
            // unverified: w\w\r toggles event streaming and the default state is unknown; sent at most once.
            if (!anyRecord && !toggled && !stop) {
                toggled = true
                log("FreeWili: no wifiscan events, toggling wifi events once")
                io.send(RESET + "w\\w\\r\n")
                io.pump(1_000, 1_000, { stop }) { false }
            }
        }
    }

    // "[*wifiscan <bssid> <rssi> <channel> <band> <authmode> <ssid>]" per onewili docs/wifi.md; ssid last and may hold spaces
    private fun parse(line: String): Mt7612uAdapter.ApSighting? {
        val m = EVENT.matchEntire(line) ?: return null
        if (!SerialLines.MAC.matches(m.groupValues[1])) return null
        val ch = m.groupValues[3].toInt()
        // unverified: band enum values are not documented; only a literal 6 is treated as 6 GHz.
        val six = m.groupValues[4] == "6"
        val ssid = m.groupValues[6].let { if (it.length >= 2 && it.startsWith("\"") && it.endsWith("\"")) it.substring(1, it.length - 1) else it }
        return Mt7612uAdapter.ApSighting(
            m.groupValues[1].lowercase(), ssid.ifEmpty { null }, m.groupValues[2].toInt(), ch, SerialLines.freqOf(ch, six),
        )
    }

    companion object {
        private const val RESET = "\u0002"
        private val EVENT = Regex("""\[\*wifiscan (\S+) (-?\d+) (\d+) (\d+) (\d+) ?(.*)]""")
    }
}

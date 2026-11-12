package com.rootdowndigital.ouispy.wifiadapter

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// Flutter bridge for external USB WiFi monitor adapters and serial scanner firmware.
class WifiAdapterChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private enum class Kind { MT7612U, MT7921, RTL8812AU, RTL8814AU, RTL8821AU, AR9271, RT3070, RTLSDR, SERIAL }

    private val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val main = Handler(Looper.getMainLooper())

    private fun phoneWifiChannels(): Set<Int> {
        if (context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            return emptySet()
        }
        return wifi.scanResults.mapNotNullTo(HashSet()) { r ->
            val f = r.frequency
            when {
                f == 2484 -> 14
                f in 2412..2472 -> (f - 2412) / 5 + 1
                f in 5000..5900 -> (f - 5000) / 5
                else -> null
            }
        }
    }
    private val permissionAction = "${context.packageName}.WIFI_ADAPTER_PERMISSION"

    private fun rtlForceFirmware(): Boolean = java.io.File(context.filesDir, "rtl_force_fw").exists()
    private var sink: EventChannel.EventSink? = null
    private var eventSink: EventChannel.EventSink? = null
    private var sdrSink: EventChannel.EventSink? = null
    private class Session {
        var thread: Thread? = null
        @Volatile var stopFn: (() -> Unit)? = null
    }
    private val sessions = HashMap<String, Session>()
    private val pending = HashMap<String, Pair<MethodChannel.Result, Int>>()
    private var pendingSdr: (() -> Unit)? = null
    private var sdrGen = 0

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val device = deviceExtra(intent)
            when (intent.action) {
                permissionAction -> {
                    val sdrAction = pendingSdr
                    pendingSdr = null
                    if (sdrAction != null) {
                        if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) sdrAction()
                        return
                    }
                    val req = device?.let { pending.remove(it.deviceName) }
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    if (req != null && device != null) {
                        if (granted) startAdapter(device, req.first, req.second) else req.first.success(false)
                    } else if (granted && device != null &&
                        (isWifiMonitor(device) || kindOf(device) == Kind.RTLSDR)) {
                        emitAttach(true, device)
                    }
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED ->
                    if (device != null && (isWifiMonitor(device) || kindOf(device) == Kind.RTLSDR)) emitAttach(true, device)
                UsbManager.ACTION_USB_DEVICE_DETACHED ->
                    if (device != null && (isWifiMonitor(device) || kindOf(device) == Kind.RTLSDR)) emitAttach(false, device)
            }
        }
    }

    init {
        MethodChannel(messenger, "ouispy/wifiadapter").setMethodCallHandler(this)
        EventChannel(messenger, "ouispy/wifiadapter/sightings").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sink = events
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            },
        )
        EventChannel(messenger, "ouispy/wifiadapter/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
        EventChannel(messenger, "ouispy/sdr").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sdrSink = events
                }

                override fun onCancel(arguments: Any?) {
                    sdrSink = null
                }
            },
        )
        val filter = IntentFilter().apply {
            addAction(permissionAction)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    fun onAttachIntent(intent: Intent?) {
        if (intent?.action != UsbManager.ACTION_USB_DEVICE_ATTACHED) return
        val device = deviceExtra(intent) ?: return
        if (isWifiMonitor(device)) emitAttach(true, device)
    }

    fun dispose() {
        sdrSink = null
        sink = null
        eventSink = null
        stopSessions(sessions.keys.toList())
        main.removeCallbacksAndMessages(null)
        try {
            context.unregisterReceiver(receiver)
        } catch (e: IllegalArgumentException) {
            // Receiver was never registered; nothing to remove.
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> {
                result.success(candidates().filter { kindOf(it) != Kind.RTLSDR }.map { describe(it) })
            }
            "requestPermission" -> {
                val device = candidates().firstOrNull {
                    kindOf(it) != Kind.RTLSDR && !usb.hasPermission(it)
                }
                if (device != null) {
                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                    val intent = Intent(permissionAction).setPackage(context.packageName)
                    usb.requestPermission(device, PendingIntent.getBroadcast(context, 0, intent, flags))
                }
                result.success(device != null)
            }
            "start" -> {
                val id = call.argument<String>("id")
                val mask = call.argument<Int>("radioMask") ?: 0x01
                val device = candidates().firstOrNull { it.deviceName == id }
                if (device == null) {
                    result.success(false)
                } else if (usb.hasPermission(device)) {
                    startAdapter(device, result, mask)
                } else {
                    pending.remove(device.deviceName)?.first?.success(false)
                    pending[device.deviceName] = result to mask
                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                    val intent = Intent(permissionAction).setPackage(context.packageName)
                    usb.requestPermission(device, PendingIntent.getBroadcast(context, 0, intent, flags))
                }
            }
            "stop" -> {
                val id = call.argument<String>("id")
                stopSessions(if (id != null) listOf(id) else sessions.keys.filter { it != SDR_ID }) { result.success(null) }
            }
            "sdrList" -> result.success(candidates().filter { kindOf(it) == Kind.RTLSDR }.map { describe(it) })
            "sdrStart" -> {
                val id = call.argument<String>("id")
                val mode = call.argument<String>("mode") ?: "spectrum"
                val freqHz = call.argument<Number>("freqHz")?.toLong() ?: 100_100_000L
                val rate = call.argument<Int>("rate") ?: 2_048_000
                val freqsHz = call.argument<List<Number>>("freqsHz")?.map { it.toLong() } ?: emptyList()
                val raw = call.argument<Boolean>("raw") ?: false
                val categories = call.argument<List<String>>("categories") ?: Rtl433Categories.ALL_CATEGORIES
                val device = candidates().firstOrNull { it.deviceName == id && kindOf(it) == Kind.RTLSDR }
                if (device == null) {
                    result.success(false)
                } else if (usb.hasPermission(device)) {
                    startSdr(device, mode, freqHz, rate, freqsHz, raw, categories)
                    result.success(true)
                } else {
                    pendingSdr = { startSdr(device, mode, freqHz, rate, freqsHz, raw, categories) }
                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                    val intent = Intent(permissionAction).setPackage(context.packageName)
                    usb.requestPermission(device, PendingIntent.getBroadcast(context, 0, intent, flags))
                    result.success(true)
                }
            }
            "sdrStop" -> {
                sdrGen++
                stopSessions(listOf(SDR_ID)) { result.success(null) }
            }
            else -> result.notImplemented()
        }
    }

    private fun key(d: UsbDevice): Int = (d.vendorId shl 16) or d.productId

    private fun findBtInterface(device: UsbDevice): UsbInterface? {
        for (i in 0 until device.interfaceCount) {
            val f = device.getInterface(i)
            if (f.interfaceClass != 0xE0) continue
            for (e in 0 until f.endpointCount) {
                val ep = f.getEndpoint(e)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_INT && ep.direction == UsbConstants.USB_DIR_IN) return f
            }
        }
        return null
    }

    private fun pickInterface(device: UsbDevice, kind: Kind): UsbInterface {
        if (kind == Kind.MT7921) {
            for (i in 0 until device.interfaceCount) {
                val f = device.getInterface(i)
                if (f.interfaceClass != UsbConstants.USB_CLASS_VENDOR_SPEC) continue
                var bulkIn = 0
                var bulkOut = 0
                for (e in 0 until f.endpointCount) {
                    val ep = f.getEndpoint(e)
                    if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                        if (ep.direction == UsbConstants.USB_DIR_IN) bulkIn++ else bulkOut++
                    }
                }
                if (bulkIn >= 2 && bulkOut >= 4) return f
            }
        }
        return device.getInterface(0)
    }

    private fun kindOf(d: UsbDevice): Kind? {
        val k = key(d)
        return when {
            k in MT7612U_IDS -> Kind.MT7612U
            k in MT7921_IDS -> Kind.MT7921
            Rtl8812auRegs.supports(d.vendorId, d.productId) -> Kind.RTL8812AU
            k in RTL8814_IDS -> Kind.RTL8814AU
            k in RTL8821_IDS -> Kind.RTL8821AU
            k in AR9271_IDS -> Kind.AR9271
            k in RT3070_IDS -> Kind.RT3070
            k in RTLSDR_IDS -> Kind.RTLSDR
            k in SERIAL_IDS -> Kind.SERIAL
            else -> null
        }
    }

    private fun candidates(): List<UsbDevice> = usb.deviceList.values.filter { kindOf(it) != null }

    private fun isWifiMonitor(d: UsbDevice): Boolean {
        val k = kindOf(d)
        return k != null && k != Kind.SERIAL && k != Kind.RTLSDR
    }

    private fun describe(d: UsbDevice): Map<String, Any> = mapOf(
        "id" to d.deviceName,
        "vid" to d.vendorId,
        "pid" to d.productId,
        "name" to (d.productName ?: (kindOf(d)?.name ?: "USB WiFi adapter")),
    )

    private fun startAdapter(device: UsbDevice, result: MethodChannel.Result, radioMask: Int) {
        val id = device.deviceName
        if (sessions.containsKey(id)) {
            result.success(true)
            return
        }
        val kind = kindOf(device)
        if (kind == null) {
            result.success(false)
            return
        }
        val conn = usb.openDevice(device)
        if (conn == null) {
            result.success(false)
            return
        }
        val intf = pickInterface(device, kind)
        val s = Session()
        val log: (String) -> Unit = { msg -> main.post { emitStatus(msg, id) } }
        val onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit = { b -> main.post { emitBatch(b, id) } }
        val t = Thread {
            try {
                when (kind) {
                    Kind.MT7612U -> {
                        val fw = FirmwareStore.load(context)
                        val a = Mt7612uAdapter(conn, intf, fw, log, ::phoneWifiChannels)
                        s.stopFn = a::abort
                        a.run(onBatch)
                    }
                    Kind.MT7921 -> {
                        val patch = FirmwareStore.fetch(
                            context, Mt7921Regs.PATCH_FILE,
                            Mt7921Regs.FW_BASE_URL + Mt7921Regs.PATCH_FILE, Mt7921Regs.PATCH_SHA256,
                        )
                        val ram = FirmwareStore.fetch(
                            context, Mt7921Regs.RAM_FILE,
                            Mt7921Regs.FW_BASE_URL + Mt7921Regs.RAM_FILE, Mt7921Regs.RAM_SHA256,
                        )
                        val a = Mt7921Adapter(conn, intf, patch, ram, log)
                        var bt: Mt7921BtAdapter? = null
                        s.stopFn = { a.abort(); bt?.abort() }
                        val btIntf = findBtInterface(device)
                        a.run(onBatch, scanWifi = (radioMask and 0x01) != 0, onReady = {
                            if (btIntf != null && (radioMask and 0x02) != 0) {
                                Thread {
                                    runCatching {
                                        val btFw = FirmwareStore.fetch(
                                            context, Mt7921Regs.BT_FW_FILE,
                                            Mt7921Regs.FW_BASE_URL + Mt7921Regs.BT_FW_FILE, Mt7921Regs.BT_FW_SHA256,
                                        )
                                        val onAdv: (String, String, Int, ByteArray) -> Unit = { mac, name, rssi, adv ->
                                            main.post { emitBle(mac, name, rssi, adv, id) }
                                        }
                                        val b = Mt7921BtAdapter(conn, btIntf, btFw, log, onAdv)
                                        bt = b
                                        b.run()
                                    }.onFailure { log("MT7921-BT: ${it.message}") }
                                }.start()
                            }
                        })
                    }
                    Kind.RTL8812AU -> {
                        val fw = Rtl8812auAdapter.loadFirmware(context)
                        val a = Rtl8812auAdapter(conn, intf, fw, log, rtlForceFirmware())
                        s.stopFn = a::abort
                        a.run(onBatch)
                    }
                    Kind.RTL8814AU -> {
                        val fw = RtlFirmwareStore.load8814a(context)
                        val a = Rtl8814auAdapter(conn, intf, fw, log, rtlForceFirmware())
                        s.stopFn = a::abort
                        a.run(onBatch)
                    }
                    Kind.RTL8821AU -> {
                        val fw = RtlFirmwareStore.load8821a(context)
                        val a = Rtl8821auAdapter(conn, intf, fw, log, rtlForceFirmware())
                        s.stopFn = a::abort
                        a.run(onBatch)
                    }
                    Kind.AR9271 -> {
                        val fw = FirmwareStore.fetch(
                            context,
                            Ar9271Regs.FIRMWARE_FILE,
                            Ar9271Regs.FW_BASE_URL + Ar9271Regs.FIRMWARE_FILE,
                            Ar9271Regs.FIRMWARE_SHA256,
                        )
                        val a = Ar9271Adapter(conn, intf, fw, log)
                        s.stopFn = a::abort
                        a.run(onBatch)
                    }
                    Kind.RT3070 -> {
                        val fw = FirmwareStore.fetch(
                            context,
                            Rt3070Regs.FIRMWARE_FILE,
                            Rt3070Regs.FW_BASE_URL + Rt3070Regs.FIRMWARE_FILE,
                            Rt3070Regs.FIRMWARE_SHA256,
                        )
                        val a = Rt3070Adapter(conn, intf, fw, log)
                        s.stopFn = a::abort
                        a.run(onBatch)
                    }
                    Kind.RTLSDR -> log("RTL-SDR: use SDR controls")
                    Kind.SERIAL -> runSerial(device, conn, intf, log, onBatch, s)
                }
            } catch (e: Exception) {
                main.post { emitStatus("${device.productName ?: kind.name}: ${e.message}", id) }
            } finally {
                try {
                    conn.close()
                } catch (e: Exception) {
                    // Connection already torn down by the OS on detach.
                }
                main.post {
                    if (sessions[id] === s) sessions.remove(id)
                    emitStopped(id)
                }
            }
        }
        t.name = "wifi-adapter $id"
        s.thread = t
        sessions[id] = s
        t.start()
        result.success(true)
    }

    private fun runSerial(
        device: UsbDevice,
        conn: android.hardware.usb.UsbDeviceConnection,
        intf: android.hardware.usb.UsbInterface,
        log: (String) -> Unit,
        onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit,
        session: Session,
    ) {
        val port = SerialLines.open(device, conn)
        if (device.productId == 0x205a) {
            val s = FreeWiliScanner(port, intf, log)
            session.stopFn = s::abort
            s.run(onBatch)
            return
        }
        if (probeIsMarauder(port)) {
            val s = MarauderScanner(port, intf, log)
            session.stopFn = s::abort
            s.run(onBatch)
        } else {
            val s = GhostEspScanner(port, intf, log)
            session.stopFn = s::abort
            s.run(onBatch)
        }
    }

    // Send help and sniff the banner: Marauder answers with "marauder"/"sniffbeacon", GhostESP does not.
    private fun probeIsMarauder(port: com.hoho.android.usbserial.driver.UsbSerialPort): Boolean {
        val lines = SerialLines(port)
        lines.send("help\n")
        val end = System.currentTimeMillis() + 1200
        while (System.currentTimeMillis() < end) {
            val l = lines.readLine(300)?.lowercase() ?: continue
            if ("marauder" in l || "sniffbeacon" in l) return true
            if ("ghost" in l) return false
        }
        return false
    }

    private fun stopSessions(ids: List<String>, then: (() -> Unit)? = null) {
        val workers = ids.mapNotNull { sessions.remove(it) }.mapNotNull { s ->
            s.stopFn?.invoke()
            s.thread?.also { it.interrupt() }
        }
        if (then == null) return
        if (workers.isEmpty()) {
            then()
            return
        }
        Thread {
            workers.forEach { it.join(2000) }
            main.post(then)
        }.start()
    }

    private fun emitStatus(msg: String, id: String? = null) {
        sink?.success(if (id == null) mapOf("status" to msg) else mapOf("status" to msg, "id" to id))
    }

    private fun emitStopped(id: String) {
        sink?.success(mapOf("stopped" to true, "id" to id))
    }

    private fun emitBle(mac: String, name: String, rssi: Int, adv: ByteArray, id: String) {
        sink?.success(
            mapOf(
                "id" to id,
                "ble" to listOf(
                    mapOf("mac" to mac, "name" to name, "rssi" to rssi, "adv" to adv),
                ),
            ),
        )
    }

    private fun emitAttach(attached: Boolean, device: UsbDevice) {
        main.post { eventSink?.success(mapOf("attached" to attached, "device" to describe(device))) }
    }

    private fun startSdr(device: UsbDevice, mode: String, freqHz: Long, rate: Int, hopHz: List<Long> = emptyList(), raw: Boolean = false, categories: List<String> = Rtl433Categories.ALL_CATEGORIES) {
        val gen = ++sdrGen
        stopSessions(listOf(SDR_ID)) { if (gen == sdrGen) launchSdr(device, mode, freqHz, rate, hopHz, raw, categories) }
    }

    private fun launchSdr(device: UsbDevice, mode: String, freqHz: Long, rate: Int, hopHz: List<Long>, raw: Boolean, categories: List<String>) {
        val conn = usb.openDevice(device)
        if (conn == null) {
            main.post { emitStatus("RTL-SDR: open failed") }
            return
        }
        val intf = device.getInterface(0)
        val log: (String) -> Unit = { msg -> main.post { sdrSink?.success(mapOf("status" to msg)) } }
        val m = when (mode) {
            "adsb" -> SdrEngine.Mode.ADSB
            "tpms" -> SdrEngine.Mode.TPMS
            "rtl433" -> SdrEngine.Mode.RTL433
            else -> SdrEngine.Mode.SPECTRUM
        }
        val eng = SdrEngine(
            conn, intf, log,
            onSpectrum = { power, c, r ->
                val arr = DoubleArray(power.size) { power[it].toDouble() }
                main.post { sdrSink?.success(mapOf("power" to arr, "centerHz" to c, "rate" to r)) }
            },
            onDetection = { d -> main.post { sdrSink?.success(mapOf("detection" to d)) } },
        )
        val s = Session()
        s.stopFn = eng::abort
        val t = Thread {
            try {
                eng.run(m, freqHz, rate, hopHz, raw, categories)
            } catch (e: Exception) {
                main.post { emitStatus("RTL-SDR: ${e.message}") }
            } finally {
                try {
                    conn.close()
                } catch (e: Exception) {
                    // already torn down
                }
                main.post { if (sessions[SDR_ID] === s) sessions.remove(SDR_ID) }
            }
        }
        t.name = "sdr"
        s.thread = t
        sessions[SDR_ID] = s
        t.start()
    }

    private fun emitBatch(batch: List<Mt7612uAdapter.ApSighting>, id: String) {
        sink?.success(
            mapOf(
                "id" to id,
                "aps" to batch.map {
                    mapOf(
                        "bssid" to it.bssid,
                        "ssid" to it.ssid,
                        "rssi" to it.rssi,
                        "channel" to it.channel,
                        "frequency" to it.frequency,
                        "client" to it.client,
                        "authMode" to it.authMode,
                    )
                },
            ),
        )
    }

    @Suppress("DEPRECATION")
    private fun deviceExtra(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }

    private companion object {
        const val SDR_ID = "sdr"
        val MT7612U_IDS = setOf(0x0e8d7612, 0x0e8d7610)
        val MT7921_IDS = setOf(0x0e8d7961)
        val AR9271_IDS = setOf(0x0cf39271, 0x0cf31006, 0x07b89271)
        val RT3070_IDS = setOf(0x148f3070, 0x148f5370, 0x148f5372)
        val RTLSDR_IDS = setOf(0x0bda2838, 0x0bda2832)
        val SERIAL_IDS = setOf(0x10c4ea60, 0x303a1001, 0x093c205a)
        val RTL8814_IDS = setOf(
            0x056e400b, 0x056e400d, 0x08469054, 0x0b051817, 0x0b051852, 0x0b051853, 0x0e660026,
            0x2001331a, 0x20f4809a, 0x20f4809b, 0x23570106, 0x7392a834, 0x7392a833,
        )
        val RTL8821_IDS = setOf(
            0x0bda0811, 0x0bda8811, 0x0bdaa811,
            0x04110242, 0x0411029b, 0x04bb0953, 0x056e4007, 0x056e400e, 0x056e400f, 0x08469052,
            0x0e660023, 0x20013314, 0x20013318, 0x2019ab32, 0x20f4804b, 0x2357011e, 0x2357011f,
            0x23570120, 0x38236249, 0x7392a811, 0x7392a812, 0x7392a813, 0x7392b611,
        )
    }
}

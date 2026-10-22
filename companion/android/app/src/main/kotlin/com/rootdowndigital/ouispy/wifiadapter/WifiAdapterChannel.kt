package com.rootdowndigital.ouispy.wifiadapter

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbDevice
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

    private enum class Kind { MT7612U, RTL8812AU, RTL8814AU, RTL8821AU, AR9271, SERIAL }

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
    private var sink: EventChannel.EventSink? = null
    private var eventSink: EventChannel.EventSink? = null
    private var worker: Thread? = null
    @Volatile private var stopFn: (() -> Unit)? = null
    private var pending: MethodChannel.Result? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val device = deviceExtra(intent)
            when (intent.action) {
                permissionAction -> {
                    val result = pending
                    pending = null
                    if (result == null) return
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    if (granted && device != null) startAdapter(device, result) else result.success(false)
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED ->
                    if (device != null && isWifiMonitor(device)) emitAttach(true, device)
                UsbManager.ACTION_USB_DEVICE_DETACHED ->
                    if (device != null && isWifiMonitor(device)) emitAttach(false, device)
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
        stopAdapter()
        try {
            context.unregisterReceiver(receiver)
        } catch (e: IllegalArgumentException) {
            // Receiver was never registered; nothing to remove.
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> result.success(candidates().map { describe(it) })
            "start" -> {
                val id = call.argument<String>("id")
                val device = candidates().firstOrNull { it.deviceName == id }
                if (device == null) {
                    result.success(false)
                } else if (usb.hasPermission(device)) {
                    startAdapter(device, result)
                } else {
                    pending?.success(false)
                    pending = result
                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                    val intent = Intent(permissionAction).setPackage(context.packageName)
                    usb.requestPermission(device, PendingIntent.getBroadcast(context, 0, intent, flags))
                }
            }
            "stop" -> {
                stopAdapter()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun key(d: UsbDevice): Int = (d.vendorId shl 16) or d.productId

    private fun kindOf(d: UsbDevice): Kind? {
        val k = key(d)
        return when {
            k in MT7612U_IDS -> Kind.MT7612U
            Rtl8812auRegs.supports(d.vendorId, d.productId) -> Kind.RTL8812AU
            k in RTL8814_IDS -> Kind.RTL8814AU
            k in RTL8821_IDS -> Kind.RTL8821AU
            k in AR9271_IDS -> Kind.AR9271
            k in SERIAL_IDS -> Kind.SERIAL
            else -> null
        }
    }

    private fun candidates(): List<UsbDevice> = usb.deviceList.values.filter { kindOf(it) != null }

    private fun isWifiMonitor(d: UsbDevice): Boolean {
        val k = kindOf(d)
        return k != null && k != Kind.SERIAL
    }

    private fun describe(d: UsbDevice): Map<String, Any> = mapOf(
        "id" to d.deviceName,
        "vid" to d.vendorId,
        "pid" to d.productId,
        "name" to (d.productName ?: (kindOf(d)?.name ?: "USB WiFi adapter")),
    )

    private fun startAdapter(device: UsbDevice, result: MethodChannel.Result) {
        stopAdapter()
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
        val intf = device.getInterface(0)
        val log: (String) -> Unit = { msg -> main.post { emitStatus(msg) } }
        val onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit = { b -> main.post { emitBatch(b) } }
        val t = Thread {
            try {
                when (kind) {
                    Kind.MT7612U -> {
                        val fw = FirmwareStore.load(context)
                        val a = Mt7612uAdapter(conn, intf, fw, log, ::phoneWifiChannels)
                        stopFn = a::abort
                        a.run(onBatch)
                    }
                    Kind.RTL8812AU -> {
                        val fw = Rtl8812auAdapter.loadFirmware(context)
                        val a = Rtl8812auAdapter(conn, intf, fw, log)
                        stopFn = a::abort
                        a.run(onBatch)
                    }
                    Kind.RTL8814AU -> {
                        val fw = RtlFirmwareStore.load8814a(context)
                        val a = Rtl8814auAdapter(conn, intf, fw, log)
                        stopFn = a::abort
                        a.run(onBatch)
                    }
                    Kind.RTL8821AU -> {
                        val fw = RtlFirmwareStore.load8821a(context)
                        val a = Rtl8821auAdapter(conn, intf, fw, log)
                        stopFn = a::abort
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
                        stopFn = a::abort
                        a.run(onBatch)
                    }
                    Kind.SERIAL -> runSerial(device, conn, intf, log, onBatch)
                }
            } catch (e: Exception) {
                main.post { emitStatus("${device.productName ?: kind.name}: ${e.message}") }
            } finally {
                try {
                    conn.close()
                } catch (e: Exception) {
                    // Connection already torn down by the OS on detach.
                }
            }
        }
        t.name = "wifi-adapter"
        worker = t
        t.start()
        result.success(true)
    }

    private fun runSerial(
        device: UsbDevice,
        conn: android.hardware.usb.UsbDeviceConnection,
        intf: android.hardware.usb.UsbInterface,
        log: (String) -> Unit,
        onBatch: (List<Mt7612uAdapter.ApSighting>) -> Unit,
    ) {
        val port = SerialLines.open(device, conn)
        if (device.productId == 0x205a) {
            val s = FreeWiliScanner(port, intf, log)
            stopFn = s::abort
            s.run(onBatch)
            return
        }
        if (probeIsMarauder(port)) {
            val s = MarauderScanner(port, intf, log)
            stopFn = s::abort
            s.run(onBatch)
        } else {
            val s = GhostEspScanner(port, intf, log)
            stopFn = s::abort
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

    private fun stopAdapter() {
        stopFn?.invoke()
        stopFn = null
        worker?.let { w ->
            w.interrupt()
            w.join(2000)
        }
        worker = null
    }

    private fun emitStatus(msg: String) {
        sink?.success(mapOf("status" to msg))
    }

    private fun emitAttach(attached: Boolean, device: UsbDevice) {
        main.post { eventSink?.success(mapOf("attached" to attached, "device" to describe(device))) }
    }

    private fun emitBatch(batch: List<Mt7612uAdapter.ApSighting>) {
        sink?.success(
            mapOf(
                "aps" to batch.map {
                    mapOf(
                        "bssid" to it.bssid,
                        "ssid" to it.ssid,
                        "rssi" to it.rssi,
                        "channel" to it.channel,
                        "frequency" to it.frequency,
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
        val MT7612U_IDS = setOf(0x0e8d7612, 0x0e8d7610)
        val AR9271_IDS = setOf(0x0cf39271, 0x0cf31006, 0x07b89271)
        val SERIAL_IDS = setOf(0x10c4ea60, 0x303a1001, 0x093c205a)
        val RTL8814_IDS = setOf(
            0x056e400b, 0x056e400d, 0x08469054, 0x0b051817, 0x0b051852, 0x0b051853, 0x0e660026,
            0x2001331a, 0x20f4809a, 0x20f4809b, 0x23570106, 0x7392a834, 0x7392a833,
        )
        val RTL8821_IDS = setOf(
            0x04110242, 0x0411029b, 0x04bb0953, 0x056e4007, 0x056e400e, 0x056e400f, 0x08469052,
            0x0e660023, 0x20013314, 0x20013318, 0x2019ab32, 0x20f4804b, 0x2357011e, 0x2357011f,
            0x23570120, 0x38236249, 0x7392a811, 0x7392a812, 0x7392a813, 0x7392b611,
        )
    }
}

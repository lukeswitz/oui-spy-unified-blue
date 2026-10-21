package com.rootdowndigital.ouispy

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.hoho.android.usbserial.driver.UsbSerialDriver
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import com.hoho.android.usbserial.util.SerialInputOutputManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class UsbLinkChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val main = Handler(Looper.getMainLooper())
    private val writer = Executors.newSingleThreadExecutor()
    private val permissionAction = "${context.packageName}.USB_PERMISSION"
    private var dataSink: EventChannel.EventSink? = null
    private var eventSink: EventChannel.EventSink? = null
    private var port: UsbSerialPort? = null
    private var io: SerialInputOutputManager? = null
    private var openDeviceName: String? = null
    private var pendingOpen: Pair<UsbSerialDriver, MethodChannel.Result>? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val device = deviceExtra(intent) ?: return
            when (intent.action) {
                permissionAction -> {
                    val pending = pendingOpen ?: return
                    if (pending.first.device.deviceName != device.deviceName) return
                    pendingOpen = null
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    if (granted) openPort(pending.first, pending.second) else pending.second.success(false)
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    if (device.deviceName == openDeviceName) closePort()
                    describe(device)?.let { emitEvent(false, it) }
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> describe(device)?.let { emitEvent(true, it) }
            }
        }
    }

    init {
        MethodChannel(messenger, "ouispy/usb").setMethodCallHandler(this)
        EventChannel(messenger, "ouispy/usb/data").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                dataSink = events
            }

            override fun onCancel(arguments: Any?) {
                dataSink = null
            }
        })
        EventChannel(messenger, "ouispy/usb/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        val filter = IntentFilter().apply {
            addAction(permissionAction)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
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
        describe(device)?.let { emitEvent(true, it) }
    }

    fun dispose() {
        closePort()
        try {
            context.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
        }
        writer.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> result.success(drivers().map { describeDriver(it) })
            "open" -> {
                val id = call.argument<String>("id")
                val driver = drivers().firstOrNull { it.device.deviceName == id }
                if (driver == null) {
                    result.success(false)
                } else if (usb.hasPermission(driver.device)) {
                    openPort(driver, result)
                } else {
                    pendingOpen?.second?.success(false)
                    pendingOpen = Pair(driver, result)
                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                    val intent = Intent(permissionAction).setPackage(context.packageName)
                    usb.requestPermission(driver.device, PendingIntent.getBroadcast(context, 0, intent, flags))
                }
            }
            "write" -> {
                val bytes = call.arguments as? ByteArray
                val p = port
                if (bytes == null || p == null) {
                    result.error("usb_write", "port not open", null)
                    return
                }
                writer.execute {
                    try {
                        p.write(bytes, WRITE_TIMEOUT_MS)
                        main.post { result.success(null) }
                    } catch (e: Exception) {
                        main.post { result.error("usb_write", e.message, null) }
                    }
                }
            }
            "close" -> {
                closePort()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun drivers(): List<UsbSerialDriver> = UsbSerialProber.getDefaultProber().findAllDrivers(usb)

    private fun describe(device: UsbDevice): Map<String, Any>? {
        val driver = UsbSerialProber.getDefaultProber().probeDevice(device) ?: return null
        return describeDriver(driver)
    }

    private fun describeDriver(driver: UsbSerialDriver): Map<String, Any> {
        val d = driver.device
        return mapOf(
            "id" to d.deviceName,
            "vid" to d.vendorId,
            "pid" to d.productId,
            "name" to (d.productName ?: ""),
        )
    }

    private fun openPort(driver: UsbSerialDriver, result: MethodChannel.Result) {
        closePort()
        val connection = usb.openDevice(driver.device)
        if (connection == null) {
            result.success(false)
            return
        }
        val p = driver.ports.firstOrNull()
        if (p == null) {
            connection.close()
            result.success(false)
            return
        }
        try {
            p.open(connection)
            p.setParameters(BAUD, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE)
            p.dtr = false
            p.rts = false
        } catch (e: Exception) {
            try {
                p.close()
            } catch (_: Exception) {
            }
            result.error("usb_open", e.message, null)
            return
        }
        port = p
        openDeviceName = driver.device.deviceName
        val manager = SerialInputOutputManager(p, object : SerialInputOutputManager.Listener {
            override fun onNewData(data: ByteArray) {
                main.post { dataSink?.success(data) }
            }

            override fun onRunError(e: Exception) {
                main.post {
                    if (port === p) {
                        closePort()
                        dataSink?.endOfStream()
                    }
                }
            }
        })
        manager.readBufferSize = READ_BUFFER
        manager.start()
        io = manager
        result.success(true)
    }

    private fun closePort() {
        io?.stop()
        io = null
        val p = port
        port = null
        openDeviceName = null
        if (p != null) {
            try {
                p.close()
            } catch (_: Exception) {
            }
            main.post { dataSink?.endOfStream() }
        }
    }

    private fun emitEvent(attached: Boolean, device: Map<String, Any>) {
        main.post { eventSink?.success(mapOf("attached" to attached, "device" to device)) }
    }

    @Suppress("DEPRECATION")
    private fun deviceExtra(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }

    private companion object {
        const val BAUD = 115200
        const val WRITE_TIMEOUT_MS = 2000
        const val READ_BUFFER = 16384
    }
}

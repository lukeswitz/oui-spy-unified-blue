package com.rootdowndigital.ouispy

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

@SuppressLint("MissingPermission")
class PhoneScanChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val method = MethodChannel(messenger, "ouispy/phone_scan")
    private val events = EventChannel(messenger, "ouispy/phone_scan/results")
    private var sink: EventChannel.EventSink? = null
    private var callback: ScanCallback? = null

    init {
        method.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                if (Build.VERSION.SDK_INT < 33) {
                    result.success(false)
                    return
                }
                try {
                    start(call.argument<Int>("mode") ?: ScanSettings.SCAN_MODE_LOW_LATENCY)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("scan_start", e.message, null)
                }
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun dispose() {
        stop()
        method.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    private fun scanner() =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager)
            .adapter?.bluetoothLeScanner

    private fun start(mode: Int) {
        stop()
        val le = scanner() ?: throw IllegalStateException("Bluetooth scanner unavailable")
        val filters = (1..255).map {
            ScanFilter.Builder().setAdvertisingDataTypeWithData(it, ByteArray(0), ByteArray(0)).build()
        }
        val settings = ScanSettings.Builder()
            .setScanMode(mode)
            .setLegacy(false)
            .setPhy(ScanSettings.PHY_LE_ALL_SUPPORTED)
            .build()
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                sink?.success(encode(result))
            }

            override fun onScanFailed(errorCode: Int) {
                sink?.error("scan_failed", errorCode.toString(), null)
            }
        }
        le.startScan(filters, settings, cb)
        callback = cb
    }

    private fun stop() {
        val cb = callback ?: return
        callback = null
        try {
            scanner()?.stopScan(cb)
        } catch (_: Exception) {
        }
    }

    private fun encode(r: ScanResult): Map<String, Any?> {
        val rec = r.scanRecord
        val mfg = HashMap<Int, ByteArray>()
        rec?.manufacturerSpecificData?.let { a ->
            for (i in 0 until a.size()) mfg[a.keyAt(i)] = a.valueAt(i)
        }
        val svcData = HashMap<String, ByteArray>()
        rec?.serviceData?.forEach { (k, v) -> svcData[k.toString()] = v }
        val look = rec?.advertisingDataMap?.get(0x19)
        return mapOf(
            "id" to r.device.address,
            "name" to (rec?.deviceName ?: ""),
            "rssi" to r.rssi,
            "connectable" to r.isConnectable,
            "tx" to rec?.txPowerLevel?.takeIf { it != Int.MIN_VALUE },
            "appearance" to look?.takeIf { it.size == 2 }
                ?.let { (it[0].toInt() and 0xFF) or ((it[1].toInt() and 0xFF) shl 8) },
            "mfg" to mfg,
            "svcData" to svcData,
            "svc" to (rec?.serviceUuids?.map { it.toString() } ?: emptyList<String>()),
        )
    }
}

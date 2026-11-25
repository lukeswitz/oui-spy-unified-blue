// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

package com.rootdowndigital.ouispy

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.net.wifi.aware.AttachCallback
import android.net.wifi.aware.DiscoverySessionCallback
import android.net.wifi.aware.PeerHandle
import android.net.wifi.aware.SubscribeConfig
import android.net.wifi.aware.SubscribeDiscoverySession
import android.net.wifi.aware.WifiAwareManager
import android.net.wifi.aware.WifiAwareSession
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
    private val nanEvents = EventChannel(messenger, "ouispy/phone_scan/nan")
    private var sink: EventChannel.EventSink? = null
    private var nanSink: EventChannel.EventSink? = null
    private var callback: ScanCallback? = null
    private var nanSession: WifiAwareSession? = null
    private var nanSubscribe: SubscribeDiscoverySession? = null

    init {
        method.setMethodCallHandler(this)
        events.setStreamHandler(this)
        nanEvents.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
                nanSink = eventSink
            }

            override fun onCancel(arguments: Any?) {
                nanSink = null
            }
        })
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
            "wifiOdid" -> {
                try {
                    result.success(wifiOdid())
                } catch (e: SecurityException) {
                    result.error("wifi_odid", e.message, null)
                }
            }
            "nanStart" -> {
                try {
                    result.success(nanStart())
                } catch (e: SecurityException) {
                    result.error("nan_start", e.message, null)
                }
            }
            "nanStop" -> {
                nanStop()
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
        nanStop()
        method.setMethodCallHandler(null)
        events.setStreamHandler(null)
        nanEvents.setStreamHandler(null)
    }

    private var nanWanted = false
    private var nanReceiver: BroadcastReceiver? = null

    private fun nanStart(): Boolean {
        if (Build.VERSION.SDK_INT < 26) return false
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_AWARE)) return false
        val mgr = context.getSystemService(Context.WIFI_AWARE_SERVICE) as? WifiAwareManager ?: return false
        nanWanted = true
        if (nanReceiver == null) {
            val r = object : BroadcastReceiver() {
                override fun onReceive(c: Context, intent: Intent) {
                    if (!nanWanted) return
                    if (mgr.isAvailable) {
                        if (nanSession == null) nanAttach(mgr)
                    } else {
                        nanSubscribe = null
                        nanSession = null
                    }
                }
            }
            val filter = IntentFilter(WifiAwareManager.ACTION_WIFI_AWARE_STATE_CHANGED)
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(r, filter)
            }
            nanReceiver = r
        }
        if (mgr.isAvailable && nanSession == null) nanAttach(mgr)
        return true
    }

    private var nanAttaching = false

    private fun nanAttach(mgr: WifiAwareManager) {
        if (Build.VERSION.SDK_INT < 26 || nanAttaching) return
        nanAttaching = true
        mgr.attach(object : AttachCallback() {
            override fun onAttached(session: WifiAwareSession) {
                nanAttaching = false
                if (!nanWanted) {
                    session.close()
                    return
                }
                nanSession = session
                val cfg = SubscribeConfig.Builder()
                    .setServiceName("org.opendroneid.remoteid")
                    .setSubscribeType(SubscribeConfig.SUBSCRIBE_TYPE_PASSIVE)
                    .build()
                session.subscribe(cfg, object : DiscoverySessionCallback() {
                    override fun onSubscribeStarted(s: SubscribeDiscoverySession) {
                        nanSubscribe = s
                    }

                    override fun onServiceDiscovered(peer: PeerHandle, ssi: ByteArray, matchFilter: List<ByteArray>) {
                        nanSink?.success(mapOf("peer" to peer.hashCode(), "ssi" to ssi))
                    }
                }, null)
            }

            override fun onAttachFailed() {
                nanAttaching = false
                nanSession = null
            }
        }, null)
    }

    private fun nanStop() {
        nanWanted = false
        nanReceiver?.let { context.unregisterReceiver(it) }
        nanReceiver = null
        if (Build.VERSION.SDK_INT < 26) return
        nanSubscribe?.close()
        nanSubscribe = null
        nanSession?.close()
        nanSession = null
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

    private fun wifiOdid(): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < 30) return emptyList()
        val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val out = ArrayList<Map<String, Any>>()
        for (r in wm.scanResults) {
            for (ie in r.informationElements) {
                if (ie.id != 221) continue
                val buf = ie.bytes.duplicate()
                val b = ByteArray(buf.remaining())
                buf.get(b)
                if (b.size < 5) continue
                val oui = ((b[0].toInt() and 0xFF) shl 16) or ((b[1].toInt() and 0xFF) shl 8) or (b[2].toInt() and 0xFF)
                if ((oui == 0xFA0BBC || oui == 0x903AE6) && (b[3].toInt() and 0xFF) == 0x0D) {
                    out.add(mapOf("bssid" to r.BSSID, "rssi" to r.level, "freq" to r.frequency, "ie" to b))
                }
            }
        }
        return out
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

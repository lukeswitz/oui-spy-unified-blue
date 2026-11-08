package com.rootdowndigital.ouispy

import android.annotation.SuppressLint
import android.content.Context
import android.location.GnssStatus
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.telephony.CellIdentityGsm
import android.telephony.CellIdentityLte
import android.telephony.CellIdentityNr
import android.telephony.CellIdentityWcdma
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoWcdma
import android.telephony.TelephonyManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

@SuppressLint("MissingPermission")
class PhoneWatchChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val method = MethodChannel(messenger, "ouispy/phone_watch")
    private val events = EventChannel(messenger, "ouispy/phone_watch/gnss")
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var gnss: GnssStatus.Callback? = null
    private var lastSent = 0L

    init {
        method.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "servingCell" -> try {
                result.success(servingCell())
            } catch (e: SecurityException) {
                result.success(null)
            } catch (e: Exception) {
                result.error("cell", e.message, null)
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun plmn(mcc: Int, mnc: Int, mccS: String?, mncS: String?): String =
        if (Build.VERSION.SDK_INT >= 28) "${mccS ?: ""}-${mncS ?: ""}" else "$mcc-$mnc"

    @Suppress("DEPRECATION")
    private fun servingCell(): Map<String, Any?>? {
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager ?: return null
        val cell = tm.allCellInfo?.firstOrNull { it.isRegistered } ?: return null
        return when (cell) {
            is CellInfoLte -> {
                val id: CellIdentityLte = cell.cellIdentity
                val p = if (Build.VERSION.SDK_INT >= 28) plmn(0, 0, id.mccString, id.mncString) else plmn(id.mcc, id.mnc, null, null)
                mapOf("rat" to "LTE", "plmn" to p, "area" to id.tac, "cid" to id.ci.toLong(), "dbm" to cell.cellSignalStrength.dbm)
            }
            is CellInfoGsm -> {
                val id: CellIdentityGsm = cell.cellIdentity
                val p = if (Build.VERSION.SDK_INT >= 28) plmn(0, 0, id.mccString, id.mncString) else plmn(id.mcc, id.mnc, null, null)
                mapOf("rat" to "GSM", "plmn" to p, "area" to id.lac, "cid" to id.cid.toLong(), "dbm" to cell.cellSignalStrength.dbm)
            }
            is CellInfoWcdma -> {
                val id: CellIdentityWcdma = cell.cellIdentity
                val p = if (Build.VERSION.SDK_INT >= 28) plmn(0, 0, id.mccString, id.mncString) else plmn(id.mcc, id.mnc, null, null)
                mapOf("rat" to "WCDMA", "plmn" to p, "area" to id.lac, "cid" to id.cid.toLong(), "dbm" to cell.cellSignalStrength.dbm)
            }
            else -> if (Build.VERSION.SDK_INT >= 29 && cell is CellInfoNr) {
                val id = cell.cellIdentity as CellIdentityNr
                mapOf("rat" to "NR", "plmn" to plmn(0, 0, id.mccString, id.mncString), "area" to id.tac, "cid" to id.nci, "dbm" to cell.cellSignalStrength.dbm)
            } else null
        }
    }

    @Suppress("DEPRECATION")
    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink
        if (Build.VERSION.SDK_INT < 24) return
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return
        val cb = object : GnssStatus.Callback() {
            override fun onSatelliteStatusChanged(status: GnssStatus) {
                val now = SystemClock.elapsedRealtime()
                if (now - lastSent < 1000) return
                lastSent = now
                val cn0 = ArrayList<Double>()
                for (i in 0 until status.satelliteCount) {
                    if (status.usedInFix(i)) cn0.add(status.getCn0DbHz(i).toDouble())
                }
                sink?.success(mapOf("t" to System.currentTimeMillis(), "sats" to status.satelliteCount, "cn0" to cn0))
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= 30) lm.registerGnssStatusCallback(context.mainExecutor, cb)
            else lm.registerGnssStatusCallback(cb, main)
            gnss = cb
        } catch (e: SecurityException) {
            eventSink.error("gnss", e.message, null)
        }
    }

    override fun onCancel(arguments: Any?) {
        stopGnss()
        sink = null
    }

    private fun stopGnss() {
        val cb = gnss ?: return
        (context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager)?.unregisterGnssStatusCallback(cb)
        gnss = null
    }

    fun dispose() {
        stopGnss()
        sink = null
        method.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }
}

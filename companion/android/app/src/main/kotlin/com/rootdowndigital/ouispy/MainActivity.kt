package com.rootdowndigital.ouispy

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.rootdowndigital.ouispy.wifiadapter.WifiAdapterChannel

class MainActivity : FlutterActivity() {
    private var usbLink: UsbLinkChannel? = null
    private var wifiAdapter: WifiAdapterChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startService(Intent(this, KillTaskService::class.java))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        usbLink = UsbLinkChannel(applicationContext, messenger)
        wifiAdapter = WifiAdapterChannel(applicationContext, messenger)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        usbLink?.onAttachIntent(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        usbLink?.dispose()
        usbLink = null
        wifiAdapter?.dispose()
        wifiAdapter = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

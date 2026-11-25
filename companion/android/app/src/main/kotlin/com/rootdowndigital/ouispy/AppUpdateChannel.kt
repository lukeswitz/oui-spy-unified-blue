// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

package com.rootdowndigital.ouispy

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class AppUpdateChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "oui_spy/app_update")

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installApk" -> try {
                result.success(installApk(call.argument<String>("path")))
            } catch (e: Exception) {
                result.error("install", e.message, null)
            }
            else -> result.notImplemented()
        }
    }

    private fun installApk(path: String?): String {
        val updates = File(context.cacheDir, "updates").canonicalFile
        val apk = File(path ?: throw IllegalArgumentException("no path")).canonicalFile
        require(apk.parentFile == updates && apk.name.endsWith(".apk") && apk.isFile) {
            "not a downloaded update"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !context.packageManager.canRequestPackageInstalls()) {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            return "permission"
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.apkprovider", apk)
        context.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        return "started"
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}

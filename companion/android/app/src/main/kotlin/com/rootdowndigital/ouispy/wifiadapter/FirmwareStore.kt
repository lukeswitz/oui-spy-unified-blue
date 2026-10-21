package com.rootdowndigital.ouispy.wifiadapter

import android.content.Context
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

// Downloads MT7612U MCU firmware from linux-firmware once, verifies SHA-256, caches it.
internal object FirmwareStore {

    class Blobs(val romPatch: ByteArray, val firmware: ByteArray)

    fun load(ctx: Context): Blobs {
        val patch = ensure(ctx, Mt76Regs.ROM_PATCH_FILE, Mt76Regs.ROM_PATCH_SHA256)
        val fw = ensure(ctx, Mt76Regs.FIRMWARE_FILE, Mt76Regs.FIRMWARE_SHA256)
        return Blobs(patch, fw)
    }

    private fun ensure(ctx: Context, name: String, wantSha256: String): ByteArray =
        fetch(ctx, name, Mt76Regs.FW_BASE_URL + name, wantSha256)

    // Generic cache+hash-pinned fetch, used by AR9271 and any other single-blob chip.
    fun fetch(ctx: Context, name: String, url: String, wantSha256: String): ByteArray {
        val dir = File(ctx.cacheDir, "wifi_fw").apply { mkdirs() }
        val f = File(dir, name)
        if (f.exists()) {
            val have = f.readBytes()
            if (sha256(have) == wantSha256) return have
            f.delete()
        }
        val bytes = download(url)
        val got = sha256(bytes)
        if (got != wantSha256) {
            throw IllegalStateException("$name sha256 $got != expected $wantSha256")
        }
        f.writeBytes(bytes)
        return bytes
    }

    private fun download(url: String): ByteArray {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15000
            readTimeout = 30000
            requestMethod = "GET"
            setRequestProperty("User-Agent", "oui-spy-companion/1.0")
        }
        try {
            val code = conn.responseCode
            if (code != 200) throw IllegalStateException("download $url HTTP $code")
            return conn.inputStream.use { it.readBytes() }
        } finally {
            conn.disconnect()
        }
    }

    private fun sha256(b: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }
}

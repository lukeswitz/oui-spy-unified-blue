package com.rootdowndigital.ouispy.wifiadapter

import android.content.Context
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

// Downloads rtw88 firmware (linux-firmware) and the BSD-3-Clause PHY init tables (Linux rtw88, pinned commit) once, verifies SHA-256, caches them.
internal object RtlFirmwareStore {

    class Blobs(val firmware: ByteArray, val tables: String)

    private const val FW_BASE_URL =
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtw88/"
    private const val TBL_BASE_URL = "https://raw.githubusercontent.com/torvalds/linux/"
    private const val TBL_DIR = "/drivers/net/wireless/realtek/rtw88/"

    const val FW_8814A_FILE = "rtw8814a_fw.bin"
    const val FW_8814A_SHA256 = "aa6bf9d62b2d2d8a37254fd6d917ba2839888cdedc21850d4481874cb1d3d7cb"
    const val TBL_8814A_FILE = "rtw8814a_table.c"
    const val TBL_8814A_COMMIT = "e38246889cc9f8497c8d7413b73856ae1634322d"
    const val TBL_8814A_SHA256 = "40418d3774023b8bdcc17e377ed302ecac03c786a7500c9ee3faac955d40451a"

    const val FW_8821A_FILE = "rtw8821a_fw.bin"
    const val FW_8821A_SHA256 = "4693ece655044d96f81bd3f3e8db14dc352b493219c4fd0a75788a6fbd9eac3c"
    const val TBL_8821A_FILE = "rtw8821a_table.c"
    const val TBL_8821A_COMMIT = "4b81da5cd2b4c7231272216639bacecc818d8b51"
    const val TBL_8821A_SHA256 = "08fb956aaa71ae0df8651f73c847922bedcfe44c695cdc6867bd3a3900ef2393"

    fun load8814a(ctx: Context): Blobs = Blobs(
        ensure(ctx, FW_8814A_FILE, FW_BASE_URL + FW_8814A_FILE, FW_8814A_SHA256),
        String(
            ensure(ctx, TBL_8814A_FILE, TBL_BASE_URL + TBL_8814A_COMMIT + TBL_DIR + TBL_8814A_FILE, TBL_8814A_SHA256),
            Charsets.US_ASCII,
        ),
    )

    fun load8821a(ctx: Context): Blobs = Blobs(
        ensure(ctx, FW_8821A_FILE, FW_BASE_URL + FW_8821A_FILE, FW_8821A_SHA256),
        String(
            ensure(ctx, TBL_8821A_FILE, TBL_BASE_URL + TBL_8821A_COMMIT + TBL_DIR + TBL_8821A_FILE, TBL_8821A_SHA256),
            Charsets.US_ASCII,
        ),
    )

    private fun ensure(ctx: Context, name: String, url: String, wantSha256: String): ByteArray {
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
            readTimeout = 60000
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

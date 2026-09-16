package com.cinematy.tv

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.cinematy.tv/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "deviceInfo" -> {
                    val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: "unknown"
                    result.success(mapOf(
                        "id" to androidId,
                        "name" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                        "model" to Build.MODEL,
                        "manufacturer" to Build.MANUFACTURER
                    ))
                }
                "openTelegram" -> {
                    val username = (call.argument<String>("username") ?: "mooo5").removePrefix("@")
                    try {
                        val tg = Intent(Intent.ACTION_VIEW, Uri.parse("tg://resolve?domain=$username"))
                        tg.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(tg)
                        result.success(true)
                    } catch (_: Exception) {
                        try {
                            val web = Intent(Intent.ACTION_VIEW, Uri.parse("https://t.me/$username"))
                            web.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(web)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_FAILED", "تعذر فتح تيليجرام", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

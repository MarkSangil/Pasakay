package com.pasakay.pasakay_driver

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val channelName = "pasakay/contact"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "dial" -> {
            val number = call.argument<String>("number")
            if (number.isNullOrBlank()) {
              result.error("bad_args", "number required", null)
              return@setMethodCallHandler
            }
            try {
              val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number"))
              intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
              startActivity(intent)
              result.success(true)
            } catch (e: Exception) {
              result.error("launch_failed", e.message, null)
            }
          }
          "sms" -> {
            val number = call.argument<String>("number")
            val body = call.argument<String>("body")
            if (number.isNullOrBlank()) {
              result.error("bad_args", "number required", null)
              return@setMethodCallHandler
            }
            try {
              val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$number"))
              if (!body.isNullOrBlank()) {
                intent.putExtra("sms_body", body)
              }
              val defaultSms =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                  Telephony.Sms.getDefaultSmsPackage(this)
                } else {
                  null
                }
              if (!defaultSms.isNullOrBlank()) {
                intent.setPackage(defaultSms)
              }
              intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
              startActivity(intent)
              result.success(true)
            } catch (e: Exception) {
              result.error("launch_failed", e.message, null)
            }
          }
          else -> result.notImplemented()
        }
      }
  }
}

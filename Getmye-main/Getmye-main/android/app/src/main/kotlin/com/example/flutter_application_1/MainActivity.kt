package com.example.flutter_application_1

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.getmye.alarm"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableLockScreenAndTurnScreenOn()
    }

    private fun enableLockScreenAndTurnScreenOn() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startOrderService" -> {
                    val baseUrl = call.argument<String>("baseUrl") ?: "http://10.0.2.2:5000"
                    val partnerId = call.argument<String>("partnerId") ?: "DP001"
                    DeliveryOrderForegroundService.startService(applicationContext, baseUrl, partnerId)
                    result.success(true)
                }
                "stopOrderService" -> {
                    DeliveryOrderForegroundService.stopService(applicationContext)
                    result.success(true)
                }
                "startAlarm" -> {
                    val orderId = call.argument<String>("orderId") ?: "NEW"
                    val item = call.argument<String>("item") ?: ""
                    val custName = call.argument<String>("customerName") ?: ""
                    val address = call.argument<String>("address") ?: ""
                    val budget = call.argument<Double>("budget") ?: 0.0
                    DeliveryOrderForegroundService.startAlarm(applicationContext, orderId, item, custName, address, budget)
                    result.success(true)
                }
                "stopAlarm" -> {
                    DeliveryOrderForegroundService.stopAlarm(applicationContext)
                    result.success(true)
                }
                "silenceOrder" -> {
                    val orderId = call.argument<String>("orderId") ?: ""
                    DeliveryOrderForegroundService.silenceOrder(applicationContext, orderId)
                    result.success(true)
                }
                "playSuccessSound" -> {
                    playPaymentSuccessSound()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun playPaymentSuccessSound() {
        try {
            val resId = resources.getIdentifier("payment_success", "raw", packageName)
            if (resId != 0) {
                val mp = android.media.MediaPlayer.create(applicationContext, resId)
                mp?.apply {
                    setAudioAttributes(
                        android.media.AudioAttributes.Builder()
                            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION_EVENT)
                            .build()
                    )
                    setOnCompletionListener { it.release() }
                    start()
                } ?: playFallbackTone()
            } else {
                playFallbackTone()
            }
        } catch (e: Exception) {
            playFallbackTone()
        }
    }

    private fun playFallbackTone() {
        try {
            val tone = android.media.ToneGenerator(android.media.AudioManager.STREAM_NOTIFICATION, 100)
            tone.startTone(android.media.ToneGenerator.TONE_PROP_ACK, 350)
        } catch (_: Exception) {
            try {
                val uri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION)
                val r = android.media.RingtoneManager.getRingtone(applicationContext, uri)
                r.play()
            } catch (_: Exception) {}
        }
    }
}

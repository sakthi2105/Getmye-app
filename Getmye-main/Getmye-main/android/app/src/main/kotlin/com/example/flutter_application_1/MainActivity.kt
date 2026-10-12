package com.example.flutter_application_1

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.getmye.alarm"
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var isAlarmRunning = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAlarm" -> {
                    startAlarm()
                    result.success(true)
                }
                "stopAlarm" -> {
                    stopAlarm()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startAlarm() {
        if (isAlarmRunning && mediaPlayer?.isPlaying == true) return
        isAlarmRunning = true

        try {
            var playerStarted = false
            try {
                val resId = resources.getIdentifier("order_alarm", "raw", packageName)
                if (resId != 0) {
                    val afd = resources.openRawResourceFd(resId)
                    if (afd != null) {
                        mediaPlayer?.release()
                        mediaPlayer = MediaPlayer().apply {
                            setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_ALARM)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                    .build()
                            )
                            setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                            afd.close()
                            isLooping = true
                            setVolume(1.0f, 1.0f)
                            setOnCompletionListener { mp ->
                                if (isAlarmRunning) {
                                    try {
                                        mp.seekTo(0)
                                        mp.start()
                                    } catch (e: Exception) {
                                        e.printStackTrace()
                                    }
                                }
                            }
                            prepare()
                            start()
                        }
                        playerStarted = true
                    }
                }
            } catch (rawEx: Exception) {
                rawEx.printStackTrace()
            }

            if (!playerStarted) {
                var alertUri: Uri? = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                if (alertUri == null) {
                    alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                }
                if (alertUri == null) {
                    alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                }

                if (alertUri != null) {
                    mediaPlayer?.release()
                    mediaPlayer = MediaPlayer().apply {
                        setDataSource(applicationContext, alertUri)
                        setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ALARM)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                        )
                        isLooping = true
                        setVolume(1.0f, 1.0f)
                        setOnCompletionListener { mp ->
                            if (isAlarmRunning) {
                                try {
                                    mp.seekTo(0)
                                    mp.start()
                                } catch (e: Exception) {
                                    e.printStackTrace()
                                }
                            }
                        }
                        prepare()
                        start()
                    }
                }
            }

            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }

            val pattern = longArrayOf(0, 800, 400, 800, 400)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopAlarm() {
        isAlarmRunning = false
        try {
            mediaPlayer?.let {
                if (it.isPlaying) {
                    it.stop()
                }
                it.release()
            }
            mediaPlayer = null
            vibrator?.cancel()
            vibrator = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }
}

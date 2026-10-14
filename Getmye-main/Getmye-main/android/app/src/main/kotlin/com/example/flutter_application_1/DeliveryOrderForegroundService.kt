package com.example.flutter_application_1

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.Collections
import java.util.HashSet
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import org.json.JSONObject

/**
 * High-reliability Foreground Service that keeps Getmye Partner active in the background.
 * Ensures that even when the delivery person exits the app, uses other apps (WhatsApp, YouTube, etc.),
 * or the phone screen is turned off / locked, incoming orders immediately trigger a loud repeating alarm,
 * vibration, screen wake-up, and a full-screen heads-up notification.
 */
class DeliveryOrderForegroundService : Service() {

    companion object {
        const val SERVICE_CHANNEL_ID = "getmye_online_service_v1"
        const val ALARM_CHANNEL_ID = "getmye_order_alarm_high_v7"
        const val SERVICE_NOTIFICATION_ID = 1001
        const val ALARM_NOTIFICATION_ID = 999

        const val ACTION_START_SERVICE = "com.getmye.ACTION_START_SERVICE"
        const val ACTION_STOP_SERVICE = "com.getmye.ACTION_STOP_SERVICE"
        const val ACTION_START_ALARM = "com.getmye.ACTION_START_ALARM"
        const val ACTION_STOP_ALARM = "com.getmye.ACTION_STOP_ALARM"
        const val ACTION_SILENCE_ORDER = "com.getmye.ACTION_SILENCE_ORDER"

        const val EXTRA_BASE_URL = "extra_base_url"
        const val EXTRA_PARTNER_ID = "extra_partner_id"
        const val EXTRA_ORDER_ID = "extra_order_id"
        const val EXTRA_ITEM = "extra_item"
        const val EXTRA_CUSTOMER_NAME = "extra_customer_name"
        const val EXTRA_ADDRESS = "extra_address"
        const val EXTRA_BUDGET = "extra_budget"

        var instance: DeliveryOrderForegroundService? = null
        var isAlarmActive = false
        var currentAlarmOrderId: String? = null

        fun startService(context: Context, baseUrl: String, partnerId: String) {
            val intent = Intent(context, DeliveryOrderForegroundService::class.java).apply {
                action = ACTION_START_SERVICE
                putExtra(EXTRA_BASE_URL, baseUrl)
                putExtra(EXTRA_PARTNER_ID, partnerId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, DeliveryOrderForegroundService::class.java).apply {
                action = ACTION_STOP_SERVICE
            }
            context.startService(intent)
        }

        fun startAlarm(
            context: Context,
            orderId: String,
            item: String = "",
            custName: String = "",
            address: String = "",
            budget: Double = 0.0
        ) {
            val intent = Intent(context, DeliveryOrderForegroundService::class.java).apply {
                action = ACTION_START_ALARM
                putExtra(EXTRA_ORDER_ID, orderId)
                putExtra(EXTRA_ITEM, item)
                putExtra(EXTRA_CUSTOMER_NAME, custName)
                putExtra(EXTRA_ADDRESS, address)
                putExtra(EXTRA_BUDGET, budget)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopAlarm(context: Context) {
            try {
                instance?.stopAlarmInternal()
            } catch (_: Exception) {}
            try {
                val intent = Intent(context, DeliveryOrderForegroundService::class.java).apply {
                    action = ACTION_STOP_ALARM
                }
                context.startService(intent)
            } catch (_: Exception) {}
        }

        fun silenceOrder(context: Context, orderId: String) {
            try {
                if (orderId.isNotEmpty()) {
                    instance?.silencedOrderIds?.add(orderId)
                }
                instance?.stopAlarmInternal()
            } catch (_: Exception) {}
            try {
                val intent = Intent(context, DeliveryOrderForegroundService::class.java).apply {
                    action = ACTION_SILENCE_ORDER
                    putExtra(EXTRA_ORDER_ID, orderId)
                }
                context.startService(intent)
            } catch (_: Exception) {}
        }
    }

    private var baseUrl: String? = null
    private var partnerId: String? = null
    private var isServiceRunning = false

    private var mediaPlayer: MediaPlayer? = null
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private var scheduler: ScheduledExecutorService? = null
    private val knownOrderIds = Collections.synchronizedSet(HashSet<String>())
    private val silencedOrderIds = Collections.synchronizedSet(HashSet<String>())
    private var isInitialCheckDone = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START_SERVICE

        when (action) {
            ACTION_START_SERVICE -> {
                val bUrl = intent?.getStringExtra(EXTRA_BASE_URL)
                val pId = intent?.getStringExtra(EXTRA_PARTNER_ID)
                if (!bUrl.isNullOrEmpty()) baseUrl = bUrl
                if (!pId.isNullOrEmpty()) partnerId = pId

                startAsForeground()
                startBackgroundPolling()
            }
            ACTION_STOP_SERVICE -> {
                stopAlarmInternal()
                stopBackgroundPolling()
                isServiceRunning = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
            }
            ACTION_START_ALARM -> {
                // Ensure service is running as foreground so sound is never killed
                startAsForeground()
                val orderId = intent?.getStringExtra(EXTRA_ORDER_ID) ?: "NEW"
                val item = intent?.getStringExtra(EXTRA_ITEM) ?: ""
                val cName = intent?.getStringExtra(EXTRA_CUSTOMER_NAME) ?: ""
                val addr = intent?.getStringExtra(EXTRA_ADDRESS) ?: ""
                val budget = intent?.getDoubleExtra(EXTRA_BUDGET, 0.0) ?: 0.0

                startAlarmInternal(orderId, item, cName, addr, budget)
            }
            ACTION_STOP_ALARM -> {
                stopAlarmInternal()
            }
            ACTION_SILENCE_ORDER -> {
                val orderId = intent?.getStringExtra(EXTRA_ORDER_ID) ?: ""
                if (orderId.isNotEmpty()) {
                    silencedOrderIds.add(orderId)
                }
                stopAlarmInternal()
            }
        }

        return START_STICKY
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // 1. Silent Service Channel for online persistent status
            val serviceChannel = NotificationChannel(
                SERVICE_CHANNEL_ID,
                "Getmye Partner Online Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps delivery app active in background to receive orders"
                setShowBadge(false)
            }
            manager.createNotificationChannel(serviceChannel)

            // 2. High-priority Alarm Channel for loud incoming orders
            val alarmSoundUri = Uri.parse("android.resource://$packageName/${R.raw.order_alarm}")
            val audioAttrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            val alarmChannel = NotificationChannel(
                ALARM_CHANNEL_ID,
                "🚨 New Order Alerts & Alarm",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Loud alarm, vibration, and banner for incoming delivery orders"
                setSound(alarmSoundUri, audioAttrs)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(alarmChannel)
        }
    }

    private fun startAsForeground() {
        if (isServiceRunning) return
        isServiceRunning = true

        val notification = buildServiceNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                SERVICE_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(SERVICE_NOTIFICATION_ID, notification)
        }
    }

    private fun buildServiceNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: Intent(this, MainActivity::class.java)
        launchIntent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, pendingIntentFlags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, SERVICE_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("🟢 Getmye Partner: Online")
            .setContentText("Listening for new orders in background")
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun startBackgroundPolling() {
        if (scheduler != null && !scheduler!!.isShutdown) return
        scheduler = Executors.newSingleThreadScheduledExecutor()
        scheduler?.scheduleWithFixedDelay({
            try {
                checkPendingOrders()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }, 1, 2, TimeUnit.SECONDS)
    }

    private fun stopBackgroundPolling() {
        try {
            scheduler?.shutdownNow()
            scheduler = null
        } catch (e: Exception) {}
    }

    private fun checkPendingOrders() {
        val bUrl = baseUrl ?: return
        val pId = partnerId ?: return
        if (!isServiceRunning) return

        var conn: HttpURLConnection? = null
        try {
            val url = URL("$bUrl/api/order/pending?partner_id=$pId")
            conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 3000
            conn.readTimeout = 3000
            conn.setRequestProperty("Accept", "application/json")

            val code = conn.responseCode
            if (code == 200) {
                val reader = BufferedReader(InputStreamReader(conn.inputStream))
                val sb = StringBuilder()
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    sb.append(line)
                }
                reader.close()

                val json = JSONObject(sb.toString())
                val orders = json.optJSONArray("orders")
                val cancelledOrders = json.optJSONArray("cancelled_orders")

                // 🚨 CANCELLATION DETECTOR: If alarm is currently ringing, check if customer cancelled!
                if (isAlarmActive && currentAlarmOrderId != null) {
                    val ringingId = currentAlarmOrderId!!
                    var isCancelled = false
                    var cancelReason = "Order was cancelled by customer"

                    // Check cancelled_orders array
                    if (cancelledOrders != null) {
                        for (i in 0 until cancelledOrders.length()) {
                            val co = cancelledOrders.optJSONObject(i)
                            if (co?.optString("order_id", "") == ringingId) {
                                isCancelled = true
                                val r = co.optString("cancel_reason", "")
                                if (r.isNotEmpty()) cancelReason = r
                                break
                            }
                        }
                    }

                    // Check orders array
                    if (!isCancelled && orders != null) {
                        for (i in 0 until orders.length()) {
                            val o = orders.optJSONObject(i)
                            if (o?.optString("order_id", "") == ringingId) {
                                if (o.optString("status", "").lowercase() == "cancelled") {
                                    isCancelled = true
                                    val r = o.optString("cancel_reason", "")
                                    if (r.isNotEmpty()) cancelReason = r
                                    break
                                }
                            }
                        }
                    }

                    // Check if ringing order disappeared from pending list (cancelled by customer before acceptance)
                    if (!isCancelled && orders != null) {
                        var foundStillPending = false
                        for (i in 0 until orders.length()) {
                            val o = orders.optJSONObject(i)
                            if (o?.optString("order_id", "") == ringingId && o.optString("status", "").lowercase() == "pending") {
                                foundStillPending = true
                                break
                            }
                        }
                        if (!foundStillPending) {
                            isCancelled = true
                        }
                    }

                    if (isCancelled) {
                        silencedOrderIds.add(ringingId)
                        stopAlarmInternal()
                        showCancelledNotification(ringingId, cancelReason)
                    }
                }

                if (orders != null) {
                    // Pre-populate existing orders on first startup to avoid alerting old orders
                    if (!isInitialCheckDone) {
                        isInitialCheckDone = true
                        for (i in 0 until orders.length()) {
                            val o = orders.optJSONObject(i)
                            val oid = o?.optString("order_id") ?: ""
                            if (oid.isNotEmpty()) {
                                knownOrderIds.add(oid)
                            }
                        }
                        return
                    }

                    // Check for newly arriving pending orders
                    for (i in 0 until orders.length()) {
                        val o = orders.optJSONObject(i) ?: continue
                        val oid = o.optString("order_id", "")
                        val status = o.optString("status", "").lowercase()
                        if (oid.isNotEmpty() && status == "pending" && !knownOrderIds.contains(oid) && !silencedOrderIds.contains(oid)) {
                            knownOrderIds.add(oid)
                            val item = o.optString("item_name", "Food Order")
                            val cName = o.optString("customer_name", "Customer")
                            val addr = o.optString("delivery_address", "")
                            val budget = o.optDouble("budget", 150.0)

                            startAlarmInternal(oid, item, cName, addr, budget)
                            break
                        }
                    }
                }
            }
        } catch (e: Exception) {
            // Quiet network catch in background poller
        } finally {
            conn?.disconnect()
        }
    }

    private fun startAlarmInternal(
        orderId: String,
        item: String,
        custName: String,
        address: String,
        budget: Double
    ) {
        if (silencedOrderIds.contains(orderId)) return

        isAlarmActive = true
        currentAlarmOrderId = orderId

        try {
            // 1. Wake up the CPU and turn ON the screen even if the phone is locked or screen off
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "GetMye:DeliveryAlarmWakeLock"
            ).apply {
                acquire(3 * 60 * 1000L) // 3 min max safety auto-release
            }

            // 2. Request Audio Focus with USAGE_ALARM (Forces full alarm volume)
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val audioAttrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                    .setAudioAttributes(audioAttrs)
                    .build()
                audioManager.requestAudioFocus(focusRequest)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(null, AudioManager.STREAM_ALARM, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
            }

            // 3. Play order_alarm sound via MediaPlayer in loop
            var playerStarted = false
            try {
                val resId = resources.getIdentifier("order_alarm", "raw", packageName)
                if (resId != 0) {
                    val afd = resources.openRawResourceFd(resId)
                    if (afd != null) {
                        mediaPlayer?.release()
                        mediaPlayer = MediaPlayer().apply {
                            setAudioAttributes(audioAttrs)
                            setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
                            setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                            afd.close()
                            isLooping = true
                            setVolume(1.0f, 1.0f)
                            prepare()
                            start()
                        }
                        playerStarted = true
                    }
                }
            } catch (rawEx: Exception) {
                rawEx.printStackTrace()
            }

            // 4. Fallback to system Ringtone if raw resource failed
            if (!playerStarted) {
                val alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                alertUri?.let {
                    ringtone = RingtoneManager.getRingtone(applicationContext, it)?.apply {
                        audioAttributes = audioAttrs
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            isLooping = true
                        }
                        play()
                    }
                }
            }

            // 5. Heavy Pulsing Vibration
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

            // 6. Show Full Screen Heads-Up Alarm Notification
            showAlarmNotification(orderId, item, custName, address, budget)

        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun showAlarmNotification(
        orderId: String,
        item: String,
        custName: String,
        address: String,
        budget: Double
    ) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: Intent(this, MainActivity::class.java)
        launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        launchIntent.putExtra("order_id", orderId)
        launchIntent.putExtra("route", "incoming_order")

        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(this, ALARM_NOTIFICATION_ID, launchIntent, pendingIntentFlags)

        val body = buildString {
            if (item.isNotEmpty()) append("Item: $item")
            if (budget > 0) append(" (₹${budget.toInt()})")
            if (custName.isNotEmpty()) append(" • $custName")
            if (address.isNotEmpty()) append("\n📍 $address")
            append("\n⚡ New order waiting! Tap to accept now.")
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, ALARM_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val notif = builder
            .setContentTitle("🚨 NEW DELIVERY ORDER: #$orderId")
            .setContentText(body)
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(fullScreenPendingIntent)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setAutoCancel(false)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_MAX)
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(ALARM_NOTIFICATION_ID, notif)
    }

    private fun showCancelledNotification(orderId: String, reason: String) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: Intent(this, MainActivity::class.java)
        launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 3003, launchIntent, pendingIntentFlags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, SERVICE_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val notif = builder
            .setContentTitle("🚨 Order Cancelled by Customer")
            .setContentText("Order #$orderId was cancelled by customer: $reason")
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(3003, notif)
    }

    fun stopAlarm() {
        stopAlarmInternal()
    }

    private fun stopAlarmInternal() {
        isAlarmActive = false
        currentAlarmOrderId = null

        try {
            mediaPlayer?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
            mediaPlayer = null

            ringtone?.let {
                if (it.isPlaying) it.stop()
            }
            ringtone = null

            vibrator?.cancel()
            vibrator = null

            wakeLock?.let {
                if (it.isHeld) it.release()
            }
            wakeLock = null

            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(ALARM_NOTIFICATION_ID)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        stopAlarmInternal()
        stopBackgroundPolling()
        instance = null
        super.onDestroy()
    }
}

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AlarmService {
  static const MethodChannel _channel = MethodChannel('com.getmye.alarm');
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static bool _isPlaying = false;
  static bool _notifInitialized = false;

  // Track order IDs that have been silenced/accepted/declined so they never alarm again
  static final Set<String> _silencedOrderIds = {};

  // Flag to know if initial check on app boot/login has occurred (prevents ringing on login)
  static bool hasCompletedInitialCheck = false;

  static void silenceOrder(String? orderId) {
    if (orderId != null && orderId.isNotEmpty) {
      _silencedOrderIds.add(orderId);
    }
    stopAlarm();
  }

  static bool isOrderSilenced(String? orderId) {
    if (orderId == null || orderId.isEmpty) return false;
    return _silencedOrderIds.contains(orderId);
  }

  static Future<void> _initNotif() async {
    if (_notifInitialized) return;
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);
    _notifInitialized = true;
  }

  /// Start playing the loud repeating alarm sound (uses Android STREAM_ALARM + Vibration + Local Notification)
  static Future<void> startAlarm({String? orderId, String? item}) async {
    if (orderId != null && isOrderSilenced(orderId)) {
      return; // Order has already been accepted/declined/silenced
    }
    if (_isPlaying) return;
    _isPlaying = true;
    try {
      await _channel.invokeMethod('startAlarm');
    } catch (e) {
      // Fallback
      SystemSound.play(SystemSoundType.alert);
    }

    // High-priority notification so it alerts outside the app with order_alarm sound
    try {
      await _initNotif();
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'new_order_alarm_channel_v2',
        'Incoming Orders Alarm',
        channelDescription: 'Loud alarm for incoming delivery orders',
        importance: Importance.max,
        priority: Priority.high,
        sound: RawResourceAndroidNotificationSound('order_alarm'),
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
      );
      const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
      await _notifications.show(
        999,
        '🚨 NEW DELIVERY ORDER AVAILABLE!',
        item != null ? 'New order for $item ($orderId). Tap to accept now!' : 'New delivery order received! Tap to accept now.',
        platformDetails,
      );
    } catch (_) {}
  }

  /// Stop playing the alarm immediately
  static Future<void> stopAlarm() async {
    _isPlaying = false;
    try {
      await _channel.invokeMethod('stopAlarm');
    } catch (_) {}
    try {
      await _notifications.cancel(999);
    } catch (_) {}
  }
}

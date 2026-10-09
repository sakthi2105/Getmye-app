import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AppNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  static Future<void> init() async {
    if (_isInitialized) return;
    try {
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notificationsPlugin.initialize(initSettings);

      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'getmye_alerts_v2',
        'Getmye Alerts',
        description: 'Real-time alerts for orders, chat, and sign-in OTP',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await androidPlugin?.createNotificationChannel(channel);

      _isInitialized = true;
      debugPrint("✅ AppNotificationService initialized successfully with permissions");
    } catch (e) {
      debugPrint("⚠️ AppNotificationService init error: $e");
    }
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      if (!_isInitialized) {
        await init();
      }

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'getmye_alerts_v2',
        'Getmye Alerts',
        channelDescription: 'Real-time alerts for orders, chat, and sign-in OTP',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(body),
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        id,
        title,
        body,
        platformDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint("⚠️ Error showing notification: $e");
    }
  }

  // 1. Sign-In OTP Notification (shown on target device)
  static Future<void> showOtpNotification(String otp, {String? targetMobile}) async {
    final subText = targetMobile != null && targetMobile.isNotEmpty
        ? "Your OTP for +91 $targetMobile is $otp"
        : "Your GETMYE verification code is $otp";
    await showNotification(
      id: 1001,
      title: '🔐 GETMYE Sign-In OTP',
      body: '$subText. Valid for 5 minutes. Do not share.',
    );
  }

  // 2. Chat Message Notification (Customer & Delivery Partner)
  static Future<void> showChatMessageNotification({
    required String senderName,
    required String message,
  }) async {
    await showNotification(
      id: 2002,
      title: '💬 Message from $senderName',
      body: message,
    );
  }

  // 3. Customer Order Cancelled Notification for Delivery Partner
  static Future<void> showOrderCancelledNotification({
    required String orderId,
    String? reason,
  }) async {
    final rText = reason != null && reason.trim().isNotEmpty
        ? "Reason: $reason"
        : "Order was cancelled by customer";
    await showNotification(
      id: 3003,
      title: '🚨 Order Cancelled!',
      body: 'Order $orderId has been cancelled. $rText',
    );
  }
}

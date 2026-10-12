import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api_config.dart';
import 'alarm_service.dart';

class AppNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  // Track chat state so notifications don't spam if user is actively looking at the chat sheet
  static bool isChatOpen = false;
  static String? activeChatOrderId;

  static Timer? _globalChatPollingTimer;

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

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint("🔔 Notification clicked with payload: ${response.payload}");
        },
      );

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

      const AndroidNotificationChannel orderChannel = AndroidNotificationChannel(
        'getmye_orders_emergency_channel_v3',
        '🚨 New Order Alerts & Alarm',
        description: 'Loud alarm, vibration, and banner for incoming delivery orders',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('order_alarm'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
      );
      await androidPlugin?.createNotificationChannel(orderChannel);

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
    final uniqueId = DateTime.now().millisecondsSinceEpoch % 100000;
    await showNotification(
      id: uniqueId,
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

  // 4. Incoming Delivery Order Alert Notification (Maximum priority, alarm sound & banner)
  static Future<void> showIncomingOrderNotification({
    required String orderId,
    String? item,
    String? customerName,
    String? address,
    double? budget,
  }) async {
    try {
      if (!_isInitialized) {
        await init();
      }

      final bodyBuffer = StringBuffer();
      if (item != null && item.isNotEmpty) {
        bodyBuffer.write("Item: $item");
      }
      if (budget != null && budget > 0) {
        bodyBuffer.write(" (₹${budget.toStringAsFixed(0)})");
      }
      if (customerName != null && customerName.isNotEmpty) {
        bodyBuffer.write(" • $customerName");
      }
      if (address != null && address.isNotEmpty) {
        bodyBuffer.write("\n📍 $address");
      }
      bodyBuffer.write("\n⚡ New order waiting! Tap to accept now.");

      const AndroidNotificationDetails orderAlarmDetails = AndroidNotificationDetails(
        'getmye_orders_emergency_channel_v3',
        '🚨 New Order Alerts & Alarm',
        channelDescription: 'Loud alarm, vibration, and banner for incoming delivery orders',
        importance: Importance.max,
        priority: Priority.max,
        sound: RawResourceAndroidNotificationSound('order_alarm'),
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        ticker: '🚨 NEW DELIVERY ORDER!',
        audioAttributesUsage: AudioAttributesUsage.alarm,
        styleInformation: BigTextStyleInformation(''),
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'order_alarm.wav',
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: orderAlarmDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        999,
        '🚨 NEW DELIVERY ORDER: #$orderId',
        bodyBuffer.toString(),
        platformDetails,
        payload: 'order:$orderId',
      );
    } catch (e) {
      debugPrint("⚠️ Error showing incoming order notification: $e");
    }
  }

  static Future<void> cancelNotification(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
    } catch (_) {}
  }

  static bool _isCheckingMessages = false;

  // 4. Global Background Chat Polling System for Both Models (Customer & Partner)
  static void startGlobalChatPolling() {
    _globalChatPollingTimer?.cancel();
    _globalChatPollingTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) async {
      await checkAndNotifyNewMessages();
    });
  }

  // Set of message signature keys that have already shown a system notification
  static final Set<String> _notifiedMessageKeys = {};

  /// Checks whether a message has already been notified on this device.
  /// If NOT, marks it as notified and returns true. If already notified, returns false.
  static Future<bool> shouldNotifyMessage(String uniqueKey) async {
    if (_notifiedMessageKeys.contains(uniqueKey)) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> saved = prefs.getStringList('notified_chat_message_keys') ?? [];
      if (saved.contains(uniqueKey)) {
        _notifiedMessageKeys.add(uniqueKey);
        return false;
      }
      _notifiedMessageKeys.add(uniqueKey);
      saved.add(uniqueKey);
      if (saved.length > 250) {
        saved.removeRange(0, saved.length - 250);
      }
      await prefs.setStringList('notified_chat_message_keys', saved);
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Generates a unique signature for a message
  static String getMessageKey(String orderId, Map msg, int index) {
    final sender = msg['sender']?.toString() ?? '';
    final text = msg['text']?.toString() ?? '';
    final time = msg['time']?.toString() ?? '';
    final timestamp = msg['timestamp']?.toString() ?? '';
    return '${orderId}_${sender}_${index}_${timestamp.isNotEmpty ? timestamp : time}_${text.hashCode}';
  }

  static Future<void> checkAndNotifyNewMessages() async {
    if (_isCheckingMessages) return;
    _isCheckingMessages = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      if (!isLoggedIn) return;

      final String accountType = prefs.getString('account_type') ?? 'customer';
      final String? activeOrderId = prefs.getString('active_order_id');
      // If user has no active order in progress, no chat messages exist to poll
      if (activeOrderId == null || activeOrderId.isEmpty) return;

      // Query latest messages for the active order
      final msgRes = await http.get(ApiConfig.orderMessages(activeOrderId)).timeout(const Duration(seconds: 3));
      if (msgRes.statusCode != 200) return;

      final data = jsonDecode(msgRes.body);
      final List remoteMessages = data['messages'] ?? [];
      if (remoteMessages.isEmpty) return;

      final String countKey = 'global_last_seen_msg_count_${accountType}_$activeOrderId';
      final int lastSeenCount = prefs.getInt(countKey) ?? -1;

      // First time observing this order in this login session / account:
      // Establish baseline and pre-mark existing messages so NO notifications fire on login!
      if (lastSeenCount == -1) {
        for (int i = 0; i < remoteMessages.length; i++) {
          final m = remoteMessages[i];
          if (m is Map) {
            final key = getMessageKey(activeOrderId, m, i);
            _notifiedMessageKeys.add(key);
          }
        }
        await prefs.setInt(countKey, remoteMessages.length);
        return;
      }

      if (remoteMessages.length > lastSeenCount) {
        for (int i = lastSeenCount; i < remoteMessages.length; i++) {
          final msg = remoteMessages[i];
          if (msg is! Map) continue;
          final sender = msg['sender']?.toString();
          final text = msg['text']?.toString() ?? '';

          if (text.trim().isEmpty) continue;

          // Unique message key for deduplication across restarts and logins
          final key = getMessageKey(activeOrderId, msg, i);
          final canNotify = await shouldNotifyMessage(key);
          if (!canNotify) continue;

          // 1. Customer receives message from Partner
          if (accountType == 'customer' && sender == 'partner') {
            // Only suppress if user currently has this exact chat sheet open on screen
            if (!isChatOpen || activeChatOrderId != activeOrderId) {
              final pName = prefs.getString('active_order_partner_name') ?? 'Delivery Partner';
              await showChatMessageNotification(
                senderName: pName,
                message: text,
              );
            }
          }

          // 2. Partner receives message from Customer
          if (accountType == 'partner' && sender == 'customer') {
            // Only suppress if user currently has this exact chat sheet open on screen
            if (!isChatOpen || activeChatOrderId != activeOrderId) {
              final cName = prefs.getString('active_order_customer_name') ?? 'Customer';
              await showChatMessageNotification(
                senderName: cName,
                message: text,
              );
            }
          }
        }

        await prefs.setInt(countKey, remoteMessages.length);
      }
    } catch (_) {
    } finally {
      _isCheckingMessages = false;
    }
  }

  // 5. Global Partner Order Alerts Poller (Guarantees <3s incoming order alerts!)
  static final StreamController<Map<String, dynamic>> _newOrderStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get onNewOrderReceived =>
      _newOrderStreamController.stream;

  static Timer? _globalPartnerOrderPollingTimer;
  static bool _isPollingPartnerOrders = false;

  static void startGlobalPartnerOrderPolling() {
    _globalPartnerOrderPollingTimer?.cancel();
    // ⚡ Fast: 1500ms polling cycle ensures notification reaches partner within 1.5 - 3 seconds!
    _globalPartnerOrderPollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      await checkAndNotifyPendingOrders();
    });
  }

  static Future<void> checkAndNotifyPendingOrders() async {
    if (_isPollingPartnerOrders) return;
    _isPollingPartnerOrders = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      final String accountType = prefs.getString('account_type') ?? 'customer';
      if (!isLoggedIn || accountType != 'partner') return;

      final bool isOnline = prefs.getBool('d_is_online') ?? true;
      if (!isOnline) {
        AlarmService.stopAlarm();
        return;
      }

      final pId = prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? 'DP001';
      final uri = Uri.parse('${ApiConfig.orderPending}?partner_id=$pId');
      final res = await http.get(uri).timeout(const Duration(milliseconds: 2000));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List orders = data['orders'] ?? [];
        final declinedIds = prefs.getStringList('partner_declined_order_ids') ?? [];
        final partnerActiveId = prefs.getString('partner_active_order_id');

        final unhandledOrders = orders.where((o) {
          final id = o['order_id']?.toString() ?? '';
          final status = (o['status']?.toString() ?? '').toLowerCase();
          return !declinedIds.contains(id) &&
              !AlarmService.isOrderSilenced(id) &&
              (partnerActiveId == null || partnerActiveId.isEmpty || id != partnerActiveId) &&
              status == 'pending';
        }).toList();

        if (unhandledOrders.isNotEmpty) {
          final firstOrder = unhandledOrders.first;
          final orderId = firstOrder['order_id']?.toString() ?? '';
          final itemName = firstOrder['item_name']?.toString() ?? 'Food Order';
          final custName = firstOrder['customer_name']?.toString() ?? 'Customer';
          final address = firstOrder['delivery_address']?.toString() ?? '';
          final budget = (firstOrder['budget'] as num?)?.toDouble() ?? 150.0;

          // 🚨 Alarm sound + Heads-up Notification within 3 seconds!
          AlarmService.startAlarm(
            orderId: orderId,
            item: itemName,
            customerName: custName,
            address: address,
            budget: budget,
          );

          if (firstOrder is Map<String, dynamic>) {
            _newOrderStreamController.add(firstOrder);
          }
        }
      }
    } catch (_) {
    } finally {
      _isPollingPartnerOrders = false;
    }
  }
}


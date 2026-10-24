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

      // Clean up previous channel IDs so Android updates sound and importance cleanly
      try {
        await androidPlugin?.deleteNotificationChannel('getmye_orders_emergency_channel_v3');
        await androidPlugin?.deleteNotificationChannel('getmye_orders_emergency_channel_v2');
      } catch (_) {}

      final AndroidNotificationChannel orderChannel = AndroidNotificationChannel(
        'getmye_order_alarm_high_v7',
        '🚨 New Order Alerts & Alarm',
        description: 'Loud alarm, vibration, and banner for incoming delivery orders',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        sound: const RawResourceAndroidNotificationSound('order_alarm'),
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

  // 3b. Delivery Partner Accepted Order Notification for Customer
  static Future<void> showOrderAcceptedNotification({
    required String orderId,
    required String partnerName,
    String? partnerPhone,
  }) async {
    final phoneInfo = (partnerPhone != null && partnerPhone.trim().isNotEmpty)
        ? " (Contact: $partnerPhone)"
        : "";
    await showNotification(
      id: 2002,
      title: '🎉 Delivery Partner Assigned!',
      body: '$partnerName$phoneInfo has accepted your order #$orderId and is heading to the store.',
      payload: 'order:$orderId',
    );
  }

  // Price range notification disabled per user requirement (only accept, bill, payment success allowed)
  static Future<void> showPriceRangeAcknowledgementNotification({
    required String orderId,
    required String priceRange,
    String? partnerName,
  }) async {
    // No-op
    return;
  }

  // 3d. Store Bill Acknowledgement / Upload Notification for Customer
  static Future<void> showBillAcknowledgementNotification({
    required String orderId,
    String? partnerName,
    double? grandTotal,
    int? itemCount,
  }) async {
    final pName = (partnerName != null && partnerName.trim().isNotEmpty)
        ? partnerName
        : "Delivery Partner";
    final amountText = (grandTotal != null && grandTotal > 0)
        ? " (₹${grandTotal.toStringAsFixed(0)})"
        : "";
    final itemsText = (itemCount != null && itemCount > 0)
        ? " with $itemCount item${itemCount > 1 ? 's' : ''}"
        : "";

    await showNotification(
      id: 2004,
      title: '🧾 Order Confirmed & Bill Sent$amountText',
      body: '$pName has confirmed your order and sent the bill$amountText$itemsText for Order #$orderId. Tap to verify and proceed to pay!',
      payload: 'bill:$orderId',
    );
  }

  // 3f. Payment Successful Notification for Customer
  static Future<void> showPaymentSuccessNotification({
    required String orderId,
    required double amount,
    String? otp,
    String? partnerName,
    String? paymentMethod,
  }) async {
    final methodStr = (paymentMethod != null && paymentMethod.trim().isNotEmpty)
        ? " via $paymentMethod"
        : "";
    final otpStr = (otp != null && otp.trim().isNotEmpty)
        ? " Share Delivery OTP $otp with your partner upon food arrival."
        : " Your delivery partner will hand over your order shortly.";

    await showNotification(
      id: 2006,
      title: '✅ Payment Successful: ₹${amount.toStringAsFixed(0)}',
      body: 'Payment of ₹${amount.toStringAsFixed(0)}$methodStr was successful for Order #$orderId.$otpStr',
      payload: 'payment_success:$orderId',
    );
  }

  // 3g. Order Delivered Notification for Customer
  static Future<void> showOrderDeliveredCustomerNotification({
    required String orderId,
    String? partnerName,
  }) async {
    final pName = (partnerName != null && partnerName.trim().isNotEmpty)
        ? partnerName
        : "Delivery Partner";
    await showNotification(
      id: 2005,
      title: '🎉 Order Delivered Successfully!',
      body: '$pName has delivered your order #$orderId. Enjoy your meal! Thank you for choosing GETMYE.',
      payload: 'delivered:$orderId',
    );
  }

  // 3h. Order Delivered Notification for Delivery Partner
  static Future<void> showOrderDeliveredPartnerNotification({
    required String orderId,
    String? customerName,
  }) async {
    final cName = (customerName != null && customerName.trim().isNotEmpty)
        ? " to $customerName"
        : "";
    await showNotification(
      id: 3006,
      title: '✅ Delivery Completed!',
      body: 'Order #$orderId has been successfully delivered$cName. Great job!',
      payload: 'partner_delivered:$orderId',
    );
  }

  // 3e. Customer Price Range Response Notification
  static Future<void> showCustomerAckResponseNotification({
    required String orderId,
    required bool isAccepted,
    String? reason,
  }) async {
    if (isAccepted) {
      await showNotification(
        id: 3004,
        title: '✅ Customer Accepted Price Range!',
        body: 'Customer approved your price acknowledgement for Order #$orderId. You can now proceed to purchase.',
        payload: 'ack_accepted:$orderId',
      );
    } else {
      final rText = (reason != null && reason.trim().isNotEmpty)
          ? reason
          : 'Customer declined the price range acknowledgement';
      await showNotification(
        id: 3005,
        title: '❌ Acknowledgement Declined by Customer',
        body: 'Order #$orderId: $rText.',
        payload: 'ack_declined:$orderId',
      );
    }
  }

  static Future<void> checkAndNotifyCollectedItems({
    required String orderId,
    required List items,
    String? partnerName,
  }) async {
    // Disabled per user request: only order accept, bill upload, and payment success notifications are sent
    return;
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

      final AndroidNotificationDetails orderAlarmDetails = AndroidNotificationDetails(
        'getmye_order_alarm_high_v7',
        '🚨 New Order Alerts & Alarm',
        channelDescription: 'Loud alarm, vibration, and banner for incoming delivery orders',
        importance: Importance.max,
        priority: Priority.max,
        sound: const RawResourceAndroidNotificationSound('order_alarm'),
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        ticker: '🚨 NEW DELIVERY ORDER!',
        audioAttributesUsage: AudioAttributesUsage.alarm,
        styleInformation: BigTextStyleInformation(bodyBuffer.toString()),
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'order_alarm.mp3',
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      final NotificationDetails platformDetails = NotificationDetails(
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

  static final Set<String> _globalKnownOrderIds = {};
  static Timer? _globalPartnerOrderPollingTimer;
  static bool _isPollingPartnerOrders = false;

  static void registerOrderAsKnown(String orderId) {
    if (orderId.isNotEmpty) {
      _globalKnownOrderIds.add(orderId);
    }
  }

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
      final String accountType = prefs.getString('account_type') ?? 'customer';
      final hasPartnerSession = accountType == 'partner' ||
          (prefs.getString('d_id') != null && prefs.getString('d_id')!.isNotEmpty) ||
          (prefs.getString('d_phone') != null && prefs.getString('d_phone')!.isNotEmpty) ||
          (prefs.getBool('d_is_online') == true);
      if (!hasPartnerSession) return;

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
        final List cancelledOrders = data['cancelled_orders'] ?? [];
        final declinedIds = prefs.getStringList('partner_declined_order_ids') ?? [];
        final partnerActiveId = prefs.getString('partner_active_order_id');

        // 🚨 1. CANCELLATION DETECTOR: Stop alarm immediately if ringing order is cancelled by customer!
        final ringingId = AlarmService.currentAlarmOrderId;
        if (AlarmService.isPlaying && ringingId != null && ringingId.isNotEmpty) {
          bool isOrderCancelled = false;
          String cancelReason = 'Order was cancelled by customer';

          // Check in cancelled_orders list
          for (final co in cancelledOrders) {
            if (co is Map && co['order_id']?.toString() == ringingId) {
              isOrderCancelled = true;
              final r = co['cancel_reason']?.toString();
              if (r != null && r.isNotEmpty) cancelReason = r;
              break;
            }
          }

          // Check in orders list
          if (!isOrderCancelled) {
            for (final o in orders) {
              if (o is Map && o['order_id']?.toString() == ringingId) {
                if ((o['status']?.toString() ?? '').toLowerCase() == 'cancelled') {
                  isOrderCancelled = true;
                  final r = o['cancel_reason']?.toString();
                  if (r != null && r.isNotEmpty) cancelReason = r;
                  break;
                }
              }
            }
          }

          // Also check: is it no longer pending in orders? (Cancelled before acceptance)
          if (!isOrderCancelled) {
            final stillPending = orders.any((o) =>
                o is Map &&
                o['order_id']?.toString() == ringingId &&
                (o['status']?.toString() ?? '').toLowerCase() == 'pending');
            if (!stillPending) {
              isOrderCancelled = true;
            }
          }

          if (isOrderCancelled) {
            AlarmService.stopAlarm();
            AlarmService.silenceOrder(ringingId);
            await showOrderCancelledNotification(
              orderId: ringingId,
              reason: cancelReason,
            );
          }
        }

        final unhandledOrders = orders.where((o) {
          final id = o['order_id']?.toString() ?? '';
          final status = (o['status']?.toString() ?? '').toLowerCase();
          return !declinedIds.contains(id) &&
              !AlarmService.isOrderSilenced(id) &&
              (partnerActiveId == null || partnerActiveId.isEmpty || id != partnerActiveId) &&
              status == 'pending';
        }).toList();

        // 🚨 Trigger loud alarm for unhandled pending orders
        if (unhandledOrders.isNotEmpty && !AlarmService.isPlaying) {
          final firstOrder = unhandledOrders.first;
          final orderId = firstOrder['order_id']?.toString() ?? '';
          final itemName = firstOrder['item_name']?.toString() ?? 'Food Order';
          final custName = firstOrder['customer_name']?.toString() ?? 'Customer';
          final address = firstOrder['delivery_address']?.toString() ?? '';
          final budget = (firstOrder['budget'] as num?)?.toDouble() ?? 150.0;

          // 🚨 Alarm sound + Heads-up Notification within 1-2 seconds!
          AlarmService.startAlarm(
            orderId: orderId,
            item: itemName,
            customerName: custName,
            address: address,
            budget: budget,
          );

          final Map<String, dynamic> safeOrderMap =
              firstOrder is Map ? Map<String, dynamic>.from(firstOrder) : {};
          if (safeOrderMap.isNotEmpty) {
            _newOrderStreamController.add(safeOrderMap);
          }
        }
      }
    } catch (e) {
      debugPrint("Global partner orders check error: $e");
    } finally {
      _isPollingPartnerOrders = false;
    }
  }

  // 6. Global Customer Order Status Poller
  static Timer? _globalCustomerOrderPollingTimer;
  static bool _isPollingCustomerOrder = false;

  static void startGlobalCustomerOrderPolling() {
    _globalCustomerOrderPollingTimer?.cancel();
    _globalCustomerOrderPollingTimer =
        Timer.periodic(const Duration(milliseconds: 2000), (_) async {
      await checkAndNotifyCustomerOrderStatus();
    });
  }

  static Future<void> checkAndNotifyCustomerOrderStatus() async {
    if (_isPollingCustomerOrder) return;
    _isPollingCustomerOrder = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      if (!isLoggedIn) return;

      final String accountType = prefs.getString('account_type') ?? 'customer';
      if (accountType != 'customer') return;

      final String? activeOrderId = prefs.getString('active_order_id');
      if (activeOrderId == null || activeOrderId.isEmpty) return;

      final res = await http
          .get(ApiConfig.orderById(activeOrderId))
          .timeout(const Duration(milliseconds: 2500));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final order = data['order'];
        if (order != null) {
          final st = (order['status']?.toString() ?? '').toLowerCase();
          final pName = (order['partner_name'] != null &&
                  order['partner_name'].toString().trim().isNotEmpty)
              ? order['partner_name'].toString().trim()
              : 'Delivery Partner';
          final pPhone = (order['partner_phone'] != null &&
                  order['partner_phone'].toString().trim().isNotEmpty)
              ? order['partner_phone'].toString().trim()
              : '';

          // 1. Order Accepted Notification (ONLY order accept notification)
          final bool isAccepted = (st == 'accepted' ||
              st == 'purchasing_food' ||
              st == 'bill_sent' ||
              st == 'picked_up' ||
              st == 'in_transit');

          final bool alreadyNotifiedAccepted =
              prefs.getBool('has_notified_partner_accepted_$activeOrderId') ?? false;

          if (isAccepted && !alreadyNotifiedAccepted) {
            await prefs.setBool('has_notified_partner_accepted_$activeOrderId', true);
            await prefs.setBool('active_order_partner_accepted', true);
            await prefs.setString('active_order_status', st);
            await prefs.setString('active_order_partner_name', pName);
            if (pPhone.isNotEmpty) {
              await prefs.setString('active_order_partner_phone', pPhone);
            }

            await showOrderAcceptedNotification(
              orderId: activeOrderId,
              partnerName: pName,
              partnerPhone: pPhone,
            );
          }

          // 2. Store Bill Upload Notification (ONLY when status is bill_sent)
          final bool hasBill = (st == 'bill_sent') &&
              ((order['bill_confirmed'] == true) ||
               (order['bill_image_url'] != null && order['bill_image_url'].toString().trim().isNotEmpty) ||
               (order['bill_images'] is List && (order['bill_images'] as List).isNotEmpty));
          if (hasBill) {
            final bool alreadyNotifiedBill =
                prefs.getBool('has_notified_bill_ack_$activeOrderId') ?? false;
            if (!alreadyNotifiedBill) {
              await prefs.setBool('has_notified_bill_ack_$activeOrderId', true);
              final num? gTot = order['grand_total'] ?? order['total_amount'];
              final List? itms = order['items'] is List ? order['items'] : null;
              await showBillAcknowledgementNotification(
                orderId: activeOrderId,
                partnerName: pName,
                grandTotal: gTot?.toDouble(),
                itemCount: itms?.length,
              );
            }
          }

          // 3. Payment Successful Notification
          final String payStatus = (order['payment_status'] ?? '').toString().toLowerCase().trim();
          final bool isPaid = payStatus == 'paid' || payStatus == 'success' || order['is_paid'] == true;
          if (isPaid) {
            final bool alreadyNotifiedPayment =
                prefs.getBool('has_notified_payment_success_$activeOrderId') ?? false;
            if (!alreadyNotifiedPayment) {
              await prefs.setBool('has_notified_payment_success_$activeOrderId', true);
              final num? gTot = order['grand_total'] ?? order['total_amount'];
              final String pMethod = (order['payment_method'] ?? 'Online').toString();
              final String codOtp = (order['cod_otp'] ?? '').toString();
              await showPaymentSuccessNotification(
                orderId: activeOrderId,
                amount: (gTot?.toDouble()) ?? 0.0,
                otp: codOtp,
                partnerName: pName,
                paymentMethod: pMethod,
              );
            }
          }

          // 4. Order Delivered Notification for Customer
          final bool isDelivered = (st == 'delivered' || st == 'completed');
          if (isDelivered) {
            final bool alreadyNotifiedDelivered =
                prefs.getBool('has_notified_delivered_$activeOrderId') ?? false;
            if (!alreadyNotifiedDelivered) {
              await prefs.setBool('has_notified_delivered_$activeOrderId', true);
              await showOrderDeliveredCustomerNotification(
                orderId: activeOrderId,
                partnerName: pName,
              );
            }
            await AlarmService.stopCustomerOrderListeningService();
          } else if (st == 'cancelled') {
            await AlarmService.stopCustomerOrderListeningService();
          } else {
            AlarmService.startCustomerOrderListeningService(
              baseUrl: ApiConfig.baseUrl,
              orderId: activeOrderId,
            );
          }
        }
      }
    } catch (_) {
    } finally {
      _isPollingCustomerOrder = false;
    }
  }
}


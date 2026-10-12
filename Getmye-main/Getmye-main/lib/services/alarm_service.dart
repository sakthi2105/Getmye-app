import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app_notification_service.dart';

class AlarmService {
  static const MethodChannel _channel = MethodChannel('com.getmye.alarm');
  static bool _isPlaying = false;
  static String? _currentAlarmOrderId;

  static bool get isPlaying => _isPlaying;

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

  /// Start playing the loud repeating alarm sound (uses Android USAGE_ALARM + Vibration + Local Notification)
  static Future<void> startAlarm({
    String? orderId,
    String? item,
    String? customerName,
    String? address,
    double? budget,
  }) async {
    if (orderId != null && isOrderSilenced(orderId)) {
      return; // Order has already been accepted/declined/silenced
    }

    // Immediate instant feedback on device hardware
    try {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    } catch (_) {}

    final bool isNewOrder = orderId != null && orderId != _currentAlarmOrderId;
    _currentAlarmOrderId = orderId;

    if (!_isPlaying || isNewOrder) {
      _isPlaying = true;
      try {
        await _channel.invokeMethod('startAlarm');
      } catch (e) {
        debugPrint("⚠️ Native startAlarm channel error: $e");
      }
    }

    // High-priority notification so it alerts outside the app with order_alarm sound & heads-up banner
    try {
      await AppNotificationService.showIncomingOrderNotification(
        orderId: orderId ?? 'NEW',
        item: item,
        customerName: customerName,
        address: address,
        budget: budget,
      );
    } catch (e) {
      debugPrint("⚠️ AlarmService notification error: $e");
    }
  }

  /// Stop playing the alarm immediately
  static Future<void> stopAlarm() async {
    _isPlaying = false;
    _currentAlarmOrderId = null;
    try {
      await _channel.invokeMethod('stopAlarm');
    } catch (_) {}
    try {
      await AppNotificationService.cancelNotification(999);
    } catch (_) {}
  }
}


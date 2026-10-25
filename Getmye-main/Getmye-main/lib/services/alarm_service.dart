import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app_notification_service.dart';

class AlarmService {
  static const MethodChannel _channel = MethodChannel('com.getmye.alarm');
  static bool _isPlaying = false;
  static String? _currentAlarmOrderId;

  static bool get isPlaying => _isPlaying;
  static String? get currentAlarmOrderId => _currentAlarmOrderId;

  // Track order IDs that have been silenced/accepted/declined so they never alarm again
  static final Set<String> _silencedOrderIds = {};

  // Flag to know if initial check on app boot/login has occurred (prevents ringing on login)
  static bool hasCompletedInitialCheck = false;

  /// Start the background foreground service for delivery partner when online.
  /// Keeps process alive and listening even when user minimizes app or locks screen.
  static Future<void> startOrderListeningService({
    required String baseUrl,
    required String partnerId,
  }) async {
    try {
      await _channel.invokeMethod('startOrderService', {
        'baseUrl': baseUrl,
        'partnerId': partnerId,
      });
      debugPrint("🟢 Started background order listening foreground service for partner: $partnerId");
    } catch (e) {
      debugPrint("⚠️ startOrderListeningService error: $e");
    }
  }

  /// Stop the background foreground service when delivery partner goes offline
  static Future<void> stopOrderListeningService() async {
    try {
      await _channel.invokeMethod('stopOrderService');
      debugPrint("🔴 Stopped background order listening service");
    } catch (e) {
      debugPrint("⚠️ stopOrderListeningService error: $e");
    }
  }

  /// Start the background foreground service for customer active order.
  /// Keeps app alive and listening even when minimized, using other apps, or phone locked.
  static Future<void> startCustomerOrderListeningService({
    required String baseUrl,
    required String orderId,
  }) async {
    try {
      await _channel.invokeMethod('startCustomerOrderService', {
        'baseUrl': baseUrl,
        'orderId': orderId,
      });
      debugPrint("🟢 Started customer order foreground service for order: $orderId");
    } catch (e) {
      debugPrint("⚠️ startCustomerOrderListeningService error: $e");
    }
  }

  /// Stop the customer background foreground service when order completes or cancels
  static Future<void> stopCustomerOrderListeningService() async {
    try {
      await _channel.invokeMethod('stopCustomerOrderService');
      debugPrint("🔴 Stopped customer order foreground service");
    } catch (e) {
      debugPrint("⚠️ stopCustomerOrderListeningService error: $e");
    }
  }

  /// Request exemption from Android Doze battery optimization so background polling continues with screen off
  static Future<void> requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimizationExemption');
    } catch (e) {
      debugPrint("⚠️ requestBatteryOptimizationExemption error: $e");
    }
  }

  static void silenceAll() {
    stopAlarm();
  }

  static void silenceOrder(String? orderId) {
    if (orderId != null && orderId.isNotEmpty) {
      _silencedOrderIds.add(orderId);
      try {
        _channel.invokeMethod('silenceOrder', {'orderId': orderId});
      } catch (_) {}
    }
    stopAlarm();
  }

  static bool isOrderSilenced(String? orderId) {
    if (orderId == null || orderId.isEmpty) return false;
    return _silencedOrderIds.contains(orderId);
  }

  /// Play instant pleasant payment confirmation sound & vibration for both customer and delivery partner
  static Future<void> playPaymentSuccessSound() async {
    try {
      await _channel.invokeMethod('playSuccessSound');
    } catch (e) {
      debugPrint("⚠️ playSuccessSound native channel error: $e");
    }

    try {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    } catch (_) {}
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
        await _channel.invokeMethod('startAlarm', {
          'orderId': orderId ?? 'NEW',
          'item': item ?? '',
          'customerName': customerName ?? '',
          'address': address ?? '',
          'budget': budget ?? 0.0,
        });
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

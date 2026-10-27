import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/deliveryhistroy.dart';
import 'package:flutter_application_1/delivery_bill_flow.dart';
import 'package:flutter_application_1/dprofile.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'services/alarm_service.dart';
import 'services/app_notification_service.dart';
import 'widgets/delivery_bottom_nav_bar.dart';
import 'widgets/price_range_dialogs.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: const DeliveryHomePage(),
      debugShowCheckedModeBanner: false,
    ),
  );
}

class DeliveryHomePage extends StatefulWidget {
  const DeliveryHomePage({super.key});

  @override
  _DeliveryHomePageState createState() => _DeliveryHomePageState();
}

class _DeliveryHomePageState extends State<DeliveryHomePage> {
  int touchpoints = 0;
  String milestoneResetCountdown = "24h left";
  bool isOnline = true;
  double currentBalance = 0.00;
  double totalEarnings = 0.00;
  double todayEarnings = 0.00;
  int totalDeliveries = 0;
  int todayDeliveries = 0;
  String partnerName = "Delivery Partner";
  String? profileImagePath;
  String? profileImageBase64;
  String? profileImageUrl;
  Uint8List? _cachedProfileBytes;
  ImageProvider? _cachedAvatarProvider;
  String? _lastDecodedBase64;
  String? _lastProfilePath;
  String? _lastProfileUrl;
  bool _isProfileFetched = false;
  int pendingOrderCount = 0;
  Timer? _pendingOrdersTimer;
  StreamSubscription<Map<String, dynamic>>? _orderAlertSubscription;
  StreamSubscription<ServiceStatus>? _locationServiceStatusSubscription;
  final Set<String> _notifiedCancelledOrderIds = {};
  bool _isFirstOrdersCheckDone = false;
  final DateTime _screenStartTime = DateTime.now();
  bool _isAcceptingOrder = false;
  bool _isShowingCancellationDialog = false;
  bool _isShowingIncomingModal = false;
  String? _currentIncomingModalOrderId;
  bool _isCheckingPendingOrders = false;
  bool _isUpdatingLocation = false;
  Position? _lastKnownPosition;
  int _pollCount = 0;
  Map<String, dynamic>? activeDeliveryOrder;

  @override
  void initState() {
    super.initState();
    _loadPartnerData();
    _startOrdersPolling();
    _orderAlertSubscription = AppNotificationService.onNewOrderReceived.listen((order) {
      if (mounted && isOnline && !_isShowingIncomingModal) {
        _showIncomingOrderModal(order);
      }
    });

    // 🛰️ Real-time OS Location / GPS toggles listener:
    // If delivery partner turns off device GPS at any time, immediately auto-switch to OFFLINE!
    _locationServiceStatusSubscription = Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      if (status == ServiceStatus.disabled && isOnline) {
        _handleDeviceLocationTurnedOff();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptLocationService();
    });
  }

  @override
  void dispose() {
    _locationServiceStatusSubscription?.cancel();
    _orderAlertSubscription?.cancel();
    _pendingOrdersTimer?.cancel();
    AlarmService.stopAlarm();
    super.dispose();
  }

  /// 🛰️ Check if device GPS location is enabled and permission is granted
  Future<bool> _isDeviceLocationAvailable() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 🛑 Automatically transitions delivery person to OFFLINE when device location is turned off
  Future<void> _handleDeviceLocationTurnedOff({bool showToast = true}) async {
    if (!isOnline && !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('d_is_online', false);
    final pId = prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? 'DP001';

    if (mounted) {
      setState(() {
        isOnline = false;
      });
    }

    // 🛑 Stop alarms and listening service immediately
    AlarmService.silenceAll();
    AlarmService.stopAlarm();
    AlarmService.stopOrderListeningService();
    AppNotificationService.cancelNotification(999);

    // Dismiss incoming order modal if open on screen
    if (_isShowingIncomingModal && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      _isShowingIncomingModal = false;
      _currentIncomingModalOrderId = null;
    }

    // 📡 Sync offline status with backend MongoDB
    try {
      http.post(
        ApiConfig.partnerStatus,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'partner_id': pId,
          'status': 'offline',
        }),
      ).catchError((_) => http.Response('', 500));

      http.post(
        ApiConfig.trackingUpdate,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'partner_id': pId,
          'latitude': 10.9601,
          'longitude': 79.3845,
          'is_online': false,
          'status': 'offline',
        }),
      ).catchError((_) => http.Response('', 500));
    } catch (_) {}

    if (showToast && mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.location_off_rounded, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Device location is turned OFF! You are now OFFLINE. Turn on GPS to receive orders.",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: "Turn On GPS",
            textColor: Colors.white,
            onPressed: () async {
              await Geolocator.openLocationSettings();
            },
          ),
        ),
      );
    }
  }

  // 🛰️ Requirement: "app kull avanthathum 2 perukum location on pana solanum"
  Future<void> _checkAndPromptLocationService() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && mounted) {
        if (isOnline) {
          await _handleDeviceLocationTurnedOff(showToast: false);
        }
        await _showTurnOnGPSDialog(
          title: "Turn On GPS Location",
          message: "Please turn ON device GPS location to receive incoming orders and enable live tracking. Delivery partner status can only be ONLINE when location is turned ON.",
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever && mounted) {
        if (isOnline) {
          await _handleDeviceLocationTurnedOff(showToast: false);
        }
        await _showTurnOnGPSDialog(
          title: "Location Permission Required",
          message: "Location permission is disabled for Getmye Delivery. You cannot go ONLINE without location permission. Please enable it in device settings.",
          isPermissionSettings: true,
        );
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        if (serviceEnabled) {
          _updateLiveLocationToBackend();
        }
      }
    } catch (e) {
      debugPrint("Partner location service check error: $e");
    }
  }

  Future<void> _showTurnOnGPSDialog({
    required String title,
    required String message,
    bool isPermissionSettings = false,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.location_on_rounded, color: Color(0xFF2563EB), size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Later", style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 16),
            label: Text(
              isPermissionSettings ? "Open Settings" : "Turn On GPS",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (isPermissionSettings) {
                await Geolocator.openAppSettings();
              } else {
                await Geolocator.openLocationSettings();
              }
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) _checkAndPromptLocationService();
              });
            },
          ),
        ],
      ),
    );
  }

  void _startOrdersPolling() {
    _pendingOrdersTimer?.cancel();
    _checkPendingOrders();
    _updateLiveLocationToBackend();
    // ⚡ Optimized polling: 2500ms ensures sub-3-second order arrival alerts without battery/network strain!
    _pendingOrdersTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) async {
      // 🛰️ REQUIREMENT: If delivery person's location is turned OFF, automatically switch status to OFFLINE!
      if (isOnline) {
        final hasLocation = await _isDeviceLocationAvailable();
        if (!hasLocation) {
          await _handleDeviceLocationTurnedOff();
          return;
        }
      }
      _pollCount++;
      if (_pollCount % 4 == 0) {
        _updateLiveLocationToBackend();
      }
      if (_pollCount % 25 == 0) {
        _checkMilestoneReset();
      }
      _checkPendingOrders();
    });
  }

  Future<void> _updateLiveLocationToBackend() async {
    if (!isOnline || _isUpdatingLocation) return;
    _isUpdatingLocation = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pId = prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? 'DP001';
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) _lastKnownPosition = pos;
      final lat = _lastKnownPosition?.latitude ?? 10.9601;
      final lng = _lastKnownPosition?.longitude ?? 79.3845;
      await http.post(
        ApiConfig.trackingUpdate,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'partner_id': pId,
          'latitude': lat,
          'longitude': lng,
          'is_online': isOnline,
          'status': activeDeliveryOrder != null ? 'delivering' : 'idle',
          'order_id': activeDeliveryOrder?['order_id'],
        }),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {
    } finally {
      _isUpdatingLocation = false;
    }
  }

  /// Automatically checks and resets partner daily milestone if 24 hours have elapsed
  Future<void> _checkMilestoneReset() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastResetStr = prefs.getString('partner_milestone_last_reset_time');
    int currentTouchpoints = prefs.getInt('partner_milestone_touchpoints') ?? 0;
    String countdown = "24h left";

    if (lastResetStr == null || lastResetStr.isEmpty) {
      await prefs.setString('partner_milestone_last_reset_time', now.toIso8601String());
    } else {
      final lastReset = DateTime.tryParse(lastResetStr) ?? now;
      final diff = now.difference(lastReset);
      if (diff.inHours >= 24) {
        currentTouchpoints = 0;
        await prefs.setInt('partner_milestone_touchpoints', 0);
        await prefs.setString('partner_milestone_last_reset_time', now.toIso8601String());
        countdown = "24h left";
      } else {
        final remaining = const Duration(hours: 24) - diff;
        final hoursLeft = remaining.inHours;
        final minsLeft = remaining.inMinutes % 60;
        countdown = "${hoursLeft}h ${minsLeft}m left";
      }
    }

    if (mounted) {
      if (touchpoints != currentTouchpoints || milestoneResetCountdown != countdown) {
        setState(() {
          touchpoints = currentTouchpoints;
          milestoneResetCountdown = countdown;
        });
      }
    }
  }

  Future<void> _checkPendingOrders() async {
    if (!isOnline) {
      AlarmService.stopAlarm();
      return;
    }
    if (_isCheckingPendingOrders) return;
    _isCheckingPendingOrders = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final pId = prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? 'DP001';
      final partnerActiveId = prefs.getString('partner_active_order_id') ?? prefs.getString('active_order_id');

      // 🚨 CRITICAL: Check live status of current ongoing order directly so cancellation is NEVER missed!
      final String? curOngoingOrderId = activeDeliveryOrder?['order_id']?.toString() ?? partnerActiveId;
      if (curOngoingOrderId != null && curOngoingOrderId.isNotEmpty && _pollCount % 2 == 0) {
        try {
          final ordRes = await http.get(ApiConfig.orderById(curOngoingOrderId)).timeout(const Duration(seconds: 3));
          if (ordRes.statusCode == 200) {
            final ordData = jsonDecode(ordRes.body);
            final ordObj = ordData['order'] ?? ordData;
            final st = (ordObj['status']?.toString() ?? '').toLowerCase();
            if (st == 'cancelled') {
              final reason = ordObj['cancel_reason']?.toString() ?? 'Cancelled by customer';
              await _clearActiveOrderStorage(prefs);
              if (mounted) {
                setState(() {
                  activeDeliveryOrder = null;
                });
              }
              AlarmService.silenceOrder(curOngoingOrderId);
              AlarmService.stopAlarm();
              AppNotificationService.cancelNotification(999);
              if (!_notifiedCancelledOrderIds.contains(curOngoingOrderId)) {
                _notifiedCancelledOrderIds.add(curOngoingOrderId);
                AppNotificationService.showOrderCancelledNotification(
                  orderId: curOngoingOrderId,
                  reason: reason,
                );
                if (mounted) {
                  _showCancellationNoticeDialog(curOngoingOrderId, reason);
                }
              }
            } else if (st == 'delivered' || st == 'completed') {
              await _clearActiveOrderStorage(prefs);
              if (mounted) {
                setState(() {
                  activeDeliveryOrder = null;
                });
              }
            }

            final prSt = (ordObj['price_range_status'] ?? '').toString().toLowerCase();
            if (prSt == 'accepted') {
              final notifKey = 'partner_notified_ack_acc_$curOngoingOrderId';
              if (prefs.getBool(notifKey) != true) {
                await prefs.setBool(notifKey, true);
                await AppNotificationService.showCustomerAckResponseNotification(
                  orderId: curOngoingOrderId,
                  isAccepted: true,
                );
              }
            }
          }
        } catch (_) {}
      }

      final uri = Uri.parse('${ApiConfig.orderPending}?partner_id=$pId');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List orders = data['orders'] ?? [];
        final List cancelledOrders = data['cancelled_orders'] ?? [];
        final declinedIds = prefs.getStringList('partner_declined_order_ids') ?? [];

        final allOrdersForCancel = [...cancelledOrders, ...orders];

        // 🛑 FIRST-TIME BOOT / RECENT APP ENTRY CHECK:
        // Pre-populate all existing orders & cancellations so entering the app NEVER triggers
        // old alarm sounds or unwanted "Order Cancelled" dialog popups!
        final bool isWithinAppEntryGrace = DateTime.now().difference(_screenStartTime).inSeconds < 8;
        if (!_isFirstOrdersCheckDone || isWithinAppEntryGrace) {
          _isFirstOrdersCheckDone = true;
          for (final o in cancelledOrders) {
            final id = o['order_id']?.toString();
            if (id != null && id.isNotEmpty) {
              _notifiedCancelledOrderIds.add(id);
              // If this cancelled order was our active ongoing delivery, clear it immediately and alert partner
              if (id == curOngoingOrderId || (activeDeliveryOrder != null && activeDeliveryOrder!['order_id'] == id)) {
                final cReason = o['cancel_reason']?.toString() ?? 'Cancelled by customer';
                await _clearActiveOrderStorage(prefs);
                if (mounted) {
                  setState(() {
                    activeDeliveryOrder = null;
                  });
                  _showCancellationNoticeDialog(id, cReason);
                }
                await AppNotificationService.showOrderCancelledNotification(
                  orderId: id,
                  reason: cReason,
                );
              }
            }
          }
        } else {
          // 🚨 CANCELLATION DETECTOR: Alert delivery partner with dialog ONLY if customer cancels
          // an order that is actively ringing on screen OR is the partner's active ongoing delivery!
          for (final o in allOrdersForCancel) {
            final oStatus = (o['status']?.toString() ?? '').toLowerCase();
            final oId = o['order_id']?.toString() ?? '';
            final cReason = o['cancel_reason']?.toString() ?? 'Cancelled by customer';

            if (oStatus == 'cancelled' && !_notifiedCancelledOrderIds.contains(oId)) {
              _notifiedCancelledOrderIds.add(oId);

              // Do not trigger cancellation dialog if delivery partner is in the middle of accepting this order!
              if (_isAcceptingOrder) continue;

              final bool isCurrentlyRingingThisOrder = (AlarmService.isPlaying && AlarmService.currentAlarmOrderId == oId) ||
                  (_isShowingIncomingModal && _currentIncomingModalOrderId == oId);
              // Must be actively tracked in memory as ongoing delivery - do NOT rely on stale prefs
              final bool isPartnerActiveOngoingDelivery = (activeDeliveryOrder != null && activeDeliveryOrder!['order_id'] == oId) ||
                  (partnerActiveId != null && partnerActiveId == oId) ||
                  (curOngoingOrderId != null && curOngoingOrderId == oId);

              // 1. Immediately silence and stop any ringing alarm
              if (isCurrentlyRingingThisOrder) {
                AlarmService.silenceOrder(oId);
                AlarmService.stopAlarm();
                AppNotificationService.cancelNotification(999);
              }

              // 2. Dismiss incoming order modal if open on screen for this order
              if (_isShowingIncomingModal && (_currentIncomingModalOrderId == oId || _currentIncomingModalOrderId == null)) {
                if (mounted) {
                  Navigator.of(context, rootNavigator: true).pop();
                }
                _isShowingIncomingModal = false;
                _currentIncomingModalOrderId = null;
              }

              // 3. Clear active ongoing delivery if customer cancelled it
              if (isPartnerActiveOngoingDelivery) {
                if (mounted) {
                  setState(() {
                    activeDeliveryOrder = null;
                  });
                }
                await _clearActiveOrderStorage(prefs);
              }

              // 4. Show cancellation notice dialog & heads-up notification ONLY if partner was actively involved!
              if (isCurrentlyRingingThisOrder || isPartnerActiveOngoingDelivery) {
                AppNotificationService.showOrderCancelledNotification(
                  orderId: oId,
                  reason: cReason,
                );
                if (mounted) {
                  _showCancellationNoticeDialog(oId, cReason);
                }
              }
            }
          }

          // 🚨 Also: If alarm is currently ringing or incoming modal is open, but that order is cancelled or no longer pending
          final currentRingingOrModalId = AlarmService.currentAlarmOrderId ?? _currentIncomingModalOrderId;
          if (currentRingingOrModalId != null && currentRingingOrModalId.isNotEmpty) {
            final bool isStillPending = orders.any((o) =>
                o['order_id']?.toString() == currentRingingOrModalId &&
                (o['status']?.toString() ?? '').toLowerCase() == 'pending');
            if (!isStillPending) {
              AlarmService.silenceOrder(currentRingingOrModalId);
              AlarmService.stopAlarm();
              AppNotificationService.cancelNotification(999);

              if (_isShowingIncomingModal && mounted) {
                Navigator.of(context, rootNavigator: true).pop();
                _isShowingIncomingModal = false;
                _currentIncomingModalOrderId = null;
              }

              String cancelReason = 'Order was cancelled by customer';
              for (final co in allOrdersForCancel) {
                if (co['order_id']?.toString() == currentRingingOrModalId) {
                  final r = co['cancel_reason']?.toString();
                  if (r != null && r.isNotEmpty) cancelReason = r;
                  break;
                }
              }

              if (!_notifiedCancelledOrderIds.contains(currentRingingOrModalId)) {
                _notifiedCancelledOrderIds.add(currentRingingOrModalId);
                AppNotificationService.showOrderCancelledNotification(
                  orderId: currentRingingOrModalId,
                  reason: cancelReason,
                );
                if (mounted) {
                  _showCancellationNoticeDialog(currentRingingOrModalId, cancelReason);
                }
              }
            }
          }
        }

        // 🚴 Ongoing Delivery Sync: Strictly match orders belonging to THIS delivery person!
        final ongoingMatch = orders.firstWhere(
          (o) {
            final st = (o['status']?.toString() ?? '').toLowerCase();
            final isOngoingStatus = st == 'accepted' ||
                st == 'purchasing_food' ||
                st == 'bill_sent' ||
                st == 'picked_up' ||
                st == 'in_transit';
            if (!isOngoingStatus) return false;

            final oPartnerId = (o['partner_id'] ?? '').toString().trim().toLowerCase();
            final myPId = pId.trim().toLowerCase();
            final numPart = myPId.replaceAll(RegExp(r'[^0-9]'), '');
            final List declinedList = (o['declined_partners'] as List?)
                ?.map((e) => e.toString().toLowerCase().trim())
                .toList() ?? [];

            // If old delivery person was declined or order is in their declined list, NEVER match!
            if (declinedList.contains(myPId) ||
                (numPart.isNotEmpty && declinedList.any((d) => d.contains(numPart))) ||
                declinedIds.contains(o['order_id']?.toString())) {
              return false;
            }

            return oPartnerId.isNotEmpty && (
              oPartnerId == myPId ||
              (numPart.isNotEmpty && oPartnerId.contains(numPart))
            );
          },
          orElse: () => null,
        );

        if (ongoingMatch != null) {
          final Map<String, dynamic> safeOngoing = Map<String, dynamic>.from(ongoingMatch);
          if (mounted && (activeDeliveryOrder == null || activeDeliveryOrder!['order_id'] != safeOngoing['order_id'] || activeDeliveryOrder!['status'] != safeOngoing['status'])) {
            setState(() {
              activeDeliveryOrder = safeOngoing;
            });
          }
          final curSavedId = prefs.getString('partner_active_order_id');
          final curSavedStatus = prefs.getString('active_order_status');
          final newId = safeOngoing['order_id']?.toString() ?? '';
          final newStatus = safeOngoing['status']?.toString() ?? 'accepted';
          if (curSavedId != newId || curSavedStatus != newStatus) {
            await prefs.setString('partner_active_order_id', newId);
            await prefs.setString('active_order_id', newId);
            await prefs.setString('active_order_status', newStatus);
          }
        } else {
          // If no ongoing delivery exists in backend for this partner, clear activeDeliveryOrder immediately!
          if (activeDeliveryOrder != null || partnerActiveId != null) {
            if (activeDeliveryOrder != null && mounted) {
              setState(() {
                activeDeliveryOrder = null;
              });
            }
            await _clearActiveOrderStorage(prefs);
          }
        }

        // Only consider pending orders strictly unhandled
        final unhandledOrders = orders.where((o) {
          final id = o['order_id']?.toString() ?? '';
          final status = (o['status']?.toString() ?? '').toLowerCase();
          final List declinedList = (o['declined_partners'] as List?)
              ?.map((e) => e.toString().toLowerCase().trim())
              .toList() ?? [];
          final myPId = pId.trim().toLowerCase();
          final numPart = myPId.replaceAll(RegExp(r'[^0-9]'), '');
          final bool isDeclined = declinedIds.contains(id) ||
              declinedList.contains(myPId) ||
              (numPart.isNotEmpty && declinedList.any((d) => d.contains(numPart)));

          return !isDeclined &&
              !AlarmService.isOrderSilenced(id) &&
              (partnerActiveId == null || partnerActiveId.isEmpty || id != partnerActiveId) &&
              activeDeliveryOrder == null &&
              status == 'pending';
        }).toList();

        // Mark initial check completed so alarm can sound for unhandled orders
        AlarmService.hasCompletedInitialCheck = true;

        if (mounted && pendingOrderCount != unhandledOrders.length) {
          setState(() {
            pendingOrderCount = unhandledOrders.length;
          });
        }



        // 🚨 PENDING ORDERS FROM CUSTOMER TRIGGER ALARM SOUND & POPUP MODAL!
        if (unhandledOrders.isNotEmpty && isOnline) {
          final firstOrder = unhandledOrders.first;
          final newId = firstOrder['order_id']?.toString() ?? '';
          final itemName = firstOrder['item_name']?.toString() ?? 'Food Order';
          final custName = firstOrder['customer_name']?.toString() ?? 'Customer';
          final addr = firstOrder['delivery_address']?.toString() ?? '';
          final budget = (firstOrder['budget'] as num?)?.toDouble() ?? 150.0;

          if (!AlarmService.isPlaying || AlarmService.currentAlarmOrderId != newId) {
            AlarmService.startAlarm(
              orderId: newId,
              item: itemName,
              customerName: custName,
              address: addr,
              budget: budget,
            );
          }

          if (!_isShowingIncomingModal && mounted) {
            final Map<String, dynamic> safeMap =
                firstOrder is Map ? Map<String, dynamic>.from(firstOrder) : {};
            if (safeMap.isNotEmpty) {
              _showIncomingOrderModal(safeMap);
            }
          }
        } else if (unhandledOrders.isEmpty) {
          AlarmService.stopAlarm();
        }
      }
    } catch (e) {
      debugPrint("Partner pending check error: $e");
    } finally {
      _isCheckingPendingOrders = false;
    }
  }

  Future<void> _showIncomingOrderModal(Map<String, dynamic> order) async {
    if (_isShowingIncomingModal || !mounted) return;
    _isShowingIncomingModal = true;

    final orderId = order['order_id']?.toString() ?? '';
    _currentIncomingModalOrderId = orderId;
    final itemName = order['item_name']?.toString() ?? 'Food Order';
    final budget = order['budget']?.toString() ?? '150';
    final customerName = order['customer_name']?.toString() ?? 'Customer';
    final customerPhone = order['customer_phone']?.toString() ?? '';
    final address = order['delivery_address']?.toString() ?? 'Customer Delivery Location';

    // ⏳ Proximity-Based 2-Minute Acceptance Window
    int totalRemainingSeconds = 120;
    if (order['assignment_expires_at'] != null) {
      final exp = DateTime.tryParse(order['assignment_expires_at'].toString());
      if (exp != null) {
        final diff = exp.difference(DateTime.now()).inSeconds;
        if (diff > 0 && diff <= 120) totalRemainingSeconds = diff;
      }
    }

    Timer? countdownTimer;

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        int secondsLeft = totalRemainingSeconds;

        return StatefulBuilder(
          builder: (context, setModalState) {
            countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (tm) {
              if (secondsLeft > 1) {
                if (modalCtx.mounted) {
                  setModalState(() {
                    secondsLeft--;
                  });
                }
              } else {
                tm.cancel();
                // ⏰ 2-Minute Timeout Reached: Auto-forward/reassign order to next closest delivery partner
                AlarmService.silenceOrder(orderId);
                AlarmService.stopAlarm();
                AppNotificationService.cancelNotification(999);
                if (modalCtx.mounted) {
                  Navigator.of(modalCtx).pop();
                }
                _isShowingIncomingModal = false;
                _currentIncomingModalOrderId = null;
                _checkPendingOrders();
              }
            });

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    // Header with glowing icon and distance badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            color: Color(0xFFEF4444),
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "New Order Alert! 🔔",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Order #$orderId",
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF6EE7B7)),
                          ),
                          child: const Text(
                            "⚡ Online Alert",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF047857),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ⏳ Proximity-Based 2-Minute Live Acceptance Timer
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    const Icon(Icons.timer_rounded, size: 16, color: Color(0xFFB45309)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        "Auto-forwards in: ${secondsLeft ~/ 60}:${(secondsLeft % 60).toString().padLeft(2, '0')}",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF92400E),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "${secondsLeft}s",
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: (secondsLeft / 120.0).clamp(0.0, 1.0),
                              backgroundColor: const Color(0xFFFDE68A),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                secondsLeft < 30 ? const Color(0xFFEF4444) : const Color(0xFFD97706),
                              ),
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Item and Budget card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    const Icon(Icons.restaurant_rounded, size: 20, color: AppColors.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        itemName,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                "₹$budget",
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.location_on_rounded, size: 18, color: Color(0xFFEF4444)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      customerName.isNotEmpty ? customerName : "Customer Delivery",
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      address,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Action Buttons: Decline & Accept
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              countdownTimer?.cancel();
                              AlarmService.silenceOrder(orderId);
                              AlarmService.stopAlarm();
                              AppNotificationService.cancelNotification(999);
                              final prefs = await SharedPreferences.getInstance();
                              final declined = prefs.getStringList('partner_declined_order_ids') ?? [];
                              if (!declined.contains(orderId)) {
                                declined.add(orderId);
                                await prefs.setStringList('partner_declined_order_ids', declined);
                              }
                              try {
                                final pId = prefs.getString('d_id') ?? prefs.getString('partner_id') ?? 'DP001';
                                await http.post(
                                  ApiConfig.orderDecline,
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode({
                                    'order_id': orderId,
                                    'decline_reason': 'Declined from alert modal',
                                    'partner_id': pId,
                                  }),
                                ).timeout(const Duration(seconds: 3));
                              } catch (_) {}
                              if (modalCtx.mounted) Navigator.pop(modalCtx);
                              _checkPendingOrders();
                            },
                            child: const Text(
                              "Decline",
                              style: TextStyle(
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                            ),
                            onPressed: () async {
                              countdownTimer?.cancel();
                              // 1. Immediately close modal and cancel ringing so it cannot be considered incoming
                              if (modalCtx.mounted) Navigator.pop(modalCtx);
                              _isShowingIncomingModal = false;
                              _currentIncomingModalOrderId = null;
                              _isAcceptingOrder = true;

                          AlarmService.silenceOrder(orderId);
                          AlarmService.stopAlarm();
                          AppNotificationService.cancelNotification(999);

                          final prefs = await SharedPreferences.getInstance();
                          String pName = prefs.getString('d_name') ?? prefs.getString('partner_name') ?? "";
                          if (pName.trim().isEmpty) {
                            pName = "Delivery Partner";
                          }
                          String pPhone = prefs.getString('d_phone') ?? prefs.getString('partner_phone') ?? "";
                          String pId = prefs.getString('d_id') ?? prefs.getString('partner_id') ?? prefs.getString('active_order_partner_id') ?? "";
                          final pPic = prefs.getString('d_profile_picture_base64');

                          bool acceptSuccess = false;
                          try {
                            final acceptRes = await http.post(
                              ApiConfig.orderAccept,
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode({
                                'order_id': orderId,
                                'partner_id': pId,
                                'partner_name': pName,
                                'partner_phone': pPhone,
                                if (pPic != null && pPic.isNotEmpty) 'partner_profile_picture': pPic,
                              }),
                            ).timeout(const Duration(seconds: 4));
                            if (acceptRes.statusCode == 200) {
                              acceptSuccess = true;
                              final resData = jsonDecode(acceptRes.body);
                              if (resData['order'] != null) {
                                final oObj = resData['order'];
                                if (oObj['partner_name'] != null && oObj['partner_name'].toString().isNotEmpty) {
                                  pName = oObj['partner_name'].toString();
                                }
                                if (oObj['partner_phone'] != null && oObj['partner_phone'].toString().isNotEmpty) {
                                  pPhone = oObj['partner_phone'].toString();
                                }
                                if (oObj['partner_id'] != null && oObj['partner_id'].toString().isNotEmpty) {
                                  pId = oObj['partner_id'].toString();
                                }
                              }
                            } else {
                              acceptSuccess = false;
                              try {
                                final resData = jsonDecode(acceptRes.body);
                                final isCancelled = resData['cancelled'] == true ||
                                    resData['error'] == 'ORDER_CANCELLED' ||
                                    (resData['cancel_reason'] != null && resData['cancel_reason'].toString().isNotEmpty);
                                if (isCancelled) {
                                  final cancelReason = (resData['cancel_reason'] ?? resData['message'] ?? 'Customer cancelled the order').toString();
                                  _notifiedCancelledOrderIds.add(orderId);
                                  await AppNotificationService.showOrderCancelledNotification(
                                    orderId: orderId,
                                    reason: cancelReason,
                                  );
                                  if (mounted) {
                                    _showCancellationNoticeDialog(orderId, cancelReason);
                                  }
                                  _checkPendingOrders();
                                  return;
                                }
                              } catch (_) {}

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Order is no longer available or was already accepted."),
                                    backgroundColor: Color(0xFFDC2626),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            debugPrint("Error accepting order: $e");
                            acceptSuccess = true;
                          } finally {
                            _isAcceptingOrder = false;
                          }

                          if (!acceptSuccess) {
                            _checkPendingOrders();
                            return;
                          }

                          await prefs.setString('order_${orderId}_status', 'accepted');
                          await prefs.setString('partner_active_order_id', orderId);
                          await prefs.setBool('active_order_partner_accepted', true);
                          await prefs.setString('active_order_partner_id', pId);
                          await prefs.setString('active_order_partner_name', pName);
                          await prefs.setString('active_order_partner_phone', pPhone);
                          await prefs.setString('active_order_id', orderId);
                          await prefs.setString('active_order_status', 'accepted');
                          await prefs.setString('active_order_customer_name', customerName);
                          await prefs.setString('active_order_customer_phone', customerPhone);
                          await prefs.setString('active_order_customer_address', address);
                          await prefs.setString('active_order_item', itemName);

                          if (mounted) {
                            setState(() {
                              activeDeliveryOrder = order;
                              pendingOrderCount = 0;
                            });
                          }

                          final deliveryOrder = DeliveryOrder(
                            orderId: orderId,
                            customerName: customerName,
                            customerPhone: customerPhone,
                            deliveryAddress: address,
                            restaurantName: "Local Restaurant",
                            restaurantAddress: "Pickup Point (Store)",
                            items: [
                              BillItem(
                                name: itemName,
                                quantity: 1,
                                price: double.tryParse(budget) ?? 150.0,
                                isCollected: false,
                              ),
                            ],
                            deliveryFee: 0.0,
                            status: "Accepted",
                          );

                          if (mounted) {
                            // Show popup: Call Customer & Send Estimated Price Range Acknowledgement
                            final acceptedByCustomer = await showDialog<bool>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => DeliveryPartnerPriceRangeDialog(
                                orderId: orderId,
                                customerName: customerName,
                                customerPhone: customerPhone,
                                itemName: itemName,
                                budget: budget,
                              ),
                            );

                            if (mounted && (acceptedByCustomer == true)) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DeliveryBillPostPage(order: deliveryOrder),
                                ),
                              ).then((_) => _loadPartnerData());
                            } else if (mounted) {
                              // Customer declined price range / chose another partner / cancelled
                              setState(() {
                                activeDeliveryOrder = null;
                              });
                              await prefs.remove('partner_active_order_id');
                              await prefs.remove('active_order_id');
                              await prefs.remove('active_order_status');
                              await prefs.remove('active_order_customer_name');
                              await prefs.remove('active_order_customer_phone');
                              await prefs.remove('active_order_customer_address');
                              await prefs.remove('active_order_item');
                              await prefs.remove('active_order_budget');
                              await prefs.remove('active_order_bill_sent');
                              await prefs.remove('active_order_food_purchased');
                              await prefs.remove('active_order_partner_accepted');
                              await prefs.remove('active_order_restaurant');
                              await prefs.remove('active_order_grand_total');

                              final curDeclined = prefs.getStringList('partner_declined_order_ids') ?? [];
                              if (!curDeclined.contains(orderId)) {
                                curDeclined.add(orderId);
                                await prefs.setStringList('partner_declined_order_ids', curDeclined);
                              }

                              AlarmService.silenceOrder(orderId);
                              AlarmService.stopAlarm();
                              AppNotificationService.cancelNotification(999);

                              _loadPartnerData();
                            }
                          }
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 20, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              "Accept Order",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
          },
        );
      },
    );

    countdownTimer?.cancel();
    _isShowingIncomingModal = false;
    _currentIncomingModalOrderId = null;
  }

  Future<void> _clearActiveOrderStorage([SharedPreferences? prefsInstance]) async {
    try {
      final prefs = prefsInstance ?? await SharedPreferences.getInstance();
      await prefs.remove('partner_active_order_id');
      await prefs.remove('active_order_id');
      await prefs.remove('active_order_status');
      await prefs.remove('active_order_customer_name');
      await prefs.remove('active_order_customer_phone');
      await prefs.remove('active_order_customer_address');
      await prefs.remove('active_order_item');
      await prefs.remove('active_order_budget');
      await prefs.remove('active_order_bill_sent');
      await prefs.remove('active_order_food_purchased');
      await prefs.remove('active_order_partner_accepted');
      await prefs.remove('active_order_restaurant');
      await prefs.remove('active_order_grand_total');
      await prefs.remove('active_order_items_json');
      await prefs.remove('active_cod_otp');
    } catch (_) {}
  }

  Future<void> _verifyOngoingOrderNotCancelled(String orderId) async {
    try {
      final res = await http.get(ApiConfig.orderById(orderId)).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final ord = data['order'] ?? data;
        final st = (ord['status']?.toString() ?? '').toLowerCase();
        if (st == 'cancelled') {
          final cReason = ord['cancel_reason']?.toString() ?? 'Cancelled by customer';
          await _clearActiveOrderStorage();
          if (mounted) {
            setState(() {
              activeDeliveryOrder = null;
            });
            _showCancellationNoticeDialog(orderId, cReason);
          }
        } else if (st == 'delivered' || st == 'completed') {
          await _clearActiveOrderStorage();
          if (mounted) {
            setState(() {
              activeDeliveryOrder = null;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadPartnerData() async {
    final prefs = await SharedPreferences.getInstance();
    final dId = prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? '';
    final dPhone = prefs.getString('d_phone') ?? '';
    final localPath = prefs.getString('d_profile_image');
    final localBase64 = prefs.getString('d_profile_picture_base64');

    final milestoneKey = dId.isNotEmpty ? '${dId}_partner_milestone_touchpoints' : 'partner_milestone_touchpoints';
    final lastResetKey = dId.isNotEmpty ? '${dId}_partner_milestone_last_reset_time' : 'partner_milestone_last_reset_time';

    // 24-hour milestone cycle check & reset
    final now = DateTime.now();
    final lastResetStr = prefs.getString(lastResetKey);
    int currentTouchpoints = prefs.getInt(milestoneKey) ?? 0;
    String resetCountdown = "24h left";

    if (lastResetStr == null || lastResetStr.isEmpty) {
      await prefs.setString(lastResetKey, now.toIso8601String());
    } else {
      final lastReset = DateTime.tryParse(lastResetStr) ?? now;
      final diff = now.difference(lastReset);
      if (diff.inHours >= 24) {
        currentTouchpoints = 0;
        await prefs.setInt(milestoneKey, 0);
        await prefs.setString(lastResetKey, now.toIso8601String());
        resetCountdown = "24h left";
      } else {
        final remaining = const Duration(hours: 24) - diff;
        final hoursLeft = remaining.inHours;
        final minsLeft = remaining.inMinutes % 60;
        resetCountdown = "${hoursLeft}h ${minsLeft}m left";
      }
    }

    final balanceKey = dId.isNotEmpty ? '${dId}_wallet_balance' : 'wallet_balance';
    final totalEarnKey = dId.isNotEmpty ? '${dId}_total_earnings' : 'total_earnings';
    final todayEarnKey = dId.isNotEmpty ? '${dId}_today_earnings' : 'today_earnings';
    final totalDelivKey = dId.isNotEmpty ? '${dId}_total_deliveries' : 'total_deliveries';
    final todayDelivKey = dId.isNotEmpty ? '${dId}_today_deliveries' : 'today_deliveries';

    setState(() {
      partnerName = prefs.getString('d_name') ?? "Delivery Partner";
      totalEarnings = prefs.getDouble(totalEarnKey) ?? 0.00;
      todayEarnings = prefs.getDouble(todayEarnKey) ?? 0.00;
      currentBalance = prefs.getDouble(balanceKey) ?? 0.00;
      totalDeliveries = prefs.getInt(totalDelivKey) ?? 0;
      todayDeliveries = prefs.getInt(todayDelivKey) ?? 0;
      touchpoints = currentTouchpoints;
      milestoneResetCountdown = resetCountdown;
      isOnline = prefs.getBool('d_is_online') ?? false;
      profileImagePath = localPath;
      profileImageBase64 = localBase64;
      profileImageUrl = prefs.getString('d_photo_url') ?? prefs.getString('partner_photo_url');
    });

    if (dId.isNotEmpty) {
      _fetchRealPartnerMetrics(dId, balanceKey, totalEarnKey, todayEarnKey, totalDelivKey, todayDelivKey);
    }

    // 🛰️ REQUIREMENT: Partner can only be ONLINE if location is ON. Check upon app load:
    if (isOnline) {
      final hasLocation = await _isDeviceLocationAvailable();
      if (!hasLocation) {
        await _handleDeviceLocationTurnedOff(showToast: false);
      }
    }

    final identifier = dId.isNotEmpty ? dId : dPhone;
    if (identifier.isNotEmpty && !_isProfileFetched && (profileImagePath == null || !File(profileImagePath!).existsSync())) {
      _isProfileFetched = true;
      _fetchPartnerProfileFromBackend(identifier);
    }

    final savedOngoingId = prefs.getString('partner_active_order_id') ?? prefs.getString('active_order_id');
    final savedOngoingStatus = (prefs.getString('active_order_status') ?? '').toLowerCase();
    final savedCustName = prefs.getString('active_order_customer_name');
    final isRealOngoingStatus = savedOngoingStatus == 'accepted' ||
        savedOngoingStatus == 'purchasing_food' ||
        savedOngoingStatus == 'bill_sent' ||
        savedOngoingStatus == 'picked_up' ||
        savedOngoingStatus == 'in_transit';

    if (savedOngoingStatus == 'cancelled' || savedOngoingStatus == 'delivered' || savedOngoingStatus == 'completed') {
      await _clearActiveOrderStorage(prefs);
      if (mounted) {
        setState(() {
          activeDeliveryOrder = null;
        });
      }
    } else if (savedOngoingId != null &&
        savedOngoingId.isNotEmpty &&
        isRealOngoingStatus &&
        savedCustName != null &&
        savedCustName.isNotEmpty &&
        savedCustName != 'Customer') {
      activeDeliveryOrder ??= {
        'order_id': savedOngoingId,
        'customer_name': savedCustName,
        'customer_phone': prefs.getString('active_order_customer_phone') ?? '',
        'delivery_address': prefs.getString('active_order_customer_address') ?? 'Delivery Address',
        'item_name': prefs.getString('active_order_item') ?? 'Food Order',
        'budget': prefs.getString('active_order_budget') ?? '150',
        'status': savedOngoingStatus,
      };
      _verifyOngoingOrderNotCancelled(savedOngoingId);
    }

    // 🟢 Keep listening active in background foreground service so orders alert when app is outside or screen off
    if (isOnline) {
      final pId = dId.isNotEmpty ? dId : (prefs.getString('active_order_partner_id') ?? 'DP001');
      AlarmService.startOrderListeningService(
        baseUrl: ApiConfig.baseUrl,
        partnerId: pId,
      );
      AlarmService.requestBatteryOptimizationExemption();
    }

    _checkPendingOrders();
  }

  Future<void> _fetchPartnerProfileFromBackend(String identifier) async {
    try {
      final res = await http.get(ApiConfig.partnerById(identifier));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final b64 = data['profile_picture']?.toString();
        final newName = data['name']?.toString();
        final newPhone = data['mobile_number']?.toString();
        final pUrl = data['photo_url']?.toString() ?? data['profile_picture_url']?.toString();
        final bool picChanged = b64 != null && b64.isNotEmpty && b64 != profileImageBase64;
        final bool nameChanged = newName != null && newName.isNotEmpty && newName != partnerName;
        final bool urlChanged = pUrl != null && pUrl.isNotEmpty && pUrl != profileImageUrl;

        if (picChanged || nameChanged || urlChanged) {
          final prefs = await SharedPreferences.getInstance();
          if (picChanged) {
            await prefs.setString('d_profile_picture_base64', b64);
            await prefs.setString('active_order_partner_pic', b64);
            await prefs.setString('active_order_partner_image', b64);
          }
          if (urlChanged) {
            await prefs.setString('d_photo_url', pUrl);
            await prefs.setString('partner_photo_url', pUrl);
          }
          if (nameChanged) {
            await prefs.setString('d_name', newName);
            await prefs.setString('partner_name', newName);
            await prefs.setString('active_order_partner_name', newName);
          }
          if (newPhone != null && newPhone.isNotEmpty) {
            await prefs.setString('d_phone', newPhone);
            await prefs.setString('partner_phone', newPhone);
            await prefs.setString('active_order_partner_phone', newPhone);
          }
          if (mounted) {
            setState(() {
              if (picChanged) profileImageBase64 = b64;
              if (urlChanged) profileImageUrl = pUrl;
              if (nameChanged) partnerName = newName;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchRealPartnerMetrics(
    String partnerId,
    String balanceKey,
    String totalEarnKey,
    String todayEarnKey,
    String totalDelivKey,
    String todayDelivKey,
  ) async {
    try {
      final res = await http.get(ApiConfig.orderPartner(partnerId)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List orders = data['orders'] ?? [];
        final now = DateTime.now();
        final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

        int deliveredCount = 0;
        int todayDeliveredCount = 0;
        double earnings = 0.0;
        double todayEarn = 0.0;

        for (final o in orders) {
          final st = (o['status'] ?? '').toString().toLowerCase();
          if (st == 'delivered') {
            deliveredCount++;
            final fee = (o['delivery_fee'] != null)
                ? (double.tryParse(o['delivery_fee'].toString()) ?? 75.0)
                : 75.0;
            earnings += fee;

            final deliveredAt = o['delivered_at']?.toString() ?? '';
            if (deliveredAt.startsWith(todayStr)) {
              todayDeliveredCount++;
              todayEarn += fee;
            }
          }
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(totalDelivKey, deliveredCount);
        await prefs.setInt(todayDelivKey, todayDeliveredCount);
        await prefs.setDouble(totalEarnKey, earnings);
        await prefs.setDouble(todayEarnKey, todayEarn);
        final existingBal = prefs.getDouble(balanceKey);
        if (existingBal == null) {
          await prefs.setDouble(balanceKey, earnings);
        }

        if (mounted) {
          setState(() {
            totalDeliveries = deliveredCount;
            todayDeliveries = todayDeliveredCount;
            totalEarnings = earnings;
            todayEarnings = todayEarn;
            if (existingBal == null) currentBalance = earnings;
          });
        }
      }
    } catch (_) {}
  }

  ImageProvider _getProfileAvatarProvider() {
    if (profileImagePath != null && profileImagePath!.isNotEmpty) {
      if (_lastProfilePath == profileImagePath && _cachedAvatarProvider != null) {
        return _cachedAvatarProvider!;
      }
      final file = File(profileImagePath!);
      if (file.existsSync()) {
        _lastProfilePath = profileImagePath;
        _cachedAvatarProvider = FileImage(file);
        return _cachedAvatarProvider!;
      }
    }

    if (profileImageBase64 != null && profileImageBase64!.isNotEmpty) {
      if (_lastDecodedBase64 == profileImageBase64 && _cachedAvatarProvider != null) {
        return _cachedAvatarProvider!;
      }
      try {
        _cachedProfileBytes = base64Decode(profileImageBase64!);
        _lastDecodedBase64 = profileImageBase64;
        _cachedAvatarProvider = MemoryImage(_cachedProfileBytes!);
        return _cachedAvatarProvider!;
      } catch (_) {}
    }

    if (profileImageUrl != null && profileImageUrl!.isNotEmpty) {
      if (_lastProfileUrl == profileImageUrl && _cachedAvatarProvider != null) {
        return _cachedAvatarProvider!;
      }
      _lastProfileUrl = profileImageUrl;
      _cachedAvatarProvider = ResizeImage(NetworkImage(profileImageUrl!), width: 160);
      return _cachedAvatarProvider!;
    }

    return const AssetImage('assets/delivery_boy_toon.png');
  }

  Widget _buildProfileAvatar() {
    final avatarProvider = _getProfileAvatarProvider();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const dEditProfilePage()),
        ).then((_) {
          _isProfileFetched = false;
          _loadPartnerData();
        });
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: Image(
            image: avatarProvider,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.two_wheeler_rounded, size: 36, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _lastBackPressTime;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 34,
              width: 34,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/G_LOGO.PNG',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 10),
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                children: [
                  TextSpan(
                    text: 'Get',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  TextSpan(
                    text: 'Mye',
                    style: TextStyle(color: AppColors.primaryDark),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isOnline ? const Color(0xFFD1FAE5) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isOnline ? const Color(0xFF6EE7B7) : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isOnline ? const Color(0xFF059669) : AppColors.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isOnline ? "ONLINE" : "OFFLINE",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isOnline ? const Color(0xFF047857) : AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Hero Earnings & Driver Card (Profile icons removed as requested)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF0C1B30), // Deep Midnight Navy
                    Color(0xFF142B4A), // Primary Navy Blue (#142B4A)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryDark.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          "VERIFIED PARTNER",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Row(
                        children: const [
                          Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                          SizedBox(width: 4),
                          Text(
                            "4.8 Rating",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              partnerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Delivery Executive • On-Duty",
                              style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      // Delivery Partner Profile Picture (Dynamic from storage/backend)
                      _buildProfileAvatar(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Total Earnings",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "₹${totalEarnings.toStringAsFixed(0)}",
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 36,
                          color: Colors.white24,
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Today Earnings",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFE8F2FF),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "₹${todayEarnings.toStringAsFixed(0)}",
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFE8F2FF),
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Online / Offline Status Toggle Banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isOnline ? const Color(0xFFECFDF5) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isOnline ? const Color(0xFFA7F3D0) : AppColors.border,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            isOnline ? Icons.check_circle_rounded : Icons.pause_circle_outline_rounded,
                            color: isOnline ? const Color(0xFF059669) : AppColors.textMuted,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isOnline ? "You are Online" : "You are Offline",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isOnline ? const Color(0xFF047857) : AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  isOnline ? "Receiving new delivery orders" : "Toggle online to receive new orders",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch.adaptive(
                      value: isOnline,
                      activeThumbColor: const Color(0xFF059669),
                      activeTrackColor: const Color(0xFFA7F3D0),
                      onChanged: (val) async {
                        // 🛰️ REQUIREMENT: Partner can ONLY go online if device location (GPS & permission) is enabled!
                        if (val == true) {
                          final hasLocation = await _isDeviceLocationAvailable();
                          if (!hasLocation) {
                            if (mounted) {
                              await _showTurnOnGPSDialog(
                                title: "GPS Location Required",
                                message: "You can only be ONLINE when device location is turned ON. Please enable GPS location to go online and receive delivery orders.",
                              );
                            }
                            return; // Do NOT set online if location is turned off!
                          }
                        }

                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('d_is_online', val);
                        final pId = prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? 'DP001';
                        setState(() {
                          isOnline = val;
                        });

                        // 📡 Sync online/offline status with backend MongoDB
                        try {
                          http.post(
                            ApiConfig.partnerStatus,
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode({
                              'partner_id': pId,
                              'status': val ? 'online' : 'offline',
                            }),
                          ).catchError((_) => http.Response('', 500));

                          if (val) {
                            _updateLiveLocationToBackend();
                          }
                        } catch (_) {}

                        if (!val) {
                          AlarmService.stopAlarm();
                          AlarmService.stopOrderListeningService();
                        } else {
                          AlarmService.startOrderListeningService(
                            baseUrl: ApiConfig.baseUrl,
                            partnerId: pId,
                          );
                          AlarmService.requestBatteryOptimizationExemption();
                          _checkPendingOrders();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Orders Notifications Banner (Only sent/visible when partner is ONLINE)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: isOnline
                  ? (activeDeliveryOrder != null
                      ? InkWell(
                          onTap: () {
                            if (activeDeliveryOrder != null) {
                              _openOngoingDeliveryPage(activeDeliveryOrder!);
                            }
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF3B82F6), width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withValues(alpha: 0.15),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563EB),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 26),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Ongoing Delivery: #${activeDeliveryOrder?['order_id'] ?? ''}",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: Color(0xFF1E3A8A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      const Text(
                                        "Finish this delivery to receive new orders",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF1D4ED8),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        if (activeDeliveryOrder != null) {
                                          _openOngoingDeliveryPage(activeDeliveryOrder!);
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1D4ED8),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          "Continue",
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                      : InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const NewOrdersPage()),
                            ).then((_) => _loadPartnerData());
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD97706),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Flexible(
                                        child: Text(
                                          "New Orders Ready",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                            color: Color(0xFF78350F),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (pendingOrderCount > 0)
                                        CircleAvatar(
                                          radius: 9,
                                          backgroundColor: const Color(0xFFEF4444),
                                          child: Text(
                                            "$pendingOrderCount",
                                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    pendingOrderCount > 0
                                        ? "Incoming orders waiting! Tap to accept or decline"
                                        : "Tap to view current orders",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF92400E),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF92400E),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                "View",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ))
                  : Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.notifications_off_outlined, color: AppColors.textSecondary, size: 22),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "You are currently Offline. Turn Online to start receiving incoming order notifications.",
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 14),

            // 3 Metric Stat Cards: Total Deliveries, Current Balance (calculated), Today Deliveries
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildClickableCard(
                      "Total Deliveries",
                      "$totalDeliveries",
                      Icons.delivery_dining_rounded,
                      context,
                      false,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      "Current Balance",
                      "₹${currentBalance.toStringAsFixed(0)}",
                      Icons.account_balance_wallet_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildClickableCard(
                      "Today Deliveries",
                      "$todayDeliveries",
                      Icons.receipt_long_rounded,
                      context,
                      true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Prominent Delivery History Quick Access Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DeliveryListPage(isTodayOnly: false),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          color: AppColors.primaryDark,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Delivery History",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "View all completed orders with date & time",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Milestone Progress Card (Refreshes every 24 hours)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Flexible(
                                    child: Text(
                                      "Daily Milestone",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0F2FE),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.timer_outlined, size: 12, color: Color(0xFF0369A1)),
                                        const SizedBox(width: 4),
                                        Text(
                                          milestoneResetCountdown,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0369A1),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                "Refreshes every 24 hours",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            "$touchpoints / 40 Pts",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 320,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(10, (index) {
                            int pointValue = (index + 1) * 4;
                            bool reached = touchpoints >= pointValue;
                            return Column(
                              children: [
                                Container(
                                  height: 14,
                                  width: 14,
                                  decoration: BoxDecoration(
                                    color: reached ? AppColors.primary : const Color(0xFFE2E8F0),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: reached ? AppColors.primaryDark : const Color(0xFFCBD5E1),
                                      width: reached ? 1.5 : 1,
                                    ),
                                  ),
                                  child: reached
                                      ? const Icon(
                                          Icons.check,
                                          size: 9,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "$pointValue",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: reached ? FontWeight.w700 : FontWeight.w500,
                                    color: reached ? AppColors.primaryDark : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (touchpoints / 40).clamp(0.0, 1.0),
                        backgroundColor: const Color(0xFFF1F5F9),
                        color: AppColors.primary,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.card_giftcard_rounded,
                            size: 18,
                            color: AppColors.primaryDark,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Every 4 orders completed grants an extra bonus of ₹30! Keep going!",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primaryDeep,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: const DeliveryBottomNavBar(currentIndex: 2),
    ),
  );
}

  Widget _buildClickableCard(
    String title,
    String value,
    IconData icon,
    BuildContext context,
    bool goToNextPage,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DeliveryListPage(isTodayOnly: goToNextPage),
          ),
        );
      },
      child: _buildStatCard(title, value, icon),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: AppColors.primaryDark),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCancellationNoticeDialog(String orderId, String reason) {
    if (_isShowingCancellationDialog || !mounted) return;
    _isShowingCancellationDialog = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 24),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                "Order Cancelled",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFFDC2626)),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Customer has cancelled Order #$orderId.",
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Reason Provided:",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reason.isNotEmpty ? reason : "No reason provided",
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF991B1B)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "You are now free to accept incoming orders.",
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                _isShowingCancellationDialog = false;
                Navigator.pop(ctx);
                _loadPartnerData();
              },
              child: const Text("OK, Got It", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    ).then((_) {
      _isShowingCancellationDialog = false;
    });
  }



  DeliveryOrder _createDeliveryOrderFromMap(Map<String, dynamic> o) {
    final orderId = o['order_id']?.toString() ?? 'ORD-0001';
    final customerName = o['customer_name']?.toString() ?? 'Customer';
    final customerPhone = o['customer_phone']?.toString() ?? '';
    final address = o['delivery_address']?.toString() ?? 'Customer Delivery Location';
    final itemName = o['item_name']?.toString() ?? 'Food Item';
    final budgetStr = o['budget']?.toString() ?? '150';
    final budget = double.tryParse(budgetStr) ?? 150.0;
    final status = o['status']?.toString() ?? 'Accepted';
    final double? custLat = (o['customer_latitude'] as num?)?.toDouble();
    final double? custLng = (o['customer_longitude'] as num?)?.toDouble();

    List<BillItem> billItems = [];
    if (o['items'] is List && (o['items'] as List).isNotEmpty) {
      billItems = (o['items'] as List).map((it) {
        if (it is Map) {
          return BillItem(
            name: it['name']?.toString() ?? 'Item',
            quantity: (it['quantity'] as num?)?.toInt() ?? 1,
            price: (it['price'] as num?)?.toDouble() ?? 0.0,
            isCollected: it['isCollected'] as bool? ?? false,
          );
        }
        return BillItem(name: it.toString(), quantity: 1, price: 0.0);
      }).toList();
    }
    if (billItems.isEmpty) {
      billItems = [
        BillItem(
          name: itemName,
          quantity: 1,
          price: budget,
          isCollected: false,
        ),
      ];
    }

    return DeliveryOrder(
      orderId: orderId,
      customerName: customerName,
      customerPhone: customerPhone,
      deliveryAddress: address,
      restaurantName: o['restaurant_name']?.toString() ?? "Local Restaurant",
      restaurantAddress: o['restaurant_address']?.toString() ?? "Pickup Point (Store)",
      items: billItems,
      deliveryFee: (o['delivery_fee'] as num?)?.toDouble() ?? 0.0,
      status: status,
      customerLatitude: custLat,
      customerLongitude: custLng,
    );
  }

  Future<void> _openOngoingDeliveryPage(Map<String, dynamic> o) async {
    final deliveryOrder = _createDeliveryOrderFromMap(o);

    // Verify order is not cancelled before continuing
    try {
      final res = await http.get(ApiConfig.orderById(deliveryOrder.orderId)).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final ord = data['order'] ?? data;
        final st = (ord['status']?.toString() ?? '').toLowerCase();
        if (st == 'cancelled') {
          final reason = ord['cancel_reason']?.toString() ?? 'Cancelled by customer';
          await _clearActiveOrderStorage();
          if (mounted) {
            setState(() {
              activeDeliveryOrder = null;
            });
            _showCancellationNoticeDialog(deliveryOrder.orderId, reason);
          }
          return;
        } else if (st == 'delivered' || st == 'completed') {
          await _clearActiveOrderStorage();
          if (mounted) {
            setState(() {
              activeDeliveryOrder = null;
            });
          }
          return;
        }
      }
    } catch (_) {}

    final status = (o['status']?.toString() ?? '').toLowerCase();

    if (!mounted) return;
    if (status == 'bill_sent' || status == 'in_transit' || status == 'picked_up') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DeliveryNavigationMapPage(
            order: deliveryOrder,
            items: deliveryOrder.items,
            deliveryFee: deliveryOrder.deliveryFee,
            totalAmount: deliveryOrder.grandTotal,
          ),
        ),
      ).then((_) => _loadPartnerData());
    } else {
      // Strictly verify whether customer has approved the price range acknowledgement
      bool isPriceRangeAccepted = false;
      try {
        final res = await http.get(ApiConfig.orderById(deliveryOrder.orderId)).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final ord = data['order'];
          if (ord != null && (ord['price_range_status'] ?? '').toString().toLowerCase() == 'accepted') {
            isPriceRangeAccepted = true;
          }
        }
      } catch (_) {}

      if (!isPriceRangeAccepted) {
        if (!mounted) return;
        final acceptedByCustomer = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => DeliveryPartnerPriceRangeDialog(
            orderId: deliveryOrder.orderId,
            customerName: deliveryOrder.customerName,
            customerPhone: deliveryOrder.customerPhone,
            itemName: deliveryOrder.items.isNotEmpty ? deliveryOrder.items.first.name : 'Food Order',
            budget: deliveryOrder.items.isNotEmpty ? deliveryOrder.items.first.price.toString() : '150',
          ),
        );

        if (mounted && (acceptedByCustomer == true)) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DeliveryBillPostPage(order: deliveryOrder),
            ),
          ).then((_) => _loadPartnerData());
        }
        return;
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DeliveryBillPostPage(order: deliveryOrder),
        ),
      ).then((_) => _loadPartnerData());
    }
  }
}

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
  int touchpoints = 18;
  bool isOnline = true;
  double currentBalance = 2500.00;
  double totalEarnings = 10000.00;
  double todayEarnings = 350.00;
  int totalDeliveries = 120;
  int todayDeliveries = 8;
  String partnerName = "Karthi";
  String? profileImagePath;
  String? profileImageBase64;
  int pendingOrderCount = 0;
  Timer? _pendingOrdersTimer;
  final Set<String> _knownOrderIds = {};
  final Set<String> _notifiedCancelledOrderIds = {};
  bool _isShowingIncomingModal = false;
  int _pollCount = 0;
  Map<String, dynamic>? activeDeliveryOrder;

  @override
  void initState() {
    super.initState();
    _loadPartnerData();
    _startOrdersPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptLocationService();
    });
  }

  @override
  void dispose() {
    _pendingOrdersTimer?.cancel();
    AlarmService.stopAlarm();
    super.dispose();
  }

  // 🛰️ Requirement: "app kull avanthathum 2 perukum location on pana solanum"
  Future<void> _checkAndPromptLocationService() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && mounted) {
        await _showTurnOnGPSDialog(
          title: "Turn On GPS Location",
          message: "Please turn ON device GPS location to receive incoming orders within 10 km and enable live tracking.",
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever && mounted) {
        await _showTurnOnGPSDialog(
          title: "Location Permission Required",
          message: "Location permission is disabled for Getmye Delivery. Please enable it in device settings to receive delivery orders.",
          isPermissionSettings: true,
        );
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        _updateLiveLocationToBackend();
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
    // ⚡ Fast polling: 1500ms for instantaneous order alerts!
    _pendingOrdersTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _pollCount++;
      if (_pollCount % 4 == 0) {
        _updateLiveLocationToBackend();
      }
      _checkPendingOrders();
    });
  }

  Future<void> _updateLiveLocationToBackend() async {
    if (!isOnline) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pId = prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? 'DP001';
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 4),
          );
      await http.post(
        ApiConfig.trackingUpdate,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'partner_id': pId,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'is_online': isOnline,
          'status': activeDeliveryOrder != null ? 'delivering' : 'idle',
          'order_id': activeDeliveryOrder?['order_id'],
        }),
      );
    } catch (_) {}
  }

  Future<void> _checkPendingOrders() async {
    if (!isOnline) {
      AlarmService.stopAlarm();
      return;
    }


    try {
      final res = await http.get(ApiConfig.orderPending);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List orders = data['orders'] ?? [];
        final prefs = await SharedPreferences.getInstance();
        final declinedIds = prefs.getStringList('partner_declined_order_ids') ?? [];
        final activeId = prefs.getString('partner_active_order_id') ?? prefs.getString('active_order_id');

        // 🚨 CANCELLATION DETECTOR: Alert delivery partner immediately with Reason if order cancelled
        for (final o in orders) {
          final oStatus = (o['status']?.toString() ?? '').toLowerCase();
          final oId = o['order_id']?.toString() ?? '';
          final cReason = o['cancel_reason']?.toString() ?? 'Cancelled by customer';
          if (oStatus == 'cancelled' && !_notifiedCancelledOrderIds.contains(oId)) {
            _notifiedCancelledOrderIds.add(oId);

            // 1. Immediately stop and silence any ringing alarm
            AlarmService.stopAlarm();
            AlarmService.silenceOrder(oId);

            // 2. High-priority local notification with the exact cancellation reason
            AppNotificationService.showOrderCancelledNotification(
              orderId: oId,
              reason: cReason,
            );

            // 3. If incoming order modal is currently open on screen, dismiss it
            if (_isShowingIncomingModal && mounted) {
              Navigator.of(context, rootNavigator: true).pop();
              _isShowingIncomingModal = false;
            }

            // 4. If this order was partner's ongoing delivery, clear it immediately
            if (activeDeliveryOrder != null && activeDeliveryOrder!['order_id'] == oId) {
              if (mounted) {
                setState(() {
                  activeDeliveryOrder = null;
                });
              }
              final p = await SharedPreferences.getInstance();
              await p.remove('partner_active_order_id');
              await p.remove('active_order_id');
            }

            // 5. Show prominent cancellation notice dialog on partner screen
            if (mounted) {
              _showCancellationNoticeDialog(oId, cReason);
            }
          }
        }

        // Only consider pending orders strictly unhandled
        final unhandledOrders = orders.where((o) {
          final id = o['order_id']?.toString() ?? '';
          final status = (o['status']?.toString() ?? '').toLowerCase();
          return !declinedIds.contains(id) &&
              !AlarmService.isOrderSilenced(id) &&
              id != activeId &&
              status == 'pending';
        }).toList();

        // Mark initial check completed so alarm can sound for unhandled orders
        AlarmService.hasCompletedInitialCheck = true;

        if (mounted) {
          setState(() {
            pendingOrderCount = unhandledOrders.length;
          });

          // 🚨 ALARM SOUND & MODAL: Alert partner for incoming orders (broadcast to online partners)
          if (unhandledOrders.isNotEmpty && isOnline) {
            final firstOrder = unhandledOrders.first;
            final newId = firstOrder['order_id']?.toString();
            if (newId != null) _knownOrderIds.add(newId);
            AlarmService.startAlarm(
              orderId: newId,
              item: firstOrder['item_name']?.toString(),
            );
            if (!_isShowingIncomingModal && mounted) {
              _showIncomingOrderModal(firstOrder as Map<String, dynamic>);
            }
          } else {
            AlarmService.stopAlarm();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _showIncomingOrderModal(Map<String, dynamic> order) async {
    if (_isShowingIncomingModal || !mounted) return;
    _isShowingIncomingModal = true;

    final orderId = order['order_id']?.toString() ?? '';
    final itemName = order['item_name']?.toString() ?? 'Food Order';
    final budget = order['budget']?.toString() ?? '150';
    final customerName = order['customer_name']?.toString() ?? 'Customer';
    final customerPhone = order['customer_phone']?.toString() ?? '';
    final address = order['delivery_address']?.toString() ?? 'Customer Delivery Location';

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
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
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: const Text(
                        "⚡ Online Alert",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

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
                          AlarmService.silenceOrder(orderId);
                          AlarmService.stopAlarm();
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
                            );
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
                          AlarmService.silenceOrder(orderId);
                          AlarmService.stopAlarm();
                          final prefs = await SharedPreferences.getInstance();
                          final pName = prefs.getString('d_name') ?? prefs.getString('partner_name') ?? "Delivery Partner";
                          final pPhone = prefs.getString('d_phone') ?? prefs.getString('partner_phone') ?? "";
                          final pId = prefs.getString('d_id') ?? prefs.getString('partner_id') ?? prefs.getString('active_order_partner_id') ?? 'DP001';

                          try {
                            await http.post(
                              ApiConfig.orderAccept,
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode({
                                'order_id': orderId,
                                'partner_id': pId,
                                'partner_name': pName,
                                'partner_phone': pPhone,
                              }),
                            );
                          } catch (e) {
                            debugPrint("Error accepting order: $e");
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

                          if (modalCtx.mounted) Navigator.pop(modalCtx);

                          if (mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DeliveryBillPostPage(order: deliveryOrder),
                              ),
                            ).then((_) => _loadPartnerData());
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
        );
      },
    );

    _isShowingIncomingModal = false;
  }

  Future<void> _loadPartnerData() async {
    final prefs = await SharedPreferences.getInstance();
    final dId = prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? '';
    final dPhone = prefs.getString('d_phone') ?? '';
    final localPath = prefs.getString('d_profile_image');
    final localBase64 = prefs.getString('d_profile_picture_base64');

    setState(() {
      partnerName = prefs.getString('d_name') ?? "Karthi";
      totalEarnings = prefs.getDouble('total_earnings') ?? 10000.00;
      todayEarnings = prefs.getDouble('today_earnings') ?? 350.00;
      currentBalance = prefs.getDouble('wallet_balance') ?? 2500.00;
      totalDeliveries = prefs.getInt('total_deliveries') ?? 120;
      todayDeliveries = prefs.getInt('today_deliveries') ?? 8;
      touchpoints = prefs.getInt('partner_milestone_touchpoints') ?? 18;
      isOnline = prefs.getBool('d_is_online') ?? true;
      profileImagePath = localPath;
      profileImageBase64 = localBase64;
    });

    final identifier = dId.isNotEmpty ? dId : dPhone;
    if (identifier.isNotEmpty && (profileImagePath == null || !File(profileImagePath!).existsSync())) {
      _fetchPartnerProfileFromBackend(identifier);
    }

    _checkPendingOrders();
  }

  Future<void> _fetchPartnerProfileFromBackend(String identifier) async {
    try {
      final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/deliveryperson/$identifier'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final b64 = data['profile_picture']?.toString();
        if (b64 != null && b64.isNotEmpty && mounted) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('d_profile_picture_base64', b64);
          setState(() {
            profileImageBase64 = b64;
          });
        }
        if (data['name'] != null && data['name'].toString().isNotEmpty && mounted) {
          setState(() {
            partnerName = data['name'].toString();
          });
        }
      }
    } catch (_) {}
  }

  Widget _buildProfileAvatar() {
    ImageProvider? imageProvider;

    // 1. Try local file path (from camera/gallery in dprofile or registration)
    if (profileImagePath != null && profileImagePath!.isNotEmpty) {
      final file = File(profileImagePath!);
      if (file.existsSync()) {
        imageProvider = FileImage(file);
      }
    }

    // 2. Try base64 from backend MongoDB
    if (imageProvider == null && profileImageBase64 != null && profileImageBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(profileImageBase64!);
        imageProvider = MemoryImage(bytes);
      } catch (_) {}
    }

    // 3. Fallback toon asset
    imageProvider ??= const AssetImage('assets/delivery_boy_toon.png');

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const dEditProfilePage()),
        ).then((_) => _loadPartnerData());
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
            image: imageProvider,
            fit: BoxFit.cover,
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
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.two_wheeler_rounded,
                color: AppColors.primaryDark,
                size: 22,
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
              color: isOnline ? AppColors.primaryLight : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isOnline ? AppColors.primarySubtle : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isOnline ? AppColors.primary : AppColors.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isOnline ? "ONLINE" : "OFFLINE",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isOnline ? AppColors.primaryDark : AppColors.textSecondary,
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
                              Text(
                                "₹${totalEarnings.toStringAsFixed(0)}",
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
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
                              Text(
                                "₹${todayEarnings.toStringAsFixed(0)}",
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFE8F2FF),
                                  letterSpacing: -0.5,
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isOnline ? Icons.check_circle_rounded : Icons.pause_circle_outline_rounded,
                          color: isOnline ? AppColors.primary : AppColors.textMuted,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOnline ? "You are Online" : "You are Offline",
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              isOnline ? "Receiving new delivery orders" : "Toggle online to receive new orders",
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: isOnline,
                      activeThumbColor: AppColors.primary,
                      onChanged: (val) async {
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
                        } else {
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
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: Color(0xFF1E3A8A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      const Text(
                                        "Finish this delivery to receive new orders",
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
                                        final oId = activeDeliveryOrder?['order_id']?.toString() ?? '';
                                        if (oId.isNotEmpty) {
                                          _showPartnerCancelDeliveryDialog(oId);
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEE2E2),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFFCA5A5)),
                                        ),
                                        child: const Text(
                                          "Cancel",
                                          style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
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
                                      const Text(
                                        "New Orders Ready",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: Color(0xFF78350F),
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
            const SizedBox(height: 18),

            // Milestone Progress Card
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
                        const Text(
                          "Milestone Progress",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                    Row(
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
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
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
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _showCancellationNoticeDialog(String orderId, String reason) {
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
                Navigator.pop(ctx);
                _loadPartnerData();
              },
              child: const Text("OK, Got It", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _showPartnerCancelDeliveryDialog(String orderId) {
    String selectedReason = "Emergency / Vehicle issue";
    final customReasonController = TextEditingController();
    final reasons = [
      "Emergency / Vehicle issue",
      "Store is closed / items unavailable",
      "Unable to reach customer",
      "Heavy rain / road blocked",
      "Other reason",
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Cancel Ongoing Delivery",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        Text(
                          "Order #$orderId",
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                "Please select why you need to cancel:",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: reasons.map((r) {
                  final isSelected = selectedReason == r;
                  return ChoiceChip(
                    label: Text(r),
                    selected: isSelected,
                    selectedColor: const Color(0xFFFEE2E2),
                    backgroundColor: const Color(0xFFF1F5F9),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? const Color(0xFFDC2626) : AppColors.textPrimary,
                    ),
                    onSelected: (_) {
                      setModalState(() {
                        selectedReason = r;
                      });
                    },
                  );
                }).toList(),
              ),
              if (selectedReason == "Other reason") ...[
                const SizedBox(height: 12),
                TextField(
                  controller: customReasonController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: "Enter specific reason...",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("Keep Order", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        final finalReason = selectedReason == "Other reason" && customReasonController.text.trim().isNotEmpty
                            ? customReasonController.text.trim()
                            : selectedReason;
                        Navigator.pop(ctx);
                        await _cancelDeliveryAsPartner(orderId, finalReason);
                      },
                      child: const Text("Confirm Cancel", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelDeliveryAsPartner(String orderId, String reason) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final partnerId = prefs.getString('active_order_partner_id') ?? prefs.getString('d_id') ?? 'DP001';

      await http.post(
        ApiConfig.orderCancel,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'order_id': orderId,
          'cancel_reason': reason,
          'cancelled_by': 'partner',
          'partner_id': partnerId,
        }),
      );

      await prefs.remove('partner_active_order_id');
      await prefs.remove('active_order_id');
      await prefs.setString('order_${orderId}_status', 'cancelled');

      AlarmService.stopAlarm();
      AlarmService.silenceOrder(orderId);

      if (mounted) {
        setState(() {
          activeDeliveryOrder = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Order #$orderId has been cancelled ($reason)"),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
      _loadPartnerData();
    } catch (e) {
      debugPrint("Error cancelling delivery as partner: $e");
    }
  }
}

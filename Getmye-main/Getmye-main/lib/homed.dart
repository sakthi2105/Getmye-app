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
  bool _isShowingIncomingModal = false;
  int _pollCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPartnerData();
    _startOrdersPolling();
  }

  @override
  void dispose() {
    _pendingOrdersTimer?.cancel();
    AlarmService.stopAlarm();
    super.dispose();
  }

  void _startOrdersPolling() {
    _pendingOrdersTimer?.cancel();
    _checkPendingOrders();
    _updateLiveLocationToBackend();
    _pendingOrdersTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollCount++;
      if (_pollCount % 5 == 0) {
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
          'status': 'idle',
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
      final prefs = await SharedPreferences.getInstance();
      final pId = prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? '';

      // 📍 Retrieve live GPS coordinates to enforce 2 KM radius matching
      double? lat;
      double? lng;
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          lat = pos.latitude;
          lng = pos.longitude;
        }
      } catch (_) {}

      final uri = ApiConfig.orderPendingWithParams(
        partnerId: pId,
        latitude: lat,
        longitude: lng,
      );

      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        // If backend reports partner is busy on active delivery or offline, stop alarm
        if (data['is_online'] == false || data['has_active_delivery'] == true) {
          AlarmService.stopAlarm();
          if (mounted) {
            setState(() {
              pendingOrderCount = 0;
            });
          }
          return;
        }

        final List orders = data['orders'] ?? [];
        final declinedIds = prefs.getStringList('partner_declined_order_ids') ?? [];
        final activeId = prefs.getString('active_order_id');

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

          // 🚨 ALARM SOUND & MODAL: Alert partner for incoming orders (2 KM match or online broadcast)
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
    final isWithin2km = order['is_within_2km'] == true;
    final distanceKm = order['distance_km'];

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
                        color: isWithin2km ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isWithin2km ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Text(
                        isWithin2km ? "⚡ < 2 KM" : (distanceKm != null ? "📡 ${distanceKm}km" : "Online Alert"),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isWithin2km ? const Color(0xFF15803D) : const Color(0xFFB45309),
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
                          final pName = prefs.getString('d_name') ?? "Karthi";
                          final pPhone = prefs.getString('d_phone') ?? "+91 98765 43210";
                          final pId = prefs.getString('active_order_partner_id') ?? prefs.getString('d_id') ?? 'DP001';

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

                          if (modalCtx.mounted) Navigator.pop(modalCtx);

                          if (mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const NewOrdersPage()),
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
                    )
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
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_config.dart';
import 'services/alarm_service.dart';
import 'services/app_notification_service.dart';
import 'services/order_chat_sheet.dart';
import 'theme/app_theme.dart';
import 'widgets/delivery_bottom_nav_bar.dart';
import 'ppp.dart';
import 'homed.dart';
import 'services/route_service.dart';

class BillItem {
  String name;
  int quantity;
  double price;
  bool isCollected;

  BillItem({
    required this.name,
    required this.quantity,
    required this.price,
    this.isCollected = false,
  });

  double get total => quantity * price;

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'price': price,
        'isCollected': isCollected,
      };

  factory BillItem.fromJson(Map<String, dynamic> json) => BillItem(
        name: json['name'] as String? ?? 'Item',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        isCollected: json['isCollected'] as bool? ?? true,
      );
}

class DeliveryOrder {
  final String orderId;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final String restaurantName;
  final String restaurantAddress;
  final List<BillItem> items;
  final double deliveryFee;
  String status;
  final String? cancelReason;
  final double? customerLatitude;
  final double? customerLongitude;

  DeliveryOrder({
    required this.orderId,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    required this.restaurantName,
    required this.restaurantAddress,
    required this.items,
    this.deliveryFee = 0.0,
    this.status = "Ready for Pickup",
    this.cancelReason,
    this.customerLatitude,
    this.customerLongitude,
  });

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.total);
  double get grandTotal => subtotal + deliveryFee;
}

/// 1. New Orders Page for Delivery Partner
class NewOrdersPage extends StatefulWidget {
  const NewOrdersPage({super.key});

  @override
  State<NewOrdersPage> createState() => _NewOrdersPageState();
}

class _NewOrdersPageState extends State<NewOrdersPage> {
  final List<DeliveryOrder> _orders = [];
  final Set<String> _declinedOrderIds = {};
  final Set<String> _acceptedOrderIds = {};
  final Set<String> _notifiedCancelledOrderIds = {};
  Timer? _pollingTimer;
  bool _isFetchingOrders = false;

  @override
  void initState() {
    super.initState();
    _fetchPendingOrders();
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _fetchPendingOrders();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    AlarmService.stopAlarm();
    super.dispose();
  }

  Future<void> _fetchPendingOrders() async {
    if (_isFetchingOrders) return;
    _isFetchingOrders = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final isOnline = prefs.getBool('d_is_online') ?? true;
      if (!isOnline) {
        if (mounted) {
          setState(() {
            _orders.clear();
            AlarmService.stopAlarm();
          });
        }
        return;
      }

      final savedDeclined = prefs.getStringList('partner_declined_order_ids') ?? [];
      _declinedOrderIds.addAll(savedDeclined);
      final activeSavedId = prefs.getString('partner_active_order_id');
      if (activeSavedId != null && activeSavedId.isNotEmpty) {
        _acceptedOrderIds.add(activeSavedId);
      }

      final pId = prefs.getString('active_order_partner_id') ?? prefs.getString('d_id') ?? 'DP001';
      final res = await http.get(Uri.parse("${ApiConfig.orderPending}?partner_id=$pId")).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List ordersList = data['orders'] ?? [];
        final List<DeliveryOrder> loaded = [];

        for (var o in ordersList) {
          final oId = o['order_id'] ?? '';
          final status = o['status'] ?? 'pending';
          final localStatus = prefs.getString('order_${oId}_status');
          final isDeliveredLocal = prefs.getBool('order_${oId}_completed') ?? false;

          // 1. Handle Customer Order Cancellation
          if (status == 'cancelled' || localStatus == 'cancelled') {
            final cReason = o['cancel_reason']?.toString() ?? 'Cancelled by customer';
            if (!_notifiedCancelledOrderIds.contains(oId)) {
              _notifiedCancelledOrderIds.add(oId);
              AppNotificationService.showOrderCancelledNotification(
                orderId: oId,
                reason: cReason,
              );
              AlarmService.stopAlarm();
            }

            // Save to today_completed_deliveries so it stays visible in Today Deliveries list
            final localJson = prefs.getString('today_completed_deliveries');
            List localList = [];
            if (localJson != null && localJson.isNotEmpty) {
              try {
                localList = jsonDecode(localJson);
              } catch (_) {}
            }
            if (!localList.any((e) => e['order_id'] == oId)) {
              localList.insert(0, {
                'order_id': oId,
                'item_name': o['item_name'] ?? 'Food Item',
                'budget': o['budget'] ?? 150,
                'grand_total': o['grand_total'] ?? o['budget'] ?? 150,
                'delivery_address': o['delivery_address'] ?? 'Customer Delivery Location',
                'customer_name': o['customer_name'] ?? 'Customer',
                'customer_phone': o['customer_phone'] ?? '',
                'status': 'cancelled',
                'cancel_reason': cReason,
                'cancelled_at': DateTime.now().toIso8601String(),
              });
              await prefs.setString('today_completed_deliveries', jsonEncode(localList));
            }

            // Keep in loaded orders list with status cancelled
            loaded.add(
              DeliveryOrder(
                orderId: oId,
                customerName: o['customer_name'] ?? 'Customer',
                customerPhone: o['customer_phone'] ?? '+91 98765 43210',
                deliveryAddress: o['delivery_address'] ?? 'Customer Delivery Location',
                restaurantName: "Local Restaurant",
                restaurantAddress: "Pickup Point (Store)",
                items: [
                  BillItem(name: o['item_name'] ?? 'Food Item', quantity: 1, price: (o['budget'] as num?)?.toDouble() ?? 150.0, isCollected: false),
                ],
                deliveryFee: 0.0,
                status: "cancelled",
                cancelReason: cReason,
                customerLatitude: (o['customer_latitude'] as num?)?.toDouble(),
                customerLongitude: (o['customer_longitude'] as num?)?.toDouble(),
              ),
            );
            continue;
          }

          if (localStatus == 'delivered' || isDeliveredLocal || status == 'delivered') {
            continue;
          }

          final cName = o['customer_name'] ?? 'Customer';
          final cPhone = o['customer_phone'] ?? '+91 98765 43210';
          final dAddr = o['delivery_address'] ?? 'Customer Delivery Location';
          final iName = o['item_name'] ?? 'Food Item';
          final bVal = (o['budget'] as num?)?.toDouble() ?? 150.0;
          final isAccepted = status != 'pending' &&
              (_acceptedOrderIds.contains(oId) ||
                  (activeSavedId != null && activeSavedId.isNotEmpty && oId == activeSavedId) ||
                  localStatus == 'accepted' ||
                  status == 'accepted' ||
                  status == 'purchasing_food' ||
                  status == 'bill_sent' ||
                  status == 'picked_up' ||
                  status == 'in_transit' ||
                  status == 'Accepted');
          final isDeclined = !isAccepted &&
              (_declinedOrderIds.contains(oId) ||
                  localStatus == 'declined' ||
                  status == 'declined' ||
                  status == 'rejected');

          loaded.add(
            DeliveryOrder(
              orderId: oId,
              customerName: cName,
              customerPhone: cPhone,
              deliveryAddress: dAddr,
              restaurantName: "Local Restaurant",
              restaurantAddress: "Pickup Point (Store)",
              items: [
                BillItem(name: iName, quantity: 1, price: bVal, isCollected: false),
              ],
              deliveryFee: 0.0,
              status: isAccepted ? "Accepted" : (isDeclined ? "declined" : "New Customer Order"),
              customerLatitude: (o['customer_latitude'] as num?)?.toDouble(),
              customerLongitude: (o['customer_longitude'] as num?)?.toDouble(),
            ),
          );
        }

        if (mounted) {
          setState(() {
            // Keep any currently accepted, declined or cancelled order in _orders so it NEVER disappears, unless completed
            for (var cur in _orders) {
              final isDone = (prefs.getString('order_${cur.orderId}_status') == 'delivered') || (prefs.getBool('order_${cur.orderId}_completed') ?? false);
              final isKeep = cur.status == "Accepted" || cur.status == "declined" || cur.status == "rejected" || cur.status == "cancelled";
              if (isKeep && !isDone && !loaded.any((l) => l.orderId == cur.orderId)) {
                loaded.insert(0, cur);
              }
            }
            _orders.clear();
            _orders.addAll(loaded);

            // Ring alarm continuously only for unhandled pending orders (stop immediately for accepted, declined, cancelled, silenced)
            final hasPending = _orders.any((o) =>
                !_declinedOrderIds.contains(o.orderId) &&
                !_acceptedOrderIds.contains(o.orderId) &&
                !AlarmService.isOrderSilenced(o.orderId) &&
                o.status != "Accepted" &&
                o.status != "declined" &&
                o.status != "rejected" &&
                o.status != "cancelled");
            if (hasPending && isOnline) {
              AlarmService.startAlarm();
            } else {
              AlarmService.stopAlarm();
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching pending orders from backend: $e");
    } finally {
      _isFetchingOrders = false;
    }
  }

  Future<void> _showDeclineReasonDialog(DeliveryOrder order, int index) async {
    AlarmService.silenceOrder(order.orderId); // Stop sound immediately and permanently
    _declinedOrderIds.add(order.orderId);
    _acceptedOrderIds.remove(order.orderId);
    final prefs = await SharedPreferences.getInstance();
    final currentDeclined = prefs.getStringList('partner_declined_order_ids') ?? [];
    if (!currentDeclined.contains(order.orderId)) {
      currentDeclined.add(order.orderId);
      await prefs.setStringList('partner_declined_order_ids', currentDeclined);
    }
    String selectedReason = "Vehicle Breakdown / Issue";
    final TextEditingController customController = TextEditingController();

    final List<String> reasons = [
      "Vehicle Breakdown / Issue",
      "Distance Too Far / Heavy Traffic",
      "Heavy Rain / Bad Weather",
      "Shop Closed / Out of Stock",
      "Personal Emergency",
      "Other Reason"
    ];

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 24),
                  SizedBox(width: 8),
                  Text("Decline Order", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Specify the reason for declining order ${order.orderId}:",
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    ...reasons.map((r) => RadioListTile<String>(
                          value: r,
                          groupValue: selectedReason,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: const Color(0xFFDC2626),
                          title: Text(r, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedReason = val);
                            }
                          },
                        )),
                    if (selectedReason == "Other Reason") ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: customController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: "Enter specific reason...",
                          hintStyle: const TextStyle(fontSize: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.all(10),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Confirm Decline", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      final finalReason = selectedReason == "Other Reason" && customController.text.trim().isNotEmpty
          ? customController.text.trim()
          : selectedReason;

      setState(() {
        order.status = "declined";
      });
      _declinedOrderIds.add(order.orderId);
      _acceptedOrderIds.remove(order.orderId);

      // Stop alarm continuously
      AlarmService.stopAlarm();

      // Send decline reason to MongoDB
      try {
        final prefs = await SharedPreferences.getInstance();
        final pId = prefs.getString('d_id') ?? prefs.getString('partner_id') ?? 'DP001';
        await http.post(
          ApiConfig.orderDecline,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'order_id': order.orderId,
            'decline_reason': finalReason,
            'partner_id': pId,
          }),
        );
        await prefs.setString('order_${order.orderId}_status', 'declined');
      } catch (e) {
        debugPrint("Error sending decline to DB: $e");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cancel_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text("Order ${order.orderId} rejected: $finalReason")),
              ],
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _handleBackNavigation() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text(
            "New Orders",
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
            onPressed: _handleBackNavigation,
          ),
        ),
      body: _orders.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.inbox_rounded, size: 64, color: AppColors.textMuted),
                  SizedBox(height: 12),
                  Text(
                    "No new orders at the moment",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _orders.length,
              itemBuilder: (context, index) {
                final order = _orders[index];
                final isCancelled = order.status == "cancelled" || order.status == "CANCELLED";
                final isAccepted = order.status == "Accepted" || order.status == "accepted" || order.status == "purchasing_food";
                final isDeclined = !isAccepted && (order.status == "declined" || order.status == "rejected" || order.status == "Declined" || order.status == "Rejected");
                final isReady = order.status == "Ready for Pickup" || isAccepted;
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: (isCancelled || isDeclined)
                          ? const Color(0xFFEF4444)
                          : (isAccepted ? const Color(0xFF86EFAC) : AppColors.border),
                      width: (isCancelled || isDeclined) ? 1.8 : (isAccepted ? 1.5 : 1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: (isCancelled || isDeclined)
                              ? const Color(0xFFFEE2E2)
                              : (isAccepted
                                  ? const Color(0xFFDCFCE7)
                                  : (isReady ? const Color(0xFFEFF6FF) : const Color(0xFFFEF3C7))),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  (isCancelled || isDeclined)
                                      ? Icons.cancel_rounded
                                      : (isAccepted
                                          ? Icons.check_circle_rounded
                                          : (isReady ? Icons.local_shipping_rounded : Icons.hourglass_top_rounded)),
                                  size: 18,
                                  color: (isCancelled || isDeclined)
                                      ? const Color(0xFFDC2626)
                                      : (isAccepted
                                          ? const Color(0xFF15803D)
                                          : (isReady ? const Color(0xFF2563EB) : const Color(0xFFB45309))),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  order.orderId,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: (isCancelled || isDeclined)
                                        ? const Color(0xFFDC2626)
                                        : (isAccepted
                                            ? const Color(0xFF15803D)
                                            : (isReady ? const Color(0xFF2563EB) : const Color(0xFFB45309))),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (isCancelled || isDeclined) ? const Color(0xFFDC2626) : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isCancelled ? "CANCELLED" : (isDeclined ? "REJECTED" : (isAccepted ? "ACCEPTED" : order.status)),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: (isCancelled || isDeclined) ? Colors.white : (isAccepted ? const Color(0xFF15803D) : AppColors.textPrimary),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Restaurant Info
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.storefront_rounded, size: 20, color: AppColors.primaryDark),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        order.restaurantName,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                                      ),
                                      Text(
                                        order.restaurantAddress,
                                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Customer Info
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.location_on_rounded, size: 20, color: Color(0xFFEF4444)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "${order.customerName} (${order.customerPhone})",
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                                      ),
                                      Text(
                                        order.deliveryAddress,
                                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            // Ordered Items Preview
                            const Text(
                              "Items Ordered:",
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            ...order.items.map((it) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("• ${it.quantity}× ${it.name}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  Text("₹${it.total.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                ],
                              ),
                            )),
                            const SizedBox(height: 16),
                            // Total Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Estimated Total", style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                    Text(
                                      "₹${order.grandTotal.toStringAsFixed(0)}",
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primaryDark),
                                    ),
                                  ],
                                ),
                                if (isAccepted)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      "ACCEPTED",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF15803D),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Actions Row / Banner
                            if (isCancelled) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFFCA5A5)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.cancel_rounded, size: 18, color: Color(0xFFDC2626)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        order.cancelReason != null && order.cancelReason!.isNotEmpty
                                            ? "CANCELLED: ${order.cancelReason}"
                                            : "ORDER CANCELLED BY CUSTOMER",
                                        style: const TextStyle(
                                          color: Color(0xFFDC2626),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else if (isDeclined) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFFCA5A5)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.cancel_outlined, size: 18, color: Color(0xFFDC2626)),
                                    SizedBox(width: 8),
                                    Text(
                                      "ORDER REJECTED",
                                      style: TextStyle(
                                        color: Color(0xFFDC2626),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else if (isAccepted) ...[
                              Row(
                                children: [
                                  IconButton.filled(
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.primaryLight,
                                      foregroundColor: AppColors.primary,
                                      minimumSize: const Size(42, 42),
                                    ),
                                    icon: const Icon(Icons.phone_rounded, size: 18),
                                    tooltip: "Call Customer",
                                    onPressed: () async {
                                      final uri = Uri.parse("tel:${order.customerPhone.replaceAll(' ', '')}");
                                      if (await canLaunchUrl(uri)) launchUrl(uri);
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filled(
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xFFFEF3C7),
                                      foregroundColor: const Color(0xFFD97706),
                                      minimumSize: const Size(42, 42),
                                    ),
                                    icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                                    tooltip: "Chat with Customer",
                                    onPressed: () {
                                      OrderChatSheet.show(
                                        context,
                                        orderId: order.orderId,
                                        senderRole: 'partner',
                                        otherPartyName: order.customerName,
                                        otherPartyPhone: order.customerPhone,
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SizedBox(
                                      height: 44,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF047857),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        icon: const Icon(Icons.shopping_bag_rounded, size: 18),
                                        label: const Text(
                                          "Buy Food & Bill",
                                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => DeliveryBillPostPage(order: order),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 44,
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFFDC2626),
                                          side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        icon: const Icon(Icons.close_rounded, size: 16),
                                        label: const Text("Decline", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                        onPressed: () => _showDeclineReasonDialog(order, index),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SizedBox(
                                      height: 44,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                                        label: const Text("Accept", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                        onPressed: () async {
                                          AlarmService.silenceOrder(order.orderId);
                                          _declinedOrderIds.remove(order.orderId);
                                          _acceptedOrderIds.add(order.orderId);
                                          setState(() {
                                            order.status = "Accepted";
                                          });
                                          AlarmService.stopAlarm();
                                          final prefs = await SharedPreferences.getInstance();
                                          await prefs.setString('order_${order.orderId}_status', 'accepted');
                                          final savedDeclined = prefs.getStringList('partner_declined_order_ids') ?? [];
                                          if (savedDeclined.contains(order.orderId)) {
                                            savedDeclined.remove(order.orderId);
                                            await prefs.setStringList('partner_declined_order_ids', savedDeclined);
                                          }
                                          final partnerName = prefs.getString('d_name') ?? prefs.getString('partner_name') ?? "Delivery Partner";
                                          final partnerPhone = prefs.getString('d_phone') ?? prefs.getString('partner_phone') ?? "";
                                          final partnerId = prefs.getString('d_id') ?? prefs.getString('partner_id') ?? prefs.getString('active_order_partner_id') ?? 'DP001';
                                          try {
                                            await http.post(
                                              ApiConfig.orderAccept,
                                              headers: {'Content-Type': 'application/json'},
                                              body: jsonEncode({
                                                'order_id': order.orderId,
                                                'partner_id': partnerId,
                                                'partner_name': partnerName,
                                                'partner_phone': partnerPhone,
                                              }),
                                            );
                                          } catch (e) {
                                            debugPrint("Error accepting order on backend: $e");
                                          }
                                          await prefs.setBool('active_order_partner_accepted', true);
                                          await prefs.setString('active_order_partner_id', partnerId);
                                          await prefs.setString('active_order_partner_name', partnerName);
                                          await prefs.setString('active_order_partner_phone', partnerPhone);
                                          await prefs.setBool('has_new_order_notification', false);
                                          await prefs.setString('active_order_id', order.orderId);
                                          await prefs.setString('active_order_status', 'accepted');
                                          await prefs.setString('active_order_customer_name', order.customerName);
                                          await prefs.setString('active_order_customer_phone', order.customerPhone);
                                          await prefs.setString('active_order_customer_address', order.deliveryAddress);
                                          await prefs.setString('active_order_restaurant', order.restaurantName);
                                          await prefs.setDouble('active_order_grand_total', order.grandTotal);
                                          if (!context.mounted) return;
                                           Navigator.push(
                                             context,
                                             MaterialPageRoute(
                                               builder: (_) => DeliveryBillPostPage(order: order),
                                             ),
                                           );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: const DeliveryBottomNavBar(currentIndex: 3),
    ),
  );
}
}

/// 2. Delivery Partner Page to Confirm Order and Post Food Bill Image with Items & Prices
class DeliveryBillPostPage extends StatefulWidget {
  final DeliveryOrder? order;
  const DeliveryBillPostPage({super.key, this.order});

  @override
  State<DeliveryBillPostPage> createState() => _DeliveryBillPostPageState();
}

class _DeliveryBillPostPageState extends State<DeliveryBillPostPage> {
  late DeliveryOrder _order;
  XFile? _billImage;
  final ImagePicker _picker = ImagePicker();
  late List<BillItem> _items;
  double _deliveryFee = 0.0;
  Timer? _statusCheckTimer;
  bool _isCheckingStatus = false;
  int _lastSeenMsgCount = 0;

  @override
  void initState() {
    super.initState();
    _order = widget.order ?? DeliveryOrder(
      orderId: "ORD-8492",
      customerName: "Priya Sharma",
      customerPhone: "+91 98765 43210",
      deliveryAddress: "Customer Live Delivery Location",
      restaurantName: "Food Point Store",
      restaurantAddress: "Pickup Point (Store)",
      items: [
        BillItem(name: "Chicken Dum Biryani", quantity: 1, price: 180.0, isCollected: true),
        BillItem(name: "Chicken Shawarma Roll", quantity: 2, price: 80.0, isCollected: true),
      ],
      deliveryFee: 0.0,
    );
    _items = List.from(_order.items);
    _deliveryFee = 0.0;

    // Notify backend that partner is at restaurant purchasing food
    try {
      http.post(
        ApiConfig.orderUpdateStatus,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'order_id': _order.orderId,
          'status': 'purchasing_food',
        }),
      );
    } catch (_) {}

    _statusCheckTimer = Timer.periodic(const Duration(seconds: 4), (_) => _checkOrderCancelled());
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkOrderCancelled() async {
    if (_isCheckingStatus) return;
    _isCheckingStatus = true;
    try {
      final res = await http.get(ApiConfig.orderById(_order.orderId)).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final orderData = data['order'] ?? data;
        // Incoming chat messages are tracked globally and deduplicated via AppNotificationService

        if (orderData['status'] == 'cancelled') {
          _statusCheckTimer?.cancel();
          final reason = orderData['cancel_reason'] ?? 'Customer cancelled the order';
          AppNotificationService.showOrderCancelledNotification(
            orderId: _order.orderId,
            reason: reason,
          );
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Row(
                  children: [
                    Icon(Icons.cancel_rounded, color: Color(0xFFDC2626)),
                    SizedBox(width: 8),
                    Text("Order Cancelled", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                content: Text(
                  "Customer has cancelled this order.\n\nReason: $reason",
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
                        (route) => false,
                      );
                    },
                    child: const Text("Return to Home", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }
        }
      }
    } catch (_) {
    } finally {
      _isCheckingStatus = false;
    }
  }

  double get _subtotal => _items.fold(0.0, (sum, item) => sum + item.total);
  double get _grandTotal => _subtotal + _deliveryFee;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source, imageQuality: 85);
      if (image != null) {
        setState(() {
          _billImage = image;
        });
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  void _showImagePickerModal() {
    // Only open camera directly - Gallery upload removed
    _pickImage(ImageSource.camera);
  }

  void _showAddItemDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final qtyController = TextEditingController(text: "1");

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Food Item", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Dish Name", hintText: "e.g. Parotta"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Price (₹)", hintText: "e.g. 50"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Quantity", hintText: "e.g. 2"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryDark),
            onPressed: () {
              final name = nameController.text.trim();
              final price = double.tryParse(priceController.text.trim()) ?? 0.0;
              final qty = int.tryParse(qtyController.text.trim()) ?? 1;

              if (name.isNotEmpty && price > 0) {
                setState(() {
                  _items.add(BillItem(name: name, quantity: qty, price: price, isCollected: true));
                });
                Navigator.pop(context);
              }
            },
            child: const Text("Add Item", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndSendBill() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please add at least one item to the bill")),
      );
      return;
    }

    // Submit bill to backend API & MongoDB with base64 image if uploaded
    String? base64BillImage;
    if (_billImage != null && File(_billImage!.path).existsSync()) {
      try {
        final bytes = await File(_billImage!.path).readAsBytes();
        base64BillImage = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      } catch (e) {
        debugPrint("Error encoding bill image: $e");
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final currentPartnerId = prefs.getString('active_order_partner_id') ?? prefs.getString('d_id') ?? prefs.getString('partner_id') ?? 'DP001';
      await http.post(
        ApiConfig.billSubmit,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'order_id': _order.orderId,
          'partner_id': currentPartnerId,
          'user_id': 'usr_001',
          'shop_name': _order.restaurantName.isNotEmpty ? _order.restaurantName : 'Restaurant',
          'items': _items.map((i) => {
            'name': i.name,
            'quantity': i.quantity,
            'price': i.price,
            'total': i.total,
          }).toList(),
          'item_total': _subtotal,
          'delivery_fee': 0.0,
          'grand_total': _grandTotal,
          'bill_image_url': base64BillImage,
        }),
      );
    } catch (e) {
      debugPrint("Error submitting bill to backend: $e");
    }

    // Save active order & bill state in SharedPreferences scoped to order ID
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('active_order_bill_sent', true);
    await prefs.setBool('active_order_food_purchased', true);
    await prefs.setString('active_order_id', _order.orderId);
    await prefs.setString('active_order_customer_name', _order.customerName);
    await prefs.setString('active_order_customer_phone', _order.customerPhone);
    await prefs.setString('active_order_customer_address', _order.deliveryAddress);
    await prefs.setDouble('active_order_grand_total', _grandTotal);
    await prefs.setDouble('active_order_delivery_fee', 0.0);
    // Remove stale global key so old images never leak
    await prefs.remove('active_order_bill_image');
    if (_billImage != null) {
      await prefs.setString('order_${_order.orderId}_bill_image', _billImage!.path);
    }
    final itemsJson = jsonEncode(_items.map((i) => i.toJson()).toList());
    await prefs.setString('active_order_items_json', itemsJson);

    if (!mounted) return;

    // Show toast
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Bill sent to customer! Opening GPS Navigation Map..."),
        backgroundColor: AppColors.primaryDark,
        duration: Duration(seconds: 2),
      ),
    );

    // AUTOMATICALLY open in-app GPS Navigation Map
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryNavigationMapPage(
          order: _order,
          billImage: _billImage,
          items: List.from(_items),
          deliveryFee: _deliveryFee,
          totalAmount: _grandTotal,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          "Order & Customer Bill",
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TOP SECTION: Customer Details & Destination
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _order.orderId,
                          style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primaryDark),
                            tooltip: "Chat with Customer",
                            onPressed: () {
                              OrderChatSheet.show(
                                context,
                                orderId: _order.orderId,
                                senderRole: 'partner',
                                otherPartyName: _order.customerName,
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.phone_in_talk_rounded, color: AppColors.primaryDark),
                            tooltip: "Call Customer",
                            onPressed: () async {
                              final uri = Uri.parse("tel:${_order.customerPhone.replaceAll(' ', '')}");
                              if (await canLaunchUrl(uri)) launchUrl(uri);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.person_rounded, size: 20, color: AppColors.primaryDark),
                      const SizedBox(width: 8),
                      Text(
                        _order.customerName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_rounded, size: 20, color: Color(0xFFEF4444)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _order.deliveryAddress,
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.restaurant_rounded, size: 18, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Pickup: ${_order.restaurantName}",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ORDERED ITEMS CHECKLIST
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Ordered Items Checklist",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                Text(
                  "${_items.where((i) => i.isCollected).length}/${_items.length} Collected",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: _items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return CheckboxListTile(
                    activeColor: AppColors.primaryDark,
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Text(
                      "${item.quantity} × ₹${item.price.toStringAsFixed(0)}",
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    value: item.isCollected,
                    onChanged: (val) {
                      setState(() {
                        _items[index].isCollected = val ?? false;
                      });
                    },
                    secondary: Text(
                      "₹${item.total.toStringAsFixed(0)}",
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // Step 1: Upload Bill Photo
            const Text(
              "Post Restaurant Bill Receipt Photo",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _showImagePickerModal,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 170,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _billImage != null ? AppColors.primary : AppColors.border,
                    width: _billImage != null ? 2 : 1.5,
                  ),
                ),
                child: _billImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(_billImage!.path), fit: BoxFit.cover),
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text("Change Photo", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: const BoxDecoration(
                              color: AppColors.primaryLight,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.add_a_photo_rounded, color: AppColors.primaryDark, size: 30),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "Tap to Take or Upload Bill Photo",
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Attach receipt for customer verification & transparency",
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // Step 2: Bill Item Breakdown & Custom Edits
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Billing Summary",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                TextButton.icon(
                  onPressed: _showAddItemDialog,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text("Add Item", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  ..._items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                Text("Qty: ${item.quantity} × ₹${item.price.toStringAsFixed(0)}", style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Text("₹${item.total.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                            onPressed: () {
                              setState(() {
                                _items.removeAt(index);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                  // Delivery fee
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Delivery Partner Fee", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        const Text("FREE (₹0)", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF16A34A))),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Total row
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.3),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Total Bill Amount", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
                        Text("₹${_grandTotal.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.primaryDark)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Confirm & Send Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _confirmAndSendBill,
                icon: const Icon(Icons.navigation_rounded, color: Colors.white),
                label: const Text(
                  "Confirm Order and Send to Bill",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// 3. In-App GPS Navigation Map Page (Opened automatically after confirming order & sending bill)
class DeliveryNavigationMapPage extends StatefulWidget {
  final DeliveryOrder order;
  final XFile? billImage;
  final List<BillItem> items;
  final double deliveryFee;
  final double totalAmount;

  const DeliveryNavigationMapPage({
    super.key,
    required this.order,
    this.billImage,
    required this.items,
    required this.deliveryFee,
    required this.totalAmount,
  });

  @override
  State<DeliveryNavigationMapPage> createState() => _DeliveryNavigationMapPageState();
}

class _DeliveryNavigationMapPageState extends State<DeliveryNavigationMapPage> {
  // Real GPS live location for driver
  LatLng _driverLocation = const LatLng(10.9601, 79.3845);
  LatLng _destinationLocation = const LatLng(10.9625, 79.3870);
  List<LatLng> _routePoints = [];
  String? _partnerId;
  GoogleMapController? _navMapController;
  StreamSubscription<Position>? _gpsStreamSubscription;
  Timer? _trackingTimer;
  bool _isBroadcasting = false;
  bool _isCheckingCancel = false;
  int _lastSeenMsgCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPartnerId();
    _initCustomerLocation();
    _initRealGpsNavigation();

    // Update order status to in_transit
    http.post(
      ApiConfig.orderUpdateStatus,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'order_id': widget.order.orderId,
        'status': 'in_transit',
      }),
    ).catchError((_) => http.Response('', 500));

    // Broadcast live location to backend every 3 seconds
    _broadcastLocation();
    _trackingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _broadcastLocation();
    });
  }

  Future<void> _loadPartnerId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _partnerId = prefs.getString('active_order_partner_id') ?? prefs.getString('d_id') ?? prefs.getString('partner_id') ?? 'DP001';
      });
    }
  }

  void _initCustomerLocation() {
    if (widget.order.customerLatitude != null &&
        widget.order.customerLongitude != null &&
        widget.order.customerLatitude != 0.0) {
      _destinationLocation = LatLng(widget.order.customerLatitude!, widget.order.customerLongitude!);
    }
  }

  Future<void> _fetchRoadRoute() async {
    try {
      final points = await RouteService.getRoadRoute(_driverLocation, _destinationLocation);
      if (mounted && points.isNotEmpty) {
        setState(() {
          _routePoints = points;
        });
      }
    } catch (_) {}
  }

  Future<void> _initRealGpsNavigation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        if (mounted) {
          setState(() {
            _driverLocation = LatLng(pos.latitude, pos.longitude);
            if (widget.order.customerLatitude != null &&
                widget.order.customerLongitude != null &&
                widget.order.customerLatitude != 0.0) {
              _destinationLocation = LatLng(widget.order.customerLatitude!, widget.order.customerLongitude!);
            } else {
              _destinationLocation = LatLng(pos.latitude + 0.003, pos.longitude + 0.003);
            }
          });
          _fetchRoadRoute();
          _navMapController?.animateCamera(
            CameraUpdate.newLatLngZoom(_driverLocation, 16.0),
          );
        }
      }
    } catch (e) {
      debugPrint("Driver GPS init error: $e");
    }

    _gpsStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position pos) {
      if (mounted) {
        setState(() {
          _driverLocation = LatLng(pos.latitude, pos.longitude);
        });
        _fetchRoadRoute();
        _broadcastLocation();
      }
    });
  }

  @override
  void dispose() {
    _gpsStreamSubscription?.cancel();
    _trackingTimer?.cancel();
    super.dispose();
  }

  void _broadcastLocation() {
    _checkOrderCancelled();
    if (_isBroadcasting) return;
    _isBroadcasting = true;
    http.post(
      ApiConfig.trackingUpdate,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'partner_id': _partnerId ?? 'DP001',
        'order_id': widget.order.orderId,
        'latitude': _driverLocation.latitude,
        'longitude': _driverLocation.longitude,
        'heading': 45.0,
        'speed': 25.0,
        'status': 'in_transit',
      }),
    ).timeout(const Duration(seconds: 3)).catchError((_) => http.Response('', 500)).whenComplete(() {
      _isBroadcasting = false;
    });
  }

  Future<void> _checkOrderCancelled() async {
    if (_isCheckingCancel) return;
    _isCheckingCancel = true;
    try {
      final res = await http.get(ApiConfig.orderById(widget.order.orderId)).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final orderData = data['order'] ?? data;

        // Check if customer live GPS is available
        if (orderData['customer_latitude'] != null && orderData['customer_longitude'] != null) {
          final cLat = (orderData['customer_latitude'] as num).toDouble();
          final cLng = (orderData['customer_longitude'] as num).toDouble();
          if (cLat != 0.0 && (_destinationLocation.latitude != cLat || _destinationLocation.longitude != cLng)) {
            if (mounted) {
              setState(() {
                _destinationLocation = LatLng(cLat, cLng);
              });
              _fetchRoadRoute();
            }
          }
        }
        // Incoming chat messages are tracked globally and deduplicated via AppNotificationService

        if (orderData['status'] == 'cancelled') {
          _trackingTimer?.cancel();
          final reason = orderData['cancel_reason'] ?? 'Customer cancelled the order';
          AppNotificationService.showOrderCancelledNotification(
            orderId: widget.order.orderId,
            reason: reason,
          );
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Row(
                  children: [
                    Icon(Icons.cancel_rounded, color: Color(0xFFDC2626)),
                    SizedBox(width: 8),
                    Text("Order Cancelled", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                content: Text(
                  "Customer has cancelled this order.\n\nReason: $reason",
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
                        (route) => false,
                      );
                    },
                    child: const Text("Return to Home", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }
        }
      }
    } catch (_) {
    } finally {
      _isCheckingCancel = false;
    }
  }

  void _showArrivedBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.pin_drop_rounded, color: AppColors.primaryDark, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Arrived at Destination", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                        Text("Select customer payment mode to complete order", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Bill Amount to Collect", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    Text("₹${widget.totalAmount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.primaryDark)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Option 1: Verify Online Payment OTP
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF047857),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.verified_user_rounded),
                  label: const Text("Verify Online Payment OTP", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final prefs = await SharedPreferences.getInstance();
                    String? savedOtp = prefs.getString('active_cod_otp');
                    if (savedOtp == null || savedOtp.isEmpty) {
                      final random = Random();
                      savedOtp = (1000 + random.nextInt(9000)).toString();
                      await prefs.setString('active_cod_otp', savedOtp);
                    }
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DeliveryCodVerificationPage(
                          order: widget.order,
                          totalAmount: widget.totalAmount,
                          expectedOtp: savedOtp!,
                          isOnlinePayment: true,
                          paymentMethod: "Online UPI",
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              // Option 2: Cash on Delivery (COD) Flow
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.payments_rounded),
                  label: const Text("Collect Cash on Delivery (COD)", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final prefs = await SharedPreferences.getInstance();
                    String? savedOtp = prefs.getString('active_cod_otp');
                    if (savedOtp == null || savedOtp.isEmpty) {
                      final random = Random();
                      savedOtp = (1000 + random.nextInt(9000)).toString();
                      await prefs.setString('active_cod_otp', savedOtp);
                    }
                    await prefs.setDouble('active_cod_amount', widget.totalAmount);
                    await prefs.setBool('is_cod_selected', true);

                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DeliveryCodVerificationPage(
                          order: widget.order,
                          totalAmount: widget.totalAmount,
                          expectedOtp: savedOtp!,
                          isOnlinePayment: false,
                          paymentMethod: "Cash on Delivery (COD)",
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              // Option 3: View Customer Bill Details
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primaryDark, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.receipt_long_rounded, color: AppColors.primaryDark),
                  label: const Text("View Customer Bill Details", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CustomerBillViewPage(
                          order: widget.order,
                          orderId: widget.order.orderId,
                          customerName: widget.order.customerName,
                          customerPhone: widget.order.customerPhone,
                          billImage: widget.billImage,
                          items: widget.items,
                          deliveryFee: widget.deliveryFee,
                          totalAmount: widget.totalAmount,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Turn-by-Turn GPS Navigation", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded, color: AppColors.primaryDark),
            tooltip: "View Customer Bill Details",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CustomerBillViewPage(
                    order: widget.order,
                    orderId: widget.order.orderId,
                    customerName: widget.order.customerName,
                    customerPhone: widget.order.customerPhone,
                    billImage: widget.billImage,
                    items: widget.items,
                    deliveryFee: widget.deliveryFee,
                    totalAmount: widget.totalAmount,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primaryDark),
            tooltip: "Chat with Customer",
            onPressed: () {
              OrderChatSheet.show(
                context,
                orderId: widget.order.orderId,
                senderRole: 'partner',
                otherPartyName: widget.order.customerName,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.phone_in_talk_rounded, color: AppColors.primaryDark),
            tooltip: "Call Customer",
            onPressed: () async {
              final uri = Uri.parse("tel:${widget.order.customerPhone.replaceAll(' ', '')}");
              if (await canLaunchUrl(uri)) launchUrl(uri);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Google Map Navigation
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _driverLocation,
              zoom: 16.0,
            ),
            onMapCreated: (ctrl) => _navMapController = ctrl,
            zoomControlsEnabled: false,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: {
              Marker(
                markerId: const MarkerId('driver'),
                position: _driverLocation,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                infoWindow: const InfoWindow(title: 'Your Location (Rider)'),
              ),
              Marker(
                markerId: const MarkerId('customer'),
                position: _destinationLocation,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                infoWindow: InfoWindow(title: widget.order.customerName, snippet: widget.order.deliveryAddress),
              ),
            },
            polylines: {
              Polyline(
                polylineId: const PolylineId('nav_route'),
                points: _routePoints.isNotEmpty ? _routePoints : [
                  _driverLocation,
                  _destinationLocation,
                ],
                color: const Color(0xFF15803D),
                width: 5,
              ),
            },
          ),

          // Top Turn Instruction Card
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.turn_right_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("In 200m, turn right onto Cross Cut Rd", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 2),
                        Text("1.8 km • 6 mins remaining to destination", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Destination Card & Arrived Button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, -4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.order.customerName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text("Order ${widget.order.orderId} • ₹${widget.totalAmount.toStringAsFixed(0)}", style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.near_me_rounded, size: 14, color: AppColors.primaryDark),
                            SizedBox(width: 4),
                            Text("1.8 km", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primaryDark)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.order.deliveryAddress,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text("I have Arrived at Delivery Address", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      onPressed: _showArrivedBottomSheet,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 4. Delivery OTP Verification Page for Delivery Partner (Supports Online & COD)
class DeliveryCodVerificationPage extends StatefulWidget {
  final DeliveryOrder order;
  final double totalAmount;
  final String expectedOtp;
  final bool isOnlinePayment;
  final String paymentMethod;

  const DeliveryCodVerificationPage({
    super.key,
    required this.order,
    required this.totalAmount,
    required this.expectedOtp,
    this.isOnlinePayment = false,
    this.paymentMethod = "Cash on Delivery (COD)",
  });

  @override
  State<DeliveryCodVerificationPage> createState() => _DeliveryCodVerificationPageState();
}

class _DeliveryCodVerificationPageState extends State<DeliveryCodVerificationPage> {
  final TextEditingController _otpController = TextEditingController();
  bool _isVerifying = false;
  String _effectiveOtp = "";
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _effectiveOtp = widget.expectedOtp;
    _loadSavedOtp();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) => _loadSavedOtp());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedOtp() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('active_cod_otp');
    if (saved != null && saved.isNotEmpty && _effectiveOtp.isEmpty) {
      if (mounted) {
        setState(() {
          _effectiveOtp = saved;
        });
      }
    }
    // Cross-device sync: Fetch live OTP stored in MongoDB from customer's device
    try {
      final res = await http.get(ApiConfig.orderById(widget.order.orderId));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final order = data['order'];
        if (order != null && order['cod_otp'] != null && order['cod_otp'].toString().isNotEmpty) {
          final backendOtp = order['cod_otp'].toString();
          if (mounted && _effectiveOtp != backendOtp) {
            setState(() {
              _effectiveOtp = backendOtp;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching OTP from backend: $e");
    }
  }

  Future<void> _verifyOtp() async {
    final enteredOtp = _otpController.text.trim();
    if (enteredOtp.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter the complete 4-digit OTP provided by customer")),
      );
      return;
    }

    setState(() => _isVerifying = true);

    bool isValid = (enteredOtp == _effectiveOtp || enteredOtp == widget.expectedOtp);

    if (!isValid) {
      // Cross-check with backend endpoint
      try {
        final verifyRes = await http.post(
          ApiConfig.orderVerifyDeliveryOtp,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'order_id': widget.order.orderId,
            'entered_otp': enteredOtp,
          }),
        );
        if (verifyRes.statusCode == 200) {
          isValid = true;
        }
      } catch (_) {}
    }

    if (isValid) {
      _refreshTimer?.cancel();
      // Update Total Earnings, Today Earnings, Deliveries counts & Wallet Balance
      final prefs = await SharedPreferences.getInstance();
      double currentBalance = prefs.getDouble('wallet_balance') ?? 2500.0;
      double totalEarnings = prefs.getDouble('total_earnings') ?? 10000.0;
      double todayEarnings = prefs.getDouble('today_earnings') ?? 350.0;
      int totalDeliveries = prefs.getInt('total_deliveries') ?? 120;
      int todayDeliveries = prefs.getInt('today_deliveries') ?? 8;

      const double partnerEarnings = 75.0; // Payout for this completed delivery
      await prefs.setDouble('wallet_balance', currentBalance + partnerEarnings);
      await prefs.setDouble('total_earnings', totalEarnings + partnerEarnings);
      await prefs.setDouble('today_earnings', todayEarnings + partnerEarnings);
      await prefs.setInt('total_deliveries', totalDeliveries + 1);
      await prefs.setInt('today_deliveries', todayDeliveries + 1);
      await prefs.setBool('active_order_bill_sent', false);
      await prefs.setString('active_order_status', 'Delivered & Paid');

      // Milestone increment upon order completion
      int touchpoints = prefs.getInt('partner_milestone_touchpoints') ?? 18;
      await prefs.setInt('partner_milestone_touchpoints', (touchpoints + 4).clamp(0, 50));

      // Save to today_completed_deliveries for Today Deliveries / Delivery History
      final localJson = prefs.getString('today_completed_deliveries');
      List<dynamic> localList = [];
      if (localJson != null && localJson.isNotEmpty) {
        try {
          localList = jsonDecode(localJson);
        } catch (_) {}
      }
      final now = DateTime.now();
      localList.insert(0, {
        'order_id': widget.order.orderId,
        'customer_name': widget.order.customerName,
        'customer_phone': widget.order.customerPhone,
        'delivery_address': widget.order.deliveryAddress,
        'restaurant_name': widget.order.restaurantName,
        'item_name': widget.order.items.isNotEmpty ? widget.order.items.first.name : 'Food Package',
        'budget': widget.totalAmount,
        'total_amount': widget.totalAmount,
        'partner_earnings': partnerEarnings,
        'payment_method': widget.paymentMethod,
        'status': 'delivered',
        'delivered_at': now.toIso8601String(),
      });
      await prefs.setString('today_completed_deliveries', jsonEncode(localList));
      await prefs.setString('order_${widget.order.orderId}_status', 'delivered');
      await prefs.setBool('order_${widget.order.orderId}_completed', true);

      // Update backend status to delivered in MongoDB
      try {
        await http.post(
          ApiConfig.orderUpdateStatus,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'order_id': widget.order.orderId,
            'status': 'delivered',
            'payment_status': 'success',
            'payment_method': widget.paymentMethod,
          }),
        );
      } catch (_) {}

      setState(() => _isVerifying = false);

      if (!mounted) return;
      // Show full-screen green Payment Successful celebration screen without overlapping
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => FullScreenPaymentSuccessScreen(
            orderId: widget.order.orderId,
            totalAmount: widget.totalAmount,
            paymentMethod: widget.paymentMethod,
            isDeliveryPartner: true,
            earnedAmount: partnerEarnings,
          ),
        ),
        (route) => false,
      );
    } else {
      setState(() => _isVerifying = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Invalid OTP ($enteredOtp)! Ask customer for the 4-digit OTP displayed on their screen."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isOnline = widget.isOnlinePayment;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isOnline ? "Verify Online Delivery OTP" : "Verify COD Delivery OTP", style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isOnline ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                      shape: BoxShape.circle,
                      border: Border.all(color: isOnline ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
                    ),
                    child: Icon(
                      isOnline ? Icons.verified_user_rounded : Icons.currency_rupee_rounded,
                      size: 40,
                      color: isOnline ? const Color(0xFF047857) : const Color(0xFFD97706),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isOnline ? "Customer Paid Online" : "Collect Cash from Customer",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isOnline
                        ? "Customer paid ₹${widget.totalAmount.toStringAsFixed(0)} online.\nAsk customer for their 4-digit Delivery OTP"
                        : "Ask customer for ₹${widget.totalAmount.toStringAsFixed(0)} cash and their 4-digit Delivery OTP",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: isOnline ? const Color(0xFFECFDF5) : AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isOnline
                          ? "Online Paid: ₹${widget.totalAmount.toStringAsFixed(0)}"
                          : "Amount to Collect: ₹${widget.totalAmount.toStringAsFixed(0)}",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: isOnline ? const Color(0xFF047857) : AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // OTP Input Field
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Enter Customer's 4-Digit Delivery OTP", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 8),
                    decoration: InputDecoration(
                      hintText: "••••",
                      counterText: "",
                      hintStyle: const TextStyle(letterSpacing: 8, color: AppColors.textMuted),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _isVerifying ? null : _verifyOtp,
                      child: _isVerifying
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(isOnline ? "Verify OTP & Complete Delivery" : "Verify OTP & Confirm Delivery", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 5. COD Confirmed Confirmation Screen
class CodConfirmedScreen extends StatelessWidget {
  final DeliveryOrder order;
  final double totalAmount;
  final double earnedAmount;

  const CodConfirmedScreen({
    super.key,
    required this.order,
    required this.totalAmount,
    required this.earnedAmount,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 56),
              ),
              const SizedBox(height: 20),
              const Text("COD Confirmed!", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              const Text(
                "Cash collected and delivery completed successfully.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Cash Collected", style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                        Text("₹${totalAmount.toStringAsFixed(0)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Your Earnings Added", style: TextStyle(fontSize: 14, color: Color(0xFF15803D), fontWeight: FontWeight.w700)),
                        Text("+₹${earnedAmount.toStringAsFixed(0)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF15803D))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  child: const Text("Return to Home", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 6. Customer Bill Details Page (Delivery Partner Side)
class CustomerBillViewPage extends StatefulWidget {
  final DeliveryOrder? order;
  final String? orderId;
  final String? customerName;
  final String? otherPartyName;
  final String? customerPhone;
  final XFile? billImage;
  final List<BillItem> items;
  final double deliveryFee;
  final double totalAmount;

  const CustomerBillViewPage({
    super.key,
    this.order,
    this.orderId,
    this.customerName,
    this.otherPartyName,
    this.customerPhone,
    this.billImage,
    required this.items,
    required this.deliveryFee,
    required this.totalAmount,
  });

  @override
  State<CustomerBillViewPage> createState() => _CustomerBillViewPageState();
}

class _CustomerBillViewPageState extends State<CustomerBillViewPage> {
  String _customerName = "Customer";
  String _customerPhone = "+91 98765 43210";
  List<BillItem> _displayItems = [];
  double _displayDeliveryFee = 0.0;
  double _displayTotal = 0.0;
  String? _billImagePath;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadBillData();
  }

  Future<void> _loadBillData() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Resolve customer name & phone
    String cName = widget.customerName ??
        widget.otherPartyName ??
        widget.order?.customerName ??
        prefs.getString('active_order_customer_name') ??
        '';
    String cPhone = widget.customerPhone ??
        widget.order?.customerPhone ??
        prefs.getString('active_order_customer_phone') ??
        '';

    if (cName.isEmpty || cName == 'Customer' || cPhone.isEmpty) {
      final userMobile = prefs.getString('mobile_number') ?? prefs.getString('user_mobile');
      final userName = prefs.getString('user_name');
      if (cName.isEmpty && userName != null && userName.isNotEmpty) {
        cName = userName;
      }
      if (cPhone.isEmpty && userMobile != null && userMobile.isNotEmpty) {
        cPhone = userMobile;
      }
    }

    // Try backend order lookup to ensure freshest customer details
    final activeOrderId = widget.orderId ??
        widget.order?.orderId ??
        prefs.getString('active_order_id') ??
        'ORD-8492';

    try {
      final res = await http.get(ApiConfig.orderById(activeOrderId));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final orderObj = data['order'];
        if (orderObj != null) {
          if (orderObj['customer_name'] != null &&
              orderObj['customer_name'].toString().trim().isNotEmpty) {
            cName = orderObj['customer_name'];
          }
          if (orderObj['customer_phone'] != null &&
              orderObj['customer_phone'].toString().trim().isNotEmpty) {
            cPhone = orderObj['customer_phone'];
          }
        }
      }
    } catch (_) {}

    if (cName.isEmpty) cName = "Customer";
    if (cPhone.isEmpty) cPhone = "+91 98765 43210";

    // 2. Load items
    List<BillItem> loadedItems = List.from(widget.items);
    final itemsJson = prefs.getString('active_order_items_json');
    if (itemsJson != null && itemsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(itemsJson);
        final parsed = decoded
            .map((e) => BillItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (parsed.isNotEmpty) {
          loadedItems = parsed;
        }
      } catch (_) {}
    }

    if (loadedItems.isEmpty) {
      loadedItems = [
        BillItem(name: "Chicken Dum Biryani", quantity: 1, price: 180.0, isCollected: true),
        BillItem(name: "Chicken Shawarma Roll", quantity: 2, price: 80.0, isCollected: true),
      ];
    }

    for (var item in loadedItems) {
      item.isCollected = true;
    }

    String? imgPath = widget.billImage?.path ?? prefs.getString('order_${activeOrderId}_bill_image');
    double savedFee = 0.0;
    double subtotal = loadedItems.fold(0.0, (s, i) => s + i.total);
    double total = subtotal > 0 ? (subtotal + savedFee) : widget.totalAmount;

    if (mounted) {
      setState(() {
        _customerName = cName;
        _customerPhone = cPhone;
        _displayItems = loadedItems;
        _displayDeliveryFee = 0.0;
        _displayTotal = total;
        _billImagePath = imgPath;
      });
    }
  }

  void _callCustomer() async {
    final cleanPhone = _customerPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source, imageQuality: 85);
      if (image != null) {
        final prefs = await SharedPreferences.getInstance();
        final activeOrderId = widget.orderId ??
            widget.order?.orderId ??
            prefs.getString('active_order_id') ??
            'ORD-8492';
        await prefs.setString('order_${activeOrderId}_bill_image', image.path);
        await prefs.remove('active_order_bill_image');
        setState(() {
          _billImagePath = image.path;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Bill receipt photo updated successfully!"),
              backgroundColor: AppColors.primary,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error picking bill image: $e");
    }
  }

  void _showImagePickerModal() {
    // Only open camera directly - Gallery upload removed
    _pickImage(ImageSource.camera);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          "Customer Bill Details",
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Customer Name, Mobile Number & Call Customer Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_rounded, color: Color(0xFF2563EB), size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _customerName,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _customerPhone,
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFEFF6FF),
                          foregroundColor: AppColors.primaryDark,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                        tooltip: "Chat with Customer",
                        onPressed: () {
                          final oId = widget.orderId ?? widget.order?.orderId ?? 'ORD-8492';
                          OrderChatSheet.show(
                            context,
                            orderId: oId,
                            senderRole: 'partner',
                            otherPartyName: _customerName,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _callCustomer,
                        icon: const Icon(Icons.phone_rounded, size: 16),
                        label: const Text(
                          "Call Customer",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 2. Bill Details & Food Items (up to Grand Total)
            const Text(
              "Order Bill Details",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: Column(
                children: [
                  ..._displayItems.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                "${item.quantity}× ${item.name}",
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                            Text(
                              "₹${item.total.toStringAsFixed(0)}",
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ],
                        ),
                      )),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Delivery Charges", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      Text(
                        _displayDeliveryFee == 0.0 ? "FREE (₹0)" : "₹${_displayDeliveryFee.toStringAsFixed(0)}",
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF16A34A)),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Grand Total", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textPrimary)),
                      Text(
                        "₹${_displayTotal.toStringAsFixed(0)}",
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.primaryDark),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 3. Uploaded Hotel Food Bill Receipt
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Uploaded Hotel Food Bill Receipt",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                TextButton.icon(
                  onPressed: _showImagePickerModal,
                  icon: const Icon(Icons.camera_alt_rounded, size: 16, color: AppColors.primaryDark),
                  label: Text(
                    (_billImagePath != null && File(_billImagePath!).existsSync()) ? "Change Photo" : "Upload Photo",
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                color: Colors.white,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: (_billImagePath != null && File(_billImagePath!).existsSync())
                    ? Image.file(File(_billImagePath!), fit: BoxFit.cover)
                    : (widget.billImage != null && File(widget.billImage!.path).existsSync())
                        ? Image.file(File(widget.billImage!.path), fit: BoxFit.cover)
                        : InkWell(
                            onTap: _showImagePickerModal,
                            child: Container(
                              color: const Color(0xFFF8FAFC),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo_rounded, size: 48, color: Color(0xFF94A3B8)),
                                  SizedBox(height: 10),
                                  Text(
                                    "Upload Hotel Food Bill Photo",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    "Tap here to capture food bill with camera",
                                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

/// 7. Customer Module: Order Success Celebration Screen
class OrderSuccessScreen extends StatelessWidget {
  final double totalAmount;
  final String orderId;

  const OrderSuccessScreen({
    super.key,
    required this.totalAmount,
    this.orderId = "ORD-8492",
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // 3D Animated Celebration Food Box Illustration
              Container(
                height: 240,
                width: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/order_success_box.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.celebration_rounded, color: AppColors.primary, size: 80),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Celebration Heading
              const Text(
                "Order Placed Successfully!",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                "Your delicious food is being prepared & packed with care. Rider will arrive soon!",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 24),

              // Order Summary Badge Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Order Reference", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        Text(orderId, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Estimated Arrival", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        const Row(
                          children: [
                            Icon(Icons.timer_outlined, size: 16, color: AppColors.primaryDark),
                            SizedBox(width: 4),
                            Text("20–25 mins", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.primaryDark)),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Paid Amount", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        Text("₹${totalAmount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.primaryDark)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Track Order on Live Map Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.map_rounded),
                  label: const Text("Track Order on Live Map", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const HomePage()),
                      (route) => false,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Back to Home Text Button
              TextButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomePage()),
                    (route) => false,
                  );
                },
                child: const Text("Back to Home Screen", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 8. Full-Screen Green Payment Success Celebration Screen / Popup
class FullScreenPaymentSuccessScreen extends StatefulWidget {
  final double totalAmount;
  final String orderId;
  final String paymentMethod;
  final bool isDeliveryPartner;
  final double? earnedAmount;

  const FullScreenPaymentSuccessScreen({
    super.key,
    required this.totalAmount,
    this.orderId = "ORD-8492",
    this.paymentMethod = "Payment Successful",
    this.isDeliveryPartner = false,
    this.earnedAmount,
  });

  @override
  State<FullScreenPaymentSuccessScreen> createState() => _FullScreenPaymentSuccessScreenState();
}

class _FullScreenPaymentSuccessScreenState extends State<FullScreenPaymentSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF047857), // Deep emerald green
              Color(0xFF059669), // Vivid emerald green
              Color(0xFF10B981), // Lush bright green
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Animated White Circle with Vibrant Green Checkmark
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 72,
                      color: Color(0xFF059669),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Title: PAYMENT SUCCESSFUL & ORDER COMPLETE
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      const Text(
                        "Payment Successful!",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),

                      // Order Complete Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1.5),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              "Order Complete 🎉",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),
                      Text(
                        widget.isDeliveryPartner
                            ? "Delivery OTP verified! Payment and order completed successfully."
                            : "Delivery OTP verified by delivery partner! Your order has been delivered.",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Frosted Glassmorphic Payment Details Card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        "₹${widget.totalAmount.toStringAsFixed(0)}",
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.paymentMethod,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Divider(color: Colors.white.withValues(alpha: 0.25), height: 1),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Order ID", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                          Text(widget.orderId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Status", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                          const Row(
                            children: [
                              Icon(Icons.verified_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text("Verified & Completed", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                      if (widget.isDeliveryPartner && widget.earnedAmount != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Partner Payout", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                            Text("+₹${widget.earnedAmount!.toStringAsFixed(0)}", style: const TextStyle(color: Color(0xFFFEF08A), fontWeight: FontWeight.w900, fontSize: 15)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const Spacer(),

                // Click to Home Primary Button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF047857),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      if (!widget.isDeliveryPartner) {
                        await prefs.setBool('has_active_order', false);
                        await prefs.remove('active_order_id');
                        await prefs.setString('active_order_status', 'delivered');
                        await prefs.remove('order_${widget.orderId}_chat_messages');
                        await prefs.remove('active_cod_otp');
                        await prefs.remove('is_online_paid');
                        await prefs.remove('is_cod_selected');
                      } else {
                        await prefs.remove('order_${widget.orderId}_chat_messages');
                        await prefs.remove('active_order_id');
                      }

                      if (!context.mounted) return;
                      if (widget.isDeliveryPartner) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
                          (route) => false,
                        );
                      } else {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const HomePage()),
                          (route) => false,
                        );
                      }
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.home_rounded, size: 22),
                        SizedBox(width: 8),
                        Text(
                          "Click to Home",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

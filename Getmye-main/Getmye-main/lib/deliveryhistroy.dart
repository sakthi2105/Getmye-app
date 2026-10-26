import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'theme/app_theme.dart';

class DeliveryListPage extends StatefulWidget {
  final bool isTodayOnly;
  const DeliveryListPage({super.key, this.isTodayOnly = false});

  @override
  State<DeliveryListPage> createState() => _DeliveryListPageState();
}

class _DeliveryListPageState extends State<DeliveryListPage> {
  bool _isLoading = true;
  List<dynamic> _orders = [];
  String _partnerId = 'DP001';

  @override
  void initState() {
    super.initState();
    _fetchDeliveredOrders();
  }

  Future<void> _fetchDeliveredOrders() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _partnerId = prefs.getString('d_id') ??
        prefs.getString('partner_id') ??
        prefs.getString('active_order_partner_id') ??
        prefs.getString('d_phone') ??
        '';

    List<dynamic> combined = [];

    // Load locally saved completed orders for this specific partner
    if (_partnerId.isNotEmpty) {
      final localJson = prefs.getString('${_partnerId}_today_completed_deliveries');
      if (localJson != null && localJson.isNotEmpty) {
        try {
          final List localList = jsonDecode(localJson);
          combined.addAll(localList);
        } catch (_) {}
      }
    }

    try {
      if (_partnerId.isNotEmpty) {
        final res = await http.get(ApiConfig.orderPartner(_partnerId)).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final List orders = data['orders'] ?? [];
          for (var o in orders) {
            if (!combined.any((c) => c['order_id'] == o['order_id'])) {
              combined.add(o);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching delivery history from API: $e");
    }

    if (widget.isTodayOnly) {
      final now = DateTime.now();
      final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      combined = combined.where((o) {
        final dAt = o['delivered_at']?.toString() ?? o['cancelled_at']?.toString() ?? o['created_at']?.toString() ?? '';
        final status = (o['status'] ?? '').toString().toLowerCase();
        return dAt.startsWith(todayStr) || dAt.contains('Today') || status == 'delivered' || status == 'cancelled';
      }).toList();
    }

    // Sort orders newest first
    combined.sort((a, b) {
      final aDate = a['delivered_at'] ?? a['cancelled_at'] ?? a['created_at'];
      final bDate = b['delivered_at'] ?? b['cancelled_at'] ?? b['created_at'];
      final dtA = DateTime.tryParse(aDate?.toString() ?? '') ?? DateTime(2020);
      final dtB = DateTime.tryParse(bDate?.toString() ?? '') ?? DateTime(2020);
      return dtB.compareTo(dtA);
    });

    if (mounted) {
      setState(() {
        _orders = combined;
        _isLoading = false;
      });
    }
  }

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return "Recent Date";
    try {
      final dt = DateTime.parse(dateVal.toString()).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return "Today, ${dt.day} ${_getMonth(dt.month)}";
      }
      final yesterday = now.subtract(const Duration(days: 1));
      if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
        return "Yesterday, ${dt.day} ${_getMonth(dt.month)}";
      }
      return "${dt.day.toString().padLeft(2, '0')} ${_getMonth(dt.month)} ${dt.year}";
    } catch (_) {
      return dateVal.toString().split('T').first;
    }
  }

  String _formatTime(dynamic dateVal) {
    if (dateVal == null) return "--:--";
    try {
      final dt = DateTime.parse(dateVal.toString()).toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return "$h:$m $ampm";
    } catch (_) {
      return "";
    }
  }

  String _getMonth(int month) {
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return months[(month - 1).clamp(0, 11)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          widget.isTodayOnly ? "Today's Deliveries" : "Delivery History",
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primaryDark),
            tooltip: "Refresh Deliveries",
            onPressed: _fetchDeliveredOrders,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _fetchDeliveredOrders,
              color: AppColors.primary,
              child: _orders.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.delivery_dining_rounded, size: 54, color: AppColors.primaryDark),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "No Deliveries Yet",
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 8),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  "Orders you accept, deliver, or update will appear here in your official record.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
                      itemCount: _orders.length,
                      itemBuilder: (context, index) {
                        final order = _orders[index];
                        final orderId = order['order_id'] ?? 'ORD-000';
                        final food = order['item_name'] ?? 'Food items';
                        final location = order['delivery_address'] ?? 'Customer Address';
                        final cName = order['customer_name'] ?? 'Customer';
                        final cPhone = order['customer_phone'] ?? '';
                        final num grandTotal = order['grand_total'] ?? order['budget'] ?? 0;
                        final status = (order['status'] ?? 'delivered').toString().toUpperCase();
                        final deliveredAt = order['delivered_at'] ?? order['cancelled_at'] ?? order['created_at'];
                        final payMethod = order['payment_method'] ?? 'COD';
                        final cancelReason = (order['cancel_reason'] ?? order['cancellation_reason'] ?? '').toString();

                        final isCancelled = status == 'CANCELLED';
                        final isDelivered = status == 'DELIVERED';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isCancelled
                                  ? const Color(0xFFF87171)
                                  : (isDelivered ? const Color(0xFF86EFAC) : AppColors.border),
                              width: (isCancelled || isDelivered) ? 1.4 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isCancelled
                                    ? const Color(0xFFEF4444).withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Prominent Date & Time Banner
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: isCancelled ? const Color(0xFFFEF2F2) : AppColors.primarySubtle,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isCancelled ? const Color(0xFFFECACA) : AppColors.border,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_month_rounded,
                                            size: 15,
                                            color: isCancelled ? const Color(0xFFDC2626) : AppColors.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _formatDate(deliveredAt),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: isCancelled ? const Color(0xFFDC2626) : AppColors.primaryDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time_rounded,
                                            size: 14,
                                            color: isCancelled ? const Color(0xFFDC2626) : AppColors.textSecondary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatTime(deliveredAt),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: isCancelled ? const Color(0xFFDC2626) : AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Top row: Order ID, Status badge & Amount
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isCancelled ? const Color(0xFFFEE2E2) : AppColors.primaryLight,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            orderId,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: isCancelled ? const Color(0xFFDC2626) : AppColors.primaryDark,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isCancelled
                                                ? const Color(0xFFFEE2E2)
                                                : (isDelivered ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7)),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            status,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: isCancelled
                                                  ? const Color(0xFFDC2626)
                                                  : (isDelivered ? const Color(0xFF15803D) : const Color(0xFFB45309)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      "₹${grandTotal.toStringAsFixed(0)}",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: isCancelled ? const Color(0xFF9CA3AF) : AppColors.primaryDark,
                                        decoration: isCancelled ? TextDecoration.lineThrough : null,
                                      ),
                                    ),
                                  ],
                                ),
                                if (isCancelled) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFFECACA)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.cancel_rounded, size: 15, color: Color(0xFFDC2626)),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            cancelReason.isNotEmpty
                                                ? "Cancelled: $cancelReason"
                                                : "Order Cancelled by Customer",
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFFDC2626),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),

                                // Food item
                                Row(
                                  children: [
                                    const Icon(Icons.fastfood_rounded, size: 16, color: AppColors.primaryDark),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        food,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Customer name & phone
                                Row(
                                  children: [
                                    const Icon(Icons.person_rounded, size: 16, color: AppColors.textSecondary),
                                    const SizedBox(width: 8),
                                    Text(
                                      cName,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                    ),
                                    if (cPhone.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        "($cPhone)",
                                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Delivery address
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFFEF4444)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        location,
                                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),

                                // Bottom row: payment mode & delivery confirmation
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.payments_outlined, size: 15, color: AppColors.textMuted),
                                        const SizedBox(width: 6),
                                        Text(
                                          payMethod,
                                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                    if (isDelivered)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDCFCE7),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF15803D)),
                                            SizedBox(width: 4),
                                            Text(
                                              "Delivered",
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
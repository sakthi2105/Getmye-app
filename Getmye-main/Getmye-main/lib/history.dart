import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'theme/app_theme.dart';
import 'ppp.dart';

class OrderHistoryPage extends StatefulWidget {
  final Map? order;
  const OrderHistoryPage({super.key, this.order});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  bool _isLoading = true;
  List<dynamic> _orders = [];
  String _userId = 'USR-001';

  @override
  void initState() {
    super.initState();
    _fetchCustomerOrders();
  }

  Future<void> _fetchCustomerOrders() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final mobile = prefs.getString('mobile_number') ?? prefs.getString('user_mobile') ?? '';
    _userId = prefs.getString('user_id') ?? (mobile.isNotEmpty ? mobile : 'USR-001');

    try {
      final res = await http.get(ApiConfig.orderUser(_userId));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List orders = data['orders'] ?? [];
        if (mounted) {
          setState(() {
            _orders = orders;
            _isLoading = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint("Error fetching customer order history: $e");
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  String _formatDateTime(dynamic dateVal) {
    if (dateVal == null) return "Recent Order";
    try {
      final dt = DateTime.parse(dateVal.toString()).toLocal();
      const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
      final mName = months[dt.month - 1];
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return "${dt.day.toString().padLeft(2, '0')} $mName ${dt.year}, $h:$m $ampm";
    } catch (_) {
      return dateVal.toString();
    }
  }

  void _handleBackNavigation() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
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
          title: const Text("Order History", style: AppTypography.screenHeading),
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
            onPressed: _handleBackNavigation,
          ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primaryDark),
            tooltip: "Refresh Orders",
            onPressed: _fetchCustomerOrders,
          ),
        ],
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _fetchCustomerOrders,
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
                                child: const Icon(Icons.receipt_long_rounded, size: 54, color: AppColors.primaryDark),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "No Orders Yet",
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 8),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  "Your food delivery orders will be displayed here once placed.",
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
                      padding: const EdgeInsets.all(16),
                      itemCount: _orders.length,
                      itemBuilder: (context, index) {
                        final order = _orders[index];
                        final orderId = order['order_id'] ?? 'ORD-000';
                        final food = order['item_name'] ?? 'Food item';
                        final num grandTotal = order['grand_total'] ?? order['budget'] ?? 0;
                        final partner = order['partner_name'] ?? 'Delivery Partner';
                        final status = (order['status'] ?? 'pending').toString().toUpperCase();
                        final isDelivered = status == 'DELIVERED';
                        final createdAt = order['delivered_at'] ?? order['created_at'];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isDelivered ? const Color(0xFF86EFAC) : AppColors.border,
                              width: isDelivered ? 1.2 : 1,
                            ),
                            boxShadow: AppColors.subtleShadow,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isDelivered ? const Color(0xFFDCFCE7) : AppColors.primaryLight,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            status,
                                            style: TextStyle(
                                              color: isDelivered ? const Color(0xFF15803D) : AppColors.primaryDark,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          orderId,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      "₹${grandTotal.toStringAsFixed(0)}",
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.primaryDark,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  food,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.two_wheeler_rounded, size: 16, color: AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Text(
                                      "Rider: $partner",
                                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDateTime(createdAt),
                                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.background,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        order['payment_method'] ?? 'COD',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
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
      ),
    );
  }
}

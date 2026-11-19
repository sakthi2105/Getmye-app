import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../theme/admin_theme.dart';
import '../widgets/env_switcher_button.dart';

class OrdersManagementPage extends StatefulWidget {
  const OrdersManagementPage({super.key});

  @override
  State<OrdersManagementPage> createState() => _OrdersManagementPageState();
}

class _OrdersManagementPageState extends State<OrdersManagementPage> {
  List<dynamic> orders = [];
  bool isLoading = true;
  String selectedFilter = 'all'; // 'all', 'pending', 'active', 'delivered', 'cancelled'
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> fetchOrders() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(AdminApiConfig.ordersAll(status: selectedFilter));
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['orders'] is List) {
          setState(() {
            orders = decoded['orders'] as List;
            isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  List<dynamic> get filteredOrders {
    if (searchQuery.trim().isEmpty) return orders;
    final q = searchQuery.toLowerCase().trim();
    return orders.where((ord) {
      final id = (ord['order_id'] ?? '').toString().toLowerCase();
      final customer = (ord['customer_name'] ?? '').toString().toLowerCase();
      final phone = (ord['customer_phone'] ?? '').toString().toLowerCase();
      final item = (ord['item_name'] ?? '').toString().toLowerCase();
      final partner = (ord['partner_name'] ?? '').toString().toLowerCase();
      return id.contains(q) || customer.contains(q) || phone.contains(q) || item.contains(q) || partner.contains(q);
    }).toList();
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp.toString()).toLocal();
      return DateFormat('dd MMM, hh:mm a').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        title: const Text('Live Customer Orders Management'),
        actions: [
          EnvSwitcherButton(onEnvironmentChanged: fetchOrders),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Refresh orders',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: fetchOrders,
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AdminColors.border, height: 1),
        ),
      ),
      body: RefreshIndicator(
        color: AdminColors.primary,
        onRefresh: fetchOrders,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AdminColors.border),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => searchQuery = val),
                      style: const TextStyle(fontSize: 14, color: AdminColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search by Order ID, Customer Name, Mobile, Item...',
                        hintStyle: const TextStyle(color: AdminColors.textMuted, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.primaryDark, size: 20),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'All Orders'),
                        const SizedBox(width: 8),
                        _buildFilterChip('pending', 'Pending Dispatch'),
                        const SizedBox(width: 8),
                        _buildFilterChip('accepted', 'Accepted / In Transit'),
                        const SizedBox(width: 8),
                        _buildFilterChip('delivered', 'Delivered'),
                        const SizedBox(width: 8),
                        _buildFilterChip('cancelled', 'Cancelled'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header with Count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Orders Queue (${filteredOrders.length})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AdminColors.textPrimary,
                        ),
                      ),
                      if (isLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AdminColors.primary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Orders List
                  if (isLoading && orders.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(color: AdminColors.primary),
                      ),
                    )
                  else if (filteredOrders.isEmpty)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 24),
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AdminColors.border),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.inventory_2_outlined, size: 36, color: AdminColors.textMuted),
                            SizedBox(height: 10),
                            Text(
                              'No Orders Found',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'No customer orders match this filter or search criteria.',
                              style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredOrders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final ord = filteredOrders[index];
                        return _buildOrderCard(ord);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String filter, String label) {
    final isSelected = selectedFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          setState(() => selectedFilter = filter);
          fetchOrders();
        }
      },
      selectedColor: AdminColors.primary,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: isSelected ? Colors.white : AdminColors.textSecondary,
      ),
      side: BorderSide(color: isSelected ? AdminColors.primary : AdminColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildOrderCard(dynamic ord) {
    final orderId = ord['order_id'] ?? '#ORD';
    final customer = ord['customer_name'] ?? 'Customer';
    final phone = ord['customer_phone'] ?? 'N/A';
    final address = ord['delivery_address'] ?? 'Kumbakonam';
    final itemName = ord['item_name'] ?? 'Food items';
    final quantity = ord['quantity'] ?? 1;
    final grandTotal = ord['grand_total'] ?? (ord['budget'] ?? 0);
    final status = (ord['status'] ?? 'pending').toString().toLowerCase();
    final partnerName = ord['partner_name'];
    final partnerId = ord['partner_id'];
    final codOtp = ord['cod_otp'] ?? '----';
    final dateStr = _formatDate(ord['created_at']);

    Color statusColor;
    Color statusBg;
    if (status == 'delivered') {
      statusColor = AdminColors.success;
      statusBg = AdminColors.primaryLight;
    } else if (status == 'cancelled') {
      statusColor = AdminColors.danger;
      statusBg = AdminColors.dangerLight;
    } else if (status == 'pending') {
      statusColor = const Color(0xFFB45309);
      statusBg = AdminColors.warningLight;
    } else {
      statusColor = AdminColors.primaryDark;
      statusBg = AdminColors.primaryLight;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AdminColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: AdminColors.primaryDark, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    orderId,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  if (dateStr.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '•  $dateStr',
                      style: const TextStyle(fontSize: 11, color: AdminColors.textMuted),
                    ),
                  ],
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Order Items & Grand Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$quantity x $itemName',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 13, color: AdminColors.textMuted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            address,
                            style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹$grandTotal',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AdminColors.primaryDark,
                    ),
                  ),
                  Text(
                    'OTP: $codOtp',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AdminColors.borderLight),
          const SizedBox(height: 10),

          // Customer and Partner metadata
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Customer: $customer ($phone)',
                style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary, fontWeight: FontWeight.w500),
              ),
              Text(
                partnerName != null ? 'Partner: $partnerName (#$partnerId)' : 'Partner: Not Assigned',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: partnerName != null ? AdminColors.primaryDark : AdminColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


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
  Map<String, dynamic>? overviewStats;
  bool isLoading = true;
  String selectedSide = 'today'; // 'today' (Side 1) or 'total' (Side 2)
  String selectedFilter = 'all';
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  int get todayOrdersCount => overviewStats?['today_orders'] ?? 0;
  int get todayRemainingCount => overviewStats?['today_remaining_orders'] ?? 0;
  int get todayDeliveredCount => overviewStats?['today_delivered_orders'] ?? 0;
  int get todayCancelledCount => overviewStats?['today_cancelled_orders'] ?? 0;
  int get totalOrdersAllTimeCount => overviewStats?['total_orders_all_time'] ?? 0;

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
      final timeframe = selectedSide == 'today' ? 'today' : null;
      final results = await Future.wait([
        http.get(AdminApiConfig.ordersAll(status: selectedFilter, timeframe: timeframe)),
        http.get(AdminApiConfig.ordersOverview),
      ]);

      final ordersRes = results[0];
      final overviewRes = results[1];

      if (ordersRes.statusCode == 200) {
        final decoded = json.decode(ordersRes.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['orders'] is List) {
          orders = decoded['orders'] as List;
        }
      }

      if (overviewRes.statusCode == 200) {
        final decodedOverview = json.decode(overviewRes.body);
        if (mounted && decodedOverview is Map<String, dynamic>) {
          overviewStats = decodedOverview;
        }
      }
    } catch (_) {
    } finally {
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
                  // 1. Two-Sided Tab Switcher (Today's Orders vs Total Orders)
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AdminColors.border),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        // Side 1: Today's Orders
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (selectedSide != 'today') {
                                setState(() {
                                  selectedSide = 'today';
                                  selectedFilter = 'all';
                                });
                                fetchOrders();
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                              decoration: BoxDecoration(
                                color: selectedSide == 'today' ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: selectedSide == 'today'
                                    ? [const BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))]
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.today_rounded,
                                    size: 18,
                                    color: selectedSide == 'today' ? AdminColors.primaryDark : AdminColors.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Today's Orders",
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: selectedSide == 'today' ? AdminColors.primaryDark : AdminColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: selectedSide == 'today' ? AdminColors.primaryLight : const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$todayOrdersCount',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: selectedSide == 'today' ? AdminColors.primaryDark : AdminColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  if (todayRemainingCount > 0) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '$todayRemainingCount left',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFB45309),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Side 2: Total Orders (All-Time)
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (selectedSide != 'total') {
                                setState(() {
                                  selectedSide = 'total';
                                  selectedFilter = 'all';
                                });
                                fetchOrders();
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                              decoration: BoxDecoration(
                                color: selectedSide == 'total' ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: selectedSide == 'total'
                                    ? [const BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))]
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.inventory_2_rounded,
                                    size: 18,
                                    color: selectedSide == 'total' ? const Color(0xFF6D28D9) : AdminColors.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Total Orders (All-Time)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: selectedSide == 'total' ? const Color(0xFF6D28D9) : AdminColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: selectedSide == 'total' ? const Color(0xFFF5F3FF) : const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$totalOrdersAllTimeCount',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: selectedSide == 'total' ? const Color(0xFF6D28D9) : AdminColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2. Today's Orders Summary Bar with "Remaining Orders" Showcase
                  if (selectedSide == 'today') ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AdminColors.border),
                        boxShadow: const [
                          BoxShadow(color: Color(0x04000000), blurRadius: 8, offset: Offset(0, 3)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                    child: const Icon(Icons.speed_rounded, color: AdminColors.primaryDark, size: 18),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    "Today's Live Order Pipeline",
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: todayRemainingCount > 0 ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: todayRemainingCount > 0 ? const Color(0xFFFCD34D) : const Color(0xFF86EFAC),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 4,
                                      backgroundColor: todayRemainingCount > 0 ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      todayRemainingCount > 0
                                          ? '$todayRemainingCount Orders Remaining'
                                          : 'All Orders Delivered',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: todayRemainingCount > 0 ? const Color(0xFFB45309) : const Color(0xFF15803D),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _buildMiniMetric(
                                title: "Today Placed",
                                value: '$todayOrdersCount',
                                icon: Icons.receipt_long_rounded,
                                color: AdminColors.primaryDark,
                                bgColor: AdminColors.primaryLight,
                              ),
                              const SizedBox(width: 10),
                              _buildMiniMetric(
                                title: "Remaining Active",
                                value: '$todayRemainingCount',
                                icon: Icons.pending_actions_rounded,
                                color: const Color(0xFFB45309),
                                bgColor: const Color(0xFFFEF3C7),
                                isHighlighted: true,
                              ),
                              const SizedBox(width: 10),
                              _buildMiniMetric(
                                title: "Delivered",
                                value: '$todayDeliveredCount',
                                icon: Icons.check_circle_rounded,
                                color: const Color(0xFF047857),
                                bgColor: const Color(0xFFDCFCE7),
                              ),
                              const SizedBox(width: 10),
                              _buildMiniMetric(
                                title: "Cancelled",
                                value: '$todayCancelledCount',
                                icon: Icons.cancel_rounded,
                                color: AdminColors.danger,
                                bgColor: AdminColors.dangerLight,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // 3. Search Bar
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
                        hintText: selectedSide == 'today'
                            ? "Search today's orders by ID, Customer Name, Mobile, Item..."
                            : 'Search all-time orders by ID, Customer, Mobile, Partner...',
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

                  // 4. Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: selectedSide == 'today'
                          ? [
                              _buildFilterChip('all', 'All Today ($todayOrdersCount)'),
                              const SizedBox(width: 8),
                              _buildFilterChip('remaining', '⏳ Remaining Orders ($todayRemainingCount)'),
                              const SizedBox(width: 8),
                              _buildFilterChip('delivered', '✅ Delivered ($todayDeliveredCount)'),
                              const SizedBox(width: 8),
                              _buildFilterChip('cancelled', '❌ Cancelled ($todayCancelledCount)'),
                            ]
                          : [
                              _buildFilterChip('all', 'All Orders ($totalOrdersAllTimeCount)'),
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
                        selectedSide == 'today'
                            ? "Today's Orders List (${filteredOrders.length})"
                            : 'All-Time Orders Archive (${filteredOrders.length})',
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
                          children: [
                            const Icon(Icons.inventory_2_outlined, size: 36, color: AdminColors.textMuted),
                            const SizedBox(height: 10),
                            Text(
                              selectedSide == 'today' ? "No Orders Placed Today" : 'No Orders Found',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              selectedSide == 'today'
                                  ? 'New orders received today will automatically appear here.'
                                  : 'No customer orders match this filter or search criteria.',
                              style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
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

  Widget _buildMiniMetric({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
    bool isHighlighted = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isHighlighted ? bgColor : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted ? color.withValues(alpha: 0.35) : AdminColors.border,
            width: isHighlighted ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isHighlighted ? color : AdminColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: isHighlighted ? color : AdminColors.textPrimary,
              ),
            ),
          ],
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


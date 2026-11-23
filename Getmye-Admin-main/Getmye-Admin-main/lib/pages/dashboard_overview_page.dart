import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/admin_auth_service.dart';
import '../theme/admin_theme.dart';
import '../widgets/env_switcher_button.dart';

class DashboardOverviewPage extends StatefulWidget {
  final Function(int) onNavigateToTab;

  const DashboardOverviewPage({required this.onNavigateToTab, super.key});

  @override
  State<DashboardOverviewPage> createState() => _DashboardOverviewPageState();
}

class _DashboardOverviewPageState extends State<DashboardOverviewPage> {
  Map<String, dynamic>? overviewStats;
  Map<String, dynamic>? activeBanner;
  bool isLoading = true;
  bool isServerConnected = false;

  @override
  void initState() {
    super.initState();
    refreshDashboard();
  }

  Future<void> refreshDashboard() async {
    setState(() => isLoading = true);
    await Future.wait([
      _checkServerHealth(),
      _fetchOverviewStats(),
      _fetchActiveBanner(),
    ]);
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _checkServerHealth() async {
    try {
      final res = await http.get(AdminApiConfig.health).timeout(const Duration(seconds: 4));
      if (mounted) {
        setState(() => isServerConnected = res.statusCode == 200);
      }
    } catch (_) {
      if (mounted) setState(() => isServerConnected = false);
    }
  }

  Future<void> _fetchOverviewStats() async {
    try {
      final res = await http.get(AdminApiConfig.ordersOverview);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic>) {
          setState(() => overviewStats = decoded);
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchActiveBanner() async {
    try {
      final res = await http.get(AdminApiConfig.bannerActive);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['banner'] != null) {
          setState(() => activeBanner = decoded['banner'] as Map<String, dynamic>);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final todayOrders = overviewStats?['today_orders']?.toString() ?? '0';
    final todayRemaining = overviewStats?['today_remaining_orders']?.toString() ?? '0';
    final todayRevenue = overviewStats?['today_revenue']?.toString() ?? '0';
    final totalOrdersAllTime = overviewStats?['total_orders_all_time']?.toString() ?? overviewStats?['total_orders']?.toString() ?? '0';
    final totalRevenueAllTime = overviewStats?['total_revenue_all_time']?.toString() ?? overviewStats?['total_revenue']?.toString() ?? '0';
    final pendingKYC = overviewStats?['pending_kyc']?.toString() ?? '0';
    final onlinePartners = overviewStats?['online_partners']?.toString() ?? '0';
    final activeOrders = overviewStats?['active_orders']?.toString() ?? '0';

    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AdminColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.admin_panel_settings_rounded,
                color: AdminColors.primaryDark,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                    children: [
                      TextSpan(text: 'GetMye ', style: TextStyle(color: AdminColors.textPrimary)),
                      TextSpan(text: 'Admin Master Hub', style: TextStyle(color: AdminColors.primaryDark)),
                    ],
                  ),
                ),
                Text(
                  AdminAuthService.currentAdminEmail ?? 'sakthigopi210505@gmail.com',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AdminColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          EnvSwitcherButton(onEnvironmentChanged: refreshDashboard),
          const SizedBox(width: 6),
          // Server connectivity pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isServerConnected ? AdminColors.primaryLight : AdminColors.dangerLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 4,
                  backgroundColor: isServerConnected ? AdminColors.primary : AdminColors.danger,
                ),
                const SizedBox(width: 6),
                Text(
                  isServerConnected ? 'Server Online' : 'Connecting...',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isServerConnected ? AdminColors.primaryDark : AdminColors.danger,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh Dashboard',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: refreshDashboard,
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
        onRefresh: refreshDashboard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // KPI Overview Grid
                  const Text(
                    'Real-Time Operations Overview',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                  ),
                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      // Consolidated Customer Orders Card (Today's Orders + Remaining + Total All-Time)
                      _buildOrdersHubCard(
                        todayOrders: todayOrders,
                        todayRemaining: todayRemaining,
                        totalOrders: totalOrdersAllTime,
                        onTap: () => widget.onNavigateToTab(4),
                      ),
                      // Consolidated Gross Sales Card (Today's Sales + Total All-Time Sales)
                      _buildSalesHubCard(
                        todayRevenue: todayRevenue,
                        totalRevenue: totalRevenueAllTime,
                        onTap: () => widget.onNavigateToTab(4),
                      ),
                      _buildKpiCard(
                        title: 'Active Fleet Online',
                        value: onlinePartners,
                        icon: Icons.delivery_dining_rounded,
                        color: const Color(0xFF2563EB),
                        bgColor: const Color(0xFFEFF6FF),
                        onTap: () => _showActiveFleetDialog(context),
                      ),
                      _buildKpiCard(
                        title: 'Pending KYC Review',
                        value: pendingKYC,
                        icon: Icons.checklist_rounded,
                        color: const Color(0xFFB45309),
                        bgColor: AdminColors.warningLight,
                        onTap: () => widget.onNavigateToTab(1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Quick Action Hub
                  const Text(
                    'Quick Operational Actions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _buildActionCard(
                          title: 'Upload Offer Banner',
                          subtitle: 'Change image & deal on Customer Home',
                          icon: Icons.campaign_rounded,
                          color: AdminColors.primary,
                          onTap: () => widget.onNavigateToTab(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionCard(
                          title: 'Verify Partner KYCs',
                          subtitle: '3-point document checklists inspection',
                          icon: Icons.how_to_reg_rounded,
                          color: const Color(0xFFB45309),
                          onTap: () => widget.onNavigateToTab(1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _buildActionCard(
                          title: 'Customer Grievances & Bugs',
                          subtitle: 'Review bug reports & user feedback',
                          icon: Icons.support_agent_rounded,
                          color: const Color(0xFF7C3AED),
                          onTap: () => widget.onNavigateToTab(3),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionCard(
                          title: 'Live Order Tracking',
                          subtitle: '$activeOrders active orders dispatching now',
                          icon: Icons.shopping_bag_rounded,
                          color: const Color(0xFF0284C7),
                          onTap: () => widget.onNavigateToTab(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Current Active Offer Banner Snapshot
                  _buildCurrentOfferSnapshot(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showActiveFleetDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) {
        return FutureBuilder<http.Response>(
          future: http.get(AdminApiConfig.activeFleet),
          builder: (context, snapshot) {
            Widget content;
            if (snapshot.connectionState == ConnectionState.waiting) {
              content = const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(color: AdminColors.primary),
                ),
              );
            } else if (snapshot.hasError || snapshot.data?.statusCode != 200) {
              content = Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 48, color: AdminColors.textMuted),
                    const SizedBox(height: 12),
                    const Text(
                      'Failed to load active fleet',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ensure backend server is online: ${AdminApiConfig.baseUrl}',
                      style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            } else {
              final body = json.decode(snapshot.data!.body);
              final List<dynamic> fleet = body['fleet'] ?? [];

              if (fleet.isEmpty) {
                content = Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEFF6FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delivery_dining_rounded,
                          size: 40,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '0 Delivery Partners Online',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AdminColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No delivery partners are currently active online.\nPartners will appear here in real time as soon as they log into the Delivery app with approved KYC.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AdminColors.textSecondary,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              } else {
                content = Container(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    itemCount: fleet.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final p = fleet[index] as Map<String, dynamic>;
                      final name = p['name'] ?? 'Partner';
                      final mobile = p['mobile_number'] ?? '';
                      final dpId = p['dp_id'] ?? '';
                      final liveStatus = (p['live_status'] ?? 'idle').toString().toUpperCase();
                      final isDelivering = liveStatus == 'IN_TRANSIT' || liveStatus == 'PICKED_UP';

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        leading: CircleAvatar(
                          backgroundColor: AdminColors.primaryLight,
                          child: const Icon(Icons.person_rounded, color: AdminColors.primaryDark),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        subtitle: Text(
                          '$dpId • $mobile',
                          style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isDelivering ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 4,
                                backgroundColor: isDelivering ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isDelivering ? 'Delivering' : 'Idle (Available)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isDelivering ? const Color(0xFFB45309) : const Color(0xFF15803D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(bottom: BorderSide(color: AdminColors.border)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.delivery_dining_rounded,
                                  color: Color(0xFF2563EB),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Live Active Fleet Status',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AdminColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    content,
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOrdersHubCard({
    required String todayOrders,
    required String todayRemaining,
    required String totalOrders,
    required VoidCallback onTap,
  }) {
    final int remainingInt = int.tryParse(todayRemaining) ?? 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminColors.border),
          boxShadow: const [
            BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 4)),
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
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AdminColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.receipt_long_rounded, color: AdminColors.primary, size: 20),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Customer Orders',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AdminColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AdminColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        '2 Sides View',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AdminColors.primaryDark),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_forward_ios_rounded, size: 9, color: AdminColors.primaryDark),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                // Left Side: Today's Orders & Remaining
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AdminColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Today's Orders",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AdminColors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              todayOrders,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: AdminColors.primary,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (remainingInt > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$remainingInt left',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFB45309),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Right Side: Total Orders
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE9D5FF)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total (All-Time)',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6D28D9)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          totalOrders,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF6D28D9),
                            letterSpacing: -0.5,
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
  }

  Widget _buildSalesHubCard({
    required String todayRevenue,
    required String totalRevenue,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminColors.border),
          boxShadow: const [
            BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 4)),
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
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.currency_rupee_rounded, color: Color(0xFF047857), size: 20),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Gross Sales Revenue',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AdminColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AdminColors.textMuted),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AdminColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Today's Sales",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AdminColors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹$todayRevenue',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF047857),
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDFA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFCCFBF1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total (All-Time)',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0F766E)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹$totalRevenue',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F766E),
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 215,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminColors.border),
          boxShadow: const [
            BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 20),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 13, color: AdminColors.textMuted),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AdminColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminColors.border),
          boxShadow: const [
            BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AdminColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AdminColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentOfferSnapshot() {
    final title = activeBanner?['title'] ?? 'Special Dum Biriyani Deal';
    final price = activeBanner?['offer_price'] ?? 65;
    final stock = activeBanner?['stock_remaining'] ?? 75;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.local_offer_rounded, color: AdminColors.primaryDark, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AdminColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AdminColors.primaryLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'ACTIVE ON HOME',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AdminColors.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Current Offer Price: ₹$price  •  Remaining Stock: $stock biryanis',
                  style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => widget.onNavigateToTab(2),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: const Text('Change Offer', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}


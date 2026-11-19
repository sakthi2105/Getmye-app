import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/admin_auth_service.dart';
import '../theme/admin_theme.dart';

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
    final todayRevenue = overviewStats?['today_revenue']?.toString() ?? '0';
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
                      _buildKpiCard(
                        title: "Today's Orders",
                        value: todayOrders,
                        icon: Icons.receipt_long_rounded,
                        color: AdminColors.primary,
                        bgColor: AdminColors.primaryLight,
                        onTap: () => widget.onNavigateToTab(4),
                      ),
                      _buildKpiCard(
                        title: "Today's Gross Sales",
                        value: '₹$todayRevenue',
                        icon: Icons.currency_rupee_rounded,
                        color: const Color(0xFF047857),
                        bgColor: AdminColors.primaryLight,
                        onTap: () => widget.onNavigateToTab(4),
                      ),
                      _buildKpiCard(
                        title: 'Pending KYC Review',
                        value: pendingKYC,
                        icon: Icons.checklist_rounded,
                        color: const Color(0xFFB45309),
                        bgColor: AdminColors.warningLight,
                        onTap: () => widget.onNavigateToTab(1),
                      ),
                      _buildKpiCard(
                        title: 'Active Fleet Online',
                        value: onlinePartners,
                        icon: Icons.delivery_dining_rounded,
                        color: const Color(0xFF2563EB),
                        bgColor: const Color(0xFFEFF6FF),
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


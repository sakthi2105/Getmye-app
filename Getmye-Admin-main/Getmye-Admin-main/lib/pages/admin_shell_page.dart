import 'package:flutter/material.dart';
import '../theme/admin_theme.dart';
import 'dashboard_overview_page.dart';
import 'kyc_verification_page.dart';
import 'offer_banner_page.dart';
import 'support_management_page.dart';
import 'orders_management_page.dart';
import 'admin_settings_page.dart';

class AdminShellPage extends StatefulWidget {
  const AdminShellPage({super.key});

  @override
  State<AdminShellPage> createState() => _AdminShellPageState();
}

class _AdminShellPageState extends State<AdminShellPage> {
  int _currentIndex = 0;

  void _onTabSelect(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardOverviewPage(onNavigateToTab: _onTabSelect),
      const KycVerificationPage(),
      const OfferBannerPage(),
      const SupportManagementPage(),
      const OrdersManagementPage(),
      const AdminSettingsPage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AdminColors.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onTabSelect,
          backgroundColor: Colors.white,
          indicatorColor: AdminColors.primaryLight,
          elevation: 0,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded, color: AdminColors.primaryDark),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.how_to_reg_outlined),
              selectedIcon: Icon(Icons.how_to_reg_rounded, color: AdminColors.primaryDark),
              label: 'Verify KYC',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_offer_outlined),
              selectedIcon: Icon(Icons.local_offer_rounded, color: AdminColors.primaryDark),
              label: 'Offer Banner',
            ),
            NavigationDestination(
              icon: Icon(Icons.support_agent_outlined),
              selectedIcon: Icon(Icons.support_agent_rounded, color: AdminColors.primaryDark),
              label: 'Support Hub',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded, color: AdminColors.primaryDark),
              label: 'Orders',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded, color: AdminColors.primaryDark),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../ppp.dart';
import '../profile.dart';
import '../options.dart';
import '../pay.dart';

class CustomerBottomNavBar extends StatefulWidget {
  final int currentIndex;

  const CustomerBottomNavBar({
    super.key,
    required this.currentIndex,
  });

  @override
  State<CustomerBottomNavBar> createState() => _CustomerBottomNavBarState();
}

class _CustomerBottomNavBarState extends State<CustomerBottomNavBar> {
  bool _hasActiveOrder = false;

  @override
  void initState() {
    super.initState();
    _checkActiveOrder();
  }

  Future<void> _checkActiveOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasOrder = prefs.getBool('has_active_order') ?? false;
      final activeId = prefs.getString('active_order_id');
      if (mounted) {
        setState(() {
          _hasActiveOrder = hasOrder || (activeId != null && activeId.isNotEmpty);
        });
      }
    } catch (_) {}
  }

  void _onItemTapped(BuildContext context, int index) {
    if (index == widget.currentIndex) return;

    Widget destination;
    switch (index) {
      case 0:
        destination = const HomePage();
        break;
      case 1:
        destination = const ProfilePage();
        break;
      case 2:
        destination = const OptionsPage(isDarkMode: false);
        break;
      case 3:
        destination = const PaymentPage();
        break;
      default:
        destination = const HomePage();
    }

    if (index == 0) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } else {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => destination,
          transitionDuration: Duration.zero,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: BottomAppBar(
        height: 64,
        color: Colors.white,
        elevation: 0,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(
              context: context,
              index: 0,
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'Home',
            ),
            _buildNavItem(
              context: context,
              index: 1,
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'Profile',
            ),
            _buildNavItem(
              context: context,
              index: 2,
              icon: Icons.menu_rounded,
              activeIcon: Icons.menu_rounded,
              label: 'Options',
            ),
            _buildNavItem(
              context: context,
              index: 3,
              icon: Icons.delivery_dining_outlined,
              activeIcon: Icons.delivery_dining_rounded,
              label: 'Orders',
              showBadge: _hasActiveOrder,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    bool showBadge = false,
  }) {
    final isSelected = index == widget.currentIndex;

    Widget iconWidget = Icon(
      isSelected ? activeIcon : icon,
      color: isSelected ? AppColors.primaryDark : AppColors.textSecondary,
      size: 24,
    );

    if (showBadge) {
      iconWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      );
    }

    if (isSelected) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: AppColors.primaryLight,
          shape: BoxShape.circle,
        ),
        child: iconWidget,
      );
    }

    return IconButton(
      icon: iconWidget,
      tooltip: label,
      onPressed: () => _onItemTapped(context, index),
    );
  }
}

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/alarm_service.dart';
import '../homed.dart';
import '../wallet.dart';
import '../dprofile.dart';
import '../doption.dart';
import '../delivery_bill_flow.dart';

class DeliveryBottomNavBar extends StatelessWidget {
  final int currentIndex;

  const DeliveryBottomNavBar({
    super.key,
    required this.currentIndex,
  });

  void _onItemTapped(BuildContext context, int index) {
    if (index == currentIndex) return;

    AlarmService.stopAlarm();

    Widget destination;
    switch (index) {
      case 0:
        destination = const dEditProfilePage();
        break;
      case 1:
        destination = const WalletPage();
        break;
      case 2:
        destination = const DeliveryHomePage();
        break;
      case 3:
        destination = const NewOrdersPage();
        break;
      case 4:
        destination = const dOptionsPage(isDarkMode: false);
        break;
      default:
        destination = const DeliveryHomePage();
    }

    if (index == 2) {
      // Return to home: pop back to root or replace
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
        (route) => false,
      );
    } else {
      Navigator.pushReplacement(
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
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'Profile',
            ),
            _buildNavItem(
              context: context,
              index: 1,
              icon: Icons.account_balance_wallet_outlined,
              activeIcon: Icons.account_balance_wallet_rounded,
              label: 'Wallet',
            ),
            _buildNavItem(
              context: context,
              index: 2,
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'Home',
              isCenter: true,
            ),
            _buildNavItem(
              context: context,
              index: 3,
              icon: Icons.two_wheeler_rounded,
              activeIcon: Icons.two_wheeler_rounded,
              label: 'Orders',
            ),
            _buildNavItem(
              context: context,
              index: 4,
              icon: Icons.more_horiz_rounded,
              activeIcon: Icons.more_horiz_rounded,
              label: 'Options',
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
    bool isCenter = false,
  }) {
    final isSelected = index == currentIndex;

    if (isSelected) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          shape: BoxShape.circle,
        ),
        child: Icon(activeIcon, color: AppColors.primaryDark, size: 24),
      );
    }

    return IconButton(
      icon: Icon(icon, color: AppColors.textSecondary, size: 24),
      tooltip: label,
      onPressed: () => _onItemTapped(context, index),
    );
  }
}

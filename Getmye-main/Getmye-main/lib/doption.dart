import 'package:flutter/material.dart';
import 'package:flutter_application_1/homed.dart';
import 'package:flutter_application_1/main.dart';
import 'deliveryhistroy.dart';
import 'widgets/delivery_bottom_nav_bar.dart';
import 'theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Options Page',
      theme: AppTheme.lightTheme,
      home: const dOptionsPage(isDarkMode: false),
    );
  }
}

class dOptionsPage extends StatelessWidget {
  const dOptionsPage({super.key, required bool isDarkMode});

  IconData _getIconForOption(String title) {
    switch (title.toLowerCase()) {
      case 'delivery history':
        return Icons.receipt_long_rounded;
      case 'terms and conditions':
        return Icons.description_outlined;
      case 'help':
        return Icons.help_outline_rounded;
      case 'report a bug':
        return Icons.bug_report_outlined;
      case 'raise a complaint':
        return Icons.support_agent_rounded;
      case 'feedback':
        return Icons.rate_review_outlined;
      case 'advertisement':
        return Icons.campaign_outlined;
      case 'switch to customer side':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.chevron_right_rounded;
    }
  }

  void _handleBackNavigation(BuildContext context) {
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
    final optionsList = [
      'Delivery History',
      'Switch to Customer Side',
      'Terms and conditions',
      'Help',
      'Report a bug',
      'Raise a complaint',
      'Feedback',
      'Advertisement',
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
            onPressed: () => _handleBackNavigation(context),
          ),
          title: const Text(
            'Partner Support & Settings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          centerTitle: true,
        ),
        body: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: optionsList.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final title = optionsList[index];
            return _buildOption(context, title);
          },
        ),
        bottomNavigationBar: const DeliveryBottomNavBar(currentIndex: 4),
      ),
    );
  }

  Widget _buildOption(BuildContext context, String title) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _getIconForOption(title),
            color: AppColors.primaryDark,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: AppColors.textMuted,
        ),
        onTap: () async {
          if (title == 'Delivery History') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DeliveryListPage(isTodayOnly: false),
              ),
            );
            return;
          }
          if (title == 'Switch to Customer Side') {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('is_logged_in', false);
            await prefs.remove('account_type');
            await prefs.remove('user_id');
            await prefs.remove('user_name');
            await prefs.remove('user_email');
            await prefs.remove('mobile_number');
            await prefs.remove('active_order_id');
            await prefs.remove('active_order_customer_name');
            await prefs.remove('active_order_partner_name');
            if (!context.mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => const LoginPage(
                  initialRole: 'customer',
                  forceShowLogin: true,
                ),
              ),
              (route) => false,
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DetailPage(title: title),
            ),
          );
        },
      ),
    );
  }
}

class DetailPage extends StatelessWidget {
  final String title;

  const DetailPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.primaryDark,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Details and policies regarding $title will appear here.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_application_1/dprofile.dart';
import 'package:flutter_application_1/homed.dart';
import 'package:flutter_application_1/wallet.dart';
import 'widgets/delivery_bottom_nav_bar.dart';
import 'theme/app_theme.dart';

class TransactionHistoryPage extends StatelessWidget {
  final List<Map<String, String>> transactions = [
    {"date": "Feb 5, 2025", "time": "10:30 AM", "amount": "₹500.00"},
    {"date": "Feb 3, 2025", "time": "02:15 PM", "amount": "₹300.00"},
    {"date": "Jan 30, 2025", "time": "09:45 AM", "amount": "₹200.00"},
    {"date": "Jan 12, 2025", "time": "04:10 PM", "amount": "₹150.00"},
  ];

  TransactionHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'Transaction History',
          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: CustomScrollView(
          slivers: [
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final transaction = transactions[index];
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.arrow_downward_rounded,
                            color: AppColors.primaryDark, size: 22),
                      ),
                      title: Text(
                        "Withdrawn: ${transaction['amount']}",
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                      ),
                      subtitle: Text(
                        "${transaction['date']} at ${transaction['time']}",
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "Success",
                          style: TextStyle(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                },
                childCount: transactions.length,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const DeliveryBottomNavBar(currentIndex: 1),
    );
  }
}

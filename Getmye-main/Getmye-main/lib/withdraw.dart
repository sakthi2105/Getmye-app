import 'package:flutter/material.dart';
import 'package:flutter_application_1/np.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';

class WithdrawalPage extends StatefulWidget {
  const WithdrawalPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _WithdrawalPageState createState() => _WithdrawalPageState();
}

class _WithdrawalPageState extends State<WithdrawalPage> {
  double totalCash = 2500.00;
  double minBalance = 500.00;
  final TextEditingController amountController = TextEditingController();
  final TextEditingController upiController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();
  final TextEditingController bankController = TextEditingController();
  final TextEditingController ifscController = TextEditingController();

  String selectedMethod = "UPI";

  @override
  void initState() {
    super.initState();
    _loadBalance();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstTimePinSetup();
    });
  }

  Future<void> _checkFirstTimePinSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString('partner_withdraw_pin');
    if (pin == null || pin.isEmpty) {
      _showSetPinFirstTimeDialog();
    }
  }

  void _showSetPinFirstTimeDialog() {
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text("Set Security PIN", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "First-time setup: Please set a 4-digit security PIN for authorizing your withdrawals safely.",
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: newPinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: InputDecoration(
                labelText: "Create 4-Digit PIN",
                counterText: "",
                prefixIcon: const Icon(Icons.pin_rounded, color: AppColors.primary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: InputDecoration(
                labelText: "Confirm 4-Digit PIN",
                counterText: "",
                prefixIcon: const Icon(Icons.check_circle_outline_rounded, color: AppColors.primary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final pin = newPinController.text.trim();
              final confirm = confirmPinController.text.trim();
              if (pin.length != 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("PIN must be exactly 4 digits")),
                );
                return;
              }
              if (pin != confirm) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("PINs do not match")),
                );
                return;
              }
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('partner_withdraw_pin', pin);
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Withdrawal PIN created successfully!"),
                  backgroundColor: AppColors.primaryDark,
                ),
              );
            },
            child: const Text("Save Security PIN"),
          ),
        ],
      ),
    );
  }

  Future<void> _loadBalance() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      totalCash = prefs.getDouble('wallet_balance') ?? 2500.00;
    });
  }

  Future<void> _updateBalanceAfterWithdraw(double amount) async {
    final prefs = await SharedPreferences.getInstance();
    final newBalance = totalCash - amount;
    await prefs.setDouble('wallet_balance', newBalance);
    setState(() {
      totalCash = newBalance;
    });
  }

  @override
  void dispose() {
    amountController.dispose();
    upiController.dispose();
    mobileController.dispose();
    bankController.dispose();
    ifscController.dispose();
    super.dispose();
  }

  void proceedToNextPage() {
    double enteredAmount = double.tryParse(amountController.text) ?? 0.0;
    double maxWithdrawAmount = totalCash - minBalance;

    if (enteredAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid amount to withdraw")),
      );
      return;
    }

    if (enteredAmount > maxWithdrawAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Amount exceeds limit. Max withdrawable is ₹${maxWithdrawAmount.toStringAsFixed(2)}",
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PincodePage(
          order: {},
        ),
      ),
    ).then((result) {
      if (result == true) {
        // Deduct withdrawn amount upon successful PIN confirmation
        _updateBalanceAfterWithdraw(enteredAmount);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    double maxWithdrawAmount = (totalCash - minBalance) > 0 ? (totalCash - minBalance) : 0.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          "Withdraw Funds",
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Modern 3D Withdrawal Hero Illustration
            Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  "assets/withdraw_illustration.jpg",
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.primaryLight,
                    child: const Center(
                      child: Icon(Icons.account_balance_wallet_rounded, size: 60, color: AppColors.primaryDark),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Balance Details Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Total Available Balance",
                        style: TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        "₹${totalCash.toStringAsFixed(2)}",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Reserved Min. Balance",
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      Text(
                        "₹${minBalance.toStringAsFixed(2)}",
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.red),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Max Withdrawable Now",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      Text(
                        "₹${maxWithdrawAmount.toStringAsFixed(2)}",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primaryDark),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Withdrawal Amount Input
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              decoration: InputDecoration(
                labelText: "Enter Withdrawal Amount",
                prefixText: "₹ ",
                prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                hintText: "e.g. 1000",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 16),

            // Payment Method Selector
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: selectedMethod,
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        selectedMethod = newValue;
                      });
                    }
                  },
                  items: ["UPI", "Mobile Number", "Bank Account"].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Row(
                        children: [
                          Icon(
                            value == "UPI"
                                ? Icons.flash_on_rounded
                                : value == "Mobile Number"
                                    ? Icons.phone_android_rounded
                                    : Icons.account_balance_rounded,
                            color: AppColors.primaryDark,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Conditional Fields
            if (selectedMethod == "UPI")
              TextField(
                controller: upiController,
                decoration: InputDecoration(
                  labelText: "UPI ID / VPA",
                  hintText: "e.g. user@okhdfcbank",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            if (selectedMethod == "Mobile Number")
              TextField(
                controller: mobileController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: "Linked Mobile Number",
                  hintText: "e.g. 9876543210",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            if (selectedMethod == "Bank Account") ...[
              TextField(
                controller: bankController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Bank Account Number",
                  hintText: "Enter account number",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ifscController,
                decoration: InputDecoration(
                  labelText: "Bank IFSC Code",
                  hintText: "e.g. SBIN0001234",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
            const SizedBox(height: 28),

            // Transfer Funds Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: proceedToNextPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 1,
                ),
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                label: const Text(
                  "Transfer Funds Instantly",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            SizedBox(height: 20 + MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }
}

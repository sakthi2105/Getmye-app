import 'package:flutter/material.dart';
import 'package:flutter_application_1/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';

void main() => runApp(const WalletPinApp());

class WalletPinApp extends StatelessWidget {
  const WalletPinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wallet PIN Setup',
      theme: AppTheme.lightTheme,
      home: const WalletPinSetupScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WalletPinSetupScreen extends StatefulWidget {
  const WalletPinSetupScreen({super.key});

  @override
  _WalletPinSetupScreenState createState() => _WalletPinSetupScreenState();
}

class _WalletPinSetupScreenState extends State<WalletPinSetupScreen> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isObscure = true;

  Future<void> _submitPin() async {
    if (_formKey.currentState!.validate()) {
      String pin = _pinController.text;
      String confirmPin = _confirmPinController.text;

      if (pin == confirmPin) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('partner_wallet_pin', pin);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wallet PIN saved successfully!'),
            backgroundColor: AppColors.primaryDark,
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const WalletPage(),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PINs do not match')),
        );
      }
    }
  }

  void _showForgotPinDialog() {
    final phoneController = TextEditingController();
    final newPinController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_reset_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text("Reset Wallet PIN", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Verify your registered mobile number to reset PIN:",
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: "Registered Mobile Number",
                hintText: "9876543210",
                prefixText: "+91 ",
                prefixIcon: const Icon(Icons.phone_rounded, color: AppColors.primary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: InputDecoration(
                labelText: "Enter New 4-Digit PIN",
                counterText: "",
                prefixIcon: const Icon(Icons.pin_rounded, color: AppColors.primary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              if (newPinController.text.length == 4) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('partner_wallet_pin', newPinController.text);
                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("PIN reset successful! You can now use your new PIN."),
                    backgroundColor: AppColors.primaryDark,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Please enter a valid 4-digit PIN")),
                );
              }
            },
            child: const Text("Reset PIN"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Set Your PIN Number',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Toon Illustration Mascot Container
                  Container(
                    height: 190,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/pin_security_toon.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Center(
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.security_rounded,
                              size: 72,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Heading & Description
                  const Text(
                    'Set Your PIN Number',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Secure your delivery partner earnings and instant wallet withdrawals with a 4-digit PIN.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),

                  // PIN Input Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _pinController,
                          keyboardType: TextInputType.number,
                          obscureText: _isObscure,
                          maxLength: 4,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 4,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Enter 4-Digit PIN',
                            labelStyle: const TextStyle(letterSpacing: 0),
                            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                            counterText: '',
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isObscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                color: AppColors.textSecondary,
                              ),
                              onPressed: () => setState(() => _isObscure = !_isObscure),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.length != 4) {
                              return 'PIN must be exactly 4 digits';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmPinController,
                          keyboardType: TextInputType.number,
                          obscureText: _isObscure,
                          maxLength: 4,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 4,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Confirm 4-Digit PIN',
                            labelStyle: const TextStyle(letterSpacing: 0),
                            prefixIcon: const Icon(Icons.lock_rounded, color: AppColors.primary),
                            counterText: '',
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.length != 4) {
                              return 'Confirm PIN must be 4 digits';
                            }
                            if (value != _pinController.text) {
                              return 'PIN numbers do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),

                        // Security Tip
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.shield_outlined, size: 16, color: AppColors.primaryDark),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'This PIN will be required for all future wallet transfers.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.primaryDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _submitPin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 1,
                      ),
                      icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
                      label: const Text(
                        'Set Your PIN Number',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: _showForgotPinDialog,
                    icon: const Icon(Icons.help_outline_rounded, color: AppColors.primaryDark, size: 18),
                    label: const Text(
                      'Forgot PIN? Reset / Create New PIN',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WalletHomePage extends StatelessWidget {
  final String pin;

  const WalletHomePage({super.key, required this.pin});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Wallet Home', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: Center(
        child: Text(
          'Welcome! Your PIN is: $pin',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}

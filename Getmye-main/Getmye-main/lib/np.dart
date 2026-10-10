import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';

class PincodePage extends StatefulWidget {
  const PincodePage({super.key, required Map order});

  @override
  // ignore: library_private_types_in_public_api
  _PincodePageState createState() => _PincodePageState();
}

class _PincodePageState extends State<PincodePage> {
  final List<TextEditingController> controllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> focusNodes = List.generate(4, (_) => FocusNode());
  bool isProcessing = false;

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
            Text("Reset Withdrawal PIN", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Enter your registered mobile number to reset PIN:",
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              if (newPinController.text.trim().length == 4) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('partner_withdraw_pin', newPinController.text.trim());
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (!mounted) return;
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

  void _showWrongPinDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.all(22),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Error Illustration Visual
            Container(
              height: 135,
              width: 135,
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFEF4444), width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(70),
                child: Image.asset(
                  'assets/wrong_pin_toon.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.gpp_bad_rounded, size: 68, color: Color(0xFFDC2626)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "Your PIN is Wrong!",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFFDC2626),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              "The security PIN you entered does not match. Withdrawal cannot be authorized.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showForgotPinDialog();
                    },
                    child: const Text("Forgot PIN?"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Try Again", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSubmit() async {
    String enteredPin = controllers.map((c) => c.text).join();

    if (enteredPin.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a valid 4-digit PIN."),
        ),
      );
      return;
    }

    setState(() {
      isProcessing = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('partner_withdraw_pin') ?? "1234";

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    setState(() {
      isProcessing = false;
    });

    if (enteredPin != savedPin) {
      // Clear inputs
      for (var c in controllers) {
        c.clear();
      }
      if (focusNodes.isNotEmpty) {
        focusNodes[0].requestFocus();
      }
      _showWrongPinDialog();
      return;
    }

    // Success
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Withdrawal Authorized Successfully!"),
        backgroundColor: AppColors.primary,
      ),
    );

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Enter PIN", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_rounded, color: AppColors.primaryDark, size: 36),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Enter Your Security PIN",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Enter your 4-digit PIN to authorize transaction",
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(4, (index) {
                    return SizedBox(
                      width: 55,
                      height: 55,
                      child: TextField(
                        controller: controllers[index],
                        focusNode: focusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        obscureText: true,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          counterText: "",
                          filled: true,
                          fillColor: Colors.white,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.border, width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.primary, width: 2),
                          ),
                        ),
                        onChanged: (value) {
                          if (value.isNotEmpty) {
                            if (index < 3) {
                              FocusScope.of(context)
                                  .requestFocus(focusNodes[index + 1]);
                            } else {
                              FocusScope.of(context).unfocus();
                            }
                          } else if (index > 0) {
                            FocusScope.of(context)
                                .requestFocus(focusNodes[index - 1]);
                          }
                        },
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 14),
                // Forgot PIN text button
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _showForgotPinDialog,
                    icon: const Icon(Icons.help_outline_rounded, size: 16, color: AppColors.primaryDark),
                    label: const Text(
                      "Forgot PIN?",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : _onSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 1,
                    ),
                    child: isProcessing
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Text("Confirm & Transfer", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'homed.dart';
import 'theme/app_theme.dart';
import 'ppp.dart';
import 'services/alarm_service.dart';
import 'main.dart';

class DeliveryPersonLoginPage extends StatefulWidget {
  const DeliveryPersonLoginPage({super.key});

  @override
  State<DeliveryPersonLoginPage> createState() => _DeliveryPersonLoginPageState();
}

class _DeliveryPersonLoginPageState extends State<DeliveryPersonLoginPage> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    final String accountType = prefs.getString('account_type') ?? '';
    if (isLoggedIn && accountType == 'partner' && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
      );
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _handlePartnerLogin() async {
    final input = _identifierController.text.trim();
    final password = _passwordController.text.trim();

    if (input.isEmpty) {
      _showError('Please enter your mobile number or email ID');
      return;
    }
    if (password.isEmpty) {
      _showError('Please enter your password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await http.post(
        ApiConfig.partnerLogin,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mobile_or_email': input,
          'identifier': input,
          'mobile_number': input,
          'email': input,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && (data['success'] == true || data['dp_id'] != null)) {
        final prefs = await SharedPreferences.getInstance();

        // Clear previous customer session & stale order cache if any
        await prefs.remove('user_id');
        await prefs.remove('user_name');
        await prefs.remove('user_email');
        await prefs.remove('mobile_number');
        await prefs.remove('partner_active_order_id');
        await prefs.remove('active_order_id');
        await prefs.remove('active_order_status');
        await prefs.remove('active_order_customer_name');
        await prefs.remove('active_order_customer_phone');
        await prefs.remove('active_order_customer_address');
        await prefs.remove('active_order_item');
        await prefs.remove('active_order_budget');
        await prefs.remove('active_order_bill_sent');
        await prefs.remove('active_order_food_purchased');
        await prefs.remove('active_order_partner_accepted');
        await prefs.remove('active_order_restaurant');
        await prefs.remove('active_order_grand_total');

        final dpId = (data['dp_id'] ?? data['DP_id'] ?? 'dp_001').toString();
        final partnerPhone = (data['mobile_number'] != null && data['mobile_number'].toString().isNotEmpty)
            ? data['mobile_number'].toString()
            : (!input.contains('@') ? input : '');
        final partnerEmail = (data['email'] != null && data['email'].toString().isNotEmpty)
            ? data['email'].toString()
            : (input.contains('@') ? input : '');
        final pName = (data['name'] != null && data['name'].toString().isNotEmpty)
            ? data['name'].toString()
            : 'Delivery Partner';

        await prefs.setString('d_id', dpId);
        await prefs.setString('partner_id', dpId);
        await prefs.setString('active_order_partner_id', dpId);
        await prefs.setString('d_name', pName);
        await prefs.setString('partner_name', pName);
        await prefs.setString('active_order_partner_name', pName);
        await prefs.setString('d_phone', partnerPhone);
        await prefs.setString('partner_phone', partnerPhone);
        await prefs.setString('active_order_partner_phone', partnerPhone);
        await prefs.setString('d_email', partnerEmail);
        await prefs.setString('d_address', data['address'] ?? '');
        await prefs.setBool('d_is_online', true);
        await prefs.setString('account_type', 'partner');
        await prefs.setBool('is_logged_in', true);

        if (data['profile_picture'] != null && data['profile_picture'].toString().isNotEmpty) {
          await prefs.setString('d_profile_picture_base64', data['profile_picture'].toString());
          await prefs.setString('active_order_partner_pic', data['profile_picture'].toString());
          await prefs.setString('active_order_partner_image', data['profile_picture'].toString());
        }

        final photoUrl = (data['photo_url'] ?? '').toString();
        if (photoUrl.isNotEmpty) {
          await prefs.setString('d_photo_url', photoUrl);
          await prefs.setString('partner_photo_url', photoUrl);
          await prefs.setString('active_order_partner_pic_url', photoUrl);
        }

        // 🟢 Start background foreground listening service immediately upon login
        AlarmService.startOrderListeningService(
          baseUrl: ApiConfig.baseUrl,
          partnerId: dpId,
        );
        AlarmService.requestBatteryOptimizationExemption();

        if (!mounted) return;
        _showSuccess('Welcome back, ${data['name']?.toString().isNotEmpty == true ? data['name'] : 'Partner'}!');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
          (route) => false,
        );
      } else {
        final msg = data['error'] ?? data['message'] ?? 'Login failed. Please check your credentials.';
        _showError(msg);
      }
    } catch (e) {
      _showError('Server connection error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog() {
    final loginInput = _identifierController.text.trim();
    final resetInputController = TextEditingController(text: loginInput);
    final linkEmailController = TextEditingController();
    final otpController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();
    int step = 1;
    bool isSubmitting = false;
    String? dialogError;
    String retrievedEmail = '';
    String maskedEmail = '';
    bool needsEmail = false;
    bool obscureNew = true;
    bool obscureConfirm = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.two_wheeler_rounded, color: Color(0xFFB45309), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          step == 1
                              ? "Reset Partner Password"
                              : step == 2
                                  ? "Verify Email OTP"
                                  : "Set New Password",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    step == 1
                        ? "Enter your registered partner mobile number or email. We'll automatically fetch your linked database email and dispatch a 6-digit OTP."
                        : step == 2
                            ? "Enter the 6-digit verification code sent to your registered email to verify your identity."
                            : "Create and confirm your new partner account password.",
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  if (dialogError != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(dialogError!, style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (step == 1) ...[
                    TextField(
                      controller: resetInputController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: "Registered Mobile Number or Email",
                        hintText: "e.g. 9876543210 or partner@gmail.com",
                        prefixIcon: const Icon(Icons.email_outlined, size: 20, color: AppColors.primaryDark),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                      ),
                    ),
                    if (needsEmail) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: linkEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: "Email ID to Link",
                          hintText: "e.g. partner@gmail.com",
                          prefixIcon: const Icon(Icons.email_outlined, size: 20, color: AppColors.primaryDark),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final inputVal = resetInputController.text.trim();
                                if (inputVal.isEmpty) {
                                  setModalState(() => dialogError = 'Please enter your registered email ID');
                                  return;
                                }
                                final bool isEmail = inputVal.contains('@') && inputVal.contains('.');
                                final String cleanDigits = inputVal.replaceAll(RegExp(r'[^0-9]'), '');
                                if (!isEmail && cleanDigits.length != 10) {
                                  setModalState(() => dialogError = 'Please enter a valid email address (e.g. name@gmail.com)');
                                  return;
                                }
                                if (needsEmail) {
                                  final enteredMail = linkEmailController.text.trim();
                                  if (!enteredMail.contains('@') || !enteredMail.contains('.')) {
                                    setModalState(() => dialogError = 'Please enter a valid email address');
                                    return;
                                  }
                                }
                                setModalState(() {
                                  isSubmitting = true;
                                  dialogError = null;
                                });
                                try {
                                  final Map<String, dynamic> bodyPayload = {
                                    'role': 'partner',
                                  };
                                  if (isEmail) {
                                    bodyPayload['email'] = inputVal.toLowerCase();
                                  } else {
                                    bodyPayload['mobile_number'] = cleanDigits;
                                  }
                                  if (needsEmail && linkEmailController.text.trim().isNotEmpty) {
                                    bodyPayload['email'] = linkEmailController.text.trim().toLowerCase();
                                  }

                                  final res = await http.post(
                                    ApiConfig.profileForgotPasswordSendOtp,
                                    headers: {'Content-Type': 'application/json'},
                                    body: jsonEncode(bodyPayload),
                                  ).timeout(const Duration(seconds: 45));

                                  Map<String, dynamic> data = {};
                                  try {
                                    data = jsonDecode(res.body) as Map<String, dynamic>;
                                  } catch (_) {
                                    setModalState(() {
                                      isSubmitting = false;
                                      dialogError = 'Server error (${res.statusCode}). Please ensure backend is running.';
                                    });
                                    return;
                                  }

                                  if (res.statusCode == 200 && data['success'] == true) {
                                    setModalState(() {
                                      retrievedEmail = (data['email'] ?? '').toString();
                                      maskedEmail = (data['masked_email'] ?? data['email'] ?? '').toString();
                                      step = 2;
                                      isSubmitting = false;
                                      dialogError = null;
                                    });
                                    _showSuccess('OTP sent to: $maskedEmail');
                                  } else {
                                    setModalState(() {
                                      isSubmitting = false;
                                      dialogError = data['error'] ?? 'Failed to send OTP';
                                      if (data['needs_email'] == true) {
                                        needsEmail = true;
                                      }
                                    });
                                  }
                                } catch (e) {
                                  setModalState(() {
                                    isSubmitting = false;
                                    dialogError = 'Network error: $e';
                                  });
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text("Find Account & Send OTP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ] else if (step == 2) ...[
                    // Info card showing the linked email retrieved from the database
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.mark_email_read_rounded, size: 24, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "OTP sent to linked email in database:",
                                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  maskedEmail.isNotEmpty ? maskedEmail : retrievedEmail,
                                  style: const TextStyle(fontSize: 14, color: AppColors.primary, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "💡 Tip: If not in your inbox, check Spam / Promotions folder.",
                                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: "6-Digit Email OTP",
                        hintText: "Enter 6-digit OTP",
                        counterText: "",
                        prefixIcon: const Icon(Icons.key_rounded, size: 20, color: AppColors.primaryDark),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                      ),
                    ),

                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: isSubmitting ? null : () => setModalState(() => step = 1),
                            child: const Text("Back"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final otp = otpController.text.trim();
                                    if (otp.length < 4) {
                                      setModalState(() => dialogError = 'Please enter a valid OTP');
                                      return;
                                    }
                                    setModalState(() {
                                      isSubmitting = true;
                                      dialogError = null;
                                    });
                                    try {
                                      final inputVal = resetInputController.text.trim();
                                      final cleanDigits = inputVal.replaceAll(RegExp(r'[^0-9]'), '');
                                      final Map<String, dynamic> verifyPayload = {
                                        'otp': otp,
                                        'role': 'partner',
                                      };
                                      if (cleanDigits.length == 10) {
                                        verifyPayload['mobile_number'] = cleanDigits;
                                      }
                                      if (retrievedEmail.isNotEmpty) {
                                        verifyPayload['email'] = retrievedEmail;
                                      } else if (inputVal.contains('@')) {
                                        verifyPayload['email'] = inputVal;
                                      }

                                      final res = await http.post(
                                        ApiConfig.profileForgotPasswordVerifyOtp,
                                        headers: {'Content-Type': 'application/json'},
                                        body: jsonEncode(verifyPayload),
                                      );
                                      Map<String, dynamic> data = {};
                                      try {
                                        data = jsonDecode(res.body) as Map<String, dynamic>;
                                      } catch (_) {
                                        setModalState(() {
                                          isSubmitting = false;
                                          dialogError = 'Server returned invalid response';
                                        });
                                        return;
                                      }
                                      if (res.statusCode == 200 && data['success'] == true) {
                                        setModalState(() {
                                          step = 3;
                                          isSubmitting = false;
                                          dialogError = null;
                                        });
                                        _showSuccess('OTP verified successfully! Now set your new password.');
                                      } else {
                                        setModalState(() {
                                          isSubmitting = false;
                                          dialogError = data['error'] ?? 'Invalid OTP entered';
                                        });
                                      }
                                    } catch (e) {
                                      setModalState(() {
                                        isSubmitting = false;
                                        dialogError = 'Network error: $e';
                                      });
                                    }
                                  },
                            child: isSubmitting
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text("Verify OTP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ] else if (step == 3) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_user_rounded, size: 24, color: Color(0xFF2563EB)),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              "Identity verified! Please set your new partner login password.",
                              style: TextStyle(fontSize: 12.5, color: Color(0xFF1E40AF), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: newPassController,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        labelText: "New Password",
                        hintText: "Enter new password",
                        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.primaryDark),
                        suffixIcon: IconButton(
                          icon: Icon(obscureNew ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                          onPressed: () => setModalState(() => obscureNew = !obscureNew),
                        ),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPassController,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        labelText: "Confirm New Password",
                        hintText: "Re-enter new password",
                        prefixIcon: const Icon(Icons.lock_reset_rounded, size: 20, color: AppColors.primaryDark),
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                          onPressed: () => setModalState(() => obscureConfirm = !obscureConfirm),
                        ),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: isSubmitting ? null : () => setModalState(() => step = 2),
                            child: const Text("Back"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final o = otpController.text.trim();
                                    final np = newPassController.text.trim();
                                    final cp = confirmPassController.text.trim();
                                    if (np.length < 4) {
                                      setModalState(() => dialogError = 'Password must be at least 4 characters');
                                      return;
                                    }
                                    if (np != cp) {
                                      setModalState(() => dialogError = 'Passwords do not match');
                                      return;
                                    }
                                    setModalState(() {
                                      isSubmitting = true;
                                      dialogError = null;
                                    });
                                    try {
                                      final inputVal = resetInputController.text.trim();
                                      final cleanDigits = inputVal.replaceAll(RegExp(r'[^0-9]'), '');
                                      final Map<String, dynamic> resetPayload = {
                                        'otp': o,
                                        'new_password': np,
                                        'role': 'partner',
                                      };
                                      if (cleanDigits.length == 10) {
                                        resetPayload['mobile_number'] = cleanDigits;
                                      }
                                      if (retrievedEmail.isNotEmpty) {
                                        resetPayload['email'] = retrievedEmail;
                                      } else if (inputVal.contains('@')) {
                                        resetPayload['email'] = inputVal;
                                      }

                                      final res = await http.post(
                                        ApiConfig.profileForgotPasswordReset,
                                        headers: {'Content-Type': 'application/json'},
                                        body: jsonEncode(resetPayload),
                                      );
                                      Map<String, dynamic> data = {};
                                      try {
                                        data = jsonDecode(res.body) as Map<String, dynamic>;
                                      } catch (_) {
                                        setModalState(() {
                                          isSubmitting = false;
                                          dialogError = 'Server returned invalid response';
                                        });
                                        return;
                                      }
                                      if (res.statusCode == 200 && data['success'] == true) {
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                        }
                                        _passwordController.text = np;
                                        _showSuccess('Password reset successfully! You can now log in.');
                                      } else {
                                        setModalState(() {
                                          isSubmitting = false;
                                          dialogError = data['error'] ?? 'Failed to reset password';
                                        });
                                      }
                                    } catch (e) {
                                      setModalState(() {
                                        isSubmitting = false;
                                        dialogError = 'Network error: $e';
                                      });
                                    }
                                  },
                            child: isSubmitting
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text("Save & Reset Password", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleBackNavigation() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
            onPressed: _handleBackNavigation,
          ),
          title: const Text(
            'Delivery Partner Login',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          centerTitle: true,
        ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Logo & Icon for Partner
                    Center(
                      child: Container(
                        height: 76,
                        width: 76,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppColors.border, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/G_LOGO.PNG',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title & Description
                    const Center(
                      child: Text(
                        'Delivery Partner Console',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Center(
                      child: Text(
                        'Login with your credentials to accept orders and view deliveries',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Auth Card (Login Process Only - No Registration)
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Partner Sign In',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Enter your registered mobile number or email ID and password',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Mobile or Email Field
                          TextField(
                            controller: _identifierController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Mobile Number or Email ID',
                              hintText: 'Enter 10-digit mobile or email ID',
                              prefixIcon: const Icon(Icons.badge_outlined, size: 20, color: AppColors.primaryDark),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.8)),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Password Field
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              hintText: 'Enter your password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.primaryDark),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20, color: AppColors.textMuted),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.8)),
                            ),
                          ),

                          // Forgot Password Button
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _showForgotPasswordDialog,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.lock_reset_rounded, size: 16, color: AppColors.primaryDark),
                              label: const Text(
                                "Forgot Password / Reset with OTP",
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Action Button: Login Only
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handlePartnerLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Login to Partner Console',
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(Icons.arrow_forward_rounded, size: 18),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Security Footnote
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_rounded, size: 15, color: AppColors.primaryDark),
                        SizedBox(width: 6),
                        Text(
                          'Authorized Delivery Partners Only',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginPage(
                                initialRole: 'customer',
                                forceShowLogin: true,
                              ),
                            ),
                            (route) => false,
                          );
                        },
                        icon: const Icon(Icons.person_outline_rounded, size: 18, color: AppColors.primaryDark),
                        label: const Text(
                          'Customer? Switch to Customer Login',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
}

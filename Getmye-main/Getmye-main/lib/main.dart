import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'homed.dart';
import 'ppp.dart';
import 'api_config.dart';
import 'services/app_notification_service.dart';
import 'services/alarm_service.dart';
import 'splash_screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);
  await flutterLocalNotificationsPlugin.initialize(initSettings);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Launch Flutter UI immediately so SplashScreen displays without delay
  runApp(const MyApp());
  _initServicesAsync();
}

Future<void> _initServicesAsync() async {
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Failed to load .env file: $e");
  }
  try {
    await initNotifications();
    await AppNotificationService.init();
    AppNotificationService.startGlobalChatPolling();
    AppNotificationService.startGlobalPartnerOrderPolling();
    AppNotificationService.startGlobalCustomerOrderPolling();

    // 🟢 Start background foreground listening service on startup if partner is logged in & online
    final prefs = await SharedPreferences.getInstance();
    final accountType = prefs.getString('account_type');
    final isOnline = prefs.getBool('d_is_online') ?? true;
    final pId = prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? 'DP001';
    if (accountType == 'partner' && isOnline) {
      AlarmService.startOrderListeningService(
        baseUrl: ApiConfig.baseUrl,
        partnerId: pId,
      );
      AlarmService.requestBatteryOptimizationExemption();
    } else if (accountType != 'partner') {
      final activeOrderId = prefs.getString('active_order_id');
      final activeStatus = (prefs.getString('active_order_status') ?? '').toLowerCase();
      if (activeOrderId != null && activeOrderId.isNotEmpty && activeStatus != 'delivered' && activeStatus != 'cancelled') {
        AlarmService.startCustomerOrderListeningService(
          baseUrl: ApiConfig.baseUrl,
          orderId: activeOrderId,
        );
        AlarmService.requestBatteryOptimizationExemption();
      }
    }
  } catch (e) {
    debugPrint("Failed to init notification services: $e");
  }
}

class MyApp extends StatefulWidget {
  final Widget? initialScreen;
  const MyApp({super.key, this.initialScreen});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }



  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: MyApp.navigatorKey,
      title: 'GETMYE',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: widget.initialScreen ?? const SplashScreen(),
    );
  }
}

class LoginPage extends StatefulWidget {
  final String initialRole; // 'customer' or 'partner'
  final bool forceShowLogin;
  const LoginPage({
    super.key,
    this.initialRole = 'customer',
    this.forceShowLogin = false,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final String _selectedRole = 'customer';
  bool _isSignUp = false;

  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    if (widget.forceShowLogin) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    final String accountType = prefs.getString('account_type') ?? 'customer';
    if (isLoggedIn && mounted) {
      if (accountType == 'partner') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    }
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool isValidMobile(String mobile) {
    return RegExp(r'^[0-9]{10}$').hasMatch(mobile);
  }

  bool isValidEmail(String email) {
    return RegExp(r'^[\w\.-]+@[\w\.-]+\.[a-zA-Z]{2,}$').hasMatch(email);
  }

  Future<void> _clearStaleSessionData(SharedPreferences prefs) async {
    // Clear old cache, active order ID, old status, and all previous user/partner session details
    await prefs.clear();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
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
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _handleLogin() async {
    final input = _mobileController.text.trim();
    final password = _passwordController.text.trim();

    if (!isValidMobile(input)) {
      _showError('Please enter a valid 10-digit mobile number');
      return;
    }

    if (password.isEmpty) {
      _showError('Please enter your password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await http.post(
        ApiConfig.profileLogin,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mobile_number': input,
          'password': password,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && (data['success'] == true || data['user_id'] != null)) {
        final prefs = await SharedPreferences.getInstance();
        await _clearStaleSessionData(prefs);

        final userId = data['user_id'] ?? 'usr_001';
        await prefs.setString('user_id', userId);
        await prefs.setString('mobile_number', data['mobile_number'] ?? input);
        await prefs.setString('user_name', data['name'] ?? '');
        await prefs.setString('user_email', data['email'] ?? '');
        await prefs.setString('account_type', 'customer');
        await prefs.setBool('is_logged_in', true);

        if (!mounted) return;
        _showSuccess('Welcome back, ${data['name']?.toString().isNotEmpty == true ? data['name'] : 'Customer'}!');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
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

  Future<void> _handleSignUp() async {
    final mobile = _mobileController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      _showError('Please enter your full name');
      return;
    }
    if (!isValidMobile(mobile)) {
      _showError('Please enter a valid 10-digit mobile number');
      return;
    }
    if (email.isEmpty) {
      _showError('Please enter your email ID');
      return;
    }
    if (!isValidEmail(email)) {
      _showError('Please enter a valid email address');
      return;
    }

    if (password.length < 4) {
      _showError('Password must be at least 4 characters');
      return;
    }
    if (password != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await http.post(
        ApiConfig.profileRegister,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mobile_number': mobile,
          'email': email,
          'password': password,
          'name': name,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await _clearStaleSessionData(prefs);

        final userId = data['user_id'] ?? 'usr_001';
        await prefs.setString('user_id', userId);
        await prefs.setString('mobile_number', mobile);
        await prefs.setString('user_name', name);
        if (email.isNotEmpty) {
          await prefs.setString('user_email', email);
        }
        await prefs.setString('account_type', 'customer');
        await prefs.setBool('is_logged_in', true);

        if (!mounted) return;
        _showSuccess('Account created successfully! Welcome, $name.');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
        );
      } else {
        final msg = data['error'] ?? data['message'] ?? 'Registration failed. Mobile or email may already be registered.';
        _showError(msg);
      }
    } catch (e) {
      _showError('Server connection error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog() {
    final resetMobileController = TextEditingController(text: _mobileController.text.trim());
    final linkEmailController = TextEditingController();
    final otpController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();

    int step = 1; // 1: Enter mobile, 2: Enter & verify OTP, 3: Set new password
    bool isSubmitting = false;
    String? dialogError;
    String retrievedEmail = '';
    String maskedEmail = '';
    String sentOtp = '';
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
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
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
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.lock_reset_rounded, color: AppColors.primaryDark, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        step == 1
                            ? "Forgot Password"
                            : step == 2
                                ? "Verify Email OTP"
                                : "Set New Password",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    step == 1
                        ? "Enter the email ID you used when creating your account. We will send the password reset verification OTP immediately."
                        : step == 2
                            ? "Enter the 6-digit OTP sent to your registered email to verify your identity."
                            : "Create and confirm your new password.",
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              dialogError!,
                              style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // STEP 1: Enter Email ID or Mobile Number & Send OTP
                  if (step == 1) ...[
                    TextField(
                      controller: resetMobileController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: "Registered Email ID",
                        hintText: "e.g. user@gmail.com or 10-digit mobile",
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
                          hintText: "e.g. user@gmail.com",
                          prefixIcon: const Icon(Icons.email_outlined, size: 20, color: AppColors.primaryDark),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final inputVal = resetMobileController.text.trim();
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
                                  if (!isValidEmail(enteredMail)) {
                                    setModalState(() => dialogError = 'Please enter a valid email address');
                                    return;
                                  }
                                }
                                setModalState(() {
                                  isSubmitting = true;
                                  dialogError = null;
                                });
                                try {
                                  final reqBody = <String, dynamic>{
                                    'role': _selectedRole,
                                  };
                                  if (isEmail) {
                                    reqBody['email'] = inputVal.toLowerCase();
                                  } else {
                                    reqBody['mobile_number'] = cleanDigits;
                                  }
                                  if (needsEmail && linkEmailController.text.trim().isNotEmpty) {
                                    reqBody['email'] = linkEmailController.text.trim().toLowerCase();
                                  }

                                  final res = await http.post(
                                    ApiConfig.profileForgotPasswordSendOtp,
                                    headers: {'Content-Type': 'application/json'},
                                    body: jsonEncode(reqBody),
                                  );

                                  Map<String, dynamic> data = {};
                                  try {
                                    data = jsonDecode(res.body) as Map<String, dynamic>;
                                  } catch (_) {
                                    setModalState(() {
                                      isSubmitting = false;
                                      dialogError = 'Server error (${res.statusCode}). Please ensure backend is reachable.';
                                    });
                                    return;
                                  }

                                  if (res.statusCode == 200 && data['success'] == true) {
                                    setModalState(() {
                                      retrievedEmail = (data['email'] ?? '').toString();
                                      maskedEmail = (data['masked_email'] ?? data['email'] ?? '').toString();
                                      sentOtp = (data['otp'] ?? '').toString();
                                      step = 2;
                                      isSubmitting = false;
                                      dialogError = null;
                                    });
                                    _showSuccess('OTP sent to registered email: $maskedEmail');
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
                  ]

                  // STEP 2: Enter OTP & Verify ("atha enter panni verify panna aprm")
                  else if (step == 2) ...[
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
                    if (sentOtp.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () {
                          setModalState(() {
                            otpController.text = sentOtp;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.touch_app_rounded, size: 16, color: Color(0xFF2563EB)),
                              const SizedBox(width: 6),
                              Text(
                                "Auto-fill OTP ($sentOtp)",
                                style: const TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 14),
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
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final o = otpController.text.trim();
                                    if (o.length < 4) {
                                      setModalState(() => dialogError = 'Please enter valid OTP');
                                      return;
                                    }
                                    setModalState(() {
                                      isSubmitting = true;
                                      dialogError = null;
                                    });
                                    try {
                                      final res = await http.post(
                                        ApiConfig.profileForgotPasswordVerifyOtp,
                                        headers: {'Content-Type': 'application/json'},
                                        body: jsonEncode({
                                          'mobile_number': resetMobileController.text.trim(),
                                          'email': retrievedEmail,
                                          'otp': o,
                                          'role': _selectedRole,
                                        }),
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
                                          step = 3; // Move to set password step!
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
                  ]

                  // STEP 3: Set New Password & Confirm Password ("new pass word confirm password irukanum")
                  else if (step == 3) ...[
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
                              "Identity verified! Please set your new login password below.",
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
                        hintText: "Create new password (min 4 chars)",
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
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 14),
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
                              padding: const EdgeInsets.symmetric(vertical: 14),
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
                                      final res = await http.post(
                                        ApiConfig.profileForgotPasswordReset,
                                        headers: {'Content-Type': 'application/json'},
                                        body: jsonEncode({
                                          'mobile_number': resetMobileController.text.trim(),
                                          'email': retrievedEmail,
                                          'otp': o,
                                          'new_password': np,
                                          'role': _selectedRole,
                                        }),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                    // Brand Logo & Icon
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

                    // Brand Typography
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'GET',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'MYE',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Center(
                      child: Text(
                        'Order from multiple restaurants in one delivery',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Auth Card (Login or Sign Up)
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
                          Text(
                            _isSignUp ? 'Create Customer Account' : 'Customer Login',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isSignUp
                                ? 'Set your mobile number and password to register'
                                : 'Enter your 10-digit mobile number and password to continue',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Name field (Sign Up only)
                          if (_isSignUp) ...[
                            TextField(
                              controller: _nameController,
                              textCapitalization: TextCapitalization.words,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                labelText: 'Full Name',
                                hintText: 'Enter your name',
                                prefixIcon: const Icon(Icons.person_outline_rounded, size: 20, color: AppColors.primaryDark),
                                filled: true,
                                fillColor: AppColors.background,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.8)),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // Mobile Number Field
                          TextField(
                            controller: _mobileController,
                            keyboardType: TextInputType.number,
                            maxLength: 10,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Mobile Number',
                              prefixIcon: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                margin: const EdgeInsets.only(right: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.phone_iphone_rounded, size: 20, color: AppColors.primaryDark),
                                    const SizedBox(width: 6),
                                    const Text('+91', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                    const SizedBox(width: 8),
                                    Container(height: 20, width: 1, color: AppColors.border),
                                  ],
                                ),
                              ),
                              counterText: '',
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.8)),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Email ID Field (Sign Up only)
                          if (_isSignUp) ...[
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                labelText: 'Email ID * (Compulsory)',
                                hintText: 'Enter email address (e.g. user@example.com)',
                                prefixIcon: const Icon(Icons.email_outlined, size: 20, color: AppColors.primaryDark),
                                filled: true,
                                fillColor: AppColors.background,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.8)),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // Password Field
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              labelText: _isSignUp ? 'New Password' : 'Password',
                              hintText: _isSignUp ? 'Create new password' : 'Enter password',
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
                          // Forgot Password Button (Login mode only)
                          if (!_isSignUp) ...[
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
                          ],

                          // Confirm Password Field (Sign Up only)
                          if (_isSignUp) ...[
                            const SizedBox(height: 14),
                            TextField(
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirmPassword,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                labelText: 'Set / Confirm Password',
                                hintText: 'Re-enter password',
                                prefixIcon: const Icon(Icons.lock_reset_rounded, size: 20, color: AppColors.primaryDark),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureConfirmPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20, color: AppColors.textMuted),
                                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                ),
                                filled: true,
                                fillColor: AppColors.background,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.8)),
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),

                          // Action Button (Login or Create Account)
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : (_isSignUp ? _handleSignUp : _handleLogin),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isSignUp ? const Color(0xFFF96E14) : AppColors.primary,
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
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          _isSignUp ? 'Create Account' : 'Login with Password',
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.arrow_forward_rounded, size: 18),
                                      ],
                                    ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Toggle Login vs Sign Up
                          Center(
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  _isSignUp = !_isSignUp;
                                });
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              child: _isSignUp
                                  ? const Text(
                                      'Already have an account? Login',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                        color: AppColors.primary,
                                      ),
                                    )
                                  : const Text.rich(
                                      TextSpan(
                                        text: "Don't have an account? ",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: AppColors.primaryDark,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: "Create a new account",
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              color: Color(0xFFF96E14),
                                            ),
                                          ),
                                        ],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Security Footnote
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.lock_rounded, size: 15, color: AppColors.primaryDark),
                        SizedBox(width: 6),
                        Text(
                          'Password Protected & Verified Session',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
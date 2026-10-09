import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'ppp.dart';
import 'homed.dart';
import 'dperson.dart';
import 'api_config.dart';
import 'services/app_notification_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);
  await flutterLocalNotificationsPlugin.initialize(initSettings);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  await AppNotificationService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GETMYE',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  final String initialRole; // 'customer' or 'partner'
  const LoginPage({super.key, this.initialRole = 'customer'});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late String _selectedRole; // 'customer' or 'partner'
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
    _selectedRole = widget.initialRole;
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
        backgroundColor: const Color(0xFF15803D),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _handleLogin() async {
    final input = _mobileController.text.trim();
    final password = _passwordController.text.trim();

    if (_selectedRole == 'customer') {
      if (!isValidMobile(input)) {
        _showError('Please enter a valid 10-digit mobile number');
        return;
      }
    } else {
      // For Partner: can enter either 10-digit mobile or valid email ID
      final isEmail = input.contains('@');
      if (isEmail) {
        if (!isValidEmail(input)) {
          _showError('Please enter a valid email address');
          return;
        }
      } else {
        if (!isValidMobile(input)) {
          _showError('Please enter a valid 10-digit mobile number or email ID');
          return;
        }
      }
    }

    if (password.isEmpty) {
      _showError('Please enter your password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uri = _selectedRole == 'customer'
          ? ApiConfig.profileLogin
          : ApiConfig.partnerLogin;

      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_selectedRole == 'customer'
            ? {
                'mobile_number': input,
                'password': password,
              }
            : {
                'mobile_number': input.contains('@') ? '' : input,
                'email': input.contains('@') ? input : '',
                'identifier': input,
                'password': password,
              }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && (data['success'] == true || data['user_id'] != null || data['dp_id'] != null)) {
        final prefs = await SharedPreferences.getInstance();
        await _clearStaleSessionData(prefs);

        if (_selectedRole == 'customer') {
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
          final dpId = data['dp_id'] ?? 'DP001';
          final partnerPhone = (data['mobile_number'] != null && data['mobile_number'].toString().isNotEmpty)
              ? data['mobile_number'].toString()
              : (!input.contains('@') ? input : '');
          final partnerEmail = (data['email'] != null && data['email'].toString().isNotEmpty)
              ? data['email'].toString()
              : (input.contains('@') ? input : '');

          await prefs.setString('d_id', dpId);
          await prefs.setString('active_order_partner_id', dpId);
          await prefs.setString('d_name', data['name'] ?? 'Delivery Partner');
          await prefs.setString('d_phone', partnerPhone);
          await prefs.setString('d_email', partnerEmail);
          await prefs.setString('d_address', data['address'] ?? '');
          await prefs.setBool('d_is_online', true);
          await prefs.setString('account_type', 'partner');
          await prefs.setBool('is_logged_in', true);

          if (!mounted) return;
          _showSuccess('Welcome back, ${data['name']?.toString().isNotEmpty == true ? data['name'] : 'Partner'}!');
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
            (route) => false,
          );
        }
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
    if (_selectedRole == 'partner') {
      if (email.isEmpty) {
        _showError('Please enter your email ID');
        return;
      }
      if (!isValidEmail(email)) {
        _showError('Please enter a valid email address (e.g. partner@example.com)');
        return;
      }
    } else {
      if (email.isNotEmpty && !isValidEmail(email)) {
        _showError('Please enter a valid email address');
        return;
      }
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
      final uri = _selectedRole == 'customer'
          ? ApiConfig.profileRegister
          : ApiConfig.partnerRegister;

      final res = await http.post(
        uri,
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

        if (_selectedRole == 'customer') {
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
          final dpId = data['dp_id'] ?? 'DP001';
          await prefs.setString('d_id', dpId);
          await prefs.setString('active_order_partner_id', dpId);
          await prefs.setString('d_name', name);
          await prefs.setString('d_phone', mobile);
          await prefs.setString('d_email', email);
          await prefs.setBool('d_is_online', true);
          await prefs.setString('account_type', 'partner');
          await prefs.setBool('is_logged_in', true);

          if (!mounted) return;
          _showSuccess('Partner account created! Welcome, $name.');
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
            (route) => false,
          );
        }
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

  @override
  Widget build(BuildContext context) {
    final isCustomer = _selectedRole == 'customer';

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
                        height: 68,
                        width: 68,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.primarySubtle, width: 1.5),
                        ),
                        child: Icon(
                          isCustomer ? Icons.restaurant_rounded : Icons.two_wheeler_rounded,
                          size: 36,
                          color: AppColors.primaryDark,
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
                    Center(
                      child: Text(
                        isCustomer
                            ? 'Order from multiple restaurants in one delivery'
                            : 'Delivery Partner Portal',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Role Switcher (Customer vs Delivery Partner)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedRole = 'customer';
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: isCustomer ? AppColors.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.person_rounded,
                                      size: 18,
                                      color: isCustomer ? Colors.white : AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Customer',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: isCustomer ? Colors.white : AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedRole = 'partner';
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: !isCustomer ? AppColors.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.two_wheeler_rounded,
                                      size: 18,
                                      color: !isCustomer ? Colors.white : AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Delivery Partner',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: !isCustomer ? Colors.white : AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

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
                            _isSignUp
                                ? (_selectedRole == 'customer' ? 'Create Customer Account' : 'Partner Sign Up')
                                : (_selectedRole == 'customer' ? 'Customer Login' : 'Partner Login'),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isSignUp
                                ? (_selectedRole == 'partner'
                                    ? 'Enter full name, mobile number, and email ID to register'
                                    : 'Set your mobile number and password to register')
                                : (_selectedRole == 'partner'
                                    ? 'Enter your mobile number or email ID and password'
                                    : 'Enter your mobile number and password to continue'),
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

                          // Identifier / Mobile Number Field
                          if (!_isSignUp && _selectedRole == 'partner') ...[
                            TextField(
                              controller: _mobileController,
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
                          ] else ...[
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
                          ],

                          // Email ID Field (Sign Up only)
                          if (_isSignUp) ...[
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                labelText: _selectedRole == 'partner' ? 'Email ID (Required for Partner)' : 'Email ID (Optional)',
                                hintText: _selectedRole == 'partner' ? 'Enter valid email (e.g. partner@mail.com)' : 'Enter email (e.g. user@example.com)',
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
                              child: Text(
                                _isSignUp
                                    ? 'Already have an account? Login'
                                    : "Don't have an account? Create New Account",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                          ),

                          // Full Partner KYC Registration shortcut if on Partner role
                          if (!isCustomer) ...[
                            const Divider(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const DeliveryPersonDetailsPage()),
                                  );
                                },
                                icon: const Icon(Icons.badge_rounded, size: 18, color: AppColors.textSecondary),
                                label: const Text(
                                  'Complete Full KYC Partner Registration',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                                ),
                              ),
                            ),
                          ],
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
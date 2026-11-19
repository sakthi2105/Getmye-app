import 'package:flutter/foundation.dart';

class AdminAuthService {
  // Required Admin Credentials
  static const String validEmail = 'sakthigopi210505@gmail.com';
  static const String validPassword = 'S@kthi2105';

  static bool _isLoggedIn = false;
  static String? _currentAdminEmail;
  static DateTime? _loginTime;

  static bool get isLoggedIn => _isLoggedIn;
  static String? get currentAdminEmail => _currentAdminEmail;
  static DateTime? get loginTime => _loginTime;

  static final ValueNotifier<bool> authStateListenable = ValueNotifier<bool>(_isLoggedIn);

  // Authenticate Admin
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    // Artificial small delay for polished UI transition
    await Future.delayed(const Duration(milliseconds: 350));

    final normalizedEmail = email.trim().toLowerCase();
    final targetEmail = validEmail.toLowerCase();

    if (normalizedEmail != targetEmail) {
      return {
        'success': false,
        'message': 'Invalid Admin email address. Please use the authorized GetMye admin account.',
      };
    }

    if (password != validPassword) {
      return {
        'success': false,
        'message': 'Incorrect password. Please verify your credentials and try again.',
      };
    }

    _isLoggedIn = true;
    _currentAdminEmail = validEmail;
    _loginTime = DateTime.now();
    authStateListenable.value = true;

    return {
      'success': true,
      'message': 'Welcome back, Admin!',
    };
  }

  // Logout Admin
  static void logout() {
    _isLoggedIn = false;
    _currentAdminEmail = null;
    _loginTime = null;
    authStateListenable.value = false;
  }
}


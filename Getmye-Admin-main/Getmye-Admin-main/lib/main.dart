import 'package:flutter/material.dart';
import 'pages/admin_login_page.dart';
import 'pages/admin_shell_page.dart';
import 'pages/kyc_verification_page.dart';
import 'services/admin_auth_service.dart';
import 'theme/admin_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AdminAuthService.authStateListenable,
      builder: (context, isLoggedIn, _) {
        return MaterialApp(
          title: 'GetMye Admin - Master Operations Hub',
          theme: AdminTheme.lightTheme,
          debugShowCheckedModeBanner: false,
          home: isLoggedIn ? const AdminShellPage() : const AdminLoginPage(),
        );
      },
    );
  }
}

// Backward-compatible alias for existing references
class AdminDeliveryPersonListPage extends StatelessWidget {
  const AdminDeliveryPersonListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const KycVerificationPage();
  }
}

import 'package:flutter/material.dart';
import '../services/admin_auth_service.dart';
import '../theme/admin_theme.dart';
import '../widgets/env_switcher_button.dart';
import 'admin_shell_page.dart';

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _fillCredentials() {
    setState(() {
      _emailController.text = AdminAuthService.validEmail;
      _passwordController.text = AdminAuthService.validPassword;
      _errorMessage = null;
    });
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await AdminAuthService.login(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result['success'] == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminShellPage()),
      );
    } else {
      setState(() {
        _errorMessage = result['message'] as String?;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _errorMessage ?? 'Authentication failed',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: AdminColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo & Brand Header
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AdminColors.primaryLight,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AdminColors.primarySubtle, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1010B981),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_rounded,
                        color: AdminColors.primaryDark,
                        size: 44,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title & Subtitle
                  Center(
                    child: RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                        children: [
                          TextSpan(
                            text: 'GetMye ',
                            style: TextStyle(color: AdminColors.textPrimary),
                          ),
                          TextSpan(
                            text: 'Admin Portal',
                            style: TextStyle(color: AdminColors.primaryDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(
                      'Sign in with authorized administrator credentials',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AdminColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Quick Auto-fill action chip & Environment Switcher
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.key_rounded, size: 16, color: AdminColors.primaryDark),
                        label: const Text(
                          'Auto-Fill Credentials',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.primaryDark,
                          ),
                        ),
                        backgroundColor: AdminColors.primaryLight,
                        side: const BorderSide(color: AdminColors.primarySubtle),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        onPressed: _fillCredentials,
                      ),
                      const SizedBox(width: 8),
                      const EnvSwitcherButton(),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Card Container for Form
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AdminColors.border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x06000000),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Error banner if any
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: AdminColors.dangerLight,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AdminColors.danger.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded, color: AdminColors.danger, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(
                                        color: AdminColors.danger,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Email Field
                          const Text(
                            'Administrator Email',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(fontSize: 14, color: AdminColors.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Enter admin email',
                              prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20, color: AdminColors.primaryDark),
                              hintStyle: const TextStyle(color: AdminColors.textMuted, fontSize: 13),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Email is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),

                          // Password Field
                          const Text(
                            'Password',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _handleLogin(),
                            style: const TextStyle(fontSize: 14, color: AdminColors.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Enter password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AdminColors.primaryDark),
                              hintStyle: const TextStyle(color: AdminColors.textMuted, fontSize: 13),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: AdminColors.textSecondary,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Password is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          // Login Submit Button
                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AdminColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Sign In to Dashboard',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward_rounded, size: 18),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Security notice badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.verified_user_outlined, size: 14, color: AdminColors.textMuted),
                      SizedBox(width: 6),
                      Text(
                        'GetMye Enterprise Security • End-to-End Encrypted',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AdminColors.textMuted,
                        ),
                      ),
                    ],
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


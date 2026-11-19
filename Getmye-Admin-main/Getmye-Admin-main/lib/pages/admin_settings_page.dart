import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/admin_auth_service.dart';
import '../theme/admin_theme.dart';
import 'admin_login_page.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final TextEditingController _urlController = TextEditingController();
  bool isTesting = false;
  String? testResult;
  bool? isSuccess;

  @override
  void initState() {
    super.initState();
    _urlController.text = AdminApiConfig.baseUrl;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      isTesting = true;
      testResult = null;
      isSuccess = null;
    });

    final targetUrl = _urlController.text.trim();
    AdminApiConfig.setBaseUrl(targetUrl);

    try {
      final res = await http.get(AdminApiConfig.health).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        setState(() {
          isSuccess = true;
          testResult = 'Connection successful! Backend server is online.';
        });
      } else {
        setState(() {
          isSuccess = false;
          testResult = 'Server responded with status code: ${res.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        isSuccess = false;
        testResult = 'Connection failed: Unable to connect to $targetUrl';
      });
    } finally {
      if (mounted) setState(() => isTesting = false);
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.logout_rounded, color: AdminColors.danger, size: 22),
            SizedBox(width: 8),
            Text('Confirm Sign Out', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ],
        ),
        content: const Text(
          'Are you sure you want to end your administrator session?',
          style: TextStyle(color: AdminColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              AdminAuthService.logout();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const AdminLoginPage()),
                (route) => false,
              );
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        title: const Text('Admin Settings & Server Configuration'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AdminColors.border, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Administrator Account Details
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AdminColors.border),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AdminColors.primaryLight,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AdminColors.primarySubtle),
                            ),
                            child: const Center(
                              child: Icon(Icons.shield_rounded, color: AdminColors.primaryDark, size: 26),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'GetMye Super Administrator',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  AdminAuthService.currentAdminEmail ?? 'sakthigopi210505@gmail.com',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AdminColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AdminColors.primaryLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'AUTHENTICATED',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AdminColors.primaryDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1, color: AdminColors.borderLight),
                      const SizedBox(height: 14),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Role: Executive Management',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Full access to KYC, Offer Banners, Complaints & Live Orders',
                                style: TextStyle(fontSize: 11, color: AdminColors.textMuted),
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            onPressed: _confirmLogout,
                            icon: const Icon(Icons.logout_rounded, size: 16, color: AdminColors.danger),
                            label: const Text('Sign Out', style: TextStyle(color: AdminColors.danger)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AdminColors.dangerLight),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Server Configuration Box
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AdminColors.border),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Backend Server Base URL',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Configure which server IP or cloud domain the admin portal communicates with.',
                        style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                      ),
                      const SizedBox(height: 14),

                      TextField(
                        controller: _urlController,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          hintText: 'http://192.168.29.196:5000',
                          prefixIcon: Icon(Icons.dns_rounded, size: 18),
                          labelText: 'API Base URL',
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Quick Presets
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('Local LAN (192.168.29.196:5000)', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              _urlController.text = 'http://192.168.29.196:5000';
                              _testConnection();
                            },
                          ),
                          ActionChip(
                            label: const Text('Cloud Production (Render)', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              _urlController.text = 'https://getmye-app.onrender.com';
                              _testConnection();
                            },
                          ),
                          ActionChip(
                            label: const Text('Localhost (127.0.0.1:5000)', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              _urlController.text = 'http://127.0.0.1:5000';
                              _testConnection();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (testResult != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSuccess == true ? AdminColors.primaryLight : AdminColors.dangerLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSuccess == true ? AdminColors.primarySubtle : AdminColors.danger.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSuccess == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                                color: isSuccess == true ? AdminColors.primaryDark : AdminColors.danger,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  testResult!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSuccess == true ? AdminColors.primaryDark : AdminColors.danger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      ElevatedButton.icon(
                        onPressed: isTesting ? null : _testConnection,
                        icon: isTesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.network_check_rounded, size: 18),
                        label: const Text('Save & Test Connection'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
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


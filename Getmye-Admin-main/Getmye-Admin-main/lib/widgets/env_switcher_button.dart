import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../theme/admin_theme.dart';

class EnvSwitcherButton extends StatelessWidget {
  final VoidCallback? onEnvironmentChanged;

  const EnvSwitcherButton({this.onEnvironmentChanged, super.key});

  static void showEnvironmentDialog(BuildContext context, {VoidCallback? onChanged}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EnvSwitcherSheet(onChanged: onChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AdminMode>(
      valueListenable: AdminApiConfig.modeNotifier,
      builder: (context, mode, _) {
        final isLocal = AdminApiConfig.isLocal;
        final bg = isLocal ? AdminColors.primaryLight : const Color(0xFFEFF6FF);
        final fg = isLocal ? AdminColors.primaryDark : const Color(0xFF1D4ED8);
        final border = isLocal ? AdminColors.primarySubtle : const Color(0xFFBFDBFE);
        final icon = isLocal ? Icons.computer_rounded : Icons.cloud_done_rounded;

        return InkWell(
          onTap: () => showEnvironmentDialog(context, onChanged: onEnvironmentChanged),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 5),
                Text(
                  AdminApiConfig.modeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(Icons.arrow_drop_down_rounded, size: 18, color: fg),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EnvSwitcherSheet extends StatefulWidget {
  final VoidCallback? onChanged;

  const _EnvSwitcherSheet({this.onChanged});

  @override
  State<_EnvSwitcherSheet> createState() => _EnvSwitcherSheetState();
}

class _EnvSwitcherSheetState extends State<_EnvSwitcherSheet> {
  bool isTesting = false;
  String? testStatus;
  bool? isReachable;

  Future<void> _pingActiveServer() async {
    setState(() {
      isTesting = true;
      testStatus = null;
      isReachable = null;
    });

    try {
      final res = await http.get(AdminApiConfig.health).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        setState(() {
          isReachable = true;
          testStatus = 'Connected successfully (${AdminApiConfig.baseUrl})';
        });
      } else {
        setState(() {
          isReachable = false;
          testStatus = 'Server responded with error: ${res.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        isReachable = false;
        testStatus = 'Connection failed: ${AdminApiConfig.baseUrl} is not reachable.';
      });
    } finally {
      if (mounted) setState(() => isTesting = false);
    }
  }

  void _selectMode(AdminMode mode, {String? customUrl}) {
    AdminApiConfig.setMode(mode, customUrl: customUrl);
    _pingActiveServer();
    widget.onChanged?.call();
  }

  @override
  void initState() {
    super.initState();
    _pingActiveServer();
  }

  @override
  Widget build(BuildContext context) {
    final current = AdminApiConfig.currentMode;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sheet Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AdminColors.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.tune_rounded, color: AdminColors.primaryDark, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Server Environment',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Choose between Local Development or Live Cloud',
                            style: TextStyle(fontSize: 11, color: AdminColors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Server Connectivity Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isReachable == true
                      ? AdminColors.primaryLight
                      : (isReachable == false ? AdminColors.dangerLight : AdminColors.background),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isReachable == true
                        ? AdminColors.primarySubtle
                        : (isReachable == false ? const Color(0xFFFCA5A5) : AdminColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    if (isTesting)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AdminColors.primary),
                      )
                    else
                      Icon(
                        isReachable == true
                            ? Icons.check_circle_rounded
                            : (isReachable == false ? Icons.error_outline_rounded : Icons.circle),
                        size: 16,
                        color: isReachable == true
                            ? AdminColors.primaryDark
                            : (isReachable == false ? AdminColors.danger : AdminColors.textMuted),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        testStatus ?? 'Testing server connection...',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isReachable == true
                              ? AdminColors.primaryDark
                              : (isReachable == false ? AdminColors.danger : AdminColors.textSecondary),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      onPressed: _pingActiveServer,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Option 1: LOCALHOST (Local Machine)
              _buildOptionCard(
                mode: AdminMode.local,
                isSelected: current == AdminMode.local,
                title: 'Localhost (127.0.0.1:5000)',
                subtitle: 'Recommended for PC/Web testing. Connects to your running node server.js.',
                icon: Icons.laptop_chromebook_rounded,
                badge: 'TESTING',
                badgeColor: AdminColors.primary,
                url: AdminApiConfig.defaultLocalhostUrl,
                onTap: () => _selectMode(AdminMode.local),
              ),
              const SizedBox(height: 10),

              // Option 2: LOCAL LAN (Wi-Fi for Mobile Phone)
              _buildOptionCard(
                mode: AdminMode.lan,
                isSelected: current == AdminMode.lan,
                title: 'Local Wi-Fi LAN (192.168.29.196:5000)',
                subtitle: 'Connects to your local IP over Wi-Fi. Ideal when running on physical Android phones.',
                icon: Icons.wifi_rounded,
                badge: 'MOBILE LAN',
                badgeColor: const Color(0xFF0284C7),
                url: AdminApiConfig.defaultLanUrl,
                onTap: () => _selectMode(AdminMode.lan),
              ),
              const SizedBox(height: 10),

              // Option 3: LIVE PRODUCTION CLOUD
              _buildOptionCard(
                mode: AdminMode.live,
                isSelected: current == AdminMode.live,
                title: 'Live Production Cloud (Render)',
                subtitle: 'Connects to live cloud backend. Real customer orders and live delivery partners.',
                icon: Icons.cloud_done_rounded,
                badge: 'PRODUCTION',
                badgeColor: const Color(0xFF16A34A),
                url: AdminApiConfig.defaultLiveRenderUrl,
                onTap: () => _selectMode(AdminMode.live),
              ),
              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Done & Apply Mode', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required AdminMode mode,
    required bool isSelected,
    required String title,
    required String subtitle,
    required IconData icon,
    required String badge,
    required Color badgeColor,
    required String url,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AdminColors.primaryLight.withValues(alpha: 0.35) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AdminColors.primary : AdminColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? AdminColors.primaryLight : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: isSelected ? AdminColors.primaryDark : AdminColors.textSecondary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: badgeColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    url,
                    style: const TextStyle(fontSize: 10, color: AdminColors.textMuted, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            Radio<AdminMode>(
              value: mode,
              groupValue: AdminApiConfig.currentMode,
              onChanged: (_) => onTap(),
              activeColor: AdminColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}


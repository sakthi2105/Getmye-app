import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'theme/app_theme.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _isClearing = false;
  String _userId = '';

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('user_id') ?? '';
      _userId = uid;

      if (uid.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final res = await http
          .get(ApiConfig.orderNotificationsAll(uid))
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['notifications'] as List?) ?? [];
        if (mounted) {
          setState(() {
            _notifications = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            _isLoading = false;
          });
        }

        // Mark unread notifications as read in background
        final unreadIds = _notifications
            .where((n) => n['is_read'] != true && n['notification_id'] != null)
            .map((n) => n['notification_id'].toString())
            .toList();
        if (unreadIds.isNotEmpty) {
          http
              .post(
                ApiConfig.orderNotificationsMarkRead,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'notification_ids': unreadIds, 'user_id': uid}),
              )
              .catchError((_) => http.Response('', 500));
        }
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _clearAllNotifications() async {
    if (_userId.isEmpty || _notifications.isEmpty) return;
    setState(() => _isClearing = true);
    try {
      final res = await http
          .delete(ApiConfig.orderNotificationsClear(_userId))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _notifications.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications cleared'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to clear notifications'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _deleteSingleNotification(String notificationId, int index) async {
    final removed = _notifications[index];
    setState(() => _notifications.removeAt(index));
    try {
      await http
          .delete(ApiConfig.orderNotificationDelete(notificationId))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      if (mounted) {
        setState(() => _notifications.insert(index, removed));
      }
    }
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final min = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${dt.day} ${months[dt.month - 1]}, $hour:$min $ampm';
    } catch (_) {
      return '';
    }
  }

  IconData _iconForTitle(String title) {
    final t = title.toLowerCase();
    if (t.contains('offer') || t.contains('discount') || t.contains('deal')) {
      return Icons.campaign_rounded;
    }
    if (t.contains('delivered') || t.contains('order') || t.contains('partner')) {
      return Icons.notifications_active_rounded;
    }
    if (t.contains('restaurant') || t.contains('hotel') || t.contains('new')) {
      return Icons.card_giftcard_rounded;
    }
    return Icons.favorite_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              onPressed: _isClearing ? null : _clearAllNotifications,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Clear All',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadNotifications,
        color: AppColors.primary,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _notifications.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.22),
                      Center(
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.notifications_off_outlined,
                                size: 54,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'No more notifications!',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              "We'll let you know when something new arrives.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    itemCount: _notifications.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _notifications.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: Center(
                            child: OutlinedButton.icon(
                              onPressed: _isClearing ? null : _clearAllNotifications,
                              icon: _isClearing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                    )
                                  : const Icon(Icons.check_rounded, size: 18),
                              label: Text(
                                _isClearing ? 'Clearing...' : 'Clear All Notifications',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                backgroundColor: Colors.white,
                                side: const BorderSide(color: AppColors.primary, width: 1.2),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      final n = _notifications[index];
                      final notifId = (n['notification_id'] ?? '').toString();
                      final title = (n['title'] ?? 'Notification').toString();
                      final message = (n['message'] ?? '').toString();
                      final isUnread = n['is_read'] != true;
                      final dateStr = _formatDate(n['created_at']);

                      return Dismissible(
                        key: ValueKey(notifId.isNotEmpty ? notifId : 'notif_$index'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) {
                          if (notifId.isNotEmpty) {
                            _deleteSingleNotification(notifId, index);
                          }
                        },
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.only(right: 20),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.delete_rounded, color: Colors.white),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isUnread
                                  ? AppColors.primary.withValues(alpha: 0.35)
                                  : AppColors.border,
                            ),
                            boxShadow: AppColors.subtleShadow,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 42,
                                width: 42,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _iconForTitle(title),
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        if (dateStr.isNotEmpty)
                                          Text(
                                            dateStr,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        if (isUnread) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: const BoxDecoration(
                                              color: AppColors.primary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      message,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.textSecondary,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

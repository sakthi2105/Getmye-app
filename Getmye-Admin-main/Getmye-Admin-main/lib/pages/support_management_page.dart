import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../theme/admin_theme.dart';

class SupportManagementPage extends StatefulWidget {
  const SupportManagementPage({super.key});

  @override
  State<SupportManagementPage> createState() => _SupportManagementPageState();
}

class _SupportManagementPageState extends State<SupportManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<dynamic> bugReports = [];
  List<dynamic> complaints = [];
  List<dynamic> feedbacks = [];

  bool isLoadingBugs = true;
  bool isLoadingComplaints = true;
  bool isLoadingFeedbacks = true;

  Map<String, dynamic>? supportStats;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchAllSupportData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllSupportData() async {
    fetchStats();
    fetchBugReports();
    fetchComplaints();
    fetchFeedbacks();
  }

  Future<void> fetchStats() async {
    try {
      final res = await http.get(AdminApiConfig.supportStats);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['success'] == true) {
          setState(() => supportStats = decoded);
        }
      }
    } catch (_) {}
  }

  Future<void> fetchBugReports() async {
    setState(() => isLoadingBugs = true);
    try {
      final res = await http.get(AdminApiConfig.supportBugReports);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['reports'] is List) {
          setState(() {
            bugReports = decoded['reports'] as List;
            isLoadingBugs = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoadingBugs = false);
      }
    } catch (_) {
      if (mounted) setState(() => isLoadingBugs = false);
    }
  }

  Future<void> fetchComplaints() async {
    setState(() => isLoadingComplaints = true);
    try {
      final res = await http.get(AdminApiConfig.supportComplaints);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['complaints'] is List) {
          setState(() {
            complaints = decoded['complaints'] as List;
            isLoadingComplaints = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoadingComplaints = false);
      }
    } catch (_) {
      if (mounted) setState(() => isLoadingComplaints = false);
    }
  }

  Future<void> fetchFeedbacks() async {
    setState(() => isLoadingFeedbacks = true);
    try {
      final res = await http.get(AdminApiConfig.supportFeedbacks);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['feedbacks'] is List) {
          setState(() {
            feedbacks = decoded['feedbacks'] as List;
            isLoadingFeedbacks = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoadingFeedbacks = false);
      }
    } catch (_) {
      if (mounted) setState(() => isLoadingFeedbacks = false);
    }
  }

  Future<void> _updateBugStatus(String reportId, String newStatus) async {
    try {
      final res = await http.put(
        AdminApiConfig.updateBugStatus(reportId),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'status': newStatus}),
      );
      if (res.statusCode == 200) {
        fetchBugReports();
        fetchStats();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Bug report #$reportId marked as $newStatus'),
              backgroundColor: AdminColors.success,
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _updateComplaintStatus(String complaintId, String newStatus) async {
    try {
      final res = await http.put(
        AdminApiConfig.updateComplaintStatus(complaintId),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'status': newStatus}),
      );
      if (res.statusCode == 200) {
        fetchComplaints();
        fetchStats();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Complaint #$complaintId status updated to $newStatus'),
              backgroundColor: AdminColors.success,
            ),
          );
        }
      }
    } catch (_) {}
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Recent';
    try {
      final dt = DateTime.parse(timestamp.toString()).toLocal();
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return timestamp.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        title: const Text('Support, Grievance & Feedback Hub'),
        actions: [
          IconButton(
            tooltip: 'Refresh all support tickets',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchAllSupportData,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AdminColors.primaryDark,
          unselectedLabelColor: AdminColors.textSecondary,
          indicatorColor: AdminColors.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: [
            Tab(
              icon: const Icon(Icons.bug_report_rounded, size: 18),
              text: 'Bug Reports (${bugReports.length})',
            ),
            Tab(
              icon: const Icon(Icons.report_problem_rounded, size: 18),
              text: 'Complaints (${complaints.length})',
            ),
            Tab(
              icon: const Icon(Icons.star_rounded, size: 18),
              text: 'Feedbacks (${feedbacks.length})',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // KPI Metric Header Bar
          _buildSupportKpiHeader(),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBugReportsTab(),
                _buildComplaintsTab(),
                _buildFeedbacksTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportKpiHeader() {
    final openBugs = supportStats?['open_bugs']?.toString() ?? bugReports.where((b) => b['status'] != 'resolved').length.toString();
    final pendingComplaints = supportStats?['pending_complaints']?.toString() ?? complaints.where((c) => c['status'] != 'resolved').length.toString();
    final avgRating = supportStats?['average_rating']?.toString() ?? '4.9';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Row(
            children: [
              Expanded(
                child: _buildHeaderPill(
                  label: 'Open Bugs',
                  value: openBugs,
                  icon: Icons.bug_report_rounded,
                  color: AdminColors.danger,
                  bgColor: AdminColors.dangerLight,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHeaderPill(
                  label: 'Pending Grievances',
                  value: pendingComplaints,
                  icon: Icons.assignment_late_rounded,
                  color: const Color(0xFFB45309),
                  bgColor: AdminColors.warningLight,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHeaderPill(
                  label: 'Avg Customer Rating',
                  value: '$avgRating ★',
                  icon: Icons.star_rounded,
                  color: AdminColors.primaryDark,
                  bgColor: AdminColors.primaryLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderPill({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AdminColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 1: Bug Reports
  Widget _buildBugReportsTab() {
    if (isLoadingBugs) {
      return const Center(child: CircularProgressIndicator(color: AdminColors.primary));
    }
    if (bugReports.isEmpty) {
      return _buildEmptyTabState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Zero Open Bug Reports',
        description: 'No bugs have been submitted by customers or delivery personnel.',
      );
    }

    return RefreshIndicator(
      color: AdminColors.primary,
      onRefresh: fetchBugReports,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: bugReports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final bug = bugReports[index];
          final id = bug['report_id'] ?? '#BUG';
          final title = bug['title'] ?? 'Bug Report';
          final description = bug['description'] ?? 'No description provided';
          final user = bug['user_name'] ?? 'User';
          final phone = bug['user_phone'] ?? 'N/A';
          final device = bug['device_info'] ?? 'Android App';
          final status = (bug['status'] ?? 'open').toString().toLowerCase();
          final isResolved = status == 'resolved';
          final dateStr = _formatDate(bug['created_at']);

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isResolved ? AdminColors.border : const Color(0xFFFCA5A5),
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 3)),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isResolved ? AdminColors.primaryLight : AdminColors.dangerLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.bug_report_rounded,
                            size: 16,
                            color: isResolved ? AdminColors.primaryDark : AdminColors.danger,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          id,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AdminColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    _buildStatusBadge(
                      label: status.toUpperCase(),
                      isPositive: isResolved,
                      isWarning: status == 'in_progress',
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AdminColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: AdminColors.borderLight),
                const SizedBox(height: 10),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Wrap(
                      spacing: 12,
                      children: [
                        Text('By: $user ($phone)', style: const TextStyle(fontSize: 11, color: AdminColors.textMuted)),
                        Text('Device: $device', style: const TextStyle(fontSize: 11, color: AdminColors.textMuted)),
                        Text(dateStr, style: const TextStyle(fontSize: 11, color: AdminColors.textMuted)),
                      ],
                    ),
                    if (!isResolved)
                      ElevatedButton.icon(
                        onPressed: () => _updateBugStatus(id, 'resolved'),
                        icon: const Icon(Icons.check, size: 14),
                        label: const Text('Mark Resolved'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // TAB 2: Complaints
  Widget _buildComplaintsTab() {
    if (isLoadingComplaints) {
      return const Center(child: CircularProgressIndicator(color: AdminColors.primary));
    }
    if (complaints.isEmpty) {
      return _buildEmptyTabState(
        icon: Icons.sentiment_satisfied_alt_rounded,
        title: 'No Grievance Complaints',
        description: 'All customer service requests are resolved with 100% satisfaction.',
      );
    }

    return RefreshIndicator(
      color: AdminColors.primary,
      onRefresh: fetchComplaints,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: complaints.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final comp = complaints[index];
          final id = comp['complaint_id'] ?? '#CMP';
          final subject = comp['subject'] ?? 'General Complaint';
          final text = comp['complaint_text'] ?? '';
          final user = comp['user_name'] ?? 'Customer';
          final phone = comp['user_phone'] ?? 'N/A';
          final orderId = comp['order_id'];
          final status = (comp['status'] ?? 'pending').toString().toLowerCase();
          final isResolved = status == 'resolved';
          final dateStr = _formatDate(comp['created_at']);

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isResolved ? AdminColors.border : const Color(0xFFFDE68A),
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 3)),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isResolved ? AdminColors.primaryLight : AdminColors.warningLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.report_problem_rounded,
                            size: 16,
                            color: isResolved ? AdminColors.primaryDark : const Color(0xFFB45309),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          id,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AdminColors.textPrimary,
                          ),
                        ),
                        if (orderId != null && orderId.toString().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Order: $orderId',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AdminColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    _buildStatusBadge(
                      label: status.toUpperCase(),
                      isPositive: isResolved,
                      isWarning: status == 'pending' || status == 'investigating',
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Text(
                  subject,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AdminColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: AdminColors.borderLight),
                const SizedBox(height: 10),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Customer: $user  •  $phone  •  $dateStr',
                      style: const TextStyle(fontSize: 11, color: AdminColors.textMuted),
                    ),
                    if (!isResolved)
                      ElevatedButton.icon(
                        onPressed: () => _updateComplaintStatus(id, 'resolved'),
                        icon: const Icon(Icons.done_all_rounded, size: 14),
                        label: const Text('Resolve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // TAB 3: Feedbacks
  Widget _buildFeedbacksTab() {
    if (isLoadingFeedbacks) {
      return const Center(child: CircularProgressIndicator(color: AdminColors.primary));
    }
    if (feedbacks.isEmpty) {
      return _buildEmptyTabState(
        icon: Icons.star_border_rounded,
        title: 'No Feedback Received Yet',
        description: 'Customer ratings and experience reviews will appear here in real time.',
      );
    }

    return RefreshIndicator(
      color: AdminColors.primary,
      onRefresh: fetchFeedbacks,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: feedbacks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final fb = feedbacks[index];
          final id = fb['feedback_id'] ?? '#FB';
          final user = fb['user_name'] ?? 'Customer';
          final phone = fb['user_phone'] ?? 'N/A';
          final rating = (fb['rating'] ?? 5) as int;
          final category = fb['category'] ?? 'App Experience';
          final text = fb['feedback_text'] ?? '';
          final dateStr = _formatDate(fb['created_at']);

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminColors.border),
              boxShadow: const [
                BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 3)),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          id,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AdminColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AdminColors.primaryLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            category,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Star Rating Display
                    Row(
                      children: List.generate(5, (starIdx) {
                        return Icon(
                          starIdx < rating ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 18,
                          color: const Color(0xFFF59E0B),
                        );
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Text(
                  '"$text"',
                  style: const TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: AdminColors.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: AdminColors.borderLight),
                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Customer: $user ($phone)',
                      style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary),
                    ),
                    Text(
                      dateStr,
                      style: const TextStyle(fontSize: 11, color: AdminColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBadge({
    required String label,
    required bool isPositive,
    required bool isWarning,
  }) {
    Color bg = isPositive
        ? AdminColors.primaryLight
        : (isWarning ? AdminColors.warningLight : AdminColors.dangerLight);
    Color fg = isPositive
        ? AdminColors.primaryDark
        : (isWarning ? const Color(0xFFB45309) : AdminColors.danger);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  Widget _buildEmptyTabState({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: AdminColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AdminColors.primary),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}


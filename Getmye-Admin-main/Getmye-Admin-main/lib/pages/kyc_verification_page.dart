import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../theme/admin_theme.dart';
import '../video_call_page.dart';
import 'candidate_details_dialog.dart';

class KycVerificationPage extends StatefulWidget {
  const KycVerificationPage({super.key});

  @override
  State<KycVerificationPage> createState() => _KycVerificationPageState();
}

class _KycVerificationPageState extends State<KycVerificationPage> {
  List<dynamic> deliveryPersons = [];
  bool isLoading = true;
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchDeliveryPersons();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> fetchDeliveryPersons() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(AdminApiConfig.pendingKYC);
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (mounted) {
          setState(() {
            deliveryPersons = decoded is List ? decoded : [];
            isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  List<dynamic> get filteredPersons {
    if (searchQuery.trim().isEmpty) return deliveryPersons;
    final q = searchQuery.toLowerCase().trim();
    return deliveryPersons.where((person) {
      final name = (person['name'] ?? '').toString().toLowerCase();
      final mobile = (person['mobile_number'] ?? '').toString().toLowerCase();
      final aadhar = (person['aadhar_number'] ?? '').toString().toLowerCase();
      final pan = (person['pancard_number'] ?? '').toString().toLowerCase();
      final id = (person['DP_id'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          mobile.contains(q) ||
          aadhar.contains(q) ||
          pan.contains(q) ||
          id.contains(q);
    }).toList();
  }

  void _openChecklistReview(dynamic person) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CandidateDetailsDialog(
        candidate: person as Map<String, dynamic>,
        onActionCompleted: fetchDeliveryPersons,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        title: const Text('Partner Verification Queue'),
        actions: [
          IconButton(
            tooltip: 'Refresh candidate list',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: fetchDeliveryPersons,
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AdminColors.border, height: 1),
        ),
      ),
      body: RefreshIndicator(
        color: AdminColors.primary,
        onRefresh: fetchDeliveryPersons,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // KPI Metric Overview Row
                  _buildMetricsRow(),
                  const SizedBox(height: 18),

                  // Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AdminColors.border),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => searchQuery = val),
                      style: const TextStyle(fontSize: 14, color: AdminColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search by candidate name, mobile, DP ID, or Aadhaar...',
                        hintStyle: const TextStyle(color: AdminColors.textMuted, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.primaryDark, size: 20),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // List Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Pending Verification Applications (${filteredPersons.length})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AdminColors.textPrimary,
                        ),
                      ),
                      if (isLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AdminColors.primary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Candidates Queue Content
                  if (isLoading && deliveryPersons.isEmpty)
                    _buildLoadingState()
                  else if (filteredPersons.isEmpty)
                    _buildEmptyState()
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredPersons.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final person = filteredPersons[index];
                        return _buildCandidateCard(person);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            title: 'Pending Reviews',
            value: deliveryPersons.length.toString(),
            icon: Icons.hourglass_top_rounded,
            badgeColor: AdminColors.warningLight,
            textColor: const Color(0xFFB45309),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricTile(
            title: 'Checklists Ready',
            value: deliveryPersons.length.toString(),
            icon: Icons.checklist_rounded,
            badgeColor: AdminColors.primaryLight,
            textColor: AdminColors.primaryDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricTile(
            title: 'Portal Status',
            value: 'Online',
            icon: Icons.verified_user_rounded,
            badgeColor: AdminColors.primaryLight,
            textColor: AdminColors.primaryDark,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color badgeColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: textColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AdminColors.textPrimary,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
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

  Widget _buildCandidateCard(dynamic person) {
    final name = person['name'] ?? 'Applicant';
    final mobile = person['mobile_number'] ?? 'Not provided';
    final email = person['email'] ?? 'Not provided';
    final aadhar = person['aadhar_number'] ?? 'Not provided';
    final pan = person['pancard_number'] ?? 'Not provided';
    final dpId = person['DP_id']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AdminColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AdminColors.primarySubtle),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'C',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AdminColors.primaryDark,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.textPrimary,
                            ),
                          ),
                        ),
                        if (dpId.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'ID: #$dpId',
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
                    const SizedBox(height: 3),
                    const Text(
                      'Applicant for Delivery Partner position',
                      style: TextStyle(fontSize: 11, color: AdminColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AdminColors.warningLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded, size: 12, color: Color(0xFFB45309)),
                    SizedBox(width: 4),
                    Text(
                      'Pending KYC',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AdminColors.borderLight),
          const SizedBox(height: 12),

          // Meta Info
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildMetaPill(Icons.phone_iphone_rounded, 'Mobile', mobile),
              _buildMetaPill(Icons.mail_outline_rounded, 'Email', email),
              _buildMetaPill(Icons.fingerprint_rounded, 'Aadhaar', aadhar),
              _buildMetaPill(Icons.badge_outlined, 'PAN', pan),
            ],
          ),
          const SizedBox(height: 14),

          // Actions Row: Open Checklist & Video Call
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => VideoCallPage(dpId: dpId)),
                  );
                },
                icon: const Icon(Icons.video_call_rounded, size: 16),
                label: const Text('Video Call'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.primaryDark,
                  side: const BorderSide(color: AdminColors.primarySubtle),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => _openChecklistReview(person),
                icon: const Icon(Icons.checklist_rounded, size: 16),
                label: const Text('Review Checklists & Verify'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaPill(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AdminColors.primaryDark),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary, fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 12, color: AdminColors.textPrimary, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          children: [
            CircularProgressIndicator(color: AdminColors.primary),
            SizedBox(height: 14),
            Text(
              'Fetching pending KYC applications...',
              style: TextStyle(color: AdminColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 24),
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
              child: const Icon(Icons.check_circle_outline_rounded, size: 34, color: AdminColors.primary),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Pending Applications',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'All delivery candidate registrations have been reviewed.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}


import 'dart:convert';
import 'package:flutter/material.dart';
import 'video_call_page.dart';
import 'theme/admin_theme.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GetMye Admin - KYC Portal',
      theme: AdminTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const AdminDeliveryPersonListPage(),
    );
  }
}

class AdminDeliveryPersonListPage extends StatefulWidget {
  const AdminDeliveryPersonListPage({super.key});

  @override
  State<AdminDeliveryPersonListPage> createState() =>
      _AdminDeliveryPersonListPageState();
}

class _AdminDeliveryPersonListPageState
    extends State<AdminDeliveryPersonListPage> {
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
    final url =
        'http://192.168.29.196:5000/api/getPendingKYC/pendingkyc'; // adjust IP
    try {
      final response = await http.get(Uri.parse(url));
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
        debugPrint('Failed: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      debugPrint('Error: $e');
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
      return name.contains(q) ||
          mobile.contains(q) ||
          aadhar.contains(q) ||
          pan.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AdminColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.admin_panel_settings_rounded,
                color: AdminColors.primaryDark,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                    children: [
                      TextSpan(
                        text: 'GetMye ',
                        style: TextStyle(color: AdminColors.textPrimary),
                      ),
                      TextSpan(
                        text: 'Admin',
                        style: TextStyle(color: AdminColors.primaryDark),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'KYC & Delivery Partner Verification',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AdminColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh list',
            icon: const Icon(Icons.refresh_rounded, color: AdminColors.textPrimary),
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
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // KPI Overview Cards
                  _buildKpiMetricsRow(),
                  const SizedBox(height: 20),

                  // Search and Filter Bar
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AdminColors.border),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) {
                        setState(() {
                          searchQuery = val;
                        });
                      },
                      style: const TextStyle(
                        fontSize: 14,
                        color: AdminColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search by applicant name, mobile, Aadhaar...',
                        hintStyle: const TextStyle(
                          color: AdminColors.textMuted,
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AdminColors.primaryDark,
                          size: 20,
                        ),
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Section Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Pending Verification Queue (${filteredPersons.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (isLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AdminColors.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // List Content
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
                        return _buildPersonCard(person);
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

  Widget _buildKpiMetricsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            title: 'Pending Reviews',
            count: deliveryPersons.length.toString(),
            icon: Icons.hourglass_top_rounded,
            badgeColor: AdminColors.warningLight,
            textColor: const Color(0xFFB45309),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricTile(
            title: 'Ready for Call',
            count: deliveryPersons.length.toString(),
            icon: Icons.video_call_rounded,
            badgeColor: AdminColors.primaryLight,
            textColor: AdminColors.primaryDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricTile(
            title: 'KYC Status',
            count: 'Active',
            icon: Icons.verified_user_rounded,
            badgeColor: AdminColors.primaryLight,
            textColor: AdminColors.primaryDark,
            isTextValue: true,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String count,
    required IconData icon,
    required Color badgeColor,
    required Color textColor,
    bool isTextValue = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: textColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count,
                  style: TextStyle(
                    fontSize: isTextValue ? 16 : 20,
                    fontWeight: FontWeight.w800,
                    color: AdminColors.textPrimary,
                    letterSpacing: -0.3,
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

  Widget _buildPersonCard(dynamic person) {
    final name = person['name'] ?? 'Candidate';
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
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar, Name, DP ID, Status Badge
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
              const SizedBox(width: 14),
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
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (dpId.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
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
                    const SizedBox(height: 4),
                    const Text(
                      'Applicant for Delivery Partner position',
                      style: TextStyle(
                        fontSize: 12,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AdminColors.warningLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: Color(0xFFB45309),
                    ),
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
          const SizedBox(height: 16),
          const Divider(height: 1, color: AdminColors.borderLight),
          const SizedBox(height: 14),

          // Metadata Grid
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _buildMetaItem(Icons.phone_iphone_rounded, 'Mobile', mobile),
              _buildMetaItem(Icons.mail_outline_rounded, 'Email', email),
              _buildMetaItem(Icons.fingerprint_rounded, 'Aadhaar', aadhar),
              _buildMetaItem(Icons.badge_outlined, 'PAN Card', pan),
            ],
          ),
          const SizedBox(height: 16),

          // Action Button
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoCallPage(dpId: person['DP_id']),
                  ),
                );
              },
              icon: const Icon(Icons.video_call_rounded, size: 20),
              label: const Text('Start Video Call & Verify'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaItem(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AdminColors.primaryDark),
        const SizedBox(width: 6),
        RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 13),
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(
                  color: AdminColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              TextSpan(
                text: value,
                style: const TextStyle(
                  color: AdminColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: const [
            CircularProgressIndicator(color: AdminColors.primary),
            SizedBox(height: 16),
            Text(
              'Fetching pending KYC applications...',
              style: TextStyle(
                color: AdminColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 30),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AdminColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 38,
                color: AdminColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Pending Applications',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AdminColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'All candidate submissions have been reviewed or no entries match your search criteria.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AdminColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/admin_theme.dart';
import 'package:http/http.dart' as http;

class VideoCallPage extends StatefulWidget {
  final String dpId;
  const VideoCallPage({required this.dpId, super.key});

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  Map<String, dynamic>? dpDetails;
  bool isLoading = true;
  bool checkbox1 = false; // Profile
  bool checkbox2 = false; // Aadhar
  bool checkbox3 = false; // Pancard
  String? selectedImageBase64;
  String? selectedImageTitle;
  bool isActionTaken = false;
  bool isSubmitting = false;

  // Video call UI controls
  bool isMuted = false;
  bool isCameraOff = false;

  @override
  void initState() {
    super.initState();
    fetchDpDetails();
  }

  Future<void> fetchDpDetails() async {
    final url = 'http://192.168.29.196:5000/api/getPendingKYC/${widget.dpId}';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (mounted) {
          setState(() {
            if (decoded is Map<String, dynamic>) {
              dpDetails = decoded;
            } else if (decoded is List<dynamic> && decoded.isNotEmpty) {
              dpDetails = decoded[0] as Map<String, dynamic>;
            } else {
              dpDetails = null;
            }
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

  Future<void> approveOrReject(bool isApprove) async {
    if (isApprove && !(checkbox1 && checkbox2 && checkbox3)) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: AdminColors.warning, size: 24),
              SizedBox(width: 8),
              Text(
                'Verification Incomplete',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: const Text(
            'Please verify and check all 3 identity documents (Profile Photo, Aadhaar, and PAN) before approving.',
            style: TextStyle(color: AdminColors.textSecondary, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => isSubmitting = true);

    final url = 'http://192.168.29.196:5000/api/getPendingKYC/updateKYCStatus';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'dpId': widget.dpId,
          'status': isApprove ? 'approved' : 'rejected',
        }),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            isActionTaken = true;
            isSubmitting = false;
          });
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    isApprove ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: isApprove ? AdminColors.success : AdminColors.danger,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isApprove ? 'KYC Approved' : 'KYC Rejected',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ],
              ),
              content: Text(
                isApprove
                    ? 'The delivery partner KYC has been approved and activated in the system.'
                    : 'The candidate KYC application was rejected.',
                style: const TextStyle(color: AdminColors.textSecondary, height: 1.4),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isApprove ? AdminColors.primary : AdminColors.textPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop(); // Back to candidates queue
                  },
                  child: const Text('Back to Dashboard'),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() => isSubmitting = false);
          _showErrorDialog('Failed to update status. Please try again.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isSubmitting = false);
        _showErrorDialog('Network error occurred. Please check server connectivity.');
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: AdminColors.danger, size: 24),
            SizedBox(width: 8),
            Text('Action Failed', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: AdminColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildDocThumbnail(String? base64String, String title, {double height = 130}) {
    if (base64String == null || base64String.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AdminColors.border),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image_not_supported_outlined, color: AdminColors.textMuted, size: 28),
              const SizedBox(height: 6),
              Text(
                'No image uploaded',
                style: TextStyle(color: AdminColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    try {
      final cleanBase64 = base64String.contains(',')
          ? base64String.split(',')[1]
          : base64String;
      final bytes = base64Decode(cleanBase64);

      return InkWell(
        onTap: () {
          setState(() {
            selectedImageBase64 = cleanBase64;
            selectedImageTitle = title;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AdminColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(bytes, fit: BoxFit.cover),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Inspect',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('Invalid image format', style: TextStyle(fontSize: 12, color: AdminColors.danger)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidateName = dpDetails?['name'] ?? 'Candidate';

    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AdminColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Text(
              'KYC Verification: $candidateName',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: AdminColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AdminColors.primaryLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'DP ID: #${widget.dpId}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.primaryDark,
                ),
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AdminColors.border, height: 1),
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AdminColors.primary),
            )
          : dpDetails == null
              ? const Center(
                  child: Text('Candidate record not found or inaccessible'),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWideScreen = constraints.maxWidth > 800;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Pane: Video Call Studio
                        Expanded(
                          flex: isWideScreen ? 5 : 4,
                          child: _buildVideoStudioPane(),
                        ),
                        Container(width: 1, color: AdminColors.border),
                        // Right Pane: Verification Documents & Decision Desk
                        Expanded(
                          flex: isWideScreen ? 6 : 5,
                          child: _buildVerificationDeskPane(),
                        ),
                      ],
                    );
                  },
                ),
    );
  }

  Widget _buildVideoStudioPane() {
    return Container(
      color: const Color(0xFF0F172A), // Deep Slate Video background
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Live Session Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'LIVE KYC INTERVIEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.fiber_manual_record, color: Color(0xFFEF4444), size: 10),
                    SizedBox(width: 6),
                    Text(
                      'REC',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Main Video Canvas
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (isCameraOff)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 48),
                          SizedBox(height: 10),
                          Text(
                            'Camera Disabled',
                            style: TextStyle(color: Colors.white60, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 90,
                            width: 90,
                            decoration: BoxDecoration(
                              color: AdminColors.primaryDark.withOpacity(0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: AdminColors.primary, width: 2),
                            ),
                            child: Center(
                              child: Text(
                                (dpDetails?['name'] ?? 'C')[0].toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            dpDetails?['name'] ?? 'Candidate',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: AdminColors.primaryLight.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Video call active • Audio connected',
                              style: TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Candidate Picture-in-picture simulation overlay
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      width: 100,
                      height: 130,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.person, color: Colors.white54, size: 24),
                            SizedBox(height: 4),
                            Text(
                              'Admin Feed',
                              style: TextStyle(color: Colors.white70, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Control Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: isMuted ? 'Unmute Mic' : 'Mute Mic',
                  icon: Icon(
                    isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: isMuted ? AdminColors.danger : Colors.white,
                  ),
                  onPressed: () => setState(() => isMuted = !isMuted),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: isCameraOff ? 'Turn Camera On' : 'Turn Camera Off',
                  icon: Icon(
                    isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                    color: isCameraOff ? AdminColors.danger : Colors.white,
                  ),
                  onPressed: () => setState(() => isCameraOff = !isCameraOff),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 1,
                  height: 24,
                  color: Colors.white24,
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'End Video Call Session',
                  icon: const Icon(Icons.call_end_rounded, color: Colors.redAccent),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Video session paused')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationDeskPane() {
    final verifiedCount = (checkbox1 ? 1 : 0) + (checkbox2 ? 1 : 0) + (checkbox3 ? 1 : 0);

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Inspector Header Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AdminColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Document Verification Desk',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.textPrimary,
                      ),
                    ),
                    Text(
                      '$verifiedCount of 3 documents verified',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: verifiedCount == 3 ? AdminColors.success : AdminColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: verifiedCount == 3 ? AdminColors.primaryLight : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    verifiedCount == 3 ? 'READY TO APPROVE' : 'IN REVIEW',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: verifiedCount == 3 ? AdminColors.primaryDark : AdminColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable Documents & Checklist
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fullscreen Image Preview banner if selected
                  if (selectedImageBase64 != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AdminColors.background,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AdminColors.primary, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Inspecting: ${selectedImageTitle ?? "Document"}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AdminColors.textPrimary,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () {
                                  setState(() {
                                    selectedImageBase64 = null;
                                    selectedImageTitle = null;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                base64Decode(selectedImageBase64!),
                                height: 320,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Candidate Overview
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AdminColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AdminColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Candidate Profile',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _buildDetailField('Full Name', dpDetails?['name'] ?? '-')),
                            Expanded(child: _buildDetailField('Mobile', dpDetails?['mobile_number'] ?? '-')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildDetailField('Email', dpDetails?['email'] ?? '-')),
                            Expanded(child: _buildDetailField('Candidate ID', '#${widget.dpId}')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Document 1: Profile Photo
                  _buildDocumentCard(
                    title: '1. Profile Photo',
                    subtitle: 'Verify facial likeness with the live video call stream',
                    thumbnailWidget: _buildDocThumbnail(
                      dpDetails?['profile_picture'],
                      'Profile Picture',
                    ),
                    isChecked: checkbox1,
                    onChanged: (val) => setState(() => checkbox1 = val ?? false),
                  ),
                  const SizedBox(height: 16),

                  // Document 2: Aadhaar Card
                  _buildDocumentCard(
                    title: '2. Aadhaar Card Proof',
                    subtitle: 'Aadhaar No: ${dpDetails?['aadhar_number'] ?? "N/A"}',
                    thumbnailWidget: _buildDocThumbnail(
                      dpDetails?['aadhar_proof_picture'],
                      'Aadhaar Proof',
                    ),
                    isChecked: checkbox2,
                    onChanged: (val) => setState(() => checkbox2 = val ?? false),
                  ),
                  const SizedBox(height: 16),

                  // Document 3: PAN Card
                  _buildDocumentCard(
                    title: '3. PAN Card Proof',
                    subtitle: 'PAN No: ${dpDetails?['pancard_number'] ?? "N/A"}',
                    thumbnailWidget: _buildDocThumbnail(
                      dpDetails?['pancard_proof_picture'],
                      'PAN Card Proof',
                    ),
                    isChecked: checkbox3,
                    onChanged: (val) => setState(() => checkbox3 = val ?? false),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),

          // Decision Footer Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: const Border(top: BorderSide(color: AdminColors.border)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Reject Button
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject KYC'),
                    onPressed: (isActionTaken || isSubmitting) ? null : () => approveOrReject(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.danger,
                      side: const BorderSide(color: AdminColors.danger, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Approve Button
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_rounded, size: 20),
                    label: Text(isSubmitting ? 'Updating...' : 'Approve & Activate KYC'),
                    onPressed: (isActionTaken || isSubmitting) ? null : () => approveOrReject(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AdminColors.border,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard({
    required String title,
    required String subtitle,
    required Widget thumbnailWidget,
    required bool isChecked,
    required ValueChanged<bool?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isChecked ? AdminColors.primary : AdminColors.border,
          width: isChecked ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => onChanged(!isChecked),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isChecked ? AdminColors.primaryLight : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isChecked ? AdminColors.primarySubtle : AdminColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isChecked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                        size: 18,
                        color: isChecked ? AdminColors.primaryDark : AdminColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isChecked ? 'Verified' : 'Verify',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isChecked ? AdminColors.primaryDark : AdminColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          thumbnailWidget,
        ],
      ),
    );
  }

  Widget _buildDetailField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AdminColors.textMuted, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
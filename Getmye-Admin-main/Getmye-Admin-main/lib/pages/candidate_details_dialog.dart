import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../theme/admin_theme.dart';
import '../video_call_page.dart';

class CandidateDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> candidate;
  final VoidCallback onActionCompleted;

  const CandidateDetailsDialog({
    required this.candidate,
    required this.onActionCompleted,
    super.key,
  });

  @override
  State<CandidateDetailsDialog> createState() => _CandidateDetailsDialogState();
}

class _CandidateDetailsDialogState extends State<CandidateDetailsDialog> {
  Map<String, dynamic>? fullDetails;
  bool isLoading = true;

  // The 3 mandatory verification checklists specified by user
  bool isProfileChecked = false;
  bool isAadharChecked = false;
  bool isPanChecked = false;

  bool isSubmitting = false;

  @override
  void initState() {
    super.initState();
    fetchCandidateFullDetails();
  }

  Future<void> fetchCandidateFullDetails() async {
    final dpId = widget.candidate['DP_id']?.toString() ?? '';
    if (dpId.isEmpty) {
      setState(() {
        fullDetails = widget.candidate;
        isLoading = false;
      });
      return;
    }

    try {
      final res = await http.get(AdminApiConfig.dpDetails(dpId));
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted) {
          setState(() {
            if (decoded is List && decoded.isNotEmpty) {
              fullDetails = decoded[0] as Map<String, dynamic>;
            } else if (decoded is Map<String, dynamic>) {
              fullDetails = decoded;
            } else {
              fullDetails = widget.candidate;
            }
            isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            fullDetails = widget.candidate;
            isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          fullDetails = widget.candidate;
          isLoading = false;
        });
      }
    }
  }

  int get verifiedCount {
    int c = 0;
    if (isProfileChecked) c++;
    if (isAadharChecked) c++;
    if (isPanChecked) c++;
    return c;
  }

  bool get isAllChecklistCompleted =>
      isProfileChecked && isAadharChecked && isPanChecked;

  Future<void> _updateStatus(bool isApprove) async {
    if (isApprove && !isAllChecklistCompleted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: AdminColors.warning, size: 24),
              SizedBox(width: 8),
              Text(
                'Incomplete Verification',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: const Text(
            'Mandatory Verification Checklists required before approval:\n'
            '• Profile Image\n'
            '• Aadhaar Card Image\n'
            '• PAN Card Image\n\n'
            'Please inspect all 3 documents and check each verification item.',
            style: TextStyle(color: AdminColors.textSecondary, height: 1.45),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => isSubmitting = true);
    final dpId = widget.candidate['DP_id']?.toString() ?? '';

    try {
      final res = await http.post(
        AdminApiConfig.updateKYCStatus,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'dpId': dpId,
          'status': isApprove ? 'approved' : 'rejected',
        }),
      );

      if (!mounted) return;
      setState(() => isSubmitting = false);

      if (res.statusCode == 200) {
        Navigator.pop(context); // Close dialog
        widget.onActionCompleted();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isApprove
                  ? 'Delivery partner #$dpId KYC approved and activated successfully!'
                  : 'Delivery partner #$dpId KYC rejected.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: isApprove ? AdminColors.success : AdminColors.danger,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update status. Please try again.'),
            backgroundColor: AdminColors.danger,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Network error: $e'),
          backgroundColor: AdminColors.danger,
        ),
      );
    }
  }

  void _openImageViewer(String? base64String, String title) {
    if (base64String == null || base64String.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image document uploaded by candidate.')),
      );
      return;
    }

    final clean = base64String.contains(',') ? base64String.split(',')[1] : base64String;
    try {
      final bytes = base64Decode(clean);
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Center(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Pinch or drag to zoom and inspect details',
                    style: TextStyle(fontSize: 12, color: AdminColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not decode document image.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = fullDetails ?? widget.candidate;
    final name = details['name'] ?? 'Applicant';
    final mobile = details['mobile_number'] ?? 'N/A';
    final email = details['email'] ?? 'N/A';
    final aadharNum = details['aadhar_number'] ?? 'N/A';
    final panNum = details['pancard_number'] ?? 'N/A';
    final dpId = details['DP_id']?.toString() ?? '';
    final address = details['address'] ?? 'Not provided';

    final profilePicBase64 = details['profile_picture']?.toString();
    final aadharProofBase64 = details['aadhar_proof_picture']?.toString();
    final panProofBase64 = details['pancard_proof_picture']?.toString();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Column(
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AdminColors.border)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AdminColors.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.how_to_reg_rounded,
                      color: AdminColors.primaryDark,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Partner Verification • $name',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AdminColors.textPrimary,
                          ),
                        ),
                        Text(
                          'DP ID: #$dpId  |  Mobile: $mobile',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AdminColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Content Body
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: AdminColors.primary))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Candidate Personal Overview Box
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AdminColors.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AdminColors.border),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: _buildMetaText('Full Name', name)),
                                    Expanded(child: _buildMetaText('Mobile Number', mobile)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(child: _buildMetaText('Email Address', email)),
                                    Expanded(child: _buildMetaText('Residential Address', address)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Verification Progress Indicator Bar
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isAllChecklistCompleted
                                  ? AdminColors.primaryLight
                                  : AdminColors.warningLight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isAllChecklistCompleted
                                    ? AdminColors.primarySubtle
                                    : const Color(0xFFFDE68A),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isAllChecklistCompleted
                                      ? Icons.check_circle_rounded
                                      : Icons.checklist_rounded,
                                  color: isAllChecklistCompleted
                                      ? AdminColors.primaryDark
                                      : const Color(0xFFB45309),
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Verification Checklist Status: $verifiedCount / 3 Completed',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: isAllChecklistCompleted
                                              ? AdminColors.primaryDark
                                              : const Color(0xFFB45309),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isAllChecklistCompleted
                                            ? 'All 3 registration documents are validated. Ready to approve.'
                                            : 'Please inspect Profile Photo, Aadhaar, and PAN cards below.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isAllChecklistCompleted
                                              ? AdminColors.primaryDark.withValues(alpha: 0.8)
                                              : const Color(0xFF92400E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          const Text(
                            'Mandatory Verification Checklists',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AdminColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // 1. Profile Picture Checklist
                          _buildChecklistCard(
                            index: 1,
                            title: 'Profile Image Verification',
                            subtitle: 'Candidate face matches, photo is sharp and authentic',
                            base64Image: profilePicBase64,
                            isChecked: isProfileChecked,
                            onToggle: (v) => setState(() => isProfileChecked = v ?? false),
                            detailsWidget: const Text(
                              'Ensure photo clearly shows the applicant with no hats, sunglasses or obstructions.',
                              style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 2. Aadhaar Card Checklist
                          _buildChecklistCard(
                            index: 2,
                            title: 'Aadhaar Card Proof Verification',
                            subtitle: 'Official government Aadhaar card matches candidate identity',
                            base64Image: aadharProofBase64,
                            isChecked: isAadharChecked,
                            onToggle: (v) => setState(() => isAadharChecked = v ?? false),
                            detailsWidget: Row(
                              children: [
                                const Icon(Icons.fingerprint_rounded, size: 15, color: AdminColors.primaryDark),
                                const SizedBox(width: 6),
                                Text(
                                  'Aadhaar Number: $aadharNum',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AdminColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 3. PAN Card Checklist
                          _buildChecklistCard(
                            index: 3,
                            title: 'PAN Card Proof Verification',
                            subtitle: 'PAN Card identity and alphanumeric identifier verification',
                            base64Image: panProofBase64,
                            isChecked: isPanChecked,
                            onToggle: (v) => setState(() => isPanChecked = v ?? false),
                            detailsWidget: Row(
                              children: [
                                const Icon(Icons.badge_outlined, size: 15, color: AdminColors.primaryDark),
                                const SizedBox(width: 6),
                                Text(
                                  'PAN Number: $panNum',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AdminColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Quick Video Call Link
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AdminColors.border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AdminColors.primaryLight,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.video_call_rounded,
                                    color: AdminColors.primaryDark,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Need Live Candidate Video Interview?',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AdminColors.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        'Connect directly to video call portal to verify candidate face live.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AdminColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => VideoCallPage(dpId: dpId),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.videocam_rounded, size: 16),
                                  label: const Text('Video Call'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AdminColors.primaryDark,
                                    side: const BorderSide(color: AdminColors.primarySubtle),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            // Modal Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AdminColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    onPressed: isSubmitting ? null : () => _updateStatus(false),
                    icon: const Icon(Icons.cancel_outlined, size: 18, color: AdminColors.danger),
                    label: const Text('Reject Application', style: TextStyle(color: AdminColors.danger)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AdminColors.dangerLight),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: (isSubmitting || !isAllChecklistCompleted)
                        ? null
                        : () => _updateStatus(true),
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text(
                      isAllChecklistCompleted ? 'Approve & Activate Partner' : 'Complete 3 Checklists to Approve',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFCBD5E1),
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistCard({
    required int index,
    required String title,
    required String subtitle,
    required String? base64Image,
    required bool isChecked,
    required ValueChanged<bool?> onToggle,
    required Widget detailsWidget,
  }) {
    final hasImage = base64Image != null && base64Image.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isChecked ? AdminColors.primaryLight.withValues(alpha: 0.3) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isChecked ? AdminColors.primary : AdminColors.border,
          width: isChecked ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Document Thumbnail
          InkWell(
            onTap: () => _openImageViewer(base64Image, title),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AdminColors.border),
              ),
              child: hasImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildMemoryImage(base64Image),
                          Container(
                            color: Colors.black.withValues(alpha: 0.15),
                            child: const Center(
                              child: Icon(Icons.zoom_in_rounded, color: Colors.white, size: 22),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.image_not_supported_outlined, size: 20, color: AdminColors.textMuted),
                          SizedBox(height: 2),
                          Text('No Image', style: TextStyle(fontSize: 9, color: AdminColors.textMuted)),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),

          // Details & Checkbox
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$index. $title',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.textPrimary,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AdminColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Checkbox(
                      value: isChecked,
                      onChanged: onToggle,
                      activeColor: AdminColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                detailsWidget,
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _openImageViewer(base64Image, title),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.visibility_rounded, size: 14, color: AdminColors.primaryDark),
                      SizedBox(width: 4),
                      Text(
                        'Click to view high-resolution image',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryImage(String base64String) {
    try {
      final clean = base64String.contains(',') ? base64String.split(',')[1] : base64String;
      final bytes = base64Decode(clean);
      return Image.memory(bytes, fit: BoxFit.cover);
    } catch (_) {
      return const Icon(Icons.broken_image_rounded, color: AdminColors.textMuted);
    }
  }

  Widget _buildMetaText(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AdminColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            color: AdminColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}


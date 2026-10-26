import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'dhome.dart';
import 'widgets/customer_bottom_nav_bar.dart';
import 'theme/app_theme.dart';
import 'ppp.dart';
import 'help_page.dart';
import 'terms_page.dart';
import 'privacy_policy_page.dart';

class OptionsPage extends StatelessWidget {
  const OptionsPage({super.key, required bool isDarkMode});

  IconData _getIconForOption(String title) {
    switch (title.toLowerCase()) {
      case 'join as delivery partner':
        return Icons.two_wheeler_rounded;
      case 'terms and conditions':
        return Icons.description_outlined;
      case 'help':
        return Icons.help_outline_rounded;
      case 'report a bug':
        return Icons.bug_report_outlined;
      case 'raise a complaint':
        return Icons.support_agent_rounded;
      case 'feedback':
        return Icons.rate_review_outlined;
      case 'privacy policy':
        return Icons.privacy_tip_outlined;
      default:
        return Icons.chevron_right_rounded;
    }
  }

  void _handleBackNavigation(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final optionsList = [
      'Join as Delivery Partner',
      'Report a bug',
      'Raise a complaint',
      'Feedback',
      'Terms and conditions',
      'Help',
      'Privacy policy',
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
            onPressed: () => _handleBackNavigation(context),
          ),
          title: const Text(
            'Options & Support',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          centerTitle: true,
        ),
        body: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: optionsList.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final title = optionsList[index];
            return _buildOption(context, title);
          },
        ),
        bottomNavigationBar: const CustomerBottomNavBar(currentIndex: 3),
      ),
    );
  }

  Widget _buildOption(BuildContext context, String title) {
    final isHighlight = title == 'Join as Delivery Partner';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isHighlight ? AppColors.primary : AppColors.border, width: isHighlight ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isHighlight ? const Color(0xFFFEF3C7) : AppColors.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _getIconForOption(title),
            color: isHighlight ? const Color(0xFFB45309) : AppColors.primaryDark,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isHighlight ? AppColors.primaryDark : AppColors.textPrimary,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: AppColors.textMuted,
        ),
        onTap: () {
          if (title == 'Join as Delivery Partner') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DeliveryPersonJoinPage()),
            );
          } else if (title == 'Report a bug') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportBugPage()),
            );
          } else if (title == 'Raise a complaint') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RaiseComplaintPage()),
            );
          } else if (title == 'Feedback') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SubmitFeedbackPage()),
            );
          } else if (title == 'Help') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpPage()),
            );
          } else if (title == 'Terms and conditions') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TermsPage()),
            );
          } else if (title == 'Privacy policy') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DetailPage(title: title),
              ),
            );
          }
        },
      ),
    );
  }
}

/// 1. Report a Bug Page
class ReportBugPage extends StatefulWidget {
  const ReportBugPage({super.key});

  @override
  State<ReportBugPage> createState() => _ReportBugPageState();
}

class _ReportBugPageState extends State<ReportBugPage> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submitBug() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();

    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please describe the bug in detail.")),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final prefs = await SharedPreferences.getInstance();
    final mobile = prefs.getString('mobile_number') ?? prefs.getString('user_mobile') ?? '';
    final name = prefs.getString('user_name') ?? 'Customer';

    try {
      final res = await http.post(
        ApiConfig.supportBugReport,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': mobile.isNotEmpty ? mobile : 'guest',
          'user_name': name,
          'user_phone': mobile,
          'title': title.isNotEmpty ? title : 'Mobile App Bug Report',
          'description': desc,
          'device_info': 'Flutter Android Client',
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 201 && data['success'] == true) {
        if (!mounted) return;
        _showSuccessDialog(
          "Bug Report Submitted",
          data['message'] ?? "Thank you for reporting! Our technical team is investigating.",
        );
        _titleController.clear();
        _descController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? "Failed to submit bug report")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Network error: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text("OK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleBackNavigation() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OptionsPage(isDarkMode: false)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text("Report a Bug", style: AppTypography.screenHeading),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: _handleBackNavigation,
          ),
        ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Found an issue or glitch in the app?",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              "Describe what happened below. This will be automatically recorded in the technical support database.",
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: "Issue Title (Optional)",
                hintText: "e.g. Map not loading, OTP error",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: "Detailed Description *",
                hintText: "Explain what went wrong and where it happened...",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isSubmitting ? null : _submitBug,
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Submit Bug Report", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}

/// 2. Raise a Complaint Page
class RaiseComplaintPage extends StatefulWidget {
  const RaiseComplaintPage({super.key});

  @override
  State<RaiseComplaintPage> createState() => _RaiseComplaintPageState();
}

class _RaiseComplaintPageState extends State<RaiseComplaintPage> {
  final _orderIdController = TextEditingController();
  final _complaintController = TextEditingController();
  String _category = 'Delivery Delay';
  bool _isSubmitting = false;

  final List<String> _categories = [
    'Delivery Delay',
    'Incorrect / Missing Items',
    'Delivery Partner Behavior',
    'Payment / Billing Issue',
    'Food Spillage / Quality',
    'Other Issue',
  ];

  @override
  void initState() {
    super.initState();
    _loadActiveOrderId();
  }

  Future<void> _loadActiveOrderId() async {
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString('active_order_id');
    if (activeId != null && activeId.isNotEmpty) {
      _orderIdController.text = activeId;
    }
  }

  Future<void> _submitComplaint() async {
    final text = _complaintController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please write your complaint in detail.")),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final prefs = await SharedPreferences.getInstance();
    final mobile = prefs.getString('mobile_number') ?? prefs.getString('user_mobile') ?? '';
    final name = prefs.getString('user_name') ?? 'Customer';

    try {
      final res = await http.post(
        ApiConfig.supportComplaint,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': mobile.isNotEmpty ? mobile : 'guest',
          'user_name': name,
          'user_phone': mobile,
          'order_id': _orderIdController.text.trim().isNotEmpty ? _orderIdController.text.trim() : null,
          'subject': _category,
          'complaint_text': text,
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 201 && data['success'] == true) {
        if (!mounted) return;
        _showSuccessDialog(
          "Complaint Registered",
          data['message'] ?? "Your complaint has been logged in our system. A support manager will review it.",
        );
        _complaintController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? "Failed to register complaint")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Network error: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text("OK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleBackNavigation() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OptionsPage(isDarkMode: false)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text("Raise a Complaint", style: AppTypography.screenHeading),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: _handleBackNavigation,
          ),
        ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Grievance Redressal Form",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              "Submit any complaint regarding your order or delivery. It will be stored in our complaints database for prompt resolution.",
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _orderIdController,
              decoration: InputDecoration(
                labelText: "Order ID (Optional)",
                hintText: "e.g. ORD-1024",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: InputDecoration(
                labelText: "Issue Category",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _category = val);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _complaintController,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: "Complaint Details *",
                hintText: "Please describe what happened with specific details...",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isSubmitting ? null : _submitComplaint,
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Register Complaint", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}

/// 3. Submit Feedback Page
class SubmitFeedbackPage extends StatefulWidget {
  const SubmitFeedbackPage({super.key});

  @override
  State<SubmitFeedbackPage> createState() => _SubmitFeedbackPageState();
}

class _SubmitFeedbackPageState extends State<SubmitFeedbackPage> {
  int _rating = 5;
  String _category = 'App Experience';
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _categories = [
    'App Experience',
    'Delivery Speed',
    'Partner Behavior',
    'Pricing & Transparency',
  ];

  Future<void> _submitFeedback() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please write a short comment or review.")),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final prefs = await SharedPreferences.getInstance();
    final mobile = prefs.getString('mobile_number') ?? prefs.getString('user_mobile') ?? '';
    final name = prefs.getString('user_name') ?? 'Customer';

    try {
      final res = await http.post(
        ApiConfig.supportFeedback,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': mobile.isNotEmpty ? mobile : 'guest',
          'user_name': name,
          'user_phone': mobile,
          'rating': _rating,
          'category': _category,
          'feedback_text': comment,
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 201 && data['success'] == true) {
        if (!mounted) return;
        _showSuccessDialog(
          "Feedback Submitted",
          data['message'] ?? "Thank you for rating Getmye! Your response was saved.",
        );
        _commentController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? "Failed to submit feedback")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Network error: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text("OK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleBackNavigation() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OptionsPage(isDarkMode: false)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text("Feedback & Rating", style: AppTypography.screenHeading),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: _handleBackNavigation,
          ),
        ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
            const Text(
              "How was your Getmye experience?",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              "Your rating helps us improve every day.",
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),

            // Star Rating
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                return IconButton(
                  iconSize: 38,
                  icon: Icon(
                    starIndex <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
                    color: starIndex <= _rating ? const Color(0xFFF59E0B) : AppColors.border,
                  ),
                  onPressed: () {
                    setState(() => _rating = starIndex);
                  },
                );
              }),
            ),
            const SizedBox(height: 10),
            Text(
              _rating == 5
                  ? "⭐⭐⭐⭐⭐ Outstanding!"
                  : _rating == 4
                      ? "⭐⭐⭐⭐ Very Good"
                      : _rating == 3
                          ? "⭐⭐⭐ Average"
                          : _rating == 2
                              ? "⭐⭐ Needs Improvement"
                              : "⭐ Poor",
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 24),

            Align(
              alignment: Alignment.centerLeft,
              child: DropdownButtonFormField<String>(
                value: _category,
                decoration: InputDecoration(
                  labelText: "Feedback Category",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _category = val);
                },
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _commentController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: "Your Comments / Review *",
                hintText: "What did you like or what can we do better?",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isSubmitting ? null : _submitFeedback,
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Submit Feedback", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}

/// Fallback info page for Terms, Help, Advertisement
class DetailPage extends StatelessWidget {
  final String title;

  const DetailPage({super.key, required this.title});

  void _handleBackNavigation(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OptionsPage(isDarkMode: false)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
            onPressed: () => _handleBackNavigation(context),
          ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.primaryDark,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Details and policies regarding $title are actively maintained by the Getmye platform.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
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

import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Privacy Policy',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Badge Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      "Your Privacy Matters",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "GetMye Privacy Policy",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Last updated: October 15, 2026",
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "We are committed to protecting your personal data and ensuring transparent data practices. This policy outlines how GetMye collects, uses, and safeguards your information.",
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildPolicyCard(
              icon: Icons.person_outline_rounded,
              title: "1. Information We Collect",
              content:
                  "• Account Details: Name, mobile number, email address, and delivery addresses.\n• Order Information: Items ordered, delivery instructions, and transaction history.",
            ),

            _buildPolicyCard(
              icon: Icons.location_on_outlined,
              title: "2. Location Data (Foreground & Background)",
              content:
                  "• Foreground Location: Used to pinpoint your delivery address, show nearby stores, and calculate accurate delivery estimates.\n• Background Location: Used during active order delivery to provide live tracking on Google Maps for customers and delivery partners.",
            ),

            _buildPolicyCard(
              icon: Icons.lock_outline_rounded,
              title: "3. Payment Security (Cashfree)",
              content:
                  "• Online payments are processed through RBI-authorized Cashfree Payments (UPI, Cards, Net Banking).\n• GetMye does not store confidential card details, CVV, or net banking passwords on our servers.",
            ),

            _buildPolicyCard(
              icon: Icons.camera_alt_outlined,
              title: "4. Camera & Media Access",
              content:
                  "• Camera and gallery access is requested only if you choose to upload a profile photo, provide delivery verification images, or attach photos for support inquiries.",
            ),

            _buildPolicyCard(
              icon: Icons.notifications_none_rounded,
              title: "5. Push Notifications",
              content:
                  "• We use Firebase Cloud Messaging (FCM) to send essential order updates, delivery partner arrival alerts, and OTPs.",
            ),

            _buildPolicyCard(
              icon: Icons.delete_outline_rounded,
              title: "6. Data Retention & Account Deletion",
              content:
                  "• You have the right to request deletion of your account and personal data at any time.\n• To delete your account, email sivasakthi@coderead.in with your registered mobile number. Data is permanently purged within 30 days.",
            ),

            const SizedBox(height: 12),

            // Contact / Grievance Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Grievance Officer",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text("App: GetMye", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text("Contact Person: Sivasakthi", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text("Email: sivasakthi@coderead.in", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text("Phone: +91 9344701545", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  SizedBox(height: 4),
                  Text(
                    "Address: 9C/ 6-1 South Madappa Lane, Bharathi Nagar, Kumbakonam, Thanjavur, Tamil Nadu, India",
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyCard({required IconData icon, required String title, required String content}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

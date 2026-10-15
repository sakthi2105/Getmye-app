import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

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
          'Terms & Conditions',
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
            // Top Header Card
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
                      "Legal Agreement",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "GetMye Terms of Service",
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
                    "Please read these Terms and Conditions carefully before using the GetMye application and related delivery services. By accessing or using the platform, you agree to be bound by these Terms.",
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

            _buildSection(
              number: "1",
              title: "User Eligibility & Accounts",
              content:
                  "• You must be at least 18 years of age to register and place orders.\n• You agree to provide true, accurate, and current information (name, mobile number, delivery address).\n• You are responsible for keeping your login credentials and OTPs confidential.",
            ),

            _buildSection(
              number: "2",
              title: "Orders & Pricing",
              content:
                  "• GetMye acts as an intermediary connecting you with merchants and independent delivery partners.\n• An order is confirmed once accepted by the vendor and assigned to a delivery partner.\n• Prices are shown in INR and include applicable taxes and delivery charges.",
            ),

            _buildSection(
              number: "3",
              title: "Payments (Cashfree & COD)",
              content:
                  "• We support online payments (UPI, Cards, Net Banking) via Cashfree Payments and Cash on Delivery (COD).\n• GetMye does not store confidential payment credentials or CVV on its servers.\n• For COD orders, you agree to pay the exact invoiced amount in cash upon delivery.",
            ),

            _buildSection(
              number: "4",
              title: "Delivery & Live GPS Tracking",
              content:
                  "• Please ensure you provide correct delivery addresses and contact information.\n• GetMye provides live GPS location tracking via Google Maps APIs for real-time order monitoring.\n• Estimated delivery times are approximations subject to traffic, road conditions, and merchant preparation.",
            ),

            _buildSection(
              number: "5",
              title: "Cancellations & Refunds",
              content:
                  "• Orders may be cancelled before merchant preparation or dispatch begins.\n• Approved refunds for prepaid orders are credited back to the original payment source within 3–5 business days via Cashfree Payments.",
            ),

            _buildSection(
              number: "6",
              title: "Delivery Partner Guidelines",
              content:
                  "• Registered delivery partners must hold a valid driving license, active vehicle registration, insurance, and complete KYC verification.\n• Partners must adhere to road safety standards and professional conduct.",
            ),

            _buildSection(
              number: "7",
              title: "Prohibited Conduct",
              content:
                  "• Users must not place fake or speculative orders.\n• Any abusive behavior towards delivery partners, merchants, or customer support will result in immediate account termination.",
            ),

            _buildSection(
              number: "8",
              title: "Governing Law & Jurisdiction",
              content:
                  "• These Terms are governed by the laws of India.\n• Any legal disputes shall be subject to the exclusive jurisdiction of the competent courts in Kumbakonam / Thanjavur, Tamil Nadu.",
            ),

            const SizedBox(height: 12),

            // Grievance / Contact Card
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
                    "Grievance Officer & Contact",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text("Platform: GetMye", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text("Officer: Sivasakthi", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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

  Widget _buildSection({required String number, required String title, required String content}) {
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
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  number,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
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

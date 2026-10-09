import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UpiPaymentService {
  // Default merchant / receiver UPI details (can be configured or received from backend)
  static const String defaultVpa = 'getmye@upi';
  static const String defaultPayeeName = 'GetMye Express';

  /// Generates the standard UPI URI
  static String buildUpiUri({
    required double amount,
    String vpa = defaultVpa,
    String payeeName = defaultPayeeName,
    String note = 'Food Order Payment',
  }) {
    final encodedPn = Uri.encodeComponent(payeeName);
    final encodedTn = Uri.encodeComponent(note);
    final formattedAmount = amount.toStringAsFixed(2);
    return 'upi://pay?pa=$vpa&pn=$encodedPn&mc=5411&tr=${DateTime.now().millisecondsSinceEpoch}&tn=$encodedTn&am=$formattedAmount&cu=INR';
  }

  /// Launch Google Pay specifically or fallback to UPI intent
  static Future<bool> openGooglePay(
    BuildContext context, {
    required double amount,
    String note = 'GetMye Google Pay',
  }) async {
    final upiUrl = buildUpiUri(amount: amount, note: note);

    // Google Pay custom scheme
    final gpaySchemeUri = Uri.parse(
      upiUrl.replaceFirst('upi://', 'tez://upi/'),
    );
    final fallbackUpiUri = Uri.parse(upiUrl);

    try {
      if (await canLaunchUrl(gpaySchemeUri)) {
        return await launchUrl(gpaySchemeUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(fallbackUpiUri)) {
        return await launchUrl(fallbackUpiUri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) _showNoAppError(context, 'Google Pay or any UPI app');
        return false;
      }
    } catch (e) {
      debugPrint('Error launching GPay: $e');
      if (await canLaunchUrl(fallbackUpiUri)) {
        return await launchUrl(fallbackUpiUri, mode: LaunchMode.externalApplication);
      }
      if (context.mounted) _showNoAppError(context, 'Google Pay');
      return false;
    }
  }

  /// Launch PhonePe specifically or fallback to UPI intent
  static Future<bool> openPhonePe(
    BuildContext context, {
    required double amount,
    String note = 'GetMye PhonePe',
  }) async {
    final upiUrl = buildUpiUri(amount: amount, note: note);

    // PhonePe custom scheme
    final phonePeSchemeUri = Uri.parse(
      upiUrl.replaceFirst('upi://', 'phonepe://'),
    );
    final fallbackUpiUri = Uri.parse(upiUrl);

    try {
      if (await canLaunchUrl(phonePeSchemeUri)) {
        return await launchUrl(phonePeSchemeUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(fallbackUpiUri)) {
        return await launchUrl(fallbackUpiUri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) _showNoAppError(context, 'PhonePe or any UPI app');
        return false;
      }
    } catch (e) {
      debugPrint('Error launching PhonePe: $e');
      if (await canLaunchUrl(fallbackUpiUri)) {
        return await launchUrl(fallbackUpiUri, mode: LaunchMode.externalApplication);
      }
      if (context.mounted) _showNoAppError(context, 'PhonePe');
      return false;
    }
  }

  /// General UPI launcher
  static Future<bool> openAnyUpi(
    BuildContext context, {
    required double amount,
    String note = 'GetMye Order',
  }) async {
    final upiUri = Uri.parse(buildUpiUri(amount: amount, note: note));
    if (await canLaunchUrl(upiUri)) {
      return await launchUrl(upiUri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) _showNoAppError(context, 'a supported UPI payment app');
      return false;
    }
  }

  static void _showNoAppError(BuildContext context, String appName) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Could not launch $appName. Please ensure it is installed on this device.',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

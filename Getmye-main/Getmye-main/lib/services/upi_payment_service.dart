import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UpiPaymentService {
  // Default merchant / receiver UPI details
  static const String defaultVpa = 'sivaprakashsivaprakash421@okaxis';
  static const String defaultPayeeName = 'SIVAPRAKASH MUTHUKUMAR';

  /// Generates the standard P2P UPI URI
  static String buildUpiUri({
    required double amount,
    String vpa = defaultVpa,
    String payeeName = defaultPayeeName,
    String note = 'Food Order',
  }) {
    final encodedPn = Uri.encodeComponent(payeeName);
    final encodedTn = Uri.encodeComponent(note);
    final formattedAmount = amount.toStringAsFixed(2);
    return 'upi://pay?pa=$vpa&pn=$encodedPn&am=$formattedAmount&cu=INR&tn=$encodedTn';
  }

  /// Generates a live QR code image URL that can be scanned by any UPI App (GPay, PhonePe, Paytm, etc.)
  static String getQrCodeUrl({required double amount, String note = 'GetMye Food Order'}) {
    final upiUri = buildUpiUri(amount: amount, note: note);
    return 'https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${Uri.encodeComponent(upiUri)}';
  }

  /// Launch Google Pay specifically or fallback to UPI intent
  static Future<bool> openGooglePay(
    BuildContext context, {
    required double amount,
    String note = 'GetMye Google Pay',
  }) async {
    final upiUrl = buildUpiUri(amount: amount, note: note);
    final upiUri = Uri.parse(upiUrl);

    try {
      // First try standard externalApplication launch which opens UPI chooser with Google Pay
      final launched = await launchUrl(upiUri, mode: LaunchMode.externalApplication);
      if (launched) return true;
    } catch (_) {}

    // Fallback: try tez custom scheme
    try {
      final tezUri = Uri.parse(upiUrl.replaceFirst('upi://', 'tez://upi/'));
      if (await canLaunchUrl(tezUri)) {
        return await launchUrl(tezUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    // Fallback: general UPI
    if (!context.mounted) return false;
    return await openAnyUpi(context, amount: amount, note: note);
  }

  /// Launch PhonePe specifically or fallback to UPI intent
  static Future<bool> openPhonePe(
    BuildContext context, {
    required double amount,
    String note = 'GetMye PhonePe',
  }) async {
    final upiUrl = buildUpiUri(amount: amount, note: note);
    final upiUri = Uri.parse(upiUrl);

    try {
      final launched = await launchUrl(upiUri, mode: LaunchMode.externalApplication);
      if (launched) return true;
    } catch (_) {}

    // Fallback: try phonepe custom scheme
    try {
      final phonePeUri = Uri.parse(upiUrl.replaceFirst('upi://', 'phonepe://'));
      if (await canLaunchUrl(phonePeUri)) {
        return await launchUrl(phonePeUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    // Fallback: general UPI
    if (!context.mounted) return false;
    return await openAnyUpi(context, amount: amount, note: note);
  }

  /// Launch Paytm specifically or fallback to UPI intent
  static Future<bool> openPaytm(
    BuildContext context, {
    required double amount,
    String note = 'GetMye Paytm',
  }) async {
    final upiUrl = buildUpiUri(amount: amount, note: note);

    try {
      final paytmUri = Uri.parse(upiUrl.replaceFirst('upi://', 'paytmmp://'));
      if (await canLaunchUrl(paytmUri)) {
        return await launchUrl(paytmUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    if (!context.mounted) return false;
    return await openAnyUpi(context, amount: amount, note: note);
  }

  /// Launch CRED specifically or fallback to UPI intent
  static Future<bool> openCred(
    BuildContext context, {
    required double amount,
    String note = 'GetMye CRED',
  }) async {
    final upiUrl = buildUpiUri(amount: amount, note: note);

    try {
      final credUri = Uri.parse(upiUrl.replaceFirst('upi://', 'credpay://'));
      if (await canLaunchUrl(credUri)) {
        return await launchUrl(credUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    if (!context.mounted) return false;
    return await openAnyUpi(context, amount: amount, note: note);
  }

  /// Launch BHIM or any UPI intent
  static Future<bool> openBhim(
    BuildContext context, {
    required double amount,
    String note = 'GetMye BHIM',
  }) async {
    final upiUrl = buildUpiUri(amount: amount, note: note);

    try {
      final bhimUri = Uri.parse(upiUrl.replaceFirst('upi://', 'bhim://'));
      if (await canLaunchUrl(bhimUri)) {
        return await launchUrl(bhimUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    if (!context.mounted) return false;
    return await openAnyUpi(context, amount: amount, note: note);
  }

  /// Probe available payment apps on the device
  static Future<Map<String, bool>> getInstalledUpiApps(double amount) async {
    final upiUrl = buildUpiUri(amount: amount);
    bool gpay = false;
    bool phonepe = false;
    bool paytm = false;
    bool anyUpi = false;

    try {
      final tezUri = Uri.parse(upiUrl.replaceFirst('upi://', 'tez://upi/'));
      gpay = await canLaunchUrl(tezUri);
    } catch (_) {}

    try {
      final phonepeUri = Uri.parse(upiUrl.replaceFirst('upi://', 'phonepe://'));
      phonepe = await canLaunchUrl(phonepeUri);
    } catch (_) {}

    try {
      final paytmUri = Uri.parse(upiUrl.replaceFirst('upi://', 'paytmmp://'));
      paytm = await canLaunchUrl(paytmUri);
    } catch (_) {}

    try {
      final genericUri = Uri.parse(upiUrl);
      anyUpi = await canLaunchUrl(genericUri);
    } catch (_) {}

    return {
      'gpay': gpay,
      'phonepe': phonepe,
      'paytm': paytm,
      'anyUpi': anyUpi,
    };
  }

  /// General UPI launcher
  static Future<bool> openAnyUpi(
    BuildContext context, {
    required double amount,
    String note = 'GetMye Order',
  }) async {
    final upiUri = Uri.parse(buildUpiUri(amount: amount, note: note));
    try {
      final launched = await launchUrl(upiUri, mode: LaunchMode.externalApplication);
      if (launched) return true;
    } catch (e) {
      debugPrint('Error launching general UPI: $e');
    }

    if (context.mounted) {
      _showNoAppError(context, 'a supported UPI payment app (Google Pay / PhonePe / Paytm)');
    }
    return false;
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
                'Could not launch $appName. You can copy the UPI ID or scan QR to pay directly.',
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

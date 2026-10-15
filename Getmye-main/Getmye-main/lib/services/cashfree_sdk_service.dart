import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/api/cftheme/cftheme.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart';

/// Result from backend order creation
class CashfreeOrderResult {
  final bool success;
  final String orderId;
  final String? cfOrderId;
  final String? paymentSessionId;
  final double amount;
  final String? errorMessage;
  final bool alreadyPaid;
  final String? deliveryOtp;
  final String environment;

  CashfreeOrderResult({
    required this.success,
    required this.orderId,
    this.cfOrderId,
    this.paymentSessionId,
    this.amount = 0.0,
    this.errorMessage,
    this.alreadyPaid = false,
    this.deliveryOtp,
    this.environment = 'SANDBOX',
  });
}

/// Result from server-side payment verification
class CashfreeVerificationResult {
  final bool isPaid;
  final String orderId;
  final String? cfOrderId;
  final String? deliveryOtp;
  final String? transactionId;
  final double amount;
  final String message;
  final bool isPending;

  CashfreeVerificationResult({
    required this.isPaid,
    required this.orderId,
    this.cfOrderId,
    this.deliveryOtp,
    this.transactionId,
    this.amount = 0.0,
    required this.message,
    this.isPending = false,
  });
}

/// Official Cashfree Native SDK Integration Service
class CashfreeSdkService {
  static final CashfreeSdkService _instance = CashfreeSdkService._internal();
  factory CashfreeSdkService() => _instance;
  CashfreeSdkService._internal();

  final CFPaymentGatewayService _gatewayService = CFPaymentGatewayService();

  Function(String orderId)? _onSuccessCallback;
  Function(CFErrorResponse error, String orderId)? _onErrorCallback;

  /// Register SDK callbacks with Cashfree
  void initCallbacks({
    required Function(String orderId) onSuccess,
    required Function(CFErrorResponse error, String orderId) onError,
  }) {
    _onSuccessCallback = onSuccess;
    _onErrorCallback = onError;
    _gatewayService.setCallback(_handleVerify, _handleError);
  }

  void _handleVerify(String orderId) {
    debugPrint("[CashfreeSDK] Native Checkout verify callback: $orderId");
    _onSuccessCallback?.call(orderId);
  }

  void _handleError(CFErrorResponse error, String orderId) {
    debugPrint("[CashfreeSDK] Native Checkout error callback: ${error.getMessage()} ($orderId)");
    _onErrorCallback?.call(error, orderId);
  }

  /// Step 1: Call backend to securely create Cashfree Order and obtain payment_session_id
  Future<CashfreeOrderResult> createBackendOrder({
    required String orderId,
    required double amount,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
  }) async {
    try {
      final res = await http
          .post(
            ApiConfig.cashfreeCreateOrder,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'order_id': orderId,
              'amount': amount,
              'customer_id': customerId ?? 'USER001',
              'customer_name': customerName ?? 'Customer',
              'customer_phone': customerPhone ?? '9999999999',
              'customer_email': customerEmail,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);

        if (data['already_paid'] == true) {
          return CashfreeOrderResult(
            success: true,
            orderId: orderId,
            alreadyPaid: true,
            deliveryOtp: data['delivery_otp']?.toString(),
            errorMessage: data['message'] ?? 'Order is already marked as paid.',
          );
        }

        final sessionId = data['payment_session_id'];
        final cfOrderId = data['cf_order_id'];

        if (sessionId == null || sessionId.toString().isEmpty) {
          return CashfreeOrderResult(
            success: false,
            orderId: orderId,
            errorMessage: 'Payment session ID was not received from backend.',
          );
        }

        return CashfreeOrderResult(
          success: true,
          orderId: orderId,
          cfOrderId: cfOrderId?.toString(),
          paymentSessionId: sessionId.toString(),
          amount: (data['order_amount'] as num?)?.toDouble() ?? amount,
          environment: data['environment']?.toString() ?? 'SANDBOX',
        );
      } else {
        String msg = 'Failed to create payment order.';
        try {
          final errData = jsonDecode(res.body);
          if (errData['error'] != null) msg = errData['error'].toString();
          if (errData['details'] != null) msg += ': ${errData['details']}';
        } catch (_) {}
        return CashfreeOrderResult(
          success: false,
          orderId: orderId,
          errorMessage: msg,
        );
      }
    } catch (e) {
      debugPrint("[CashfreeSDK] Create order network exception: $e");
      return CashfreeOrderResult(
        success: false,
        orderId: orderId,
        errorMessage: 'Network error connecting to payment server. Please check internet connection.',
      );
    }
  }

  /// Step 2: Launch Cashfree Official Native SDK Checkout flow
  Future<bool> startNativeDropCheckout({
    required String orderId,
    required String paymentSessionId,
    bool isProduction = false,
  }) async {
    try {
      final session = CFSessionBuilder()
          .setEnvironment(isProduction ? CFEnvironment.PRODUCTION : CFEnvironment.SANDBOX)
          .setOrderId(orderId)
          .setPaymentSessionId(paymentSessionId)
          .build();

      final theme = CFThemeBuilder()
          .setNavigationBarBackgroundColorColor("#142B4A")
          .setNavigationBarTextColor("#FFFFFF")
          .setButtonBackgroundColor("#142B4A")
          .setButtonTextColor("#FFFFFF")
          .setPrimaryTextColor("#0F1E33")
          .setSecondaryTextColor("#566981")
          .setBackgroundColor("#FFFFFF")
          .build();

      final payment = CFWebCheckoutPaymentBuilder()
          .setSession(session)
          .setTheme(theme)
          .build();

      _gatewayService.doPayment(payment);
      return true;
    } on CFException catch (e) {
      debugPrint("[CashfreeSDK] CFException during doPayment: ${e.message}");
      return false;
    } catch (e) {
      debugPrint("[CashfreeSDK] Unexpected exception during doPayment: $e");
      return false;
    }
  }

  /// Step 3: Verify payment status server-side with Cashfree before confirming
  Future<CashfreeVerificationResult> verifyPaymentWithBackend({
    required String orderId,
    required String cfOrderId,
  }) async {
    try {
      final res = await http
          .post(
            ApiConfig.cashfreeVerifyOrder,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'order_id': orderId,
              'cf_order_id': cfOrderId,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final isPaid = data['success'] == true && data['payment_status'] == 'paid';
        final isPending = data['payment_status'] == 'pending' || data['payment_status'] == 'active';

        return CashfreeVerificationResult(
          isPaid: isPaid,
          orderId: orderId,
          cfOrderId: cfOrderId,
          deliveryOtp: data['delivery_otp']?.toString(),
          transactionId: data['transaction_id']?.toString(),
          amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
          message: data['message'] ?? (isPaid ? 'Payment successful' : 'Payment pending'),
          isPending: isPending,
        );
      } else {
        return CashfreeVerificationResult(
          isPaid: false,
          orderId: orderId,
          cfOrderId: cfOrderId,
          message: 'Server verification failed with status: ${res.statusCode}',
        );
      }
    } catch (e) {
      debugPrint("[CashfreeSDK] Backend verification error: $e");
      return CashfreeVerificationResult(
        isPaid: false,
        orderId: orderId,
        cfOrderId: cfOrderId,
        isPending: true,
        message: 'Unable to verify payment with server. Checking status...',
      );
    }
  }
}

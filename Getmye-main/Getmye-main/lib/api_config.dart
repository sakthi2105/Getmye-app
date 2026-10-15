import 'package:flutter_dotenv/flutter_dotenv.dart';

class CashfreeConfig {
  static String get appId => dotenv.env['CASHFREE_APP_ID'] ?? '';
  static String get apiVersion => dotenv.env['CASHFREE_API_VERSION'] ?? '2023-08-01';
  static String get baseUrl => dotenv.env['CASHFREE_BASE_URL'] ?? 'https://sandbox.cashfree.com/pg';
}

class ApiConfig {
  // Cashfree Native Payment Gateway Endpoints (Backend-driven)
  static Uri get cashfreeCreateOrder => Uri.parse('$baseUrl/api/payment/cashfree/create-order');
  static Uri get cashfreeVerifyOrder => Uri.parse('$baseUrl/api/payment/cashfree/verify-order');
  static Uri cashfreeOrderStatus(String orderId) => Uri.parse('$baseUrl/api/payment/cashfree/status/$orderId');
  static Uri get cashfreeConfig => Uri.parse('$baseUrl/api/payment/cashfree/config');

  // Base server URL (Wi-Fi LAN IP reachable by both physical test devices)
  static const String baseUrl = 'http://192.168.29.196:5000';

  // Order Endpoints
  static Uri get orderCreate => Uri.parse('$baseUrl/api/order/create');
  static Uri get orderPending => Uri.parse('$baseUrl/api/order/pending');
  static Uri get orderAccept => Uri.parse('$baseUrl/api/order/accept');
  static Uri get orderDecline => Uri.parse('$baseUrl/api/order/decline');
  static Uri get orderUpdateStatus => Uri.parse('$baseUrl/api/order/update-status');
  static Uri get orderVerifyDeliveryOtp => Uri.parse('$baseUrl/api/order/verify-delivery-otp');
  static Uri orderById(String id) => Uri.parse('$baseUrl/api/order/$id');
  static Uri orderActive(String userId) => Uri.parse('$baseUrl/api/order/active/$userId');
  static Uri orderUser(String userId) => Uri.parse('$baseUrl/api/order/user/$userId');
  static Uri orderPartner(String partnerId) => Uri.parse('$baseUrl/api/order/partner/$partnerId');
  static Uri get orderCancel => Uri.parse('$baseUrl/api/order/cancel');
  static Uri orderMessages(String orderId) => Uri.parse('$baseUrl/api/order/$orderId/messages');
  static Uri orderSendMessage(String orderId) => Uri.parse('$baseUrl/api/order/$orderId/message');

  // Bill Endpoints
  static Uri get billSubmit => Uri.parse('$baseUrl/api/bill/submit');
  static Uri get billTip => Uri.parse('$baseUrl/api/bill/tip');
  static Uri billByOrder(String orderId) => Uri.parse('$baseUrl/api/bill/$orderId');

  // Live Location Tracking Endpoints
  static Uri get trackingUpdate => Uri.parse('$baseUrl/api/tracking/update');
  static Uri trackingByPartner(String partnerId) => Uri.parse('$baseUrl/api/tracking/$partnerId');

  // Address Endpoints
  static Uri addressList(String userId) => Uri.parse('$baseUrl/api/address/list?user_id=$userId');
  static Uri get addressAdd => Uri.parse('$baseUrl/api/address/add');
  static Uri get addressUpdate => Uri.parse('$baseUrl/api/address/update');
  static Uri addressDelete(String addId) => Uri.parse('$baseUrl/api/address/delete/$addId');
  static Uri get addressSetDefault => Uri.parse('$baseUrl/api/address/set-default');

  // Profile & Auth Endpoints
  static Uri get profile => Uri.parse('$baseUrl/api/profile');
  static Uri get profileRegister => Uri.parse('$baseUrl/api/profile/register');
  static Uri get profileLogin => Uri.parse('$baseUrl/api/profile/login');
  static Uri profileByMobile(String mobile) => Uri.parse('$baseUrl/api/profile/$mobile');
  static Uri profileOtp(String mobile) => Uri.parse('$baseUrl/api/profile/otp/$mobile');
  static Uri get profileVerifyOtp => Uri.parse('$baseUrl/api/profile/verify-otp');
  static Uri get profileUpdate => Uri.parse('$baseUrl/api/editp/update');
  static Uri get profileForgotPasswordSendOtp => Uri.parse('$baseUrl/api/profile/forgot-password/send-otp');
  static Uri get profileForgotPasswordVerifyOtp => Uri.parse('$baseUrl/api/profile/forgot-password/verify-otp');
  static Uri get profileForgotPasswordReset => Uri.parse('$baseUrl/api/profile/forgot-password/reset-password');

  // Delivery Partner Auth & Status Endpoints
  static Uri get partnerRegister => Uri.parse('$baseUrl/api/deliveryperson/register');
  static Uri get partnerLogin => Uri.parse('$baseUrl/api/deliveryperson/login');
  static Uri get partnerAdd => Uri.parse('$baseUrl/api/deliveryperson/add');
  static Uri get partnerStatus => Uri.parse('$baseUrl/api/deliveryperson/status');
  static Uri orderPendingWithParams({String? partnerId, double? latitude, double? longitude}) {
    final query = <String, String>{};
    if (partnerId != null && partnerId.isNotEmpty) query['partner_id'] = partnerId;
    if (latitude != null) query['latitude'] = latitude.toString();
    if (longitude != null) query['longitude'] = longitude.toString();
    return Uri.parse('$baseUrl/api/order/pending').replace(queryParameters: query.isNotEmpty ? query : null);
  }

  // Support Endpoints (Bug Report, Complaint, Feedback)
  static Uri get supportBugReport => Uri.parse('$baseUrl/api/support/bug-report');
  static Uri get supportComplaint => Uri.parse('$baseUrl/api/support/complaint');
  static Uri get supportFeedback => Uri.parse('$baseUrl/api/support/feedback');
}

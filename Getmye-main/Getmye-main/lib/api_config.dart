class ApiConfig {
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

  // Profile & Auth Endpoints
  static Uri get profile => Uri.parse('$baseUrl/api/profile');
  static Uri get profileRegister => Uri.parse('$baseUrl/api/profile/register');
  static Uri get profileLogin => Uri.parse('$baseUrl/api/profile/login');
  static Uri profileByMobile(String mobile) => Uri.parse('$baseUrl/api/profile/$mobile');
  static Uri profileOtp(String mobile) => Uri.parse('$baseUrl/api/profile/otp/$mobile');
  static Uri get profileVerifyOtp => Uri.parse('$baseUrl/api/profile/verify-otp');
  static Uri get profileUpdate => Uri.parse('$baseUrl/api/editp/update');

  // Delivery Partner Auth Endpoints
  static Uri get partnerRegister => Uri.parse('$baseUrl/api/deliveryperson/register');
  static Uri get partnerLogin => Uri.parse('$baseUrl/api/deliveryperson/login');
  static Uri get partnerAdd => Uri.parse('$baseUrl/api/deliveryperson/add');

  // Support Endpoints (Bug Report, Complaint, Feedback)
  static Uri get supportBugReport => Uri.parse('$baseUrl/api/support/bug-report');
  static Uri get supportComplaint => Uri.parse('$baseUrl/api/support/complaint');
  static Uri get supportFeedback => Uri.parse('$baseUrl/api/support/feedback');
}

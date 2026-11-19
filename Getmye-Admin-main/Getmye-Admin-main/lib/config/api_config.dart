class AdminApiConfig {
  // Default server base URL (LAN IP or Cloud)
  static String _baseUrl = 'http://192.168.29.196:5000';

  static String get baseUrl => _baseUrl;

  static void setBaseUrl(String newUrl) {
    String trimmed = newUrl.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }
    _baseUrl = trimmed;
  }

  // Health Check
  static Uri get health => Uri.parse('$_baseUrl/api/health');

  // KYC Endpoints
  static Uri get pendingKYC => Uri.parse('$_baseUrl/api/getPendingKYC/pendingkyc');
  static Uri dpDetails(String dpId) => Uri.parse('$_baseUrl/api/getPendingKYC/$dpId');
  static Uri get updateKYCStatus => Uri.parse('$_baseUrl/api/getPendingKYC/updateKYCStatus');

  // Offer Banner Endpoints (Customer Home Page Banner Upload)
  static Uri get bannerActive => Uri.parse('$_baseUrl/api/banner/active');
  static Uri get bannerAll => Uri.parse('$_baseUrl/api/banner/all');
  static Uri get bannerUpload => Uri.parse('$_baseUrl/api/banner/upload');
  static Uri get bannerStock => Uri.parse('$_baseUrl/api/banner/stock');
  static Uri bannerToggle(String id) => Uri.parse('$_baseUrl/api/banner/toggle/$id');

  // Support Endpoints (Bug Reports, Complaints, Feedback)
  static Uri get supportBugReports => Uri.parse('$_baseUrl/api/support/bug-reports');
  static Uri get supportComplaints => Uri.parse('$_baseUrl/api/support/complaints');
  static Uri get supportFeedbacks => Uri.parse('$_baseUrl/api/support/feedbacks');
  static Uri get supportStats => Uri.parse('$_baseUrl/api/support/stats');
  static Uri updateBugStatus(String id) => Uri.parse('$_baseUrl/api/support/bug-report/$id/status');
  static Uri updateComplaintStatus(String id) => Uri.parse('$_baseUrl/api/support/complaint/$id/status');

  // Orders Management Endpoints
  static Uri ordersAll({String? status, int limit = 100}) {
    final query = <String, String>{
      'limit': limit.toString(),
    };
    if (status != null && status.isNotEmpty && status != 'all') {
      query['status'] = status;
    }
    return Uri.parse('$_baseUrl/api/order/admin/all').replace(queryParameters: query);
  }
  static Uri get ordersOverview => Uri.parse('$_baseUrl/api/order/admin/overview');
  static Uri get ordersPending => Uri.parse('$_baseUrl/api/order/pending');
  static Uri orderById(String orderId) => Uri.parse('$_baseUrl/api/order/$orderId');
}


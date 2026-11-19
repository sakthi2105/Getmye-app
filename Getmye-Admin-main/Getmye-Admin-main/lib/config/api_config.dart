import 'package:flutter/foundation.dart';

enum AdminMode {
  local,
  lan,
  live,
  custom,
}

class AdminApiConfig {
  // Preset Server URLs
  static const String defaultLocalhostUrl = 'http://127.0.0.1:5000';
  static const String defaultLanUrl = 'http://192.168.29.196:5000';
  static const String defaultLiveRenderUrl = 'https://getmye-app.onrender.com';
  static const String defaultLiveCustomDomain = 'https://api.getmye.com';

  // Default mode starts as LOCAL so local testing works out of the box
  static AdminMode _currentMode = AdminMode.local;
  static String _baseUrl = defaultLocalhostUrl;

  static final ValueNotifier<AdminMode> modeNotifier =
      ValueNotifier<AdminMode>(_currentMode);

  static AdminMode get currentMode => _currentMode;
  static String get baseUrl => _baseUrl;
  static bool get isLocal => _currentMode == AdminMode.local || _currentMode == AdminMode.lan;
  static bool get isLive => _currentMode == AdminMode.live;

  static String get modeLabel {
    switch (_currentMode) {
      case AdminMode.local:
        return 'LOCAL (127.0.0.1)';
      case AdminMode.lan:
        return 'LOCAL LAN (Wi-Fi)';
      case AdminMode.live:
        return 'LIVE CLOUD';
      case AdminMode.custom:
        return 'CUSTOM';
    }
  }

  static void setMode(AdminMode mode, {String? customUrl}) {
    _currentMode = mode;
    switch (mode) {
      case AdminMode.local:
        _baseUrl = defaultLocalhostUrl;
        break;
      case AdminMode.lan:
        _baseUrl = defaultLanUrl;
        break;
      case AdminMode.live:
        _baseUrl = customUrl ?? defaultLiveRenderUrl;
        break;
      case AdminMode.custom:
        if (customUrl != null) setBaseUrl(customUrl);
        break;
    }
    modeNotifier.value = mode;
  }

  static void setBaseUrl(String newUrl) {
    String trimmed = newUrl.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }
    _baseUrl = trimmed;
    modeNotifier.value = _currentMode;
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

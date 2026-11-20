import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../theme/admin_theme.dart';
import '../widgets/env_switcher_button.dart';

class OfferBannerPage extends StatefulWidget {
  const OfferBannerPage({super.key});

  @override
  State<OfferBannerPage> createState() => _OfferBannerPageState();
}

class _OfferBannerPageState extends State<OfferBannerPage> {
  Map<String, dynamic>? activeBanner;
  List<dynamic> bannerHistory = [];
  bool isLoading = true;
  bool isUploading = false;

  final ImagePicker _imagePicker = ImagePicker();
  Uint8List? _pickedImageBytes;
  String? _pickedBase64;
  String? _pickedImageName;

  // Form Controllers
  final _titleController = TextEditingController(text: 'Special Dum Biriyani Deal');
  final _badgeController = TextEditingController(text: "TODAY'S SPECIAL");
  final _offerPriceController = TextEditingController(text: '65');
  final _originalPriceController = TextEditingController(text: '120');
  final _stockRemainingController = TextEditingController(text: '75');
  final _totalStockController = TextEditingController(text: '100');
  final _imageUrlController = TextEditingController();
  final _imageBase64Controller = TextEditingController();

  String _selectedUploadTab = 'device'; // 'device', 'presets', 'url', 'base64'
  String? _previewImage; // Can be URL or Base64 or preset asset

  // App Operational Schedule States (Start & End Time Window)
  TimeOfDay _startTime = const TimeOfDay(hour: 12, minute: 30);
  TimeOfDay _endTime = const TimeOfDay(hour: 12, minute: 45);
  bool _isScheduleEnabled = true;
  String _manualOverride = 'auto'; // 'auto', 'always_online', 'always_offline'
  bool _isStoreCurrentlyOnline = false;
  String _serverCurrentTimeIst = '';
  int _secondsUntilClose = 0;
  int _secondsUntilOpen = 0;
  bool _isSavingSchedule = false;
  bool _isLoadingSchedule = true;
  Timer? _schedulePollTimer;

  // Curated Preset Food & Biryani Deals for quick 1-click select
  final List<Map<String, String>> curatedPresets = [
    {
      'title': 'Woodfired Chicken Dum Biriyani',
      'price': '65',
      'orig': '120',
      'badge': 'HOT DEAL',
      'imageUrl': 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=800&q=80',
    },
    {
      'title': 'Authentic Mutton Dum Biriyani',
      'price': '140',
      'orig': '220',
      'badge': 'CHEF SPECIAL',
      'imageUrl': 'https://images.unsplash.com/photo-1589302168068-964664d93dc0?w=800&q=80',
    },
    {
      'title': 'Special Biriyani with Chicken 65',
      'price': '85',
      'orig': '150',
      'badge': 'BESTSELLER',
      'imageUrl': 'https://images.unsplash.com/photo-1633945274405-b6c8069047b0?w=800&q=80',
    },
    {
      'title': 'Juicy Chicken Shawarma Feast',
      'price': '70',
      'orig': '110',
      'badge': 'CRUSHING DEAL',
      'imageUrl': 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?w=800&q=80',
    },
  ];

  @override
  void initState() {
    super.initState();
    fetchActiveBanner();
    fetchBannerHistory();
    fetchScheduleStatus();
    _startScheduleTimer();
  }

  @override
  void dispose() {
    _schedulePollTimer?.cancel();
    _titleController.dispose();
    _badgeController.dispose();
    _offerPriceController.dispose();
    _originalPriceController.dispose();
    _stockRemainingController.dispose();
    _totalStockController.dispose();
    _imageUrlController.dispose();
    _imageBase64Controller.dispose();
    super.dispose();
  }

  Future<void> fetchActiveBanner() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(AdminApiConfig.bannerActive);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['banner'] != null) {
          setState(() {
            activeBanner = decoded['banner'] as Map<String, dynamic>;
            isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> fetchBannerHistory() async {
    try {
      final res = await http.get(AdminApiConfig.bannerAll);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['banners'] is List) {
          setState(() {
            bannerHistory = decoded['banners'] as List;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> fetchScheduleStatus() async {
    setState(() => _isLoadingSchedule = true);
    try {
      final res = await http.get(AdminApiConfig.scheduleStatus);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['success'] == true) {
          setState(() {
            _isStoreCurrentlyOnline = decoded['is_online'] == true;
            _serverCurrentTimeIst = decoded['current_time_ist'] ?? '';
            _secondsUntilClose = decoded['seconds_until_close'] ?? 0;
            _secondsUntilOpen = decoded['seconds_until_open'] ?? 0;
            _isScheduleEnabled = decoded['is_schedule_enabled'] ?? true;
            _manualOverride = decoded['manual_override'] ?? 'auto';
            if (decoded['start_time'] != null) {
              _startTime = _parseTimeOfDay(decoded['start_time']);
            }
            if (decoded['end_time'] != null) {
              _endTime = _parseTimeOfDay(decoded['end_time']);
            }
            _isLoadingSchedule = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingSchedule = false);
  }

  void _startScheduleTimer() {
    _schedulePollTimer?.cancel();
    _schedulePollTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_isStoreCurrentlyOnline) {
        if (_secondsUntilClose > 0) {
          setState(() => _secondsUntilClose--);
          if (_secondsUntilClose == 0) {
            _pollScheduleStatus();
          }
        } else {
          if (timer.tick % 5 == 0) _pollScheduleStatus();
        }
      } else {
        if (_secondsUntilOpen > 0) {
          setState(() => _secondsUntilOpen--);
          if (_secondsUntilOpen == 0) {
            _pollScheduleStatus();
          }
        } else {
          if (timer.tick % 5 == 0) _pollScheduleStatus();
        }
      }
    });
  }

  Future<void> _pollScheduleStatus() async {
    try {
      final res = await http.get(AdminApiConfig.scheduleStatus);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['success'] == true) {
          setState(() {
            _isStoreCurrentlyOnline = decoded['is_online'] == true;
            _serverCurrentTimeIst = decoded['current_time_ist'] ?? '';
            _secondsUntilClose = decoded['seconds_until_close'] ?? 0;
            _secondsUntilOpen = decoded['seconds_until_open'] ?? 0;
          });
        }
      }
    } catch (_) {}
  }

  String _formatSeconds(int totalSec) {
    if (totalSec <= 0) return "00:00";
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    }
    return '${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
  }

  Future<void> _saveSchedule() async {
    setState(() => _isSavingSchedule = true);
    try {
      final startStr = '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
      final endStr = '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}';

      final res = await http.post(
        AdminApiConfig.scheduleUpdate,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'start_time': startStr,
          'end_time': endStr,
          'is_schedule_enabled': _isScheduleEnabled,
          'manual_override': _manualOverride,
        }),
      );

      if (!mounted) return;
      setState(() => _isSavingSchedule = false);

      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('Store Operating Window saved: $startStr - $endStr!'),
              ],
            ),
            backgroundColor: AdminColors.success,
          ),
        );
        fetchScheduleStatus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update schedule on server.'),
            backgroundColor: AdminColors.danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingSchedule = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving schedule: $e'),
            backgroundColor: AdminColors.danger,
          ),
        );
      }
    }
  }

  TimeOfDay _parseTimeOfDay(String timeStr) {
    try {
      final parts = timeStr.trim().split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      return TimeOfDay(hour: h, minute: m);
    } catch (_) {
      return const TimeOfDay(hour: 12, minute: 30);
    }
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return TimeOfDay.fromDateTime(dt).format(context);
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      helpText: 'SELECT STORE OPEN START TIME',
    );
    if (picked != null && picked != _startTime) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      helpText: 'SELECT STORE CLOSE END TIME',
    );
    if (picked != null && picked != _endTime) {
      setState(() => _endTime = picked);
    }
  }

  static const int _maxAllowedImageBytes = 500 * 1024; // 500 KB size limit

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 75,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        
        // Strict file size limit validation (500 KB)
        if (bytes.lengthInBytes > _maxAllowedImageBytes) {
          final sizeKb = (bytes.lengthInBytes / 1024).toStringAsFixed(0);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Image is too large ($sizeKb KB). Maximum allowed size is 500 KB.'),
                backgroundColor: AdminColors.danger,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        final base64Str = base64Encode(bytes);
        setState(() {
          _pickedImageBytes = bytes;
          _pickedBase64 = 'data:image/jpeg;base64,$base64Str';
          _pickedImageName = file.name;
          _previewImage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting image: $e'),
            backgroundColor: AdminColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _publishOfferBanner() async {
    setState(() => isUploading = true);

    String? finalBase64;
    String? finalUrl;

    if (_selectedUploadTab == 'device') {
      if (_pickedBase64 == null) {
        if (!mounted) return;
        setState(() => isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select an image from your device first!'),
            backgroundColor: AdminColors.danger,
          ),
        );
        return;
      }
      finalBase64 = _pickedBase64;
    } else if (_selectedUploadTab == 'base64' && _imageBase64Controller.text.trim().isNotEmpty) {
      finalBase64 = _imageBase64Controller.text.trim();
    } else if (_selectedUploadTab == 'url' && _imageUrlController.text.trim().isNotEmpty) {
      finalUrl = _imageUrlController.text.trim();
    } else if (_selectedUploadTab == 'presets' && _previewImage != null) {
      finalUrl = _previewImage;
    }

    try {
      final res = await http.post(
        AdminApiConfig.bannerUpload,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'title': _titleController.text.trim(),
          'badge': _badgeController.text.trim(),
          'offer_price': int.tryParse(_offerPriceController.text) ?? 65,
          'original_price': int.tryParse(_originalPriceController.text) ?? 120,
          'stock_remaining': int.tryParse(_stockRemainingController.text) ?? 75,
          'total_stock': int.tryParse(_totalStockController.text) ?? 100,
          'image_base64': finalBase64,
          'image_url': finalUrl,
          'is_active': true,
        }),
      );

      if (!mounted) return;
      setState(() => isUploading = false);

      if (res.statusCode == 200 || res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Offer Banner published to Customer Home page!'),
              ],
            ),
            backgroundColor: AdminColors.success,
          ),
        );
        fetchActiveBanner();
        fetchBannerHistory();
      } else {
        String errDetail = 'HTTP ${res.statusCode}';
        try {
          final errBody = json.decode(res.body);
          if (errBody is Map && (errBody['error'] != null || errBody['message'] != null)) {
            errDetail = '${errBody['error'] ?? errBody['message']} (${res.statusCode})';
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish: $errDetail. (Ensure backend has /api/banner deployed)'),
            backgroundColor: AdminColors.danger,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uploading: $e'),
          backgroundColor: AdminColors.danger,
        ),
      );
    }
  }

  Future<void> _updateQuickStock(int delta) async {
    final current = int.tryParse(_stockRemainingController.text) ?? 75;
    final newCount = (current + delta).clamp(0, 500);
    _stockRemainingController.text = newCount.toString();

    try {
      await http.put(
        AdminApiConfig.bannerStock,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'stock_remaining': newCount}),
      );
      fetchActiveBanner();
    } catch (_) {}
  }

  Future<void> _setActiveBanner(String bannerId) async {
    try {
      await http.post(AdminApiConfig.bannerToggle(bannerId));
      fetchActiveBanner();
      fetchBannerHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Active offer updated!'),
            backgroundColor: AdminColors.success,
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        title: const Text('Customer Home Offer Image & Banner Control'),
        actions: [
          EnvSwitcherButton(
            onEnvironmentChanged: () {
              fetchActiveBanner();
              fetchBannerHistory();
              fetchScheduleStatus();
            },
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              fetchActiveBanner();
              fetchBannerHistory();
              fetchScheduleStatus();
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AdminColors.border, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Explanatory Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AdminColors.primaryLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AdminColors.primarySubtle),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.campaign_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Customer App Live Offer Control',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AdminColors.primaryDark,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Any image uploaded here will directly appear on the customer home page in 1:1 ratio with dynamic price and stock counter.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AdminColors.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Store Operating Hours (Online/Offline Schedule Control)
                _buildStoreScheduleSection(),
                const SizedBox(height: 20),

                // Layout: Two columns on wider screens, stacked on mobile
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 700;
                    return Flex(
                      direction: isWide ? Axis.horizontal : Axis.vertical,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left / Top: Live Preview Card
                        Expanded(
                          flex: isWide ? 4 : 0,
                          child: _buildLivePreviewSection(),
                        ),
                        if (isWide) const SizedBox(width: 20) else const SizedBox(height: 20),

                        // Right / Bottom: Upload Form
                        Expanded(
                          flex: isWide ? 6 : 0,
                          child: _buildUploadFormSection(),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 26),

                // Banner History List
                _buildBannerHistorySection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoreScheduleSection() {
    final startFormatted = '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
    final endFormatted = '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}';
    final isOnline = _isStoreCurrentlyOnline;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOnline ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Live Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.schedule_rounded,
                      color: isOnline ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Store Operational Window (App Online/Offline)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AdminColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Server Time (IST): ${_serverCurrentTimeIst.isNotEmpty ? _serverCurrentTimeIst : "Syncing..."}  •  Active Window: $startFormatted – $endFormatted',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AdminColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isOnline ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 4,
                      backgroundColor: isOnline ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnline
                          ? (_secondsUntilClose > 0 ? 'APP ONLINE (${_formatSeconds(_secondsUntilClose)})' : 'APP ONLINE')
                          : (_secondsUntilOpen > 0 ? 'APP OFFLINE (${_formatSeconds(_secondsUntilOpen)})' : 'APP OFFLINE'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: isOnline ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Time Pickers Row
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminColors.border),
            ),
            child: Row(
              children: [
                // Start Time Card
                Expanded(
                  child: InkWell(
                    onTap: _selectStartTime,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AdminColors.primary.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.login_rounded, size: 14, color: AdminColors.primary),
                              SizedBox(width: 5),
                              Text(
                                'OPEN TIME (START)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AdminColors.primaryDark,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatTimeOfDay(_startTime),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: AdminColors.textPrimary,
                                ),
                              ),
                              const Icon(Icons.edit_calendar_rounded, size: 18, color: AdminColors.primary),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.arrow_forward_rounded, color: AdminColors.textMuted, size: 20),
                ),
                // End Time Card
                Expanded(
                  child: InkWell(
                    onTap: _selectEndTime,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFEA580C).withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.logout_rounded, size: 14, color: Color(0xFFEA580C)),
                              SizedBox(width: 5),
                              Text(
                                'CLOSE TIME (END)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF9A3412),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatTimeOfDay(_endTime),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: AdminColors.textPrimary,
                                ),
                              ),
                              const Icon(Icons.edit_calendar_rounded, size: 18, color: Color(0xFFEA580C)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Options & Save Button Row
          Row(
            children: [
              // Switch: Enable Schedule
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: _isScheduleEnabled,
                    activeColor: AdminColors.primary,
                    onChanged: (val) => setState(() => _isScheduleEnabled = val),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Enforce Schedule',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),

              // Manual Override Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AdminColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _manualOverride,
                    isDense: true,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AdminColors.textPrimary),
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('Auto (By Schedule)')),
                      DropdownMenuItem(value: 'always_online', child: Text('Force Online (Always Open)')),
                      DropdownMenuItem(value: 'always_offline', child: Text('Force Offline (Emergency Closed)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _manualOverride = val);
                    },
                  ),
                ),
              ),
              const Spacer(),

              // Save Schedule Button
              ElevatedButton.icon(
                onPressed: _isSavingSchedule ? null : _saveSchedule,
                icon: _isSavingSchedule
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_rounded, size: 16),
                label: const Text('Save Operating Hours'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLivePreviewSection() {
    final title = activeBanner?['title'] ?? _titleController.text;
    final badge = activeBanner?['badge'] ?? _badgeController.text;
    final offerPrice = activeBanner?['offer_price'] ?? _offerPriceController.text;
    final origPrice = activeBanner?['original_price'] ?? _originalPriceController.text;
    final remainingStock = activeBanner?['stock_remaining'] ?? _stockRemainingController.text;
    final totalStock = activeBanner?['total_stock'] ?? _totalStockController.text;

    final bannerBase64 = activeBanner?['image_base64'] as String?;
    final bannerUrl = activeBanner?['image_url'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Live Customer View',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AdminColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AdminColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(radius: 3, backgroundColor: AdminColors.primary),
                    SizedBox(width: 5),
                    Text(
                      'LIVE ON APP',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AdminColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 1:1 Aspect Ratio Card Preview (Exact replica of Customer Home)
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFFF1F5F9),
                border: Border.all(color: AdminColors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildPreviewImage(bannerBase64, bannerUrl),
                    // Badge Overlay
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEA580C),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Text(
                          badge.toString().toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Stock Counter Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('🔥', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Text(
                      '$remainingStock out of $totalStock biryanis remaining',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'FAST SELLING',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Offer Button Preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                'Get This Offer • ₹$offerPrice (Orig: ₹$origPrice)',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Quick Stock Stepper
          Row(
            children: [
              const Text(
                'Adjust Stock:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.textSecondary),
              ),
              const Spacer(),
              IconButton.outlined(
                icon: const Icon(Icons.remove, size: 16),
                onPressed: () => _updateQuickStock(-5),
                style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              Text(
                '$remainingStock',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                icon: const Icon(Icons.add, size: 16),
                onPressed: () => _updateQuickStock(5),
                style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewImage(String? base64String, String? url) {
    if (_selectedUploadTab == 'device' && _pickedImageBytes != null) {
      return Image.memory(
        _pickedImageBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _defaultImage(),
      );
    }
    if (_previewImage != null && _previewImage!.startsWith('http')) {
      return Image.network(_previewImage!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultImage());
    }
    if (base64String != null && base64String.isNotEmpty) {
      try {
        final clean = base64String.contains(',') ? base64String.split(',')[1] : base64String;
        return Image.memory(base64Decode(clean), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultImage());
      } catch (_) {}
    }
    if (url != null && url.isNotEmpty && url.startsWith('http')) {
      return Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultImage());
    }
    return _defaultImage();
  }

  Widget _defaultImage() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.fastfood_rounded, size: 40, color: AdminColors.primaryDark),
          SizedBox(height: 6),
          Text(
            'GetMye Dum Biriyani',
            style: TextStyle(fontWeight: FontWeight.w700, color: AdminColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceImagePicker() {
    if (_pickedImageBytes == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AdminColors.primary.withOpacity(0.35),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AdminColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_photo_alternate_rounded,
                size: 32,
                color: AdminColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Upload Banner from Device',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AdminColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Select a food or offer image from your gallery or take a photo (Max: 500 KB).',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AdminColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded, size: 16),
                  label: const Text('Choose from Gallery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_rounded, size: 16),
                  label: const Text('Take Photo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    side: const BorderSide(color: AdminColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final sizeKb = (_pickedImageBytes!.lengthInBytes / 1024).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 64,
              child: Image.memory(_pickedImageBytes!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 16),
                    SizedBox(width: 5),
                    Text(
                      'Ready to Upload',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF166534),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _pickedImageName ?? 'device_image.jpg',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textPrimary,
                  ),
                ),
                Text(
                  'Size: $sizeKb KB • Auto-compressed',
                  style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Pick different image',
                icon: const Icon(Icons.edit_rounded, color: AdminColors.primary, size: 20),
                onPressed: () => _pickImage(ImageSource.gallery),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline_rounded, color: AdminColors.danger, size: 20),
                onPressed: () {
                  setState(() {
                    _pickedImageBytes = null;
                    _pickedBase64 = null;
                    _pickedImageName = null;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUploadFormSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upload / Replace Offer Banner',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AdminColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Upload an image from your device, choose a curated preset, or use an image URL.',
            style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
          ),
          const SizedBox(height: 14),

          // Upload Source Mode Selector
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTabPill('device', 'From Device', Icons.add_photo_alternate_rounded),
                const SizedBox(width: 8),
                _buildTabPill('presets', 'Curated Library', Icons.photo_library_outlined),
                const SizedBox(width: 8),
                _buildTabPill('url', 'Image URL', Icons.link_rounded),
                const SizedBox(width: 8),
                _buildTabPill('base64', 'Base64 Data', Icons.data_object_rounded),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Device Image Picker
          if (_selectedUploadTab == 'device') ...[
            _buildDeviceImagePicker(),
          ],

          // Presets Grid
          if (_selectedUploadTab == 'presets') ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.4,
              ),
              itemCount: curatedPresets.length,
              itemBuilder: (context, index) {
                final preset = curatedPresets[index];
                final isSelected = _previewImage == preset['imageUrl'];
                return InkWell(
                  onTap: () {
                    setState(() {
                      _previewImage = preset['imageUrl'];
                      _titleController.text = preset['title']!;
                      _offerPriceController.text = preset['price']!;
                      _originalPriceController.text = preset['orig']!;
                      _badgeController.text = preset['badge']!;
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AdminColors.primary : AdminColors.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            preset['imageUrl']!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(color: AdminColors.background),
                          ),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.transparent, Colors.black87],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            left: 8,
                            right: 8,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  preset['title']!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '₹${preset['price']} (Orig: ₹${preset['orig']})',
                                  style: const TextStyle(
                                    color: Color(0xFF86EFAC),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Positioned(
                              top: 6,
                              right: 6,
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: AdminColors.primary,
                                child: Icon(Icons.check, size: 12, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],

          // URL Input Field
          if (_selectedUploadTab == 'url') ...[
            TextField(
              controller: _imageUrlController,
              onChanged: (val) => setState(() => _previewImage = val.trim()),
              decoration: const InputDecoration(
                hintText: 'https://example.com/banner-image.jpg',
                prefixIcon: Icon(Icons.image_outlined, size: 18),
                labelText: 'Image Web URL (HTTPS)',
              ),
            ),
          ],

          // Base64 Input Field
          if (_selectedUploadTab == 'base64') ...[
            TextField(
              controller: _imageBase64Controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'data:image/jpeg;base64,...',
                prefixIcon: Icon(Icons.code_rounded, size: 18),
                labelText: 'Paste Base64 Image String',
              ),
            ),
          ],
          const SizedBox(height: 18),

          // Offer Form Fields
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Offer Title / Food Name',
              hintText: 'e.g., Special Dum Biriyani Deal',
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _badgeController,
                  decoration: const InputDecoration(
                    labelText: 'Tag / Badge',
                    hintText: 'e.g. HOT DEAL',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _offerPriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Offer Price (₹)',
                    hintText: '65',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _originalPriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Original (₹)',
                    hintText: '120',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _stockRemainingController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Remaining Stock',
                    hintText: '75',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _totalStockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Total Daily Stock',
                    hintText: '100',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Submit Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isUploading ? null : _publishOfferBanner,
              icon: isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_rounded, size: 18),
              label: const Text('Save & Publish to Customer Home Page'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill(String tab, String label, IconData icon) {
    final isSelected = _selectedUploadTab == tab;
    return InkWell(
      onTap: () => setState(() => _selectedUploadTab = tab),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AdminColors.primary : AdminColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? AdminColors.primary : AdminColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : AdminColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AdminColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerHistorySection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Offer Banner Upload History (${bannerHistory.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AdminColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: fetchBannerHistory,
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (bannerHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No previous banner uploads recorded yet.',
                  style: TextStyle(color: AdminColors.textMuted, fontSize: 13),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: bannerHistory.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AdminColors.borderLight),
              itemBuilder: (context, index) {
                final item = bannerHistory[index];
                final isActive = item['is_active'] == true;
                final bannerId = item['banner_id']?.toString() ?? '';
                final title = item['title'] ?? 'Offer Deal';
                final price = item['offer_price'] ?? 65;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AdminColors.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.local_offer_rounded, color: AdminColors.primaryDark, size: 20),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  subtitle: Text(
                    'ID: $bannerId  •  Price: ₹$price  •  Stock: ${item['stock_remaining'] ?? 75}',
                    style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary),
                  ),
                  trailing: isActive
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AdminColors.primaryLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Active Live',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AdminColors.primaryDark,
                            ),
                          ),
                        )
                      : OutlinedButton(
                          onPressed: () => _setActiveBanner(bannerId),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text('Make Active', style: TextStyle(fontSize: 11)),
                        ),
                );
              },
            ),
        ],
      ),
    );
  }
}


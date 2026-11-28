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
  bool _hasEditedStockField = false;
  bool _isSavingStock = false;
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

  // =========================================================================
  // 🎠 REGULAR USER SLIDING BANNERS (HOMEPAGE CAROUSEL) STATES
  // =========================================================================
  int _selectedBannerType = 0; // 0 = First-Time Special Offer, 1 = Regular Sliding Carousel Banners, 2 = Quick Cravings, 3 = Preferred Hotels
  List<dynamic> slidingBanners = [];
  bool isLoadingSliding = false;
  bool isUploadingSliding = false;

  // Preferred Hotels Manager States
  List<dynamic> preferredHotels = [];
  bool isLoadingHotels = false;
  bool isSavingHotel = false;
  final _hotelNameController = TextEditingController();
  final _hotelAreaController = TextEditingController();

  final _slidingTitleController = TextEditingController(text: 'Chicken Biryani Special');
  final _slidingItemController = TextEditingController(text: 'Chicken Biryani');
  final _slidingTagController = TextEditingController(text: 'CRUSHING OFFER');
  final _slidingOfferPriceController = TextEditingController(text: '49');
  final _slidingOriginalPriceController = TextEditingController(text: '150');
  final _slidingImageUrlController = TextEditingController();
  final _slidingBase64Controller = TextEditingController();

  String _selectedSlidingUploadTab = 'device'; // 'device', 'presets', 'url', 'base64'
  Uint8List? _slidingPickedBytes;
  String? _slidingPickedBase64;
  String? _slidingPickedName;
  String? _slidingPreviewImage;

  final List<Map<String, String>> curatedSlidingPresets = [
    {
      'title': 'Woodfired Chicken Dum Biriyani',
      'item': 'Chicken Biryani',
      'price': '49',
      'orig': '150',
      'badge': 'CRUSHING OFFER',
      'imageUrl': 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=800&q=80',
    },
    {
      'title': 'Hot & Spicy Chicken Shawarma',
      'item': 'Chicken Shawarma',
      'price': '30',
      'orig': '110',
      'badge': 'CRUSHING OFFER',
      'imageUrl': 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?w=800&q=80',
    },
    {
      'title': 'Hot & Steamy Momos',
      'item': 'Hot & Steamy Momos',
      'price': '39',
      'orig': '120',
      'badge': 'CRUSHING OFFER',
      'imageUrl': 'https://images.unsplash.com/photo-1625246333195-78d9c38ad449?w=800&q=80',
    },
    {
      'title': 'Crispy Chicken Fried Rice',
      'item': 'Chicken Fried Rice',
      'price': '55',
      'orig': '130',
      'badge': 'BEST DEAL',
      'imageUrl': 'https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=800&q=80',
    },
    {
      'title': 'Golden Crispy Chicken 65',
      'item': 'Chicken 65',
      'price': '65',
      'orig': '140',
      'badge': 'CHEF SPECIAL',
      'imageUrl': 'https://images.unsplash.com/photo-1610057099431-d73a1c9d2f2f?w=800&q=80',
    },
  ];

  // =========================================================================
  // 🥘 QUICK CRAVINGS (HOMEPAGE FOOD SUGGESTIONS) STATES
  // =========================================================================
  List<dynamic> quickCravings = [];
  bool isLoadingCravings = false;
  bool isUploadingCraving = false;

  final _cravingNameController = TextEditingController(text: 'Chicken Biryani');
  final _cravingRatingController = TextEditingController(text: '4.5');
  final _cravingBudgetController = TextEditingController(text: '49');
  final _cravingTimeController = TextEditingController(text: '20-25 mins');
  final _cravingCuisineController = TextEditingController(text: 'Biryani • North Indian');
  final _cravingIconController = TextEditingController(text: '🍗');
  final _cravingImageUrlController = TextEditingController();
  final _cravingBase64Controller = TextEditingController();

  bool _cravingIsVeg = false;
  String _selectedCravingUploadTab = 'device'; // 'device', 'presets', 'url', 'base64'
  Uint8List? _cravingPickedBytes;
  String? _cravingPickedBase64;
  String? _cravingPickedName;
  String? _cravingPreviewImage;

  final List<Map<String, dynamic>> curatedCravingPresets = [
    {
      'name': 'Chicken Biryani',
      'budget': '49',
      'rating': '4.5',
      'time': '20-25 mins',
      'cuisine': 'Biryani • North Indian',
      'icon': '🍗',
      'isVeg': false,
      'imageUrl': 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=800&q=80',
    },
    {
      'name': 'Chicken Shawarma',
      'budget': '30',
      'rating': '4.6',
      'time': '15-20 mins',
      'cuisine': 'Rolls & Fast Food',
      'icon': '🌯',
      'isVeg': false,
      'imageUrl': 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?w=800&q=80',
    },
    {
      'name': 'Hot Momos',
      'budget': '39',
      'rating': '4.4',
      'time': '15-20 mins',
      'cuisine': 'Chinese • Street Food',
      'icon': '🥟',
      'isVeg': false,
      'imageUrl': 'https://images.unsplash.com/photo-1625246333195-78d9c38ad449?w=800&q=80',
    },
    {
      'name': 'Crispy Dosa with Sambar',
      'budget': '60',
      'rating': '4.7',
      'time': '10-15 mins',
      'cuisine': 'South Indian • Tiffin',
      'icon': '🥞',
      'isVeg': true,
      'imageUrl': 'https://images.unsplash.com/photo-1668236543090-82eba5ee5976?w=800&q=80',
    },
    {
      'name': 'Paneer Butter Masala',
      'budget': '120',
      'rating': '4.5',
      'time': '20-25 mins',
      'cuisine': 'North Indian • Curry',
      'icon': '🍛',
      'isVeg': true,
      'imageUrl': 'https://images.unsplash.com/photo-1631452180519-c014fe946bc7?w=800&q=80',
    },
    {
      'name': 'Chicken 65',
      'budget': '110',
      'rating': '4.6',
      'time': '15-20 mins',
      'cuisine': 'Starters • Appetizers',
      'icon': '🍗',
      'isVeg': false,
      'imageUrl': 'https://images.unsplash.com/photo-1610057099431-d73a1c9d2f2f?w=800&q=80',
    },
    {
      'name': 'Chicken Fried Rice',
      'budget': '110',
      'rating': '4.3',
      'time': '20-25 mins',
      'cuisine': 'Chinese • Fast Food',
      'icon': '🍚',
      'isVeg': false,
      'imageUrl': 'https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=800&q=80',
    },
    {
      'name': 'Fresh Mango Juice',
      'budget': '50',
      'rating': '4.8',
      'time': '10-15 mins',
      'cuisine': 'Beverages • Shakes',
      'icon': '🥭',
      'isVeg': true,
      'imageUrl': 'https://images.unsplash.com/photo-1546173159-315724a31696?w=800&q=80',
    },
  ];

  @override
  void initState() {
    super.initState();
    fetchActiveBanner();
    fetchBannerHistory();
    fetchScheduleStatus();
    fetchSlidingBanners();
    fetchQuickCravings();
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
    _slidingTitleController.dispose();
    _slidingItemController.dispose();
    _slidingTagController.dispose();
    _slidingOfferPriceController.dispose();
    _slidingOriginalPriceController.dispose();
    _slidingImageUrlController.dispose();
    _slidingBase64Controller.dispose();
    _cravingNameController.dispose();
    _cravingRatingController.dispose();
    _cravingBudgetController.dispose();
    _cravingTimeController.dispose();
    _cravingCuisineController.dispose();
    _cravingIconController.dispose();
    _cravingImageUrlController.dispose();
    _cravingBase64Controller.dispose();
    _hotelNameController.dispose();
    _hotelAreaController.dispose();
    super.dispose();
  }

  Future<void> fetchActiveBanner({bool silent = false}) async {
    if (!silent) setState(() => isLoading = true);
    try {
      final res = await http.get(AdminApiConfig.bannerActive);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['banner'] != null) {
          final b = decoded['banner'] as Map<String, dynamic>;
          setState(() {
            activeBanner = b;
            isLoading = false;
            if (!_hasEditedStockField) {
              if (b['stock_remaining'] != null) {
                _stockRemainingController.text = b['stock_remaining'].toString();
              }
              if (b['total_stock'] != null) {
                _totalStockController.text = b['total_stock'].toString();
              }
            }
          });
        }
      }
    } catch (_) {
      if (mounted && !silent) setState(() => isLoading = false);
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

  // =========================================================================
  // 🎠 SLIDING BANNERS API HANDLERS
  // =========================================================================
  Future<void> fetchSlidingBanners() async {
    setState(() => isLoadingSliding = true);
    try {
      final res = await http.get(AdminApiConfig.bannerSlidingAll);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['banners'] is List) {
          setState(() {
            slidingBanners = decoded['banners'] as List;
            isLoadingSliding = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => isLoadingSliding = false);
  }

  Future<void> _pickSlidingImage(ImageSource source) async {
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 700,
        imageQuality: 85,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        setState(() {
          _slidingPickedBytes = bytes;
          _slidingPickedBase64 = 'data:image/jpeg;base64,$base64Str';
          _slidingPickedName = file.name;
          _slidingPreviewImage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting image: $e'), backgroundColor: AdminColors.danger),
        );
      }
    }
  }

  Future<void> _publishSlidingBanner() async {
    final itemText = _slidingItemController.text.trim();
    if (itemText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an item name (e.g. Chicken Biryani)'), backgroundColor: AdminColors.danger),
      );
      return;
    }

    setState(() => isUploadingSliding = true);

    String? finalBase64;
    String? finalUrl;

    if (_selectedSlidingUploadTab == 'device') {
      if (_slidingPickedBase64 == null) {
        if (!mounted) return;
        setState(() => isUploadingSliding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select an image from your device first!'),
            backgroundColor: AdminColors.danger,
          ),
        );
        return;
      }
      finalBase64 = _slidingPickedBase64;
    } else if (_selectedSlidingUploadTab == 'base64' && _slidingBase64Controller.text.trim().isNotEmpty) {
      finalBase64 = _slidingBase64Controller.text.trim();
    } else if (_selectedSlidingUploadTab == 'url' && _slidingImageUrlController.text.trim().isNotEmpty) {
      finalUrl = _slidingImageUrlController.text.trim();
    } else if (_selectedSlidingUploadTab == 'presets' && _slidingPreviewImage != null) {
      finalUrl = _slidingPreviewImage;
    }

    try {
      final res = await http.post(
        AdminApiConfig.bannerSlidingUpload,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'title': _slidingTitleController.text.trim().isNotEmpty ? _slidingTitleController.text.trim() : itemText,
          'item': itemText,
          'tag': _slidingTagController.text.trim().isNotEmpty ? _slidingTagController.text.trim() : 'CRUSHING OFFER',
          'offer_price': int.tryParse(_slidingOfferPriceController.text) ?? 49,
          'budget': int.tryParse(_slidingOfferPriceController.text) ?? 49,
          'original_price': int.tryParse(_slidingOriginalPriceController.text) ?? 150,
          'image_base64': finalBase64,
          'image_url': finalUrl,
          'is_active': true,
        }),
      );

      if (!mounted) return;
      setState(() => isUploadingSliding = false);

      if (res.statusCode == 200 || res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Sliding banner uploaded & live on Regular Customer Homepage!')),
              ],
            ),
            backgroundColor: AdminColors.success,
          ),
        );
        setState(() {
          _slidingPickedBytes = null;
          _slidingPickedBase64 = null;
          _slidingPickedName = null;
          _slidingPreviewImage = null;
          _slidingImageUrlController.clear();
          _slidingBase64Controller.clear();
        });
        fetchSlidingBanners();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish: HTTP ${res.statusCode}'), backgroundColor: AdminColors.danger),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => isUploadingSliding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading: $e'), backgroundColor: AdminColors.danger),
        );
      }
    }
  }

  Future<void> _toggleSlidingBanner(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return;

    // 1. Optimistic UI update so the Switch flips immediately on screen!
    final index = slidingBanners.indexWhere((b) => (b['banner_id'] ?? b['_id'] ?? '').toString() == cleanId);
    if (index != -1) {
      setState(() {
        final cur = slidingBanners[index]['is_active'] == true;
        slidingBanners[index]['is_active'] = !cur;
      });
    }

    try {
      final res = await http.post(AdminApiConfig.bannerSlidingToggle(cleanId));
      if (res.statusCode == 200) {
        fetchSlidingBanners();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to toggle: HTTP ${res.statusCode}'), backgroundColor: AdminColors.danger),
        );
        fetchSlidingBanners();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Network error: $e'), backgroundColor: AdminColors.danger),
      );
      fetchSlidingBanners();
    }
  }

  Future<void> _deleteSlidingBanner(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sliding Banner?'),
        content: const Text('Are you sure you want to remove this banner from the customer homepage carousel?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Optimistic remove from UI list immediately!
    setState(() {
      slidingBanners.removeWhere((b) => (b['banner_id'] ?? b['_id'] ?? '').toString() == cleanId);
    });

    try {
      final res = await http.delete(AdminApiConfig.bannerSlidingDelete(cleanId));
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Banner deleted successfully'), backgroundColor: AdminColors.success),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: HTTP ${res.statusCode}'), backgroundColor: AdminColors.danger),
        );
      }
      fetchSlidingBanners();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: AdminColors.danger),
      );
      fetchSlidingBanners();
    }
  }

  // =========================================================================
  // 🥘 QUICK CRAVINGS API HANDLERS
  // =========================================================================
  Future<void> fetchQuickCravings() async {
    setState(() => isLoadingCravings = true);
    try {
      final res = await http.get(AdminApiConfig.quickCravingsAll);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['cravings'] is List) {
          setState(() {
            quickCravings = decoded['cravings'] as List;
            isLoadingCravings = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => isLoadingCravings = false);
  }

  Future<void> _pickCravingImage(ImageSource source) async {
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        setState(() {
          _cravingPickedBytes = bytes;
          _cravingPickedBase64 = 'data:image/jpeg;base64,$base64Str';
          _cravingPickedName = file.name;
          _cravingPreviewImage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting image: $e'), backgroundColor: AdminColors.danger),
        );
      }
    }
  }

  Future<void> _publishQuickCraving() async {
    final nameText = _cravingNameController.text.trim();
    if (nameText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a dish name (e.g. Chicken Biryani)'), backgroundColor: AdminColors.danger),
      );
      return;
    }

    String? finalImageBase64;
    String? finalImageUrl;

    if (_selectedCravingUploadTab == 'device') {
      if (_cravingPickedBase64 != null && _cravingPickedBase64!.isNotEmpty) {
        finalImageBase64 = _cravingPickedBase64;
      } else if (_cravingPreviewImage != null && _cravingPreviewImage!.isNotEmpty) {
        if (_cravingPreviewImage!.startsWith('http://') || _cravingPreviewImage!.startsWith('https://')) {
          finalImageUrl = _cravingPreviewImage;
        } else if (_cravingPreviewImage!.startsWith('data:image')) {
          finalImageBase64 = _cravingPreviewImage;
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an image from your device or choose a preset'), backgroundColor: AdminColors.danger),
        );
        return;
      }
    } else if (_selectedCravingUploadTab == 'presets') {
      if (_cravingPreviewImage != null && _cravingPreviewImage!.isNotEmpty) {
        finalImageUrl = _cravingPreviewImage;
      } else {
        final match = curatedCravingPresets.firstWhere(
          (p) => p['name'].toString().toLowerCase() == nameText.toLowerCase(),
          orElse: () => curatedCravingPresets.first,
        );
        finalImageUrl = match['imageUrl'];
      }
    } else if (_selectedCravingUploadTab == 'url') {
      final url = _cravingImageUrlController.text.trim();
      if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid HTTP/HTTPS image URL'), backgroundColor: AdminColors.danger),
        );
        return;
      }
      finalImageUrl = url;
    } else if (_selectedCravingUploadTab == 'base64') {
      final b64 = _cravingBase64Controller.text.trim();
      if (b64.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please paste a base64 image string'), backgroundColor: AdminColors.danger),
        );
        return;
      }
      finalImageBase64 = b64.startsWith('data:image') ? b64 : 'data:image/jpeg;base64,$b64';
    }

    if ((finalImageBase64 == null || finalImageBase64.isEmpty) &&
        (finalImageUrl == null || finalImageUrl.isEmpty)) {
      final match = curatedCravingPresets.firstWhere(
        (p) => p['name'].toString().toLowerCase() == nameText.toLowerCase(),
        orElse: () => curatedCravingPresets.first,
      );
      finalImageUrl = match['imageUrl'];
    }

    setState(() => isUploadingCraving = true);

    try {
      final rating = _cravingRatingController.text.trim().isEmpty ? '4.5' : _cravingRatingController.text.trim();
      final budget = _cravingBudgetController.text.trim().isEmpty ? '49' : _cravingBudgetController.text.trim();
      final time = _cravingTimeController.text.trim().isEmpty ? '20-25 mins' : _cravingTimeController.text.trim();
      final cuisine = _cravingCuisineController.text.trim().isEmpty ? 'Special Delights' : _cravingCuisineController.text.trim();
      final icon = _cravingIconController.text.trim().isEmpty ? (_cravingIsVeg ? '🥗' : '🍗') : _cravingIconController.text.trim();

      final payload = {
        'name': nameText,
        'rating': rating,
        'budget': budget,
        'time': time,
        'cuisine': cuisine,
        'icon': icon,
        'isVeg': _cravingIsVeg,
        'image_base64': finalImageBase64,
        'image_url': finalImageUrl,
        'fallback_asset': _cravingIsVeg ? 'assets/craving_dosa.jpg' : 'assets/banner_biryani_crushing.jpg',
        'is_active': true,
      };

      final res = await http.post(
        AdminApiConfig.quickCravingsUpload,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (res.statusCode == 201 || res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 "$nameText" added to Quick Cravings!'),
              backgroundColor: AdminColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          fetchQuickCravings();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: HTTP ${res.statusCode}'), backgroundColor: AdminColors.danger),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload error: $e'), backgroundColor: AdminColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => isUploadingCraving = false);
    }
  }

  Future<void> _toggleCravingActive(String id, bool currentStatus) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return;

    final newStatus = !currentStatus;
    setState(() {
      final index = quickCravings.indexWhere((c) => (c['craving_id'] ?? c['_id'] ?? '').toString() == cleanId);
      if (index != -1) {
        quickCravings[index]['is_active'] = newStatus;
      }
    });

    try {
      final res = await http.post(AdminApiConfig.quickCravingsToggle(cleanId));
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus ? 'Quick Craving activated' : 'Quick Craving deactivated'),
            backgroundColor: newStatus ? AdminColors.success : AdminColors.warning,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        fetchQuickCravings();
      }
    } catch (_) {
      fetchQuickCravings();
    }
  }

  Future<void> _deleteQuickCraving(String id, String name) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text('Are you sure you want to remove this item from customer Quick Cravings?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      quickCravings.removeWhere((c) => (c['craving_id'] ?? c['_id'] ?? '').toString() == cleanId);
    });

    try {
      final res = await http.delete(AdminApiConfig.quickCravingsDelete(cleanId));
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$name" deleted successfully'), backgroundColor: AdminColors.success),
        );
      } else {
        fetchQuickCravings();
      }
    } catch (_) {
      fetchQuickCravings();
    }
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
      if (timer.tick % 10 == 0) {
        fetchActiveBanner(silent: true);
      }

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
        _hasEditedStockField = false;
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
    final current = int.tryParse(activeBanner?['stock_remaining']?.toString() ?? '') ??
        int.tryParse(_stockRemainingController.text) ??
        0;
    final newCount = (current + delta).clamp(0, 5000);
    _stockRemainingController.text = newCount.toString();
    _hasEditedStockField = false;

    try {
      await http.put(
        AdminApiConfig.bannerStock,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'stock_remaining': newCount}),
      );
      fetchActiveBanner(silent: true);
    } catch (_) {}
  }

  Future<void> _saveStockOnly() async {
    final rem = int.tryParse(_stockRemainingController.text.trim());
    final tot = int.tryParse(_totalStockController.text.trim());
    if (rem == null || rem < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid remaining stock count'), backgroundColor: AdminColors.danger),
      );
      return;
    }

    setState(() => _isSavingStock = true);
    try {
      final res = await http.put(
        AdminApiConfig.bannerStock,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'stock_remaining': rem,
          if (tot != null && tot >= 0) 'total_stock': tot,
        }),
      );
      if (!mounted) return;
      setState(() {
        _isSavingStock = false;
        _hasEditedStockField = false;
      });
      if (res.statusCode == 200) {
        await fetchActiveBanner(silent: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stock updated to $rem!'),
            backgroundColor: AdminColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update stock (${res.statusCode})'), backgroundColor: AdminColors.danger),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingStock = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating stock: $e'), backgroundColor: AdminColors.danger),
        );
      }
    }
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
              fetchSlidingBanners();
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
              fetchSlidingBanners();
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
                // 🌟 Mode Selection Switcher: First-Time Offer Banner vs Regular User Sliding Banners
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 20),
                  child: SegmentedButton<int>(
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                        if (states.contains(WidgetState.selected)) {
                          return AdminColors.primary;
                        }
                        return Colors.white;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.white;
                        }
                        return AdminColors.textPrimary;
                      }),
                      padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 14)),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    segments: const [
                      ButtonSegment<int>(
                        value: 0,
                        icon: Icon(Icons.local_offer_rounded),
                        label: Text('First-Time Offer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        icon: Icon(Icons.view_carousel_rounded),
                        label: Text('Sliding Banners', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      ButtonSegment<int>(
                        value: 2,
                        icon: Icon(Icons.restaurant_menu_rounded),
                        label: Text('Quick Cravings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      ButtonSegment<int>(
                        value: 3,
                        icon: Icon(Icons.apartment_rounded),
                        label: Text('Preferred Hotels', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ],
                    selected: {_selectedBannerType},
                    onSelectionChanged: (newSelection) {
                      setState(() => _selectedBannerType = newSelection.first);
                      if (_selectedBannerType == 1) {
                        fetchSlidingBanners();
                      } else if (_selectedBannerType == 2) {
                        fetchQuickCravings();
                      } else if (_selectedBannerType == 3) {
                        fetchPreferredHotels();
                      }
                    },
                  ),
                ),

                if (_selectedBannerType == 0) ...[
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
              ] else if (_selectedBannerType == 1) ...[
                // Regular User Sliding Banners (Carousel) Manager
                _buildSlidingBannersSection(),
              ] else if (_selectedBannerType == 2) ...[
                // Quick Cravings (Food Suggestions) Manager
                _buildQuickCravingsSection(),
              ] else ...[
                // Preferred Hotels (Dropdown List) Manager
                _buildPreferredHotelsSection(),
              ],
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
    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : (activeBanner?['title'] ?? 'Special Dum Biriyani Deal');
    final badge = _badgeController.text.trim().isNotEmpty
        ? _badgeController.text.trim()
        : (activeBanner?['badge'] ?? "TODAY'S SPECIAL");
    final offerPrice = _offerPriceController.text.trim().isNotEmpty
        ? _offerPriceController.text.trim()
        : (activeBanner?['offer_price'] ?? '65');
    final origPrice = _originalPriceController.text.trim().isNotEmpty
        ? _originalPriceController.text.trim()
        : (activeBanner?['original_price'] ?? '120');
    final remainingStock = _stockRemainingController.text.trim().isNotEmpty
        ? _stockRemainingController.text.trim()
        : (activeBanner?['stock_remaining'] ?? '75');
    final totalStock = _totalStockController.text.trim().isNotEmpty
        ? _totalStockController.text.trim()
        : (activeBanner?['total_stock'] ?? '100');

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
                onPressed: () => _updateQuickStock(-1),
                style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              Text(
                '${activeBanner?['stock_remaining'] ?? remainingStock}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                icon: const Icon(Icons.add, size: 16),
                onPressed: () => _updateQuickStock(1),
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
                  onChanged: (_) => setState(() {}),
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
                  onChanged: (_) => setState(() {}),
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
                  onChanged: (_) => _hasEditedStockField = true,
                  decoration: const InputDecoration(
                    labelText: 'Remaining Stock',
                    hintText: '25',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _totalStockController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _hasEditedStockField = true,
                  decoration: const InputDecoration(
                    labelText: 'Total Daily Stock',
                    hintText: '25',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSavingStock ? null : _saveStockOnly,
              icon: _isSavingStock
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.inventory_2_rounded, size: 16),
              label: const Text('Update Stock Only (Keep Current Banner)'),
            ),
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

  // =========================================================================
  // 🎠 REGULAR USER SLIDING BANNERS (HOMEPAGE CAROUSEL) WIDGETS
  // =========================================================================

  Widget _buildSlidingBannersSection() {
    return Column(
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
                child: const Icon(Icons.view_carousel_rounded, color: AdminColors.primaryDark, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Regular Customer Homepage - Sliding Carousel Banners',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AdminColors.primaryDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Upload banners that auto-slide in 1024x571 aspect ratio on the customer app. When a customer taps any banner, the food item name and offer price will auto-fill into their order form!',
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

        // Layout: Two columns on wider screens, stacked on mobile
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            return Flex(
              direction: isWide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Live Preview & Existing Banners List
                Expanded(
                  flex: isWide ? 5 : 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSlidingLivePreview(),
                      const SizedBox(height: 20),
                      _buildSlidingBannersList(),
                    ],
                  ),
                ),
                if (isWide) const SizedBox(width: 20) else const SizedBox(height: 20),

                // Right Column: Upload New Banner Form
                Expanded(
                  flex: isWide ? 5 : 0,
                  child: _buildSlidingUploadForm(),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSlidingLivePreview() {
    final title = _slidingTitleController.text.trim().isNotEmpty
        ? _slidingTitleController.text.trim()
        : 'Special Offer Deal';
    final item = _slidingItemController.text.trim().isNotEmpty
        ? _slidingItemController.text.trim()
        : 'Chicken Biryani';
    final tag = _slidingTagController.text.trim().isNotEmpty
        ? _slidingTagController.text.trim()
        : 'CRUSHING OFFER';
    final offerPrice = _slidingOfferPriceController.text.trim().isNotEmpty
        ? _slidingOfferPriceController.text.trim()
        : '49';
    final origPrice = _slidingOriginalPriceController.text.trim().isNotEmpty
        ? _slidingOriginalPriceController.text.trim()
        : '150';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.remove_red_eye_rounded, size: 18, color: AdminColors.primary),
                  SizedBox(width: 6),
                  Text(
                    'Live Customer App Preview',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '1024 : 571 Ratio',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Exact Aspect Ratio Card (1024 x 571) as in Customer App!
          AspectRatio(
            aspectRatio: 1024 / 571,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background Image
                    _buildSlidingPreviewImageWidget(),

                    // Dark gradient overlay for text readability
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.25),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.8),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Top Left Tag Badge
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),

                    // Bottom Information Overlay
                    Positioned(
                      bottom: 10,
                      left: 12,
                      right: 12,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Pre-fills: "$item"',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Price Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16A34A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (origPrice.isNotEmpty) ...[
                                  Text(
                                    '₹$origPrice',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 10,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  '₹$offerPrice',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.touch_app_rounded, size: 14, color: AdminColors.primary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Customer Action: Tapping this in app sets Order Item="$item" & Budget=₹$offerPrice',
                  style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlidingPreviewImageWidget() {
    if (_slidingPickedBytes != null) {
      return Image.memory(_slidingPickedBytes!, fit: BoxFit.cover);
    }
    if (_slidingPreviewImage != null && _slidingPreviewImage!.isNotEmpty) {
      if (_slidingPreviewImage!.startsWith('http://') || _slidingPreviewImage!.startsWith('https://')) {
        return Image.network(
          _slidingPreviewImage!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildSlidingPlaceholder(),
        );
      }
    }
    final urlText = _slidingImageUrlController.text.trim();
    if (urlText.isNotEmpty && (urlText.startsWith('http://') || urlText.startsWith('https://'))) {
      return Image.network(
        urlText,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildSlidingPlaceholder(),
      );
    }
    return _buildSlidingPlaceholder();
  }

  Widget _buildSlidingPlaceholder() {
    return Container(
      color: const Color(0xFF1E293B),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 40, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(height: 6),
            Text(
              'Select or Upload an Image (1024x571)',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlidingBannersList() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.collections_rounded, size: 18, color: AdminColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'All Uploaded Carousel Banners (${slidingBanners.length})',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Refresh Banners',
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: fetchSlidingBanners,
              ),
            ],
          ),
          const Divider(height: 16),
          if (isLoadingSliding)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (slidingBanners.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.view_carousel_outlined, size: 36, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    const Text(
                      'No custom sliding banners yet.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AdminColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Default app banners (Biryani, Shawarma, Momos) are currently displayed in Customer App.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: AdminColors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: slidingBanners.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (context, index) {
                final b = slidingBanners[index] as Map<String, dynamic>;
                final bId = (b['banner_id'] ?? b['_id'] ?? '').toString().trim();
                final bTitle = b['title'] ?? b['item'] ?? 'Offer';
                final bItem = b['item'] ?? bTitle;
                final bTag = b['tag'] ?? 'CRUSHING OFFER';
                final bOffer = b['offer_price'] ?? 49;
                final bOrig = b['original_price'] ?? 150;
                final isActive = b['is_active'] == true;
                final imgUrl = b['image_url'] as String?;
                final base64 = b['image_base64'] as String?;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: imgUrl != null && imgUrl.isNotEmpty
                          ? Image.network(
                              imgUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200, child: const Icon(Icons.broken_image, size: 20)),
                            )
                          : (base64 != null && base64.isNotEmpty
                              ? Image.memory(
                                  base64Decode(base64.contains(',') ? base64.split(',')[1] : base64),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200, child: const Icon(Icons.broken_image, size: 20)),
                                )
                              : Container(color: Colors.grey.shade200, child: const Icon(Icons.fastfood_rounded, size: 20))),
                    ),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          bTitle,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          bTag,
                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    'Item: $bItem • Offer: ₹$bOffer (Orig: ₹$bOrig)',
                    style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: isActive,
                        activeColor: AdminColors.primary,
                        onChanged: (_) => _toggleSlidingBanner(bId),
                      ),
                      IconButton(
                        tooltip: 'Delete Banner',
                        icon: const Icon(Icons.delete_outline_rounded, color: AdminColors.danger, size: 20),
                        onPressed: () => _deleteSlidingBanner(bId),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSlidingUploadForm() {
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
            'Add / Upload New Carousel Banner',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AdminColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Select banner photo and set the deal price & auto-fill food item.',
            style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
          ),
          const SizedBox(height: 16),

          // Upload Tabs
          Row(
            children: [
              _buildSlidingTabButton('device', 'Device', Icons.phone_android_rounded),
              const SizedBox(width: 6),
              _buildSlidingTabButton('presets', 'Presets', Icons.auto_awesome_rounded),
              const SizedBox(width: 6),
              _buildSlidingTabButton('url', 'URL', Icons.link_rounded),
              const SizedBox(width: 6),
              _buildSlidingTabButton('base64', 'Base64', Icons.code_rounded),
            ],
          ),
          const SizedBox(height: 14),

          // Tab Content
          if (_selectedSlidingUploadTab == 'device') ...[
            if (_slidingPickedBytes == null)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AdminColors.border, style: BorderStyle.solid),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_upload_outlined, size: 36, color: AdminColors.primary),
                      const SizedBox(height: 8),
                      const Text(
                        'Upload Promotional Banner',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AdminColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Recommended: 1024 x 571 Landscape image',
                        style: TextStyle(fontSize: 11, color: AdminColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AdminColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.photo_library_rounded, size: 16),
                            label: const Text('Choose Photo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () => _pickSlidingImage(ImageSource.gallery),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AdminColors.textPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.camera_alt_rounded, size: 16),
                            label: const Text('Camera', style: TextStyle(fontSize: 12)),
                            onPressed: () => _pickSlidingImage(ImageSource.camera),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: Image.memory(_slidingPickedBytes!, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ready to Upload', style: TextStyle(color: Color(0xFF166534), fontWeight: FontWeight.w800, fontSize: 12)),
                          Text(
                            _slidingPickedName ?? 'device_banner.jpg',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AdminColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text('${(_slidingPickedBytes!.lengthInBytes / 1024).toStringAsFixed(1)} KB', style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: AdminColors.danger),
                      onPressed: () {
                        setState(() {
                          _slidingPickedBytes = null;
                          _slidingPickedBase64 = null;
                          _slidingPickedName = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
          ] else if (_selectedSlidingUploadTab == 'presets') ...[
            const Text('Tap any preset to auto-fill image and details:', style: TextStyle(fontSize: 11, color: AdminColors.textSecondary)),
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: curatedSlidingPresets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, idx) {
                  final p = curatedSlidingPresets[idx];
                  final isSelected = _slidingPreviewImage == p['imageUrl'];
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _slidingPreviewImage = p['imageUrl'];
                        _slidingPickedBytes = null;
                        _slidingPickedBase64 = null;
                        _slidingTitleController.text = p['title'] ?? '';
                        _slidingItemController.text = p['item'] ?? '';
                        _slidingTagController.text = p['badge'] ?? 'CRUSHING OFFER';
                        _slidingOfferPriceController.text = p['price'] ?? '49';
                        _slidingOriginalPriceController.text = p['orig'] ?? '150';
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 120,
                      decoration: BoxDecoration(
                        color: isSelected ? AdminColors.primaryLight : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AdminColors.primary : AdminColors.border,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(p['imageUrl']!, fit: BoxFit.cover, width: double.infinity),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(p['item']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5), maxLines: 1),
                          Text('₹${p['price']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Color(0xFF16A34A))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else if (_selectedSlidingUploadTab == 'url') ...[
            TextField(
              controller: _slidingImageUrlController,
              decoration: InputDecoration(
                labelText: 'Direct Image URL (https://...)',
                hintText: 'https://example.com/banner.jpg',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check_circle_rounded, color: AdminColors.primary),
                  onPressed: () {
                    setState(() {
                      _slidingPreviewImage = _slidingImageUrlController.text.trim();
                      _slidingPickedBytes = null;
                    });
                  },
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _slidingPreviewImage = val.trim();
                  _slidingPickedBytes = null;
                });
              },
            ),
          ] else ...[
            TextField(
              controller: _slidingBase64Controller,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Base64 Image String',
                hintText: 'data:image/jpeg;base64,...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (val) {
                if (val.trim().isNotEmpty) {
                  try {
                    final clean = val.contains(',') ? val.split(',')[1] : val;
                    final bytes = base64Decode(clean);
                    setState(() {
                      _slidingPickedBytes = bytes;
                      _slidingPickedBase64 = val.trim();
                      _slidingPreviewImage = null;
                    });
                  } catch (_) {}
                }
              },
            ),
          ],
          const SizedBox(height: 18),

          // Form Fields: Food Item, Title, Tag, Prices
          TextField(
            controller: _slidingItemController,
            decoration: InputDecoration(
              labelText: 'Food Item Name (Auto-fills Order Form) *',
              hintText: 'e.g. Chicken Biryani, Chicken Shawarma',
              prefixIcon: const Icon(Icons.fastfood_rounded, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (val) => setState(() {}),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _slidingTitleController,
            decoration: InputDecoration(
              labelText: 'Banner Title Heading',
              hintText: 'e.g. Chicken Dum Biryani Special',
              prefixIcon: const Icon(Icons.title_rounded, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (val) => setState(() {}),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _slidingTagController,
                  decoration: InputDecoration(
                    labelText: 'Offer Badge Tag',
                    hintText: 'e.g. CRUSHING OFFER',
                    prefixIcon: const Icon(Icons.local_offer_rounded, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (val) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _slidingOfferPriceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Offer Price / Budget (₹)',
                    hintText: '49',
                    prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (val) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _slidingOriginalPriceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Original (₹)',
                    hintText: '150',
                    prefixIcon: const Icon(Icons.money_off_rounded, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (val) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Publish Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: isUploadingSliding ? null : _publishSlidingBanner,
              icon: isUploadingSliding
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_rounded, size: 20),
              label: Text(
                isUploadingSliding ? 'Publishing Sliding Banner...' : 'Publish Sliding Banner to Customer App',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlidingTabButton(String tabKey, String label, IconData icon) {
    final isSelected = _selectedSlidingUploadTab == tabKey;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedSlidingUploadTab = tabKey),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AdminColors.primaryLight : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AdminColors.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isSelected ? AdminColors.primaryDark : AdminColors.textSecondary),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? AdminColors.primaryDark : AdminColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 🥘 QUICK CRAVINGS (HOMEPAGE FOOD SUGGESTIONS) UI BUILDERS
  // =========================================================================

  Widget _buildQuickCravingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Explanatory Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.restaurant_menu_rounded, color: Color(0xFFD97706), size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Cravings Food Suggestions Manager',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF92400E),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Manage dishes displayed in the horizontal "Quick Cravings" section on customer homepage. Customers can tap any dish to auto-fill their order form!',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFFB45309)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            return Flex(
              direction: isWide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Live Preview & Cravings List
                Expanded(
                  flex: isWide ? 5 : 0,
                  child: Column(
                    children: [
                      _buildQuickCravingLivePreview(),
                      const SizedBox(height: 20),
                      _buildQuickCravingsList(),
                    ],
                  ),
                ),
                if (isWide) const SizedBox(width: 20) else const SizedBox(height: 20),

                // Right Column: Upload Form
                Expanded(
                  flex: isWide ? 5 : 0,
                  child: _buildQuickCravingUploadForm(),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildQuickCravingLivePreview() {
    final nameText = _cravingNameController.text.trim().isEmpty ? 'Chicken Biryani' : _cravingNameController.text.trim();
    final ratingText = _cravingRatingController.text.trim().isEmpty ? '4.5' : _cravingRatingController.text.trim();
    final budgetText = _cravingBudgetController.text.trim().isEmpty ? '49' : _cravingBudgetController.text.trim();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.remove_red_eye_outlined, size: 18, color: AdminColors.primary),
                  SizedBox(width: 8),
                  Text(
                    'Customer Card Live Preview',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '118 x 112 Compact Card',
                  style: TextStyle(color: Color(0xFFB45309), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Live Customer App Item Mockup
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: SizedBox(
                width: 118,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Food Image Card
                    Container(
                      width: 118,
                      height: 112,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildQuickCravingPreviewImageWidget(),
                            // Top-Right: Heart Icon
                            Positioned(
                              top: 7,
                              right: 7,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.favorite_border_rounded, color: Colors.white, size: 15),
                              ),
                            ),
                            // Top-Left: Veg / Non-Veg Indicator
                            Positioned(
                              top: 7,
                              left: 7,
                              child: Container(
                                padding: const EdgeInsets.all(2.5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 3,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.circle,
                                  size: 6,
                                  color: _cravingIsVeg ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Dish Name
                    Text(
                      nameText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),

                    // Rating & Price Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(1.5),
                              decoration: const BoxDecoration(
                                color: Color(0xFF15803D),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.star_rounded, size: 9.5, color: Colors.white),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              ratingText,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '₹$budgetText',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AdminColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickCravingPreviewImageWidget() {
    if (_cravingPickedBytes != null) {
      return Image.memory(
        _cravingPickedBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildQuickCravingPlaceholder(),
      );
    } else if (_cravingPreviewImage != null && _cravingPreviewImage!.isNotEmpty) {
      if (_cravingPreviewImage!.startsWith('http://') || _cravingPreviewImage!.startsWith('https://')) {
        return Image.network(
          _cravingPreviewImage!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildQuickCravingPlaceholder(),
        );
      } else if (_cravingPreviewImage!.startsWith('data:image')) {
        try {
          final clean = _cravingPreviewImage!.contains(',') ? _cravingPreviewImage!.split(',')[1] : _cravingPreviewImage!;
          return Image.memory(
            base64Decode(clean),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildQuickCravingPlaceholder(),
          );
        } catch (_) {
          return _buildQuickCravingPlaceholder();
        }
      }
      return _buildQuickCravingPlaceholder();
    } else if (_cravingImageUrlController.text.trim().isNotEmpty) {
      final url = _cravingImageUrlController.text.trim();
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildQuickCravingPlaceholder(),
        );
      }
    } else if (_cravingBase64Controller.text.trim().isNotEmpty) {
      try {
        final b64 = _cravingBase64Controller.text.trim();
        final clean = b64.contains(',') ? b64.split(',')[1] : b64;
        return Image.memory(
          base64Decode(clean),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildQuickCravingPlaceholder(),
        );
      } catch (_) {
        return _buildQuickCravingPlaceholder();
      }
    }
    return _buildQuickCravingPlaceholder();
  }

  Widget _buildThumbPlaceholder(bool isVeg, dynamic icon) {
    final emoji = (icon != null && icon.toString().isNotEmpty) ? icon.toString() : (isVeg ? '🥗' : '🍗');
    return Container(
      color: const Color(0xFFF1F5F9),
      child: Center(
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }

  Widget _buildQuickCravingPlaceholder() {
    final iconEmoji = _cravingIconController.text.trim().isEmpty ? (_cravingIsVeg ? '🥗' : '🍗') : _cravingIconController.text.trim();
    return Container(
      color: const Color(0xFFF1F5F9),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(iconEmoji, style: const TextStyle(fontSize: 38)),
            const SizedBox(height: 6),
            const Text(
              'Select an image',
              style: TextStyle(color: AdminColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickCravingsList() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.fastfood_rounded, size: 18, color: AdminColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'All Uploaded Quick Cravings (${quickCravings.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20, color: AdminColors.textSecondary),
                tooltip: 'Refresh list',
                onPressed: fetchQuickCravings,
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (isLoadingCravings)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (quickCravings.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(
                child: Text('No quick cravings found. Use the upload form to add items!'),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: quickCravings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final c = quickCravings[index];
                if (c is! Map) return const SizedBox.shrink();
                final cId = (c['craving_id'] ?? c['_id'] ?? '').toString();
                final name = (c['name'] ?? 'Dish').toString();
                final rating = (c['rating'] ?? '4.5').toString();
                final budget = (c['budget'] ?? '49').toString();
                final isVeg = c['isVeg'] == true;
                final isActive = c['is_active'] != false;
                final imgUrl = c['image_url'] as String?;
                final base64 = c['image_base64'] as String?;
                final fallback = (c['fallback_asset'] ?? 'assets/banner_biryani_crushing.jpg').toString();

                Widget thumbWidget;
                if (base64 != null && base64.isNotEmpty) {
                  try {
                    final clean = base64.contains(',') ? base64.split(',')[1] : base64;
                    thumbWidget = Image.memory(
                      base64Decode(clean),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildThumbPlaceholder(isVeg, c['icon']),
                    );
                  } catch (_) {
                    thumbWidget = _buildThumbPlaceholder(isVeg, c['icon']);
                  }
                } else if (imgUrl != null && imgUrl.isNotEmpty && (imgUrl.startsWith('http://') || imgUrl.startsWith('https://'))) {
                  thumbWidget = Image.network(
                    imgUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildThumbPlaceholder(isVeg, c['icon']),
                  );
                } else {
                  thumbWidget = _buildThumbPlaceholder(isVeg, c['icon']);
                }

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.white : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isActive ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(width: 52, height: 52, child: thumbWidget),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isVeg ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.star_rounded, size: 10, color: Color(0xFF15803D)),
                                      const SizedBox(width: 2),
                                      Text(
                                        rating,
                                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '₹$budget',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AdminColors.primary),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  (c['time'] ?? '20-25 mins').toString(),
                                  style: const TextStyle(fontSize: 10.5, color: AdminColors.textMuted),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isActive,
                        activeColor: AdminColors.primary,
                        onChanged: (_) => _toggleCravingActive(cId, isActive),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: AdminColors.danger, size: 20),
                        tooltip: 'Delete craving',
                        onPressed: () => _deleteQuickCraving(cId, name),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildQuickCravingUploadForm() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.add_photo_alternate_rounded, size: 20, color: AdminColors.primary),
              SizedBox(width: 8),
              Text(
                'Upload New Quick Craving',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Upload Tabs
          Row(
            children: [
              _buildCravingTabButton('device', 'Device', Icons.phone_android_rounded),
              const SizedBox(width: 8),
              _buildCravingTabButton('presets', 'Presets', Icons.auto_awesome_rounded),
              const SizedBox(width: 8),
              _buildCravingTabButton('url', 'URL', Icons.link_rounded),
              const SizedBox(width: 8),
              _buildCravingTabButton('base64', 'Base64', Icons.code_rounded),
            ],
          ),
          const SizedBox(height: 14),

          // Tab Content
          if (_selectedCravingUploadTab == 'device') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: AdminColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _pickCravingImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_rounded, size: 18),
                      label: const Text('Gallery', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: AdminColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _pickCravingImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_rounded, size: 18),
                      label: const Text('Camera', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_selectedCravingUploadTab == 'presets') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tap any preset to auto-fill details and image:', style: TextStyle(fontSize: 11.5, color: AdminColors.textSecondary)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: curatedCravingPresets.map((preset) {
                      final name = preset['name'] as String;
                      final icon = preset['icon'] as String;
                      return ActionChip(
                        avatar: Text(icon, style: const TextStyle(fontSize: 14)),
                        label: Text(name, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        onPressed: () {
                          setState(() {
                            _cravingNameController.text = preset['name'];
                            _cravingBudgetController.text = preset['budget'];
                            _cravingRatingController.text = preset['rating'];
                            _cravingTimeController.text = preset['time'];
                            _cravingCuisineController.text = preset['cuisine'];
                            _cravingIconController.text = preset['icon'];
                            _cravingIsVeg = preset['isVeg'] == true;
                            _cravingPreviewImage = preset['imageUrl'];
                            _cravingPickedBytes = null;
                            _cravingPickedBase64 = null;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ] else if (_selectedCravingUploadTab == 'url') ...[
            TextField(
              controller: _cravingImageUrlController,
              decoration: InputDecoration(
                hintText: 'https://images.unsplash.com/...',
                labelText: 'Image URL',
                prefixIcon: const Icon(Icons.link_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ] else if (_selectedCravingUploadTab == 'base64') ...[
            TextField(
              controller: _cravingBase64Controller,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'data:image/jpeg;base64,/9j/4AAQSkZJRg...',
                labelText: 'Base64 Image String',
                prefixIcon: const Icon(Icons.code_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 16),

          // Dish Name Field
          TextField(
            controller: _cravingNameController,
            decoration: InputDecoration(
              labelText: 'Dish Name *',
              hintText: 'e.g. Chicken Shawarma',
              prefixIcon: const Icon(Icons.restaurant_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),

          // Rating and Budget Row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cravingRatingController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Star Rating *',
                    hintText: '4.5',
                    prefixIcon: const Icon(Icons.star_rounded, color: Color(0xFFEAB308)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _cravingBudgetController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Budget Price (₹) *',
                    hintText: '49',
                    prefixIcon: const Icon(Icons.currency_rupee_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Veg / Non-Veg Toggle & Emoji Icon Row
          Row(
            children: [
              Expanded(
                flex: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: _cravingIsVeg ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _cravingIsVeg ? 'Veg Delights 🌱' : 'Non-Veg 🍗',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                      Switch(
                        value: _cravingIsVeg,
                        activeColor: const Color(0xFF16A34A),
                        onChanged: (val) => setState(() => _cravingIsVeg = val),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: TextField(
                  controller: _cravingIconController,
                  decoration: InputDecoration(
                    labelText: 'Emoji Icon',
                    hintText: '🍗',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Prep Time & Cuisine
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cravingTimeController,
                  decoration: InputDecoration(
                    labelText: 'Prep Time',
                    hintText: '15-20 mins',
                    prefixIcon: const Icon(Icons.timer_outlined, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _cravingCuisineController,
                  decoration: InputDecoration(
                    labelText: 'Cuisine',
                    hintText: 'Rolls & Fast Food',
                    prefixIcon: const Icon(Icons.category_outlined, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Submit Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: isUploadingCraving ? null : _publishQuickCraving,
              icon: isUploadingCraving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_rounded, size: 20),
              label: Text(
                isUploadingCraving ? 'Publishing Quick Craving...' : 'Publish to Customer Homepage',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCravingTabButton(String tabKey, String label, IconData icon) {
    final isSelected = _selectedCravingUploadTab == tabKey;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedCravingUploadTab = tabKey),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFFD97706) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isSelected ? const Color(0xFFB45309) : AdminColors.textSecondary),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? const Color(0xFFB45309) : AdminColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 🏨 PREFERRED HOTELS MANAGER (Dropdown Items for Customer Home Page)
  // =========================================================================
  Future<void> fetchPreferredHotels() async {
    setState(() => isLoadingHotels = true);
    try {
      final res = await http.get(AdminApiConfig.preferredHotelsAll).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            preferredHotels = (data['hotels'] as List?) ?? [];
            isLoadingHotels = false;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => isLoadingHotels = false);
  }

  Future<void> _addPreferredHotel() async {
    final name = _hotelNameController.text.trim();
    final area = _hotelAreaController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter hotel name'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => isSavingHotel = true);
    try {
      final res = await http.post(
        AdminApiConfig.preferredHotelsAdd,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'area': area}),
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 || res.statusCode == 201) {
        _hotelNameController.clear();
        _hotelAreaController.clear();
        await fetchPreferredHotels();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added "$name" to Preferred Hotels!'), backgroundColor: AdminColors.success),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add hotel: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => isSavingHotel = false);
    }
  }

  Future<void> _togglePreferredHotel(String id) async {
    try {
      final res = await http.patch(AdminApiConfig.preferredHotelsToggle(id)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        await fetchPreferredHotels();
      }
    } catch (_) {}
  }

  Future<void> _deletePreferredHotel(String id, String name) async {
    try {
      final res = await http.delete(AdminApiConfig.preferredHotelsDelete(id)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        await fetchPreferredHotels();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Removed "$name"'), backgroundColor: AdminColors.textPrimary),
          );
        }
      }
    } catch (_) {}
  }

  Widget _buildPreferredHotelsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AdminColors.primaryLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AdminColors.primarySubtle),
          ),
          child: const Row(
            children: [
              Icon(Icons.apartment_rounded, color: AdminColors.primary, size: 28),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Preferred Hotels Dropdown Manager',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Active hotels added here appear in the Customer Regular Home Page "Preferred Hotels" dropdown.',
                      style: TextStyle(fontSize: 12.5, color: AdminColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AdminColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add New Preferred Hotel',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _hotelNameController,
                      decoration: InputDecoration(
                        labelText: 'Hotel / Restaurant Name *',
                        hintText: 'e.g. Hotel Saravana Bhavan',
                        prefixIcon: const Icon(Icons.storefront_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _hotelAreaController,
                      decoration: InputDecoration(
                        labelText: 'Area (Optional)',
                        hintText: 'e.g. Kumbakonam',
                        prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: isSavingHotel ? null : _addPreferredHotel,
                      icon: isSavingHotel
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.add_rounded),
                      label: Text(isSavingHotel ? 'Adding...' : 'Add Hotel', style: const TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AdminColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'All Preferred Hotels (${preferredHotels.length})',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                  ),
                  IconButton(
                    onPressed: fetchPreferredHotels,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh Hotels',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (isLoadingHotels)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (preferredHotels.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No preferred hotels added yet.')),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: preferredHotels.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final h = preferredHotels[index] as Map<String, dynamic>;
                    final id = (h['hotel_id'] ?? h['_id'] ?? '').toString();
                    final name = (h['name'] ?? '').toString();
                    final area = (h['area'] ?? '').toString();
                    final isActive = h['is_active'] == true;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: isActive ? AdminColors.primaryLight : Colors.grey.shade200,
                        child: Icon(Icons.apartment_rounded, color: isActive ? AdminColors.primary : Colors.grey),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: area.isNotEmpty ? Text(area, style: const TextStyle(fontSize: 12)) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: isActive,
                            activeThumbColor: AdminColors.success,
                            onChanged: (_) => _togglePreferredHotel(id),
                          ),
                          IconButton(
                            onPressed: () => _deletePreferredHotel(id, name),
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                            tooltip: 'Delete Hotel',
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}


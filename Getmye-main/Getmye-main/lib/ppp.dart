import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/route_service.dart';
import 'package:flutter_application_1/dhome.dart';
import 'package:flutter_application_1/options.dart';
import 'package:flutter_application_1/pay.dart';
import 'package:flutter_application_1/profile.dart';
import 'delivery_bill_flow.dart';
import 'address.dart';
import 'api_config.dart';
import 'services/order_chat_sheet.dart';
import 'services/app_notification_service.dart';
import 'services/alarm_service.dart';
import 'widgets/customer_bottom_nav_bar.dart';
import 'widgets/price_range_dialogs.dart';
import 'theme/app_theme.dart';
import 'notifications_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Getmye',
      theme: AppTheme.lightTheme,
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool showDeliveryDetails = false;
  bool showCancelButtonContainer = false;
  bool isVegOnly = false;
  String _currentAddressShort = "Current Location";
  String _currentAddressFull = "Detecting exact live GPS location...";

  bool isSearchingRider = false;
  bool hasRiderAccepted = false;
  String assignedPartnerName = "";
  String assignedPartnerPhone = "";
  String assignedPartnerId = "";
  String assignedOrderOtp = "";
  String? assignedPartnerProfileImage;
  double _riderDistanceMeters = 0.0;
  List<LatLng> _trackingRoutePoints = [];
  List<String> _orderBillImages = [];

  bool _isShowingPriceRangeDialog = false;
  String? _lastPromptedPriceRange;

  void _checkAndShowCustomerPriceRangeDialog({
    required String orderId,
    required String partnerName,
    required String partnerPhone,
    String? partnerPhoto,
    required String priceRange,
  }) {
    if (!mounted || _isShowingPriceRangeDialog) return;
    if (_lastPromptedPriceRange == '${orderId}_$priceRange') return;

    _isShowingPriceRangeDialog = true;
    _lastPromptedPriceRange = '${orderId}_$priceRange';

    AppNotificationService.showPriceRangeAcknowledgementNotification(
      orderId: orderId,
      priceRange: priceRange,
      partnerName: partnerName,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerPriceRangeDialog(
        orderId: orderId,
        partnerName: partnerName,
        partnerPhone: partnerPhone,
        partnerPhoto: partnerPhoto,
        priceRange: priceRange,
        onAccepted: () {
          _isShowingPriceRangeDialog = false;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PaymentPage()),
          );
        },
        onFindAnotherPartner: () async {
          _isShowingPriceRangeDialog = false;
          final p = await SharedPreferences.getInstance();
          await p.setBool('active_order_partner_accepted', false);
          await p.remove('active_order_partner_name');
          await p.remove('active_order_partner_phone');
          await p.remove('active_order_partner_id');
          await p.remove('active_order_partner_image');
          await p.remove('active_order_partner_pic');
          await p.setString('active_order_status', 'pending');

          if (mounted) {
            setState(() {
              hasRiderAccepted = false;
              isSearchingRider = true;
              showCancelButtonContainer = true;
              showDeliveryDetails = true;
              assignedPartnerName = '';
              assignedPartnerPhone = '';
              assignedPartnerId = '';
              assignedPartnerProfileImage = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Price range declined. Searching for next delivery partner..."),
                backgroundColor: Color(0xFF2563EB),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onStopOrder: () async {
          _isShowingPriceRangeDialog = false;
          final p = await SharedPreferences.getInstance();
          await p.setBool('has_active_order', false);
          await p.remove('active_order_id');
          await p.setString('active_order_status', 'cancelled');
          await p.remove('active_order_partner_accepted');
          await p.remove('active_order_partner_name');
          await p.remove('active_order_partner_phone');
          await p.remove('active_order_partner_id');

          if (mounted) {
            setState(() {
              isSearchingRider = false;
              hasRiderAccepted = false;
              showDeliveryDetails = false;
              showCancelButtonContainer = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Order stopped and cancelled."),
                backgroundColor: Color(0xFFDC2626),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onDeclined: () {
          _isShowingPriceRangeDialog = false;
        },
      ),
    ).then((_) {
      _isShowingPriceRangeDialog = false;
    });
  }

  String _formatRiderDistance() {
    double dist = _riderDistanceMeters;
    if (dist <= 0) {
      try {
        dist = Geolocator.distanceBetween(
          _riderLocation.latitude,
          _riderLocation.longitude,
          _customerLocation.latitude,
          _customerLocation.longitude,
        );
      } catch (_) {
        dist = 0;
      }
    }
    if (dist <= 50) {
      return "Arrived";
    } else if (dist < 1000) {
      final m = dist.round();
      final mins = (dist / 350).ceil().clamp(1, 30);
      return "$m m away • ~$mins min${mins > 1 ? 's' : ''}";
    } else {
      final km = (dist / 1000).toStringAsFixed(1);
      final mins = (dist / 350).ceil().clamp(1, 60);
      return "$km km away • ~$mins mins";
    }
  }
  Timer? _searchRiderTimer;
  Timer? _riderTrackingTimer;
  Timer? _inOrderChatTimer;
  bool _isPollingRider = false;
  bool _isFetchingChat = false;
  bool _isFetchingRiderLoc = false;
  List<Map<String, dynamic>> _inOrderChatMessages = [];
  GoogleMapController? _trackingMapController;
  LatLng _customerLocation = const LatLng(10.9601, 79.3845);
  LatLng _riderLocation = const LatLng(10.9620, 79.3860);


  bool _isLocationInKumbakonam(double lat, double lng) {
    return true;
  }

  void _showGeofenceRestrictionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_off_rounded, color: Color(0xFFEF4444), size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Service Area Alert",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          "Sorry, our service is currently unavailable in your location.",
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Got it", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _itemController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(text: '1');
  final TextEditingController _chatMsgController = TextEditingController();
  final TextEditingController _customLocationTextController = TextEditingController();
  final TextEditingController _deliveryLocationController = TextEditingController();
  final TextEditingController _preferredShopController = TextEditingController();
  final FocusNode _foodFocusNode = FocusNode();
  final FocusNode _budgetFocusNode = FocusNode();
  final GlobalKey _orderFormCardKey = GlobalKey();

  bool _isLocationDialogShowing = false;
  bool _isCheckingLocation = false;
  bool _showOrderForm = false;
  bool _hasClaimedFirstOffer = false;

  // Promotional Banner Carousel Controller & Timer (Regular User Home Page)
  late PageController _bannerPageController;
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;

  List<Map<String, dynamic>> _carouselBanners = [];
  bool _isLoadingSlidingBanners = true;
  List<Map<String, dynamic>> _preferredHotels = [];
  String? _selectedPreferredHotel;
  int _unreadNotificationCount = 0;

  List<Map<String, dynamic>> _quickCravings = [
    {
      'name': 'Chicken Biryani',
      'budget': '49',
      'image': 'assets/banner_biryani_crushing.jpg',
      'icon': '🍗',
      'isVeg': false,
      'rating': '4.5',
      'time': '20-25 mins',
      'cuisine': 'Biryani • North Indian',
    },
    {
      'name': 'Chicken Shawarma',
      'budget': '30',
      'image': 'assets/banner_shawarma_crushing.jpg',
      'icon': '🌯',
      'isVeg': false,
      'rating': '4.6',
      'time': '15-20 mins',
      'cuisine': 'Rolls & Fast Food',
    },
    {
      'name': 'Hot Momos',
      'budget': '39',
      'image': 'assets/banner_momos_crushing.jpg',
      'icon': '🥟',
      'isVeg': false,
      'rating': '4.4',
      'time': '15-20 mins',
      'cuisine': 'Chinese • Street Food',
    },
    {
      'name': 'Dosa with Sambar',
      'budget': '60',
      'image': 'assets/craving_dosa.jpg',
      'icon': '🥞',
      'isVeg': true,
      'rating': '4.7',
      'time': '10-15 mins',
      'cuisine': 'South Indian • Tiffin',
    },
    {
      'name': 'Paneer Butter Masala',
      'budget': '120',
      'image': 'assets/craving_paneer.jpg',
      'icon': '🍛',
      'isVeg': true,
      'rating': '4.5',
      'time': '20-25 mins',
      'cuisine': 'North Indian • Curry',
    },
    {
      'name': 'Chicken 65',
      'budget': '110',
      'image': 'assets/craving_chicken65.jpg',
      'icon': '🍗',
      'isVeg': false,
      'rating': '4.6',
      'time': '15-20 mins',
      'cuisine': 'Starters • Appetizers',
    },
    {
      'name': 'Chicken Fried Rice',
      'budget': '110',
      'image': 'assets/banner_chicken_fried_rice.png',
      'icon': '🍚',
      'isVeg': false,
      'rating': '4.3',
      'time': '20-25 mins',
      'cuisine': 'Chinese • Fast Food',
    },
    {
      'name': 'Fresh Mango Juice',
      'budget': '50',
      'image': 'assets/craving_mango_juice.jpg',
      'icon': '🥭',
      'isVeg': true,
      'rating': '4.8',
      'time': '5-10 mins',
      'cuisine': 'Beverages • Fresh Juices',
    },
  ];

  List<Map<String, dynamic>> get _filteredCravings {
    return _quickCravings.where((dish) {
      if (isVegOnly && dish['isVeg'] != true) return false;
      return true;
    }).toList();
  }

  void _startRegularBannerAutoSlide() {
    _bannerTimer?.cancel();
    if (_carouselBanners.isEmpty) return;
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_bannerPageController.hasClients && _carouselBanners.isNotEmpty) {
        int nextPage = (_currentBannerIndex + 1) % _carouselBanners.length;
        _bannerPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  Future<void> _checkFirstTimeOfferStatus({bool forceServerCheck = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool claimed = prefs.getBool('has_claimed_first_offer') ?? false;
      final userId = prefs.getString('user_id') ?? '';
      final mobile = prefs.getString('mobile_number') ?? prefs.getString('user_mobile') ?? '';
      final queryId = (userId.isNotEmpty && userId != 'usr_001' && userId != 'guest') ? userId : mobile;

      if ((!claimed || forceServerCheck) && queryId.isNotEmpty) {
        try {
          final res = await http.get(ApiConfig.orderUser(queryId))
              .timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final List orders = (data['orders'] is List) ? (data['orders'] as List) : [];
            final bool hasCompletedOrder = orders.any((o) {
              final st = (o['status'] ?? '').toString().toLowerCase();
              return st == 'delivered' || st == 'completed';
            });
            if (hasCompletedOrder) {
              claimed = true;
              await prefs.setBool('has_claimed_first_offer', true);
            } else if (forceServerCheck) {
              claimed = false;
              await prefs.setBool('has_claimed_first_offer', false);
            }
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _hasClaimedFirstOffer = claimed;
        });
      }
    } catch (_) {}
  }

  void _toggleFirstTimeOfferForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    final newStatus = !_hasClaimedFirstOffer;
    await prefs.setBool('has_claimed_first_offer', newStatus);
    if (mounted) {
      setState(() {
        _hasClaimedFirstOffer = newStatus;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus
                ? "Switched to: REGULAR USER PAGE (Backup Design)"
                : "Switched to: FIRST-TIME USER OFFER PAGE",
          ),
          backgroundColor: newStatus ? const Color(0xFF142B4A) : const Color(0xFFEA580C),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _applyBannerOffer(Map<String, dynamic> banner) {
    if (showDeliveryDetails) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You already have an active order in progress!"),
          backgroundColor: Color(0xFFD97706),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      _itemController.text = banner['item'] as String;
      _budgetController.text = banner['budget'] as String;
    });
    final origPrice = banner['originalPrice'] as String? ?? '';
    final String priceText = origPrice.isNotEmpty
        ? "Original: ₹$origPrice → Offer: ₹${banner['offerPrice']}"
        : "Offer: ₹${banner['offerPrice']}";

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Selected: ${banner['title']} ($priceText)",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
    _scrollToOrderForm();
  }

  void _scrollToOrderForm() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _orderFormCardKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          alignment: 0.06,
        );
      } else if (_scrollController.hasClients) {
        _scrollController.animateTo(
          380.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  // Shop Advertisements Carousel Controller & Timer
  late PageController _shopAdPageController;
  int _currentShopAdIndex = 0;
  Timer? _shopAdTimer;
  int _remainingBiryaniCount = 75;
  int _totalBiryaniCount = 100;
  int _selectedOfferUnitPrice = 65;
  int _selectedOfferOriginalPrice = 120;
  String? _adminBannerBase64;
  Uint8List? _cachedAdminBannerBytes;
  String? _adminBannerUrl;
  String? _adminBannerTitle;
  String? _adminBannerBadge;
  DateTime? _orderSearchStartTime;
  int _allBusyHitCount = 0;

  // 🕒 App Operational Schedule States (Online/Offline Window)
  bool _isStoreOnline = true; // Default true so it doesn't flash closed while checking
  String _scheduleStartTime = "12:30";
  String _scheduleEndTime = "12:45";
  int _secondsUntilOpen = 0;
  int _secondsUntilClose = 0;
  String _offlineTitle = "Orders Opening Soon";
  String _offlineMessage = "We are accepting today's orders strictly during our scheduled slot. Please check back when the timer reaches zero!";
  Timer? _storeCountdownTimer;
  bool _hasAutoShownClosedPopup = false;
  bool _isClosedPopupOpen = false;
  StateSetter? _closedPopupSetState;

  static const List<Map<String, dynamic>> _kPartnerHotels = [
    {
      'name': 'Devan Biriyani',
      'tagline': 'Authentic Woodfired Dum Biriyani',
      'location': 'Kumbakonam Main Road',
      'rating': '4.9',
      'reviews': '2.4k+ orders',
      'image': 'assets/banner_biryani.jpg',
      'badge': 'ICONIC SPOT',
      'specialty': 'Woodfired Seeraga Samba',
      'color': Color(0xFFEA580C),
      'prepTime': '10-15m',
    },
    {
      'name': 'Aathurar Biriyani',
      'tagline': 'Traditional Spiced Rich Dum Feast',
      'location': 'Railway Feeder Road',
      'rating': '4.8',
      'reviews': '1.8k+ orders',
      'image': 'assets/banner_biryani_crushing.jpg',
      'badge': 'TOP RATED',
      'specialty': 'Special Masala Dum Biriyani',
      'color': Color(0xFFDC2626),
      'prepTime': '12-18m',
    },
    {
      'name': 'Sumaiya Biriyani',
      'tagline': 'Famous Wedding Style Muslim Dum Biriyani',
      'location': 'Town Hall Market',
      'rating': '4.9',
      'reviews': '3.1k+ orders',
      'image': 'assets/banner_mutton_biryani_hd.png',
      'badge': 'CHEF SPECIAL',
      'specialty': 'Royal Wedding Mutton & Chicken',
      'color': Color(0xFFD97706),
      'prepTime': '10-15m',
    },
    {
      'name': 'Thoppi Vappa Biriyani',
      'tagline': 'Aromatic Seeraga Samba Traditional Feast',
      'location': 'Bus Stand Corner',
      'rating': '4.8',
      'reviews': '1.5k+ orders',
      'image': 'assets/banner_mutton_biryani.jpg',
      'badge': 'LEGENDARY',
      'specialty': 'Classic Tamil Traditional Dum',
      'color': Color(0xFF059669),
      'prepTime': '15-20m',
    },
    {
      'name': 'Aslaam Biriyani',
      'tagline': 'Mouthwatering Charcoal Dum Biriyani',
      'location': 'Bazaar Street',
      'rating': '4.7',
      'reviews': '1.2k+ orders',
      'image': 'assets/banner_biryani_65_landscape.jpg',
      'badge': 'CROWD FAVORITE',
      'specialty': 'Charcoal Dum & Chicken 65',
      'color': Color(0xFF7C3AED),
      'prepTime': '10-15m',
    },
  ];

  final List<Map<String, dynamic>> _shopAdBanners = _kPartnerHotels;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bannerPageController = PageController();
    _shopAdPageController = PageController();
    _foodFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _budgetFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _loadSavedLocation();
    _loadCachedOfferBanner();
    _loadCachedSlidingBanners();
    _loadCachedQuickCravings();
    _loadRemainingBiryaniStock();
    _loadActiveOfferBanner();
    _loadActiveSlidingBanners();
    _loadActiveQuickCravings();
    _loadPreferredHotels();
    _loadUnreadNotificationCount();
    _checkAppScheduleStatus();
    _startStoreCountdownTimer();
    _startShopAdAutoSlide();
    _startRegularBannerAutoSlide();
    _checkFirstTimeOfferStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptLocationService();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Whenever customer returns to app from settings or background, check GPS & refresh exact location
      _checkAndPromptLocationService();
      _loadActiveOfferBanner();
      _loadActiveSlidingBanners();
      _loadActiveQuickCravings();
      _loadPreferredHotels();
      _loadUnreadNotificationCount();
      _checkAppScheduleStatus();
      _checkFirstTimeOfferStatus();
    }
  }

  // 🛰️ Requirement: Check GPS ON/OFF & permissions every time user enters the app, and fetch exact location
  Future<void> _checkAndPromptLocationService() async {
    if (_isCheckingLocation) return;
    _isCheckingLocation = true;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          await _showTurnOnGPSDialog(
            title: "Turn On GPS Location",
            message: "Please turn ON your device location (GPS) to accurately detect your delivery address and locate delivery partners.",
            isPermissionSettings: false,
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          await _showTurnOnGPSDialog(
            title: "Location Permission Required",
            message: "Location permission is disabled for Getmye. Please enable it in device settings to accurately detect your delivery address.",
            isPermissionSettings: true,
          );
        }
        return;
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        // Location is enabled & permission granted: get live location
        final prefs = await SharedPreferences.getInstance();
        final savedShort = prefs.getString('customer_address_short');
        final bool hasAddress = savedShort != null &&
            savedShort.isNotEmpty &&
            savedShort != 'Detecting...' &&
            savedShort != 'Current Location' &&
            !savedShort.toLowerCase().contains('matthi') &&
            !savedShort.toLowerCase().contains('mathi') &&
            !savedShort.toLowerCase().contains('live gps');
        await _requestLiveLocation(forceOverrideAddress: !hasAddress);
      }
    } catch (e) {
      debugPrint("Customer location service check error: $e");
    } finally {
      _isCheckingLocation = false;
    }
  }

  Future<void> _showTurnOnGPSDialog({
    required String title,
    required String message,
    bool isPermissionSettings = false,
  }) async {
    if (_isLocationDialogShowing || !mounted) return;
    _isLocationDialogShowing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.location_on_rounded, color: Color(0xFF2563EB), size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Later", style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 16),
              label: Text(
                isPermissionSettings ? "Open Settings" : "Turn On GPS",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                if (isPermissionSettings) {
                  await Geolocator.openAppSettings();
                } else {
                  await Geolocator.openLocationSettings();
                }
              },
            ),
          ],
        ),
      );
    } finally {
      _isLocationDialogShowing = false;
    }
  }

  void _startShopAdAutoSlide() {
    _shopAdTimer?.cancel();
    if (_shopAdBanners.length <= 1) return;
    _shopAdTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_shopAdPageController.hasClients) {
        int nextPage = (_currentShopAdIndex + 1) % _shopAdBanners.length;
        _shopAdPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  Future<void> _loadSavedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    String? shortA = prefs.getString('customer_address_short');
    String? fullA = prefs.getString('customer_address_full');
    final lat = prefs.getDouble('customer_latitude');
    final lng = prefs.getDouble('customer_longitude');

    // Clean any old stale 'Matthi' or 'Live GPS' string
    if (shortA != null && (shortA.toLowerCase().contains('matthi') || shortA.toLowerCase().contains('mathi'))) {
      await prefs.remove('customer_address_short');
      shortA = null;
    }
    if (fullA != null && (fullA.toLowerCase().contains('matthi') || fullA.toLowerCase().contains('mathi') || fullA.toLowerCase().contains('live gps'))) {
      await prefs.remove('customer_address_full');
      await prefs.remove('active_order_customer_address');
      fullA = null;
    }

    // 🛑 Sanitize conflated 'Nageswaran' + 'Annalagraharam' OSM tag artifact
    if (shortA != null && shortA.toLowerCase().contains('nageswaran') && shortA.toLowerCase().contains('annalagraharam')) {
      shortA = 'Nageswaran South Street';
      await prefs.setString('customer_address_short', shortA);
    }
    if (fullA != null && fullA.toLowerCase().contains('nageswaran') && fullA.toLowerCase().contains('annalagraharam')) {
      fullA = 'Nageswaran South Street, Kumbakonam - 612001';
      await prefs.setString('customer_address_full', fullA);
      await prefs.setString('active_order_customer_address', fullA);
    }

    final String validShort = shortA ?? '';
    final String validFull = (fullA != null && fullA.isNotEmpty) ? fullA : validShort;
    if (validShort.isNotEmpty) {
      setState(() {
        _currentAddressShort = validShort;
        _currentAddressFull = validFull;
        _deliveryLocationController.text = _currentAddressFull;
      });
    }

    if (lat != null && lng != null) {
      setState(() {
        _customerLocation = LatLng(lat, lng);
        _riderLocation = LatLng(lat + 0.003, lng + 0.003);
      });
    }



    // ⚡ Verify active order directly with backend server for this customer
    final userId = prefs.getString('user_id');
    final custPhone = prefs.getString('mobile_number');
    final queryId = (userId != null && userId.isNotEmpty) ? userId : custPhone;

    bool serverHasActiveOrder = false;
    Map<String, dynamic>? activeOrderObj;

    if (queryId != null && queryId.isNotEmpty) {
      try {
        final activeRes = await http.get(
          ApiConfig.orderActive(queryId),
        ).timeout(const Duration(seconds: 3));

        if (activeRes.statusCode == 200) {
          final activeData = jsonDecode(activeRes.body);
          if (activeData['order'] != null) {
            activeOrderObj = Map<String, dynamic>.from(activeData['order']);
            serverHasActiveOrder = true;
          }
        }
      } catch (err) {
        debugPrint("Active order check on server failed: $err");
      }
    }

    if (serverHasActiveOrder && activeOrderObj != null) {
      final curOrderId = (activeOrderObj['order_id'] ?? '').toString();
      final status = (activeOrderObj['status'] ?? '').toString().toLowerCase();
      final bool isAccepted = (status != 'pending');
      final pId = (activeOrderObj['partner_id'] ?? '').toString();
      final rawPName = (activeOrderObj['partner_name'] ?? '').toString();
      final pName = (rawPName.isNotEmpty && rawPName != 'Delivery Partner') ? rawPName : 'Delivery Partner';
      final pPhone = (activeOrderObj['partner_phone'] ?? '').toString();
      final pPic = activeOrderObj['partner_photo_url'] ?? activeOrderObj['partner_profile_picture'] ?? (pId.isNotEmpty ? '${ApiConfig.baseUrl}/api/deliveryperson/photo/$pId' : null);
      final pOtp = (activeOrderObj['cod_otp'] ?? '').toString();

      await prefs.setBool('has_active_order', true);
      await prefs.setString('active_order_id', curOrderId);
      await prefs.setString('active_order_status', status);
      await prefs.setBool('active_order_partner_accepted', isAccepted);
      if (pName.isNotEmpty) await prefs.setString('active_order_partner_name', pName);
      if (pPhone.isNotEmpty) await prefs.setString('active_order_partner_phone', pPhone);
      if (pId.isNotEmpty) await prefs.setString('active_order_partner_id', pId);
      if (pPic != null && pPic.isNotEmpty) await prefs.setString('active_order_partner_image', pPic);
      if (pOtp.isNotEmpty) await prefs.setString('active_cod_otp', pOtp);

      List<String> bImages = [];
      final bool isBillPhase = status == 'bill_sent' || status == 'in_transit' || status == 'delivered';
      if (isBillPhase) {
        if (activeOrderObj['bill_images'] is List) {
          bImages = (activeOrderObj['bill_images'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        } else if (activeOrderObj['bill_image_url'] != null && activeOrderObj['bill_image_url'].toString().trim().isNotEmpty) {
          bImages = [activeOrderObj['bill_image_url'].toString().trim()];
        } else {
          final savedImgs = prefs.getStringList('order_${curOrderId}_bill_images');
          if (savedImgs != null && savedImgs.isNotEmpty) bImages = savedImgs;
        }
      }
      if (bImages.isNotEmpty) {
        await prefs.setStringList('order_${curOrderId}_bill_images', bImages);
        await prefs.setString('order_${curOrderId}_bill_image', bImages.first);
      }

      if (mounted) {
        setState(() {
          showDeliveryDetails = true;
          hasRiderAccepted = isAccepted;
          isSearchingRider = !isAccepted;
          showCancelButtonContainer = !isAccepted;
          assignedPartnerName = isAccepted ? pName : '';
          assignedPartnerPhone = isAccepted ? pPhone : '';
          assignedPartnerId = isAccepted ? pId : '';
          if (pPic != null && pPic.isNotEmpty) assignedPartnerProfileImage = pPic;
          if (pOtp.isNotEmpty) assignedOrderOtp = pOtp;
          _orderBillImages = bImages;
        });
      }

      if (isAccepted) {
        final bool alreadyNotified = prefs.getBool('has_notified_partner_accepted_$curOrderId') ?? false;
        if (!alreadyNotified) {
          await prefs.setBool('has_notified_partner_accepted_$curOrderId', true);
          await AppNotificationService.showOrderAcceptedNotification(
            orderId: curOrderId,
            partnerName: pName,
            partnerPhone: pPhone,
          );
        }

        _startRiderLocationPolling();
        _startOrderChatPolling();
        _fetchTrackingRoadRoute();
      }
      AlarmService.startCustomerOrderListeningService(
        baseUrl: ApiConfig.baseUrl,
        orderId: curOrderId,
      );
      AlarmService.requestBatteryOptimizationExemption();
      _startOrderPolling(curOrderId);
    } else {
      // Server confirmed NO active order (or clean startup) - clear all local stale state!
      AlarmService.stopCustomerOrderListeningService();
      await prefs.setBool('has_active_order', false);
      await prefs.remove('active_order_id');
      await prefs.remove('active_order_status');
      await prefs.remove('active_order_partner_accepted');
      await prefs.remove('active_order_partner_name');
      await prefs.remove('active_order_partner_phone');
      await prefs.remove('active_order_partner_id');
      await prefs.remove('active_order_partner_image');
      await prefs.remove('active_order_partner_pic');
      await prefs.remove('active_cod_otp');

      if (mounted) {
        setState(() {
          showDeliveryDetails = false;
          hasRiderAccepted = false;
          isSearchingRider = false;
          assignedPartnerName = "";
          assignedPartnerPhone = "";
          assignedPartnerId = "";
          assignedOrderOtp = "";
          assignedPartnerProfileImage = null;
        });
      }
    }

    // Only refresh live device GPS position if no valid address was previously saved
    if (shortA == null || shortA.isEmpty || shortA == 'Detecting...' || shortA == 'Current Location') {
      await _requestLiveLocation(
        silent: true,
        forceOverrideAddress: true,
      );
    }
  }

  Future<void> _loadRemainingBiryaniStock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt('remaining_biryani_count');
      if (count != null && mounted) {
        setState(() {
          _remainingBiryaniCount = count;
        });
      }
    } catch (_) {}
  }

  // Load cached banner instantly from local storage (Zero flicker on startup)
  Future<void> _loadCachedOfferBanner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final base64 = prefs.getString('cached_banner_base64');
      final url = prefs.getString('cached_banner_url');
      final title = prefs.getString('cached_banner_title');
      final badge = prefs.getString('cached_banner_badge');
      final offerPrice = prefs.getInt('cached_banner_offer_price');
      final origPrice = prefs.getInt('cached_banner_orig_price');
      final remaining = prefs.getInt('cached_banner_stock_remaining');
      final total = prefs.getInt('cached_banner_total_stock');

      if (mounted && (base64 != null || url != null)) {
        Uint8List? decodedBytes;
        if (base64 != null && base64.isNotEmpty) {
          try {
            final clean = base64.contains(',') ? base64.split(',')[1] : base64;
            decodedBytes = base64Decode(clean);
          } catch (_) {}
        }
        setState(() {
          _adminBannerBase64 = base64;
          _cachedAdminBannerBytes = decodedBytes;
          _adminBannerUrl = url;
          _adminBannerTitle = title;
          _adminBannerBadge = badge;
          if (offerPrice != null) _selectedOfferUnitPrice = offerPrice;
          if (origPrice != null) _selectedOfferOriginalPrice = origPrice;
          if (remaining != null) _remainingBiryaniCount = remaining;
          if (total != null) _totalBiryaniCount = total;
        });
      }
    } catch (_) {}
  }

  // 🏷️ Dynamic Offer Banner loaded from Admin Portal
  Future<void> _loadActiveOfferBanner() async {
    try {
      final response = await http.get(ApiConfig.bannerActive).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['success'] == true && data['banner'] != null) {
          final banner = data['banner'] as Map<String, dynamic>;
          final base64 = banner['image_base64'] as String?;
          final url = banner['image_url'] as String?;
          final title = banner['title'] as String?;
          final badge = banner['badge'] as String?;
          final offerPrice = banner['offer_price'] != null ? int.tryParse(banner['offer_price'].toString()) : null;
          final origPrice = banner['original_price'] != null ? int.tryParse(banner['original_price'].toString()) : null;
          final remaining = banner['stock_remaining'] != null ? int.tryParse(banner['stock_remaining'].toString()) : null;
          final total = banner['total_stock'] != null ? int.tryParse(banner['total_stock'].toString()) : null;

          Uint8List? decodedBytes;
          if (base64 != null && base64.isNotEmpty) {
            try {
              final clean = base64.contains(',') ? base64.split(',')[1] : base64;
              decodedBytes = base64Decode(clean);
            } catch (_) {}
          }

          if (mounted) {
            setState(() {
              _adminBannerBase64 = base64;
              _cachedAdminBannerBytes = decodedBytes;
              _adminBannerUrl = url;
              _adminBannerTitle = title;
              _adminBannerBadge = badge;
              if (offerPrice != null) _selectedOfferUnitPrice = offerPrice;
              if (origPrice != null) _selectedOfferOriginalPrice = origPrice;
              if (remaining != null) _remainingBiryaniCount = remaining;
              if (total != null) _totalBiryaniCount = total;
            });
          }

          // Cache in local storage for instant flicker-free load on next app launch
          try {
            final prefs = await SharedPreferences.getInstance();
            if (base64 != null && base64.isNotEmpty) {
              await prefs.setString('cached_banner_base64', base64);
            } else {
              await prefs.remove('cached_banner_base64');
            }
            if (url != null && url.isNotEmpty) {
              await prefs.setString('cached_banner_url', url);
            } else {
              await prefs.remove('cached_banner_url');
            }
            if (title != null) await prefs.setString('cached_banner_title', title);
            if (badge != null) await prefs.setString('cached_banner_badge', badge);
            if (offerPrice != null) await prefs.setInt('cached_banner_offer_price', offerPrice);
            if (origPrice != null) await prefs.setInt('cached_banner_orig_price', origPrice);
            if (remaining != null) await prefs.setInt('cached_banner_stock_remaining', remaining);
            if (total != null) await prefs.setInt('cached_banner_total_stock', total);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // Load cached sliding banners instantly from local storage (Zero flicker on startup)
  Future<void> _loadCachedSlidingBanners() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('cached_sliding_banners_json');
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final List<dynamic> list = json.decode(cachedJson);
        // Filter out any old legacy default banners
        final validList = list.where((e) {
          if (e is! Map) return false;
          final id = (e['id'] ?? '').toString();
          final img = (e['image'] ?? '').toString();
          if (id.startsWith('DEFAULT-') || img.contains('banner_biryani_crushing.jpg')) {
            return false;
          }
          return true;
        }).map((e) => Map<String, dynamic>.from(e as Map)).toList();

        if (validList.isNotEmpty && mounted) {
          setState(() {
            _carouselBanners = validList;
            _isLoadingSlidingBanners = false;
          });
          _startRegularBannerAutoSlide();
        } else if (mounted) {
          setState(() {
            _carouselBanners = [];
            _isLoadingSlidingBanners = false;
          });
        }
      } else if (mounted) {
        setState(() {
          _carouselBanners = [];
          _isLoadingSlidingBanners = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _carouselBanners = [];
          _isLoadingSlidingBanners = false;
        });
      }
    }
  }

  // 🏨 Load Preferred Hotels from Admin Portal
  Future<void> _loadPreferredHotels() async {
    try {
      final response = await http.get(ApiConfig.preferredHotelsActive).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['success'] == true && data['hotels'] is List) {
          final List incoming = data['hotels'] as List;
          final parsed = incoming
              .whereType<Map>()
              .map((h) => Map<String, dynamic>.from(h))
              .toList();
          if (mounted) {
            setState(() {
              _preferredHotels = parsed;
              if (_selectedPreferredHotel != null &&
                  !parsed.any((h) => (h['name'] ?? '').toString() == _selectedPreferredHotel)) {
                _selectedPreferredHotel = null;
                _preferredShopController.clear();
              }
            });
          }
        }
      }
    } catch (_) {}
  }

  // 🔔 Load unread customer notification count for Bell badge
  Future<void> _loadUnreadNotificationCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('user_id') ?? '';
      if (uid.isEmpty) return;
      final res = await http.get(ApiConfig.orderNotificationsAll(uid)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final count = (data['unread_count'] as num?)?.toInt() ??
            ((data['notifications'] as List?)?.where((n) => n['is_read'] != true).length ?? 0);
        if (mounted) {
          setState(() => _unreadNotificationCount = count);
        }
      }
    } catch (_) {}
  }

  // 🎠 Dynamic Sliding Banners loaded from Admin Portal
  Future<void> _loadActiveSlidingBanners() async {
    try {
      final response = await http.get(ApiConfig.bannerSlidingActive).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['success'] == true && data['banners'] is List) {
          final List incoming = data['banners'] as List;
          if (incoming.isEmpty) {
            _bannerTimer?.cancel();
            if (mounted) {
              setState(() {
                _carouselBanners = [];
                _isLoadingSlidingBanners = false;
                _currentBannerIndex = 0;
              });
            }
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('cached_sliding_banners_json', '[]');
            } catch (_) {}
            return;
          }

          if (incoming.isNotEmpty) {
            final List<Map<String, dynamic>> parsedBanners = [];
            for (var b in incoming) {
              if (b is! Map) continue;
              final imgUrl = b['image_url'] as String?;
              final base64 = b['image_base64'] as String?;
              final fallback = (b['fallback_asset'] ?? '').toString();
              final effectiveImg = (imgUrl != null && imgUrl.isNotEmpty)
                  ? imgUrl
                  : (base64 != null && base64.isNotEmpty ? base64 : fallback);

              final title = (b['title'] ?? 'Special Offer').toString();
              final item = (b['item'] ?? title).toString();
              final tag = (b['tag'] ?? 'CRUSHING OFFER').toString();
              final origPrice = (b['original_price'] ?? '150').toString();
              final offerPrice = (b['offer_price'] ?? '49').toString();
              final budget = (b['budget'] ?? offerPrice).toString();

              Uint8List? decodedBytes;
              if (base64 != null && base64.isNotEmpty) {
                try {
                  final clean = base64.contains(',') ? base64.split(',')[1] : base64;
                  decodedBytes = base64Decode(clean);
                } catch (_) {}
              }

              parsedBanners.add({
                'id': b['banner_id'] ?? b['_id'] ?? '',
                'image': effectiveImg,
                'decodedBytes': decodedBytes,
                'fallback': fallback,
                'title': title,
                'tag': tag,
                'originalPrice': origPrice,
                'offerPrice': offerPrice,
                'item': item,
                'budget': budget,
                'isAnyDeal': false,
                'icon': Icons.restaurant_rounded,
                'color': const Color(0xFFEA580C),
              });
            }

            if (parsedBanners.isNotEmpty && mounted) {
              bool isChanged = parsedBanners.length != _carouselBanners.length;
              if (!isChanged) {
                for (int i = 0; i < parsedBanners.length; i++) {
                  if (parsedBanners[i]['id'] != _carouselBanners[i]['id'] ||
                      parsedBanners[i]['image'] != _carouselBanners[i]['image'] ||
                      parsedBanners[i]['offerPrice'] != _carouselBanners[i]['offerPrice'] ||
                      parsedBanners[i]['title'] != _carouselBanners[i]['title']) {
                    isChanged = true;
                    break;
                  }
                }
              }

              if (isChanged || _isLoadingSlidingBanners) {
                setState(() {
                  _carouselBanners = parsedBanners;
                  _isLoadingSlidingBanners = false;
                  if (_currentBannerIndex >= _carouselBanners.length) {
                    _currentBannerIndex = 0;
                  }
                });
                _startRegularBannerAutoSlide();

                try {
                  final prefs = await SharedPreferences.getInstance();
                  final toSave = parsedBanners.map((b) {
                    final copy = Map<String, dynamic>.from(b);
                    copy.remove('decodedBytes');
                    return copy;
                  }).toList();
                  await prefs.setString('cached_sliding_banners_json', json.encode(toSave));
                } catch (_) {}
              }
              return;
            }
          }
        }
      }
    } catch (_) {} finally {
      if (mounted && _isLoadingSlidingBanners) {
        setState(() {
          _isLoadingSlidingBanners = false;
        });
      }
    }
  }

  // 🥘 Load cached quick cravings from local storage (Zero delay on launch)
  Future<void> _loadCachedQuickCravings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('cached_quick_cravings_json');
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final List<dynamic> list = json.decode(cachedJson);
        if (list.isNotEmpty && mounted) {
          setState(() {
            _quickCravings = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          });
        }
      }
    } catch (_) {}
  }

  // 🥘 Dynamic Quick Cravings loaded from Admin Portal
  Future<void> _loadActiveQuickCravings() async {
    try {
      final res = await http.get(ApiConfig.quickCravingsActive).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is Map<String, dynamic> && data['success'] == true && data['cravings'] is List) {
          final List incoming = data['cravings'] as List;
          if (incoming.isNotEmpty) {
            final List<Map<String, dynamic>> parsedList = [];
            for (var c in incoming) {
              if (c is! Map) continue;
              final imgUrl = c['image_url'] as String?;
              final base64 = c['image_base64'] as String?;
              final fallback = (c['fallback_asset'] ?? 'assets/banner_biryani_crushing.jpg').toString();
              final effectiveImg = (imgUrl != null && imgUrl.isNotEmpty)
                  ? imgUrl
                  : (base64 != null && base64.isNotEmpty ? base64 : fallback);

              Uint8List? decodedBytes;
              if (base64 != null && base64.isNotEmpty) {
                try {
                  final clean = base64.contains(',') ? base64.split(',')[1] : base64;
                  decodedBytes = base64Decode(clean);
                } catch (_) {}
              }

              parsedList.add({
                'id': c['craving_id'] ?? c['_id'] ?? '',
                'name': (c['name'] ?? 'Dish').toString(),
                'budget': (c['budget'] ?? '49').toString(),
                'rating': (c['rating'] ?? '4.5').toString(),
                'time': (c['time'] ?? '20-25 mins').toString(),
                'cuisine': (c['cuisine'] ?? 'Food').toString(),
                'icon': (c['icon'] ?? '🍽️').toString(),
                'isVeg': c['isVeg'] == true,
                'image': effectiveImg,
                'decodedBytes': decodedBytes,
              });
            }

            if (parsedList.isNotEmpty && mounted) {
              bool isChanged = parsedList.length != _quickCravings.length;
              if (!isChanged) {
                for (int i = 0; i < parsedList.length; i++) {
                  if (parsedList[i]['id'] != _quickCravings[i]['id'] ||
                      parsedList[i]['name'] != _quickCravings[i]['name'] ||
                      parsedList[i]['rating'] != _quickCravings[i]['rating'] ||
                      parsedList[i]['budget'] != _quickCravings[i]['budget'] ||
                      parsedList[i]['image'] != _quickCravings[i]['image'] ||
                      parsedList[i]['isVeg'] != _quickCravings[i]['isVeg']) {
                    isChanged = true;
                    break;
                  }
                }
              }

              if (isChanged) {
                setState(() {
                  _quickCravings = parsedList;
                });

                try {
                  final prefs = await SharedPreferences.getInstance();
                  final toSave = parsedList.map((item) {
                    final copy = Map<String, dynamic>.from(item);
                    copy.remove('decodedBytes');
                    return copy;
                  }).toList();
                  await prefs.setString('cached_quick_cravings_json', json.encode(toSave));
                } catch (_) {}
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  // 🕒 App Operational Schedule Check (Enforce Store Online/Offline Window)
  Future<void> _checkAppScheduleStatus() async {
    try {
      final res = await http.get(ApiConfig.scheduleStatus).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted && data is Map<String, dynamic> && data['success'] == true) {
          final bool wasOnline = _isStoreOnline;
          final bool newOnline = data['is_online'] == true;

          setState(() {
            _isStoreOnline = newOnline;
            _scheduleStartTime = data['start_time'] ?? "12:30";
            _scheduleEndTime = data['end_time'] ?? "12:45";
            _secondsUntilOpen = data['seconds_until_open'] ?? 0;
            _secondsUntilClose = data['seconds_until_close'] ?? 0;
            if (data['offline_title'] != null && data['offline_title'].toString().trim().isNotEmpty) {
              _offlineTitle = data['offline_title'];
            }
            if (data['offline_message'] != null && data['offline_message'].toString().trim().isNotEmpty) {
              _offlineMessage = data['offline_message'];
            }
          });

          // Sync countdown & status with popup if currently visible
          _closedPopupSetState?.call(() {});

          if (newOnline) {
            _hasAutoShownClosedPopup = false;
            // If closed popup is active, dismiss it automatically
            if (_isClosedPopupOpen && Navigator.of(context, rootNavigator: true).canPop()) {
              Navigator.of(context, rootNavigator: true).pop();
            }
          } else {
            // Store is offline: show popup in front of homepage
            if (!showDeliveryDetails) {
              if (wasOnline && !newOnline) {
                // Time ended while customer was browsing or creating order
                if (_showOrderForm && Navigator.of(context, rootNavigator: true).canPop()) {
                  Navigator.of(context, rootNavigator: true).pop();
                  _showOrderForm = false;
                }
                _hasAutoShownClosedPopup = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_isStoreOnline && !_isClosedPopupOpen) {
                    _showStoreClosedPopup();
                  }
                });
              } else if (!_hasAutoShownClosedPopup) {
                // First launch while closed
                _hasAutoShownClosedPopup = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_isStoreOnline && !_isClosedPopupOpen) {
                    _showStoreClosedPopup();
                  }
                });
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  void _startStoreCountdownTimer() {
    _storeCountdownTimer?.cancel();
    _storeCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_isStoreOnline) {
        if (_secondsUntilClose > 0) {
          setState(() => _secondsUntilClose--);
          if (_secondsUntilClose == 0) {
            _checkAppScheduleStatus();
          }
        } else {
          if (t.tick % 5 == 0) {
            _checkAppScheduleStatus();
          }
        }
      } else {
        if (_secondsUntilOpen > 0) {
          setState(() => _secondsUntilOpen--);
          _closedPopupSetState?.call(() {});
          if (_secondsUntilOpen == 0) {
            _checkAppScheduleStatus();
            _loadActiveOfferBanner();
          }
        } else {
          if (t.tick % 5 == 0) {
            _checkAppScheduleStatus();
            _loadActiveOfferBanner();
          }
        }
      }
    });
  }

  String _format24to12(String timeStr) {
    try {
      final parts = timeStr.trim().split(':');
      int h = int.parse(parts[0]);
      final m = parts[1].padLeft(2, '0');
      final period = h >= 12 ? 'PM' : 'AM';
      if (h == 0) {
        h = 12;
      } else if (h > 12) {
        h -= 12;
      }
      return '$h:$m $period';
    } catch (_) {
      return timeStr;
    }
  }

  String _formatSeconds(int totalSec) {
    if (totalSec <= 0) return "00:00";
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _requestLiveLocation({bool silent = false, bool forceOverrideAddress = true}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && !silent && mounted) {
        await _showTurnOnGPSDialog(
          title: "Turn On GPS Location",
          message: "Please turn ON device GPS to detect your live location.",
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position? position;
        // 1. Fast instant fix from last known position
        try {
          position = await Geolocator.getLastKnownPosition();
        } catch (_) {}

        // 2. High-accuracy live fix
        try {
          final livePos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 8),
          );
          position = livePos;
        } catch (_) {}

        if (position == null) return;
        final curPos = position;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('customer_latitude', curPos.latitude);
        await prefs.setDouble('customer_longitude', curPos.longitude);

        if (mounted) {
          setState(() {
            _customerLocation = LatLng(curPos.latitude, curPos.longitude);
            _riderLocation = LatLng(curPos.latitude + 0.003, curPos.longitude + 0.003);
          });
          _trackingMapController?.animateCamera(
            CameraUpdate.newLatLngZoom(_customerLocation, 15.0),
          );
        }

        String road = "";
        String area = "";
        String city = "";
        String district = "";
        String state = "";
        String postcode = "";

        // 1. High-precision dynamic street/road & locality geocoding via Photon (Komoot)
        try {
          final photonRes = await http.get(
            Uri.parse('https://photon.komoot.io/reverse?lat=${curPos.latitude}&lon=${curPos.longitude}'),
            headers: {'User-Agent': 'GetmyeApp/1.0 (contact@getmye.com)'},
          ).timeout(const Duration(seconds: 4));

          if (photonRes.statusCode == 200) {
            final data = jsonDecode(photonRes.body);
            final features = data['features'] as List?;
            if (features != null && features.isNotEmpty) {
              final props = features[0]['properties'] as Map<String, dynamic>?;
              if (props != null) {
                final pStreet = (props['street'] ?? '').toString().trim();
                final pName = (props['name'] ?? '').toString().trim();
                final pDistrict = (props['district'] ?? props['suburb'] ?? '').toString().trim();
                final pCity = (props['city'] ?? props['county'] ?? '').toString().trim();
                final pState = (props['state'] ?? '').toString().trim();
                final pPostcode = (props['postcode'] ?? '').toString().trim();

                final isMatthiStreet = pStreet.toLowerCase().contains('matthi') || pStreet.toLowerCase().contains('mathi');
                final isMatthiName = pName.toLowerCase().contains('matthi') || pName.toLowerCase().contains('mathi');
                final isMatthiDist = pDistrict.toLowerCase().contains('matthi') || pDistrict.toLowerCase().contains('mathi');

                if (pStreet.isNotEmpty && !isMatthiStreet) {
                  road = pStreet;
                } else if (pName.isNotEmpty && !isMatthiName) {
                  road = pName;
                }

                if (pDistrict.isNotEmpty && !isMatthiDist) {
                  area = pDistrict;
                }

                if (pCity.isNotEmpty) city = pCity;
                if (pState.isNotEmpty) state = pState;
                if (pPostcode.isNotEmpty) postcode = pPostcode;
              }
            }
          }
        } catch (_) {}

        // 2. Secondary fallback via Nominatim dynamic reverse geocoding if road or area is not yet resolved
        if (road.isEmpty || city.isEmpty) {
          try {
            final geoRes = await http.get(
              Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${curPos.latitude}&lon=${curPos.longitude}&zoom=18&addressdetails=1'),
              headers: {'User-Agent': 'GetmyeApp/1.0 (contact@getmye.com)'},
            ).timeout(const Duration(seconds: 4));

            if (geoRes.statusCode == 200) {
              final geoData = jsonDecode(geoRes.body);
              final address = geoData['address'] as Map<String, dynamic>?;
              if (address != null) {
                final nRoad = (address['road'] ?? address['pedestrian'] ?? address['street'] ?? address['residential'] ?? '').toString().trim();
                final nSuburb = (address['suburb'] ?? address['neighbourhood'] ?? address['quarter'] ?? address['subdistrict'] ?? '').toString().trim();
                final nCity = (address['city'] ?? address['town'] ?? address['village'] ?? address['municipality'] ?? '').toString().trim();
                final nDistrict = (address['state_district'] ?? address['county'] ?? '').toString().trim();
                final nState = (address['state'] ?? '').toString().trim();
                final nPostcode = (address['postcode'] ?? '').toString().trim();

                if (road.isEmpty && nRoad.isNotEmpty && !nRoad.toLowerCase().contains('matthi') && !nRoad.toLowerCase().contains('mathi')) {
                  road = nRoad;
                }
                if (area.isEmpty && nSuburb.isNotEmpty && !nSuburb.toLowerCase().contains('matthi') && !nSuburb.toLowerCase().contains('mathi')) {
                  area = nSuburb;
                }
                if (city.isEmpty && nCity.isNotEmpty) city = nCity;
                if (district.isEmpty && nDistrict.isNotEmpty) district = nDistrict;
                if (state.isEmpty && nState.isNotEmpty) state = nState;
                if (postcode.isEmpty && nPostcode.isNotEmpty) postcode = nPostcode;
              }
            }
          } catch (_) {}
        }

        // 🛑 Filter out OpenStreetMap's erroneous suburb tagging for Kumbakonam
        // OSM has an incorrect wide suburb node 'Annalagraharam' covering central town.
        // If a specific road/street is identified (e.g. Nageswaran South Street, TSR Big St),
        // and that road itself is NOT in Annalagraharam, discard the erroneous 'Annalagraharam' tag.
        final bool isRoadInsideAnnalagraharam = road.toLowerCase().contains('annalagraharam');
        if (!isRoadInsideAnnalagraharam && area.toLowerCase().contains('annalagraharam')) {
          area = '';
        }

        // Clean out Matthi / Mathi / Live GPS artifacts
        if (road.toLowerCase().contains('matthi') || road.toLowerCase().contains('mathi') || road.toLowerCase().contains('live gps')) road = '';
        if (area.toLowerCase().contains('matthi') || area.toLowerCase().contains('mathi') || area.toLowerCase().contains('live gps')) area = '';

        if (city.isEmpty) city = 'Kumbakonam';

        // 🌟 Swiggy-style Primary Header (Short Location)
        // Swiggy rule: Show the most specific identifier (Street / Landmark), NOT a cluttered concatenation
        String shortA;
        if (road.isNotEmpty) {
          shortA = road;
        } else if (area.isNotEmpty && area.toLowerCase() != city.toLowerCase()) {
          shortA = area;
        } else {
          shortA = city;
        }

        // 🌟 Swiggy-style Detailed Delivery Address (Full Address)
        // Swiggy rule: Clean, ordered, deduplicated: [Road], [Area if distinct], [City] - [Pincode]
        final List<String> addressParts = [];
        if (road.isNotEmpty) {
          addressParts.add(road);
        }
        if (area.isNotEmpty &&
            area.toLowerCase() != road.toLowerCase() &&
            area.toLowerCase() != city.toLowerCase() &&
            !road.toLowerCase().contains(area.toLowerCase())) {
          addressParts.add(area);
        }
        if (city.isNotEmpty && !addressParts.any((p) => p.toLowerCase() == city.toLowerCase())) {
          addressParts.add(city);
        }

        String fullA = addressParts.isNotEmpty ? addressParts.join(', ') : shortA;
        if (postcode.isNotEmpty && postcode.length >= 6) {
          fullA = '$fullA - $postcode';
        }

        final existingShort = prefs.getString('customer_address_short');
        final bool isStaleShort = existingShort == null ||
            existingShort.isEmpty ||
            existingShort == 'Detecting...' ||
            existingShort == 'Current Location' ||
            existingShort.toLowerCase().contains('matthi') ||
            existingShort.toLowerCase().contains('mathi') ||
            existingShort.toLowerCase().contains('live gps');
        final bool shouldUpdateAddress = forceOverrideAddress || isStaleShort;

        if (shouldUpdateAddress) {
          await prefs.setString('customer_address_short', shortA);
          await prefs.setString('customer_address_full', fullA);
          await prefs.setString('active_order_customer_address', fullA);

          if (mounted) {
            setState(() {
              _currentAddressShort = shortA;
              _currentAddressFull = fullA;
              _deliveryLocationController.text = fullA;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Live location notice: $e");
    }
  }

  void _startOrderChatPolling() {
    _inOrderChatTimer?.cancel();
    _fetchInOrderChat();
    _inOrderChatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchInOrderChat();
    });
  }

  Future<void> _fetchInOrderChat() async {
    if (_isFetchingChat) return;
    _isFetchingChat = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final curOrderId = prefs.getString('active_order_id');
      if (curOrderId == null || curOrderId.isEmpty) return;

      final res = await http.get(ApiConfig.orderMessages(curOrderId)).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List remoteList = data['messages'] ?? [];
        if (mounted && remoteList.length != _inOrderChatMessages.length) {
          final mapped = remoteList.map((e) => Map<String, dynamic>.from(e)).toList();
          setState(() {
            _inOrderChatMessages = mapped;
          });
        }
      }
    } catch (_) {
    } finally {
      _isFetchingChat = false;
    }
  }

  void _startRiderLocationPolling() {
    _riderTrackingTimer?.cancel();
    _fetchRiderLocation();
    _riderTrackingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchRiderLocation();
    });
  }

  Future<void> _fetchTrackingRoadRoute() async {
    try {
      final points = await RouteService.getRoadRoute(_riderLocation, _customerLocation);
      if (mounted && points.isNotEmpty) {
        setState(() {
          _trackingRoutePoints = points;
        });
      }
    } catch (_) {}
  }

  void _fitTrackingMapBounds() {
    if (_trackingMapController == null) return;
    try {
      final southwest = LatLng(
        min(_riderLocation.latitude, _customerLocation.latitude),
        min(_riderLocation.longitude, _customerLocation.longitude),
      );
      final northeast = LatLng(
        max(_riderLocation.latitude, _customerLocation.latitude),
        max(_riderLocation.longitude, _customerLocation.longitude),
      );
      final bounds = LatLngBounds(southwest: southwest, northeast: northeast);
      _trackingMapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 36));
    } catch (_) {
      _trackingMapController?.animateCamera(CameraUpdate.newLatLng(_riderLocation));
    }
  }

  Future<void> _fetchRiderLocation() async {
    if (_isFetchingRiderLoc) return;
    _isFetchingRiderLoc = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pId = prefs.getString('active_order_partner_id') ?? assignedPartnerId;
      if (pId.isEmpty) return;
      final res = await http.get(ApiConfig.trackingByPartner(pId)).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final loc = data['location'];
        if (loc != null && loc['latitude'] != null && loc['longitude'] != null) {
          final lat = (loc['latitude'] as num).toDouble();
          final lng = (loc['longitude'] as num).toDouble();
          if (mounted) {
            final double dist = Geolocator.distanceBetween(
              lat,
              lng,
              _customerLocation.latitude,
              _customerLocation.longitude,
            );
            final bool locChanged = (_riderLocation.latitude != lat || _riderLocation.longitude != lng);
            if (locChanged) {
              setState(() {
                _riderLocation = LatLng(lat, lng);
                _riderDistanceMeters = dist;
              });
              _fitTrackingMapBounds();
              _fetchTrackingRoadRoute();
            }
          }
        }
      }
    } catch (_) {
    } finally {
      _isFetchingRiderLoc = false;
    }
  }

  Future<void> _callDeliveryPartner([String? phone]) async {
    final targetPhone = phone ?? assignedPartnerPhone;
    if (targetPhone.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Delivery partner contact number not available yet"),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
      }
      return;
    }
    final cleanPhone = targetPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not launch phone dialer for $targetPhone"),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  void scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _storeCountdownTimer?.cancel();
    _searchRiderTimer?.cancel();
    _riderTrackingTimer?.cancel();
    _shopAdTimer?.cancel();
    _bannerTimer?.cancel();
    _inOrderChatTimer?.cancel();
    _shopAdPageController.dispose();
    _bannerPageController.dispose();
    _itemController.dispose();
    _budgetController.dispose();
    _quantityController.dispose();
    _chatMsgController.dispose();
    _deliveryLocationController.dispose();
    _preferredShopController.dispose();
    _foodFocusNode.dispose();
    _budgetFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }



  void _showTopMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Getmye Quick Menu",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded, color: AppColors.primary),
                  title: const Text("My Profile", style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delivery_dining_rounded, color: AppColors.primary),
                  title: const Text("Join as Delivery Partner", style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const DeliveryPersonJoinPage()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary),
                  title: const Text("UPI Payment & Wallet", style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentPage()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined, color: AppColors.primary),
                  title: const Text("App Settings & Options", style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const OptionsPage(isDarkMode: false)));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showLocationPickerSheet() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final activeAddId = prefs.getString('active_delivery_add_id');

    List<dynamic> savedAddresses = [];
    bool isFetchingList = true;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            if (isFetchingList && userId != null && userId.isNotEmpty) {
              http.get(ApiConfig.addressList(userId)).then((res) {
                if (res.statusCode == 200) {
                  final data = jsonDecode(res.body);
                  if (data is Map && data['addresses'] is List) {
                    if (modalCtx.mounted) {
                      setModalState(() {
                        savedAddresses = data['addresses'] as List;
                        isFetchingList = false;
                      });
                    }
                    return;
                  }
                }
                if (modalCtx.mounted) setModalState(() => isFetchingList = false);
              }).catchError((_) {
                if (modalCtx.mounted) setModalState(() => isFetchingList = false);
              });
            } else if (isFetchingList) {
              isFetchingList = false;
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Delivery Location",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                "Choose or add address for quick delivery",
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.settings_outlined, size: 16, color: AppColors.primary),
                            label: const Text(
                              "Manage",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AddressScreen()),
                              ).then((_) => _loadSavedLocation());
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Quick Option 1: Use Current Location (GPS)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF93C5FD)),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2563EB),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 18),
                          ),
                          title: const Text(
                            "Use Current Location (GPS)",
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1E40AF)),
                          ),
                          subtitle: const Text(
                            "Auto-detect live GPS location and set as delivery address",
                            style: TextStyle(fontSize: 11, color: Color(0xFF3B82F6)),
                          ),
                          onTap: () async {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Detecting live GPS location..."),
                                duration: Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            await _requestLiveLocation(silent: false, forceOverrideAddress: true);
                          },
                        ),
                      ),

                      // Quick Option 2: Set Location Directly
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.edit_location_alt_rounded, color: AppColors.primary, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  "Set Specific Area / Landmark",
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _customLocationTextController,
                                    decoration: InputDecoration(
                                      hintText: "e.g. Kumbakonam Town, Big Temple",
                                      hintStyle: const TextStyle(fontSize: 12),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      fillColor: Colors.white,
                                      filled: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                  onPressed: () async {
                                    final val = _customLocationTextController.text.trim();
                                    if (val.isEmpty) return;
                                    final p = await SharedPreferences.getInstance();
                                    await p.setString('customer_address_short', val);
                                    await p.setString('customer_address_full', val);
                                    await p.setString('active_order_customer_address', val);
                                    if (mounted) {
                                      setState(() {
                                        _currentAddressShort = val;
                                        _currentAddressFull = val;
                                      });
                                    }
                                    if (modalCtx.mounted) Navigator.pop(modalCtx);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text("Delivery address set to: $val"),
                                          backgroundColor: const Color(0xFF047857),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  },
                                  child: const Text("Set", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Quick Option 2: Enter Location Manually
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.add_location_alt_rounded, color: AppColors.primary, size: 18),
                          ),
                          title: const Text(
                            "Enter Location Manually",
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                          ),
                          subtitle: const Text(
                            "Type house number, street, landmark, and pincode",
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const AddressScreen()),
                            ).then((_) => _loadSavedLocation());
                          },
                        ),
                      ),

                      const Text(
                        "Saved Addresses",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),

                      Flexible(
                        child: isFetchingList
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                                ),
                              )
                            : savedAddresses.isEmpty
                                ? Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.home_work_outlined, color: AppColors.textMuted, size: 22),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            "Current: $_currentAddressShort\nTap 'Enter Location Manually' above to save home/work.",
                                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: savedAddresses.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (itemCtx, index) {
                                      final addr = Map<String, dynamic>.from(savedAddresses[index]);
                                      final addId = addr['add_id']?.toString();
                                      final line1 = addr['line1']?.toString() ?? 'Saved Address';
                                      final city = addr['city']?.toString() ?? '';
                                      final state = addr['state']?.toString() ?? '';
                                      final pincode = addr['pincode']?.toString() ?? '';
                                      final full = [line1, addr['line2'], city, state, pincode]
                                          .where((p) => p != null && p.toString().trim().isNotEmpty)
                                          .join(', ');

                                      final isSelected = (addId != null && addId == activeAddId) ||
                                          _currentAddressFull == full ||
                                          _currentAddressShort == line1 ||
                                          _currentAddressShort == city;

                                      return InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () async {
                                          final p = await SharedPreferences.getInstance();
                                          final shortA = (line1.isNotEmpty && !line1.toLowerCase().contains('live gps') && !line1.toLowerCase().contains('matthi'))
                                              ? line1
                                              : (city.isNotEmpty ? city : 'Kumbakonam');
                                          final fullA = full.isNotEmpty ? full : shortA;

                                          await p.setString('customer_address_short', shortA);
                                          await p.setString('customer_address_full', fullA);
                                          await p.setString('active_order_customer_address', fullA);
                                          if (addId != null) {
                                            await p.setString('active_delivery_add_id', addId);
                                          }

                                          if (addr['latitude'] != null && addr['longitude'] != null) {
                                            final lat = (addr['latitude'] as num).toDouble();
                                            final lng = (addr['longitude'] as num).toDouble();
                                            await p.setDouble('customer_latitude', lat);
                                            await p.setDouble('customer_longitude', lng);
                                            if (mounted) {
                                              setState(() {
                                                _customerLocation = LatLng(lat, lng);
                                                _riderLocation = LatLng(lat + 0.003, lng + 0.003);
                                              });
                                            }
                                          }

                                          if (userId != null && addId != null) {
                                            try {
                                              await http.post(
                                                ApiConfig.addressSetDefault,
                                                headers: {'Content-Type': 'application/json'},
                                                body: jsonEncode({'add_id': addId, 'user_id': userId}),
                                              );
                                            } catch (_) {}
                                          }

                                          if (mounted) {
                                            setState(() {
                                              _currentAddressShort = shortA;
                                              _currentAddressFull = fullA;
                                            });
                                          }

                                          if (modalCtx.mounted) {
                                            Navigator.pop(modalCtx);
                                          }
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text("Selected delivery location: $shortA"),
                                              backgroundColor: AppColors.primary,
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                          decoration: BoxDecoration(
                                            color: isSelected ? const Color(0xFFE8F2FF) : Colors.white,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
                                              width: isSelected ? 1.5 : 1.0,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                isSelected ? Icons.check_circle_rounded : Icons.location_on_outlined,
                                                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                                size: 22,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      line1,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w700,
                                                        color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      full,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (isSelected)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Text(
                                                    "ACTIVE",
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w800,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  DateTime? _lastBackPressTime;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        SystemNavigator.pop();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: showDeliveryDetails
            ? (hasRiderAccepted
                ? SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Blue Location Bar Header (for active order tracking)
                        _buildWineHeader(context, isCompact: true),

                        // Main Body Content
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: _buildAssignedPartnerContainer(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 1. Delivery Partner Card (with Hotel Carousel 1 & SINGLE Cancel Order button inside)
                              _buildExpandedContainer(),

                              const SizedBox(height: 10),

                              // 2. Featured Partner Kitchens (Hotel Carousel 2 in the space below)
                              _buildWaitingHotelsShowcase(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ))
            : (!_hasClaimedFirstOffer
                // -----------------------------------------------------------
                // 1. FIRST-TIME USER OFFER PAGE (Current UI)
                // -----------------------------------------------------------
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Blue background header ONLY for the Location area
                      _buildWineHeader(context, isCompact: true),

                      // Biriyani Offer (1:1 Ratio), Stock, Shop Ads & Button
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: _buildOffersCarouselBanner(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                // -----------------------------------------------------------
                // 2. REGULAR USER PAGE (Design from images / backup)
                // -----------------------------------------------------------
                : SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header with Location (Compact: Location & Profile Bar only)
                        _buildWineHeader(context, isCompact: true),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildRegularOrderFormCard(),
                                  if (_carouselBanners.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    _buildRegularOffersCarouselBanner(),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
        bottomNavigationBar: const CustomerBottomNavBar(currentIndex: 0),
      ),
    ),
  );
}

  // Top Blue Header (Location & Profile bar, and regular carousel when not compact)
  Widget _buildWineHeader(BuildContext context, {bool isCompact = false}) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0C1B30), // Deep Midnight Navy
            Color(0xFF142B4A), // Primary Navy Blue (#142B4A)
            Color(0xFF19355C), // Rich Navy
          ],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A142B4A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: topPadding + 6,
        left: 16,
        right: 16,
        bottom: isCompact ? 12 : 18,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLocationAndProfileRow(),
              if (!isCompact) ...[
                const SizedBox(height: 14),
                _buildRegularOffersCarouselBanner(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationAndProfileRow() {
    return Row(
      children: [
        // Brand Logo (Long press toggles First-Time / Regular view for easy testing)
        GestureDetector(
          onLongPress: _toggleFirstTimeOfferForTesting,
          child: Container(
            height: 38,
            width: 38,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/G_LOGO.PNG',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Location address & picker trigger
        Expanded(
          child: InkWell(
            onTap: _showLocationPickerSheet,
            borderRadius: BorderRadius.circular(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _currentAddressShort,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
                Text(
                  _currentAddressFull,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFCBA0BE),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Notification Bell Icon with Unread Badge -> Opens NotificationsPage
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 24),
              tooltip: "Notifications",
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsPage()),
                );
                _loadUnreadNotificationCount();
              },
            ),
            if (_unreadNotificationCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primaryDark, width: 1.2),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    _unreadNotificationCount > 99 ? '99+' : '$_unreadNotificationCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
          onPressed: _showTopMenu,
          tooltip: "More Options",
        ),
      ],
    );
  }

  void _openOrderFormPopup() {
    if (!_isStoreOnline) {
      _showStoreClosedPopup();
      return;
    }
    setState(() {
      _showOrderForm = true;
      _itemController.text = _adminBannerTitle?.isNotEmpty == true ? _adminBannerTitle! : "Biriyani 65";
      final qty = int.tryParse(_quantityController.text.trim()) ?? 1;
      _quantityController.text = qty.toString();
      _budgetController.text = (_selectedOfferUnitPrice * qty).toString();
    });

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.88,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Grab Handle
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Form card content inside popup
                        _buildOrderFormCard(sheetContext: ctx, setSheetState: setSheetState),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // FIRST-TIME USER OFFER CONFIRMATION FLOW
  // "first time users offer page ku order now click pannathuku aparam
  //  address maatum confrim panitu order a confrim pannidanum."
  // --------------------------------------------------------------------------
  void _openFirstTimeOfferAddressConfirmSheet(BuildContext context) async {
    if (!_isStoreOnline) {
      _showStoreClosedPopup();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final hasActive = prefs.getBool('has_active_order') ?? false;
    final activeStatus = (prefs.getString('active_order_status') ?? '').toLowerCase();
    final existingOrderId = prefs.getString('active_order_id') ?? '';
    if (hasActive && activeStatus != 'delivered' && activeStatus != 'cancelled' && existingOrderId.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "You already have active order #$existingOrderId in progress! Please wait until it is delivered or cancelled before ordering again.",
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.primaryDark,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      setState(() {
        showDeliveryDetails = true;
      });
      scrollToBottom();
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final offerTitle = _adminBannerTitle?.trim().isNotEmpty == true
                ? _adminBannerTitle!.trim()
                : "Chicken Biryani (Welcome Offer)";
            final offerPrice = _selectedOfferUnitPrice;
            final displayAddress = (_deliveryLocationController.text.trim().isNotEmpty &&
                    !_deliveryLocationController.text.trim().toLowerCase().contains('live gps') &&
                    _deliveryLocationController.text.trim() != 'Detecting...')
                ? _deliveryLocationController.text.trim()
                : (_currentAddressFull.isNotEmpty && !_currentAddressFull.toLowerCase().contains('live gps')
                    ? _currentAddressFull
                    : "Detecting exact live GPS location...");

            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -4)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Grab handle
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.local_offer_rounded, color: Color(0xFFEA580C), size: 20),
                              ),
                              const SizedBox(width: 10),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Confirm Your Offer",
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    "Exclusive First Time User Special",
                                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                            onPressed: () => Navigator.pop(sheetContext),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Offer Details Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFED7AA), width: 1.2),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 60,
                                height: 60,
                                child: _buildBannerImageWidget(),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEA580C),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      "FIRST ORDER DEAL",
                                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    offerTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        "₹$offerPrice",
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFFEA580C),
                                        ),
                                      ),
                                      if (_selectedOfferOriginalPrice > offerPrice) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          "₹$_selectedOfferOriginalPrice",
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                            decoration: TextDecoration.lineThrough,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 8),
                                      const Text(
                                        "• Qty: 1",
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Delivery Address Confirmation Card
                      const Text(
                        "Delivery Address",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.location_on_rounded, color: Color(0xFF2563EB), size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              _currentAddressShort.isNotEmpty ? _currentAddressShort : "Delivery Address",
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFDCFCE7),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFF86EFAC)),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                CircleAvatar(radius: 2.5, backgroundColor: Color(0xFF16A34A)),
                                                SizedBox(width: 4),
                                                Text(
                                                  "Live GPS",
                                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        displayAddress,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton.icon(
                                  onPressed: () async {
                                    await _requestLiveLocation(forceOverrideAddress: true);
                                    setSheetState(() {});
                                  },
                                  icon: const Icon(Icons.my_location_rounded, size: 16, color: Color(0xFF2563EB)),
                                  label: const Text("Refresh GPS", style: TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.w700)),
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                                ),
                                TextButton.icon(
                                  onPressed: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const AddressScreen()),
                                    );
                                    await _loadSavedLocation();
                                    setSheetState(() {});
                                  },
                                  icon: const Icon(Icons.edit_location_alt_rounded, size: 16, color: Color(0xFFEA580C)),
                                  label: const Text("Change Address", style: TextStyle(fontSize: 12, color: Color(0xFFEA580C), fontWeight: FontWeight.w700)),
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Payment Note
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.payments_outlined, size: 18, color: Color(0xFF475569)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Payment: Cash on Delivery (COD) / Pay on Delivery",
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Big Confirm Order Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () async {
                            final custAddrRaw = displayAddress;
                            final custAddr = custAddrRaw
                                .replaceAll(RegExp(r'\bmatthi,?\s*', caseSensitive: false), '')
                                .replaceAll(RegExp(r'\bmathi,?\s*', caseSensitive: false), '')
                                .trim();

                            final orderLat = _customerLocation.latitude;
                            final orderLng = _customerLocation.longitude;

                            if (!_isLocationInKumbakonam(orderLat, orderLng)) {
                              Navigator.pop(sheetContext);
                              _showGeofenceRestrictionDialog();
                              return;
                            }

                            await _executeConfirmFirstTimeOfferOrder(
                              offerTitle: offerTitle,
                              offerPrice: offerPrice.toDouble(),
                              custAddr: custAddr,
                              orderLat: orderLat,
                              orderLng: orderLng,
                              sheetContext: sheetContext,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF142B4A),
                            foregroundColor: Colors.white,
                            elevation: 3,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80), size: 22),
                              const SizedBox(width: 10),
                              Text(
                                "Confirm Order • ₹$offerPrice",
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _executeConfirmFirstTimeOfferOrder({
    required String offerTitle,
    required double offerPrice,
    required String custAddr,
    required double orderLat,
    required double orderLng,
    required BuildContext sheetContext,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'usr_001';
    final custName = prefs.getString('user_name') ?? 'Customer';
    final custPhone = prefs.getString('mobile_number') ?? '+91 98765 43210';

    String customerFixedOtp = prefs.getString('customer_fixed_order_otp') ?? '';
    if (customerFixedOtp.isEmpty) {
      final digits = custPhone.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 4) {
        customerFixedOtp = digits.substring(digits.length - 4);
      } else {
        customerFixedOtp = (1000 + Random().nextInt(9000)).toString();
      }
      await prefs.setString('customer_fixed_order_otp', customerFixedOtp);
    }

    String newOrderId = "ORD-${1000 + Random().nextInt(9000)}";

    final safeLat = (orderLat != 0.0)
        ? orderLat
        : (_customerLocation.latitude != 0.0
            ? _customerLocation.latitude
            : 10.9585);
    final safeLng = (orderLng != 0.0)
        ? orderLng
        : (_customerLocation.longitude != 0.0
            ? _customerLocation.longitude
            : 79.3820);

    try {
      final res = await http.post(
        ApiConfig.orderCreate,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'customer_name': custName,
          'customer_phone': custPhone,
          'delivery_address': custAddr,
          'item_name': offerTitle,
          'quantity': 1,
          'budget': offerPrice,
          'cod_otp': customerFixedOtp,
          'customer_latitude': safeLat,
          'customer_longitude': safeLng,
          'is_welcome_offer': true,
          'order_type': 'welcome_offer',
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        if (data['order'] != null) {
          if (data['order']['order_id'] != null) {
            newOrderId = data['order']['order_id'];
          }
          if (data['order']['cod_otp'] != null) {
            customerFixedOtp = data['order']['cod_otp'].toString();
            await prefs.setString('customer_fixed_order_otp', customerFixedOtp);
          }
        }
      } else {
        final data = jsonDecode(res.body);
        final isGeofenceErr = data['error'] == 'GEOFENCE_RESTRICTION' ||
            (data['message'] != null && data['message'].toString().contains('unavailable in your location'));
        if (mounted) {
          if (Navigator.canPop(sheetContext)) Navigator.pop(sheetContext);
          if (isGeofenceErr) {
            _showGeofenceRestrictionDialog();
          } else {
            final errMsg = data['error'] ?? data['message'] ?? 'Failed to create order on server';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errMsg), backgroundColor: AppColors.danger, behavior: SnackBarBehavior.floating),
            );
          }
        }
        return;
      }
    } catch (e) {
      debugPrint("Backend order creation error: $e");
      if (mounted) {
        if (Navigator.canPop(sheetContext)) Navigator.pop(sheetContext);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot connect to server: $e'), backgroundColor: AppColors.danger, behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }

    // Mark offer as claimed!
    await prefs.setBool('has_claimed_first_offer', true);

    await prefs.setString('active_order_id', newOrderId);
    await prefs.setString('active_cod_otp', customerFixedOtp);
    await prefs.setBool('has_active_order', true);
    await prefs.remove('active_order_bill_images');
    await prefs.remove('active_order_bill_image');
    await prefs.remove('order_${newOrderId}_bill_images');
    await prefs.remove('order_${newOrderId}_bill_image');
    if (mounted) {
      setState(() {
        _orderBillImages = [];
      });
    }
    await prefs.remove('order_${newOrderId}_chat_messages');
    await prefs.remove('has_notified_partner_accepted_$newOrderId');
    await prefs.remove('order_${newOrderId}_notified_collected_items');
    await prefs.remove('has_notified_bill_ack_$newOrderId');
    await prefs.remove('has_notified_payment_success_$newOrderId');
    await prefs.remove('has_notified_delivered_$newOrderId');
    await prefs.setString('active_order_item', offerTitle);
    await prefs.setString('active_order_budget', offerPrice.toString());
    await prefs.setString('active_order_quantity', '1');
    _orderSearchStartTime = DateTime.now();
    _allBusyHitCount = 0;
    await prefs.setString('active_order_customer_name', custName);
    await prefs.setString('active_order_customer_phone', custPhone);
    await prefs.setString('active_order_customer_address', custAddr);
    await prefs.setString('active_order_status', 'pending');
    await prefs.setBool('active_order_partner_accepted', false);
    await prefs.setBool('active_order_bill_sent', false);
    await prefs.remove('active_order_partner_name');
    await prefs.remove('active_order_partner_phone');
    await prefs.remove('active_order_partner_id');
    await prefs.remove('active_order_partner_image');

    AlarmService.startCustomerOrderListeningService(
      baseUrl: ApiConfig.baseUrl,
      orderId: newOrderId,
    );
    AlarmService.requestBatteryOptimizationExemption();
    _startOrderPolling(newOrderId);

    if (Navigator.canPop(sheetContext)) {
      Navigator.pop(sheetContext);
    }

    setState(() {
      _hasClaimedFirstOffer = true;
      showDeliveryDetails = true;
      isSearchingRider = true;
      hasRiderAccepted = false;
      showCancelButtonContainer = true;
      assignedPartnerName = "";
      assignedPartnerPhone = "";
      assignedPartnerProfileImage = null;
      _showOrderForm = false;
    });
    scrollToBottom();
  }

  Widget _buildTimerDigitBox(String value, String unit) {
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          Text(
            unit,
            style: const TextStyle(
              color: Color(0xFF93C5FD),
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffersCarouselBanner() {
    final int secs = _secondsUntilClose > 0 ? _secondsUntilClose : 0;
    final String hrsStr = (secs ~/ 3600).toString().padLeft(2, '0');
    final String minsStr = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
    final String secsStr = (secs % 60).toString().padLeft(2, '0');

    return Column(
      children: [
        // 1. LIMITED TIME OFFER Card (Timer only, NO LEFT count inside)
        if (_isStoreOnline && _secondsUntilClose > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border, width: 1.2),
              boxShadow: AppColors.subtleShadow,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Flexible(
                            child: Text(
                              'LIMITED TIME OFFER',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Grab before timer hits zero',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTimerDigitBox(hrsStr, 'HR'),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 3),
                      child: Text(':', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    ),
                    _buildTimerDigitBox(minsStr, 'MIN'),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 3),
                      child: Text(':', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    ),
                    _buildTimerDigitBox(secsStr, 'SEC'),
                  ],
                ),
              ],
            ),
          )
        else if (!_isStoreOnline)
          GestureDetector(
            onTap: _showStoreClosedPopup,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircleAvatar(radius: 3.5, backgroundColor: Color(0xFFDC2626)),
                  const SizedBox(width: 6),
                  Text(
                    "Service Closed • Opens at ${_format24to12(_scheduleStartTime)} (Tap for details)",
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 2. Standalone 1:1 Offer Image (No outer container, no badges)
        Expanded(
          child: Center(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: InkWell(
                    onTap: () => _openFirstTimeOfferAddressConfirmSheet(context),
                    child: _buildBannerImageWidget(),
                  ),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 3. Dynamic Decreasing 'Left : <count>' Container (Matching Timer Digit Box style)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            'Holding On : $_remainingBiryaniCount',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.4,
            ),
          ),
        ),

        const SizedBox(height: 10),

        // 4. Primary Order Now Pill Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () => _openFirstTimeOfferAddressConfirmSheet(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              shadowColor: AppColors.primaryDark.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Order Now  •  ₹$_selectedOfferUnitPrice",
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 19, color: Colors.white),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 🕒 Store Closed Popup (Dialog shown in front of homepage when closed or when attempting to order)
  void _showStoreClosedPopup() {
    if (_isClosedPopupOpen) return;
    _isClosedPopupOpen = true;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setPopupState) {
            _closedPopupSetState = setPopupState;
            final startFormatted = _format24to12(_scheduleStartTime);
            final endFormatted = _format24to12(_scheduleEndTime);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Top Row: (X) Close Button
                          Align(
                            alignment: Alignment.topRight,
                            child: InkWell(
                              onTap: () => Navigator.of(dialogCtx).pop(),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF1F5F9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),

                          // Big Clock / Store Closed Icon
                          Container(
                            width: 80,
                            height: 80,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFFDE68A), width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.access_time_filled_rounded,
                              size: 46,
                              color: Color(0xFFEA580C),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Closed Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFFCA5A5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(radius: 3.5, backgroundColor: Color(0xFFDC2626)),
                                SizedBox(width: 6),
                                Text(
                                  "SERVICE CURRENTLY CLOSED",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFB91C1C),
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Title
                          Text(
                            _offlineTitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Description / Offline Message
                          Text(
                            _offlineMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Operating Hours Slot Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  "TODAY'S ORDERING WINDOW",
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF64748B),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.alarm_on_rounded, color: Color(0xFFEA580C), size: 18),
                                    const SizedBox(width: 6),
                                    Text(
                                      "$startFormatted – $endFormatted",
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                const SizedBox(height: 10),

                                // Countdown Timer
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      "Orders Open in: ",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFFDE68A)),
                                      ),
                                      child: Text(
                                        _formatSeconds(_secondsUntilOpen),
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF9A3412),
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Refresh Status Button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await _checkAppScheduleStatus();
                                await _loadActiveOfferBanner();
                                if (_isStoreOnline && dialogCtx.mounted) {
                                  Navigator.of(dialogCtx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('🎉 Store is now OPEN for orders!'),
                                      backgroundColor: Color(0xFF16A34A),
                                    ),
                                  );
                                } else {
                                  setPopupState(() {});
                                }
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 15),
                              label: const Text('Check Status Again', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF142B4A),
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      _isClosedPopupOpen = false;
      _closedPopupSetState = null;
    });
  }

  Widget _buildStoreClosedView() {
    return _buildOffersCarouselBanner();
  }

  Widget _buildBannerImageWidget() {
    if (_cachedAdminBannerBytes != null) {
      return Image.memory(
        _cachedAdminBannerBytes!,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _buildBannerPlaceholder(),
      );
    }
    if (_adminBannerUrl != null && _adminBannerUrl!.trim().isNotEmpty && _adminBannerUrl!.startsWith('http')) {
      return Image.network(
        _adminBannerUrl!,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildBannerPlaceholder();
        },
        errorBuilder: (_, __, ___) => _buildBannerPlaceholder(),
      );
    }
    return _buildBannerPlaceholder();
  }

  Widget _buildBannerPlaceholder() {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  const Color(0xFFEA580C).withValues(alpha: 0.7),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Loading Offer...",
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShopAdCarousel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.campaign_rounded, color: Color(0xFFEA580C), size: 17),
                SizedBox(width: 6),
                Text(
                  "Shop Advertisements",
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: const Text(
                "SPONSORED",
                style: TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // 3:1 Aspect Ratio Ad Carousel (View Only)
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF142B4A).withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 3.0, // 3:1 ratio
              child: PageView.builder(
                controller: _shopAdPageController,
                itemCount: _shopAdBanners.length,
                onPageChanged: (idx) {
                  setState(() => _currentShopAdIndex = idx);
                },
                itemBuilder: (context, index) {
                  final ad = _shopAdBanners[index];
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Food Image Background
                      Image.asset(
                        ad['image'] as String,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                      ),
                      // Dark Gradient Overlay for Readability
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.black.withValues(alpha: 0.88),
                              Colors.black.withValues(alpha: 0.65),
                              Colors.black.withValues(alpha: 0.20),
                            ],
                          ),
                        ),
                      ),
                      // Shop Branding Content
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (ad['color'] as Color).withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    ad['badge'] as String,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 11),
                                      const SizedBox(width: 2),
                                      Text(
                                        ad['rating'] as String,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              ad['name'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ad['tagline'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFFDE68A),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, color: Colors.white70, size: 11),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    ad['location'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),

        const SizedBox(height: 6),

        // Dots Indicator for Shop Ads
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_shopAdBanners.length, (idx) {
            final isActive = _currentShopAdIndex == idx;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              height: 3.5,
              width: isActive ? 14 : 4,
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFEA580C) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ],
    );
  }



  // Dynamic Food Image Loader for Quick Cravings (Network, Memory/Base64, or Asset)
  Widget _buildQuickCravingImage(Map<String, dynamic> dish) {
    final img = (dish['image'] ?? '').toString();
    final fallbackIcon = (dish['icon'] ?? '🍽️').toString();

    Widget placeholderWidget = Container(
      color: AppColors.primaryLight,
      child: Center(
        child: Text(fallbackIcon, style: const TextStyle(fontSize: 44)),
      ),
    );

    if (dish['decodedBytes'] is Uint8List) {
      return Image.memory(
        dish['decodedBytes'] as Uint8List,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => placeholderWidget,
      );
    }

    if (img.startsWith('http://') || img.startsWith('https://')) {
      return Image.network(
        img,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => placeholderWidget,
      );
    } else if (img.startsWith('data:image') || (img.length > 500 && !img.contains('/'))) {
      try {
        final clean = img.contains(',') ? img.split(',').last : img;
        final bytes = base64Decode(clean);
        dish['decodedBytes'] = bytes;
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => placeholderWidget,
        );
      } catch (_) {
        return placeholderWidget;
      }
    } else if (img.isNotEmpty) {
      return Image.asset(
        img,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => placeholderWidget,
      );
    }
    return placeholderWidget;
  }

  // Quick Cravings Suggestions Food Image Buttons
  Widget _buildQuickCravings() {
    final cravings = _filteredCravings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      isVegOnly ? "Pure Veg Delights 🌱" : "Quick Cravings",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text("⚡", style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
            if (isVegOnly) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Text("VEG ONLY ACTIVE", style: TextStyle(color: Color(0xFF15803D), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (cravings.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.search_off_rounded, color: AppColors.textSecondary),
                SizedBox(width: 8),
                Text("No items found. Try another search or toggle VEG filter.", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: cravings.map((dish) {
                final isSelected = _itemController.text.trim().toLowerCase() == (dish['name'] as String).trim().toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 11),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _itemController.text = dish['name'] as String;
                        _budgetController.text = dish['budget'] as String;
                      });
                      _scrollToOrderForm();
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 118,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 1. Food Image Card with Overlay
                          Container(
                            width: 118,
                            height: 112,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? AppColors.primary : Colors.transparent,
                                width: isSelected ? 2.2 : 0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(isSelected ? 13.8 : 16),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // Food Image
                                  _buildQuickCravingImage(dish),
                                  // Top-Right: Heart Outline Icon
                                  Positioned(
                                    top: 7,
                                    right: 7,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.25),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.favorite_border_rounded,
                                        color: Colors.white,
                                        size: 15,
                                      ),
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
                                        color: dish['isVeg'] == true ? AppColors.vegGreen : AppColors.nonVegRed,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),

                          // 2. Food Name Below Image
                          Text(
                            dish['name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? AppColors.primary : const Color(0xFF1E293B),
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),

                          // 3. Star Rating
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(1.5),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF15803D),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.star_rounded,
                                  size: 9.5,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "${dish['rating']}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  // Custom Food Order Form Card
  Widget _buildOrderFormCard({BuildContext? sheetContext, StateSetter? setSheetState}) {
    return Container(
      key: _orderFormCardKey,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF142B4A).withValues(alpha: 0.10),
            blurRadius: 28,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE).withValues(alpha: 0.6)),
                      ),
                      child: const Icon(Icons.restaurant_rounded, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Let's Fell Your Order",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Select quantity & confirm delivery address",
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("🔥", style: TextStyle(fontSize: 10)),
                        const SizedBox(width: 3),
                        Text(
                          "₹$_selectedOfferUnitPrice DEAL",
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (sheetContext != null) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                      onPressed: () => Navigator.pop(sheetContext),
                      tooltip: 'Close',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildTextField('Item Name (Fixed)', TextInputType.text, _itemController, Icons.fastfood_outlined, readOnly: true),
          const SizedBox(height: 14),
          _buildTextField('Budget (₹) (Fixed)', TextInputType.number, _budgetController, Icons.currency_rupee_rounded, readOnly: true),
          const SizedBox(height: 14),
          _buildQuantityField(setSheetState: setSheetState),
          const SizedBox(height: 14),
          _buildDropdown(setSheetState: setSheetState),
          const SizedBox(height: 20),

          // Order Now Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () async {
                final itemText = _itemController.text.trim();
                if (itemText.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter an item name')),
                  );
                  return;
                }

                // 🛑 Requirement: Both item name and budget are mandatory
                final budgetText = _budgetController.text.trim();
                final budgetVal = double.tryParse(budgetText);
                if (budgetText.isEmpty || budgetVal == null || budgetVal <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter your budget')),
                  );
                  return;
                }

                // 🛑 Quantity validation
                final qtyText = _quantityController.text.trim();
                final qtyVal = int.tryParse(qtyText);
                if (qtyText.isEmpty || qtyVal == null || qtyVal <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid quantity (1 or more)')),
                  );
                  return;
                }
                final prefs = await SharedPreferences.getInstance();

                // 🛑 Requirement: "cutomer um oru order mudinja tha adutha order podanum athu maari vai"
                final hasActive = prefs.getBool('has_active_order') ?? false;
                final activeStatus = (prefs.getString('active_order_status') ?? '').toLowerCase();
                final existingOrderId = prefs.getString('active_order_id') ?? '';
                if (hasActive && activeStatus != 'delivered' && activeStatus != 'cancelled' && existingOrderId.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "You already have active order #$existingOrderId in progress! Please wait until it is delivered or cancelled before ordering again.",
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: AppColors.primaryDark,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                  setState(() {
                    showDeliveryDetails = true;
                  });
                  scrollToBottom();
                  return;
                }

                final userId = prefs.getString('user_id') ?? 'usr_001';
                final custName = prefs.getString('user_name') ?? 'Customer';
                final custPhone = prefs.getString('mobile_number') ?? '+91 98765 43210';
                final custAddrRaw = (_deliveryLocationController.text.trim().isNotEmpty &&
                        !_deliveryLocationController.text.trim().toLowerCase().contains('live gps') &&
                        _deliveryLocationController.text.trim() != 'Detecting...')
                    ? _deliveryLocationController.text.trim()
                    : (_currentAddressFull.isNotEmpty && !_currentAddressFull.toLowerCase().contains('live gps')
                        ? _currentAddressFull
                        : "Kumbakonam, Thanjavur District, Tamil Nadu 612001");
                final custAddr = custAddrRaw
                    .replaceAll(RegExp(r'\bmatthi,?\s*', caseSensitive: false), '')
                    .replaceAll(RegExp(r'\bmathi,?\s*', caseSensitive: false), '')
                    .trim();

                // ⚡ Fast: Live GPS coordinates of selected customer address
                final orderLat = _customerLocation.latitude;
                final orderLng = _customerLocation.longitude;

                // 🛑 Strict Geofencing: Initially launching exclusively in Kumbakonam town
                if (!_isLocationInKumbakonam(orderLat, orderLng)) {
                  _showGeofenceRestrictionDialog();
                  return;
                }

                // Show searching immediately with clean partner state
                setState(() {
                  showDeliveryDetails = true;
                  isSearchingRider = true;
                  hasRiderAccepted = false;
                  showCancelButtonContainer = true;
                  assignedPartnerName = "";
                  assignedPartnerPhone = "";
                  assignedPartnerProfileImage = null;
                });
                scrollToBottom();

                String newOrderId = "ORD-${1000 + Random().nextInt(9000)}";

                // Retrieve or generate customer's fixed OTP
                String customerFixedOtp = prefs.getString('customer_fixed_order_otp') ?? '';
                if (customerFixedOtp.isEmpty) {
                  final digits = custPhone.replaceAll(RegExp(r'\D'), '');
                  if (digits.length >= 4) {
                    customerFixedOtp = digits.substring(digits.length - 4);
                  } else {
                    customerFixedOtp = (1000 + Random().nextInt(9000)).toString();
                  }
                  await prefs.setString('customer_fixed_order_otp', customerFixedOtp);
                }

                try {
                  // Call backend to create the real order in MongoDB with customer's fixed OTP
                  final res = await http.post(
                    ApiConfig.orderCreate,
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'user_id': userId,
                      'customer_name': custName,
                      'customer_phone': custPhone,
                      'delivery_address': custAddr,
                      'item_name': itemText,
                      'quantity': qtyVal,
                      'budget': budgetVal,
                      'cod_otp': customerFixedOtp,
                      'customer_latitude': orderLat,
                      'customer_longitude': orderLng,
                    }),
                  ).timeout(const Duration(seconds: 15));
                  if (res.statusCode == 200 || res.statusCode == 201) {
                    final data = jsonDecode(res.body);
                    if (data['order'] != null) {
                      if (data['order']['order_id'] != null) {
                        newOrderId = data['order']['order_id'];
                      }
                      if (data['order']['cod_otp'] != null) {
                        customerFixedOtp = data['order']['cod_otp'].toString();
                        await prefs.setString('customer_fixed_order_otp', customerFixedOtp);
                      }
                    }
                  } else {
                    final data = jsonDecode(res.body);
                    final isGeofenceErr = data['error'] == 'GEOFENCE_RESTRICTION' ||
                        (data['message'] != null && data['message'].toString().contains('unavailable in your location'));
                    if (mounted) {
                      setState(() {
                        isSearchingRider = false;
                        showDeliveryDetails = false;
                      });
                      if (isGeofenceErr) {
                        _showGeofenceRestrictionDialog();
                      } else {
                        final errMsg = data['error'] ?? data['message'] ?? 'Failed to create order on server';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(errMsg),
                            backgroundColor: AppColors.danger,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                    return;
                  }
                } catch (e) {
                  debugPrint("Backend order creation error: $e");
                  if (mounted) {
                    setState(() {
                      isSearchingRider = false;
                      showDeliveryDetails = true;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Cannot connect to server: $e'),
                        backgroundColor: AppColors.danger,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  return;
                }

                await prefs.setString('active_order_id', newOrderId);
                await prefs.setString('active_cod_otp', customerFixedOtp);
                await prefs.setBool('has_active_order', true);
                await prefs.remove('active_order_bill_images');
                await prefs.remove('active_order_bill_image');
                await prefs.remove('order_${newOrderId}_bill_images');
                await prefs.remove('order_${newOrderId}_bill_image');
                if (mounted) {
                  setState(() {
                    _orderBillImages = [];
                  });
                }
                await prefs.remove('order_${newOrderId}_chat_messages'); // Reset chat for fresh new order
                await prefs.remove('has_notified_partner_accepted_$newOrderId');
                await prefs.remove('order_${newOrderId}_notified_collected_items');
                await prefs.remove('has_notified_bill_ack_$newOrderId');
                await prefs.remove('has_notified_payment_success_$newOrderId');
                await prefs.remove('has_notified_delivered_$newOrderId');
                await prefs.setString('active_order_item', itemText);
                await prefs.setString('active_order_budget', _budgetController.text.trim());
                await prefs.setString('active_order_quantity', qtyVal.toString());
                _orderSearchStartTime = DateTime.now();
                _allBusyHitCount = 0;
                await prefs.setString('active_order_customer_name', custName);
                await prefs.setString('active_order_customer_phone', custPhone);
                await prefs.setString('active_order_customer_address', custAddr);
                await prefs.setString('active_order_status', 'pending');
                await prefs.setBool('active_order_partner_accepted', false);
                await prefs.setBool('active_order_bill_sent', false);
                await prefs.remove('active_order_partner_name');
                await prefs.remove('active_order_partner_phone');
                await prefs.remove('active_order_partner_id');
                await prefs.remove('active_order_partner_image');
                AlarmService.startCustomerOrderListeningService(
                  baseUrl: ApiConfig.baseUrl,
                  orderId: newOrderId,
                );
                AlarmService.requestBatteryOptimizationExemption();
                _startOrderPolling(newOrderId);
                if (sheetContext != null && Navigator.canPop(sheetContext)) {
                  Navigator.pop(sheetContext);
                }
                setState(() {
                  showDeliveryDetails = true;
                  showCancelButtonContainer = true;
                  _showOrderForm = false;
                });
                scrollToBottom();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Order Now'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextInputType type, TextEditingController controller, IconData icon, {bool readOnly = false}) {
    return Container(
      decoration: BoxDecoration(
        color: readOnly ? const Color(0xFFF1F5F9) : AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: type,
        style: TextStyle(
          fontSize: 14,
          color: readOnly ? const Color(0xFF334155) : AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: AppColors.primaryDark, size: 20),
          suffixIcon: readOnly ? const Tooltip(message: "Fixed value", child: Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF94A3B8))) : null,
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildQuantityField({StateSetter? setSheetState}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w700),
              onChanged: (val) {
                final current = int.tryParse(val.trim());
                if (current != null && current > 0) {
                  setState(() {
                    _budgetController.text = (_selectedOfferUnitPrice * current).toString();
                  });
                  if (setSheetState != null) {
                    setSheetState(() {});
                  }
                }
              },
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.format_list_numbered_rounded, color: AppColors.primaryDark, size: 20),
                labelText: 'Quantity (tap or use +/-)',
                labelStyle: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.primaryDark, size: 22),
            onPressed: () {
              final current = int.tryParse(_quantityController.text.trim()) ?? 1;
              if (current > 1) {
                final newQ = current - 1;
                setState(() {
                  _quantityController.text = newQ.toString();
                  _budgetController.text = (_selectedOfferUnitPrice * newQ).toString();
                });
                if (setSheetState != null) {
                  setSheetState(() {});
                }
              }
            },
            tooltip: "Decrease quantity",
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primaryDark, size: 22),
            onPressed: () {
              final current = int.tryParse(_quantityController.text.trim()) ?? 1;
              final newQ = current + 1;
              setState(() {
                _quantityController.text = newQ.toString();
                _budgetController.text = (_selectedOfferUnitPrice * newQ).toString();
              });
              if (setSheetState != null) {
                setSheetState(() {});
              }
            },
            tooltip: "Increase quantity",
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // REGULAR HOME PAGE WIDGETS (Matching user's images / backup design)
  // --------------------------------------------------------------------------

  Widget _buildCarouselBannerImage(Map<String, dynamic> banner) {
    final img = (banner['image'] ?? '').toString();
    final fallback = (banner['fallback'] ?? 'assets/banner_biryani_crushing.jpg').toString();

    Widget fallbackWidget = Image.asset(
      fallback,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
    );

    // If pre-decoded bytes exist in map, use them directly with gaplessPlayback
    if (banner['decodedBytes'] is Uint8List) {
      return Image.memory(
        banner['decodedBytes'] as Uint8List,
        fit: BoxFit.fill,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => fallbackWidget,
      );
    }

    if (img.startsWith('http://') || img.startsWith('https://')) {
      return Image.network(
        img,
        fit: BoxFit.fill,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => fallbackWidget,
      );
    } else if (img.startsWith('data:image') || (img.length > 500 && !img.contains('/'))) {
      try {
        final clean = img.contains(',') ? img.split(',').last : img;
        final bytes = base64Decode(clean);
        banner['decodedBytes'] = bytes;
        return Image.memory(
          bytes,
          fit: BoxFit.fill,
          gaplessPlayback: true,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => fallbackWidget,
        );
      } catch (_) {
        return fallbackWidget;
      }
    } else if (img.isNotEmpty) {
      return Image.asset(
        img,
        fit: BoxFit.fill,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => fallbackWidget,
      );
    }
    return fallbackWidget;
  }

  // 1. Promotional Auto-Sliding Offers Carousel
  Widget _buildRegularOffersCarouselBanner() {
    if (_carouselBanners.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: AspectRatio(
              aspectRatio: 1024 / 571,
              child: PageView.builder(
                controller: _bannerPageController,
                itemCount: _carouselBanners.length,
                onPageChanged: (idx) {
                  setState(() => _currentBannerIndex = idx);
                },
                itemBuilder: (context, index) {
                  final banner = _carouselBanners[index];
                  return InkWell(
                    onTap: () => _applyBannerOffer(banner),
                    child: _buildCarouselBannerImage(banner),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Dots Indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_carouselBanners.length, (idx) {
            final isActive = _currentBannerIndex == idx;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              height: 4,
              width: isActive ? 16 : 5,
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ],
    );
  }

  // Suggestion chips for Craving items
  Widget _buildItemSuggestionChips() {
    final chips = [
      {'name': 'Biryani', 'icon': '🍗'},
      {'name': 'Shawarma', 'icon': '🌯'},
      {'name': 'Dosa', 'icon': '🥞'},
      {'name': 'Fried Rice', 'icon': '🍚'},
      {'name': 'Momos', 'icon': '🥟'},
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: chips.map((chip) {
          final isSelected = _itemController.text.trim().toLowerCase().contains((chip['name'] as String).toLowerCase());
          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _itemController.text = chip['name'] as String;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFFCBD5E1),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(chip['icon'] as String, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    Text(
                      chip['name'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Suggestion pills for Budget amounts
  Widget _buildBudgetSuggestionPills() {
    final pills = ['50', '100', '150', '200', '300'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: pills.map((p) {
          final isSelected = _budgetController.text.trim() == p;
          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _budgetController.text = p;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFFF7ED) : const Color(0xFFFFF7ED).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? const Color(0xFFEA580C) : const Color(0xFFFED7AA),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  '₹$p',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                    color: const Color(0xFFC2410C),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Dropdown helpers for Food Name, Budget, and Admin-managed Preferred Hotels
  void _showFoodSuggestionsSheet() {
    final foods = [
      {'name': 'Biryani', 'icon': '🍗'},
      {'name': 'Pizza', 'icon': '🍕'},
      {'name': 'Dosa', 'icon': '🥞'},
      {'name': 'Burger', 'icon': '🍔'},
      {'name': 'Fried Rice', 'icon': '🍚'},
      {'name': 'Chicken Shawarma', 'icon': '🌯'},
      {'name': 'Hot Momos', 'icon': '🥟'},
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Food Item',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              ...foods.map((f) => ListTile(
                    dense: true,
                    leading: Text(f['icon']!, style: const TextStyle(fontSize: 20)),
                    title: Text(
                      f['name']!,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    trailing: _itemController.text.trim().toLowerCase() == f['name']!.toLowerCase()
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
                        : null,
                    onTap: () {
                      setState(() => _itemController.text = f['name']!);
                      Navigator.pop(ctx);
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showBudgetSuggestionsSheet() {
    final amounts = ['50', '100', '150', '200', '300', '500'];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Budget Range',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              ...amounts.map((amt) => ListTile(
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.currency_rupee_rounded, color: AppColors.primary, size: 18),
                    ),
                    title: Text(
                      '₹$amt',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    trailing: _budgetController.text.trim() == amt
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
                        : null,
                    onTap: () {
                      setState(() => _budgetController.text = amt);
                      Navigator.pop(ctx);
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showPreferredHotelsDropdownSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Preferred Hotel',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 20),
                    onPressed: () async {
                      await _loadPreferredHotels();
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) _showPreferredHotelsDropdownSheet();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ListTile(
                dense: true,
                leading: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 20),
                title: const Text(
                  'Any Best Hotel (No preference)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
                trailing: _selectedPreferredHotel == null
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
                    : null,
                onTap: () {
                  setState(() {
                    _selectedPreferredHotel = null;
                    _preferredShopController.clear();
                  });
                  Navigator.pop(ctx);
                },
              ),
              const Divider(height: 8),
              if (_preferredHotels.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: Text(
                      'No hotels configured by Admin yet.',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _preferredHotels.length,
                    itemBuilder: (_, index) {
                      final h = _preferredHotels[index];
                      final hotelName = (h['name'] ?? '').toString();
                      final area = (h['area'] ?? '').toString();
                      final isSelected = _selectedPreferredHotel == hotelName;
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.apartment_rounded, color: AppColors.primary, size: 20),
                        title: Text(
                          hotelName,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        subtitle: area.isNotEmpty
                            ? Text(area, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary))
                            : null,
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedPreferredHotel = hotelName;
                            _preferredShopController.text = hotelName;
                          });
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static const List<Map<String, String>> _kSouthIndianFoods = [
    {'name': 'Appam with Stew', 'icon': '🥞'},
    {'name': 'Biryani (Chicken)', 'icon': '🍗'},
    {'name': 'Biryani (Mutton)', 'icon': '🍖'},
    {'name': 'Biryani (Veg)', 'icon': '🍛'},
    {'name': 'Bisi Bele Bath', 'icon': '🍲'},
    {'name': 'Bajji (Chilli / Vazhakkai)', 'icon': '🥟'},
    {'name': 'Bonda (Mysore / Aloo)', 'icon': '🧆'},
    {'name': 'Bun Parotta', 'icon': '🫓'},
    {'name': 'Butter Naan & Gravy', 'icon': '🫓'},
    {'name': 'Badam Milk', 'icon': '🥛'},
    {'name': 'Chicken 65', 'icon': '🍗'},
    {'name': 'Chicken Fried Rice', 'icon': '🍚'},
    {'name': 'Chicken Shawarma', 'icon': '🌯'},
    {'name': 'Chilli Parotta', 'icon': '🫓'},
    {'name': 'Curd Rice', 'icon': '🍚'},
    {'name': 'Dosa (Plain / Roast)', 'icon': '🥞'},
    {'name': 'Egg Fried Rice', 'icon': '🍚'},
    {'name': 'Filter Coffee', 'icon': '☕'},
    {'name': 'Ghee Roast Dosa', 'icon': '🥞'},
    {'name': 'Hot Momos', 'icon': '🥟'},
    {'name': 'Idli & Sambar', 'icon': '⚪'},
    {'name': 'Idiyappam & Kurma', 'icon': '🍜'},
    {'name': 'Kothu Parotta', 'icon': '🥘'},
    {'name': 'Lemon Rice', 'icon': '🍋'},
    {'name': 'Masala Dosa', 'icon': '🥞'},
    {'name': 'Medu Vada', 'icon': '🍩'},
    {'name': 'Onion Uttapam', 'icon': '🥞'},
    {'name': 'Paneer Butter Masala', 'icon': '🍛'},
    {'name': 'Parotta & Salna', 'icon': '🫓'},
    {'name': 'Pongal & Vada', 'icon': '🍲'},
    {'name': 'Poori Masala', 'icon': '🫓'},
    {'name': 'Rava Dosa', 'icon': '🥞'},
    {'name': 'Sambar Rice', 'icon': '🍛'},
    {'name': 'Tomato Rice', 'icon': '🍅'},
    {'name': 'Veg Meals (Full)', 'icon': '🍱'},
  ];

  static const List<String> _kBudgetOptions = ['50', '100', '120', '150', '200', '250', '300', '500'];

  List<Map<String, String>> _filteredFoodSuggestions() {
    final query = _itemController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _kSouthIndianFoods.take(6).toList();
    }
    final startsWith = _kSouthIndianFoods
        .where((f) => f['name']!.toLowerCase().startsWith(query))
        .toList();
    final contains = _kSouthIndianFoods
        .where((f) =>
            !f['name']!.toLowerCase().startsWith(query) &&
            f['name']!.toLowerCase().contains(query))
        .toList();
    return [...startsWith, ...contains].take(6).toList();
  }

  List<String> _filteredBudgetSuggestions() {
    final query = _budgetController.text.trim();
    if (query.isEmpty) return _kBudgetOptions;
    final matches = _kBudgetOptions.where((b) => b.startsWith(query) || b.contains(query)).toList();
    return matches.isNotEmpty ? matches : _kBudgetOptions;
  }

  Widget _buildSeamlessAutocompleteField({
    required IconData icon,
    required String label,
    required String hint,
    required TextEditingController controller,
    required FocusNode focusNode,
    required TextInputType keyboardType,
    required Widget? dropdownOverlay,
  }) {
    final isFocused = focusNode.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => focusNode.requestFocus(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isFocused ? AppColors.primary : AppColors.border,
                width: isFocused ? 1.5 : 1.1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  height: 38,
                  width: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      TextField(
                        controller: controller,
                        focusNode: focusNode,
                        keyboardType: keyboardType,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: hint,
                          hintStyle: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                          filled: false,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 2),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (dropdownOverlay != null) dropdownOverlay,
      ],
    );
  }

  Widget _buildSelectorOnlyField({
    required IconData icon,
    required String label,
    required String valueText,
    required bool isPlaceholder,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 1.1),
        ),
        child: Row(
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    valueText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isPlaceholder ? 13 : 14,
                      fontWeight: isPlaceholder ? FontWeight.w400 : FontWeight.w600,
                      color: isPlaceholder ? AppColors.textSecondary : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 3. Custom Food Order Form Card (Reference-inspired layout with Brand Colors)
  Widget _buildRegularOrderFormCard() {
    final displayAddress = _deliveryLocationController.text.trim().isNotEmpty
        ? _deliveryLocationController.text.trim()
        : (_currentAddressFull.isNotEmpty ? _currentAddressFull : 'Enter delivery address');
    final hasAddress = _deliveryLocationController.text.trim().isNotEmpty || _currentAddressFull.isNotEmpty;

    final foodMatches = _foodFocusNode.hasFocus ? _filteredFoodSuggestions() : <Map<String, String>>[];
    final budgetMatches = _budgetFocusNode.hasFocus ? _filteredBudgetSuggestions() : <String>[];

    return Container(
      key: _orderFormCardKey,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border, width: 1.4),
        boxShadow: [
          // Crisp 3D bottom lip
          const BoxShadow(
            color: Color(0xFFB6C6DB),
            blurRadius: 0,
            spreadRadius: 0,
            offset: Offset(0, 6),
          ),
          // Near contact shadow
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 14,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
          // Deep 3D floating drop shadow
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.28),
            blurRadius: 36,
            spreadRadius: 1,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Anything You Crave For',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 16),

          // 1. Food Name (Seamless full TextField + Live South Indian food autocomplete dropdown)
          _buildSeamlessAutocompleteField(
            icon: Icons.restaurant_rounded,
            label: 'Food Name',
            hint: 'e.g. Biryani, Dosa, Idli...',
            controller: _itemController,
            focusNode: _foodFocusNode,
            keyboardType: TextInputType.text,
            dropdownOverlay: foodMatches.isNotEmpty
                ? Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppColors.subtleShadow,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: foodMatches.map((f) {
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _itemController.text = f['name']!;
                            });
                            _foodFocusNode.unfocus();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Text(f['icon']!, style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    f['name']!,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),

          // 2. Budget (Seamless full TextField + Live budget autocomplete dropdown)
          _buildSeamlessAutocompleteField(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Budget (₹)',
            hint: 'Select or type budget',
            controller: _budgetController,
            focusNode: _budgetFocusNode,
            keyboardType: TextInputType.number,
            dropdownOverlay: budgetMatches.isNotEmpty
                ? Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppColors.subtleShadow,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: budgetMatches.map((amt) {
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            setState(() {
                              _budgetController.text = amt;
                            });
                            _budgetFocusNode.unfocus();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '₹$amt',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),

          // 3. Address (Selector without right-side arrow)
          _buildSelectorOnlyField(
            icon: Icons.location_on_rounded,
            label: 'Address',
            valueText: displayAddress,
            isPlaceholder: !hasAddress,
            onTap: () async {
              _foodFocusNode.unfocus();
              _budgetFocusNode.unfocus();
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddressScreen()),
              );
              await _loadSavedLocation();
            },
          ),
          const SizedBox(height: 12),

          // 4. Preferred Hotels (Dropdown ONLY from Admin Portal, without right-side arrow)
          _buildSelectorOnlyField(
            icon: Icons.apartment_rounded,
            label: 'Preferred Hotels',
            valueText: _selectedPreferredHotel ?? 'Select hotel (optional)',
            isPlaceholder: _selectedPreferredHotel == null,
            onTap: () {
              _foodFocusNode.unfocus();
              _budgetFocusNode.unfocus();
              _showPreferredHotelsDropdownSheet();
            },
          ),
          const SizedBox(height: 18),

          // Action Button (Brand Navy Pill Button)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _handleRegularOrderSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Order Now',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 4. Regular Custom Order Submission Handler
  Future<void> _handleRegularOrderSubmit() async {
    if (!_isStoreOnline) {
      _showStoreClosedPopup();
      return;
    }

    final itemText = _itemController.text.trim();
    if (itemText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an item name')),
      );
      return;
    }

    final budgetText = _budgetController.text.trim();
    final budgetVal = double.tryParse(budgetText);
    if (budgetText.isEmpty || budgetVal == null || budgetVal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your budget')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    final hasActive = prefs.getBool('has_active_order') ?? false;
    final activeStatus = (prefs.getString('active_order_status') ?? '').toLowerCase();
    final existingOrderId = prefs.getString('active_order_id') ?? '';
    if (hasActive && activeStatus != 'delivered' && activeStatus != 'cancelled' && existingOrderId.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "You already have active order #$existingOrderId in progress! Please wait until it is delivered or cancelled before ordering again.",
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.primaryDark,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      setState(() {
        showDeliveryDetails = true;
      });
      scrollToBottom();
      return;
    }

    final userId = prefs.getString('user_id') ?? 'usr_001';
    final custName = prefs.getString('user_name') ?? 'Customer';
    final custPhone = prefs.getString('mobile_number') ?? '+91 98765 43210';
    final custAddrRaw = (_deliveryLocationController.text.trim().isNotEmpty &&
            !_deliveryLocationController.text.trim().toLowerCase().contains('live gps') &&
            _deliveryLocationController.text.trim() != 'Detecting...')
        ? _deliveryLocationController.text.trim()
        : (_currentAddressFull.isNotEmpty && !_currentAddressFull.toLowerCase().contains('live gps')
            ? _currentAddressFull
            : "Kumbakonam, Thanjavur District, Tamil Nadu 612001");
    final custAddr = custAddrRaw
        .replaceAll(RegExp(r'\bmatthi,?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bmathi,?\s*', caseSensitive: false), '')
        .trim();

    final orderLat = _customerLocation.latitude;
    final orderLng = _customerLocation.longitude;

    if (!_isLocationInKumbakonam(orderLat, orderLng)) {
      _showGeofenceRestrictionDialog();
      return;
    }

    setState(() {
      showDeliveryDetails = true;
      isSearchingRider = true;
      hasRiderAccepted = false;
      showCancelButtonContainer = true;
      assignedPartnerName = "";
      assignedPartnerPhone = "";
      assignedPartnerProfileImage = null;
    });
    scrollToBottom();

    String newOrderId = "ORD-${1000 + Random().nextInt(9000)}";

    String customerFixedOtp = prefs.getString('customer_fixed_order_otp') ?? '';
    if (customerFixedOtp.isEmpty) {
      final digits = custPhone.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 4) {
        customerFixedOtp = digits.substring(digits.length - 4);
      } else {
        customerFixedOtp = (1000 + Random().nextInt(9000)).toString();
      }
      await prefs.setString('customer_fixed_order_otp', customerFixedOtp);
    }

    final shopPref = _preferredShopController.text.trim();
    final effectiveItemName = shopPref.isNotEmpty ? "$itemText (Shop: $shopPref)" : itemText;

    try {
      final res = await http.post(
        ApiConfig.orderCreate,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'customer_name': custName,
          'customer_phone': custPhone,
          'delivery_address': custAddr,
          'item_name': effectiveItemName,
          'preferred_shop': shopPref,
          'quantity': 1,
          'budget': budgetVal,
          'cod_otp': customerFixedOtp,
          'customer_latitude': orderLat,
          'customer_longitude': orderLng,
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        if (data['order'] != null) {
          if (data['order']['order_id'] != null) {
            newOrderId = data['order']['order_id'];
          }
          if (data['order']['cod_otp'] != null) {
            customerFixedOtp = data['order']['cod_otp'].toString();
            await prefs.setString('customer_fixed_order_otp', customerFixedOtp);
          }
        }
      } else {
        final data = jsonDecode(res.body);
        final isGeofenceErr = data['error'] == 'GEOFENCE_RESTRICTION' ||
            (data['message'] != null && data['message'].toString().contains('unavailable in your location'));
        if (mounted) {
          setState(() {
            isSearchingRider = false;
            showDeliveryDetails = false;
          });
          if (isGeofenceErr) {
            _showGeofenceRestrictionDialog();
          } else {
            final errMsg = data['error'] ?? data['message'] ?? 'Failed to create order on server';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errMsg), backgroundColor: AppColors.danger, behavior: SnackBarBehavior.floating),
            );
          }
        }
        return;
      }
    } catch (e) {
      debugPrint("Backend order creation error: $e");
      if (mounted) {
        setState(() {
          isSearchingRider = false;
          showDeliveryDetails = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot connect to server: $e'), backgroundColor: AppColors.danger, behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }

    await prefs.setString('active_order_id', newOrderId);
    await prefs.setString('active_cod_otp', customerFixedOtp);
    await prefs.setBool('has_active_order', true);
    await prefs.remove('active_order_bill_images');
    await prefs.remove('active_order_bill_image');
    await prefs.remove('order_${newOrderId}_bill_images');
    await prefs.remove('order_${newOrderId}_bill_image');
    if (mounted) {
      setState(() {
        _orderBillImages = [];
      });
    }
    await prefs.remove('order_${newOrderId}_chat_messages');
    await prefs.remove('has_notified_partner_accepted_$newOrderId');
    await prefs.remove('order_${newOrderId}_notified_collected_items');
    await prefs.remove('has_notified_bill_ack_$newOrderId');
    await prefs.remove('has_notified_payment_success_$newOrderId');
    await prefs.remove('has_notified_delivered_$newOrderId');
    await prefs.setString('active_order_item', itemText);
    await prefs.setString('active_order_budget', _budgetController.text.trim());
    await prefs.setString('active_order_quantity', '1');
    _orderSearchStartTime = DateTime.now();
    _allBusyHitCount = 0;
    await prefs.setString('active_order_customer_name', custName);
    await prefs.setString('active_order_customer_phone', custPhone);
    await prefs.setString('active_order_customer_address', custAddr);
    await prefs.setString('active_order_status', 'pending');
    await prefs.setBool('active_order_partner_accepted', false);
    await prefs.setBool('active_order_bill_sent', false);
    await prefs.remove('active_order_partner_name');
    await prefs.remove('active_order_partner_phone');
    await prefs.remove('active_order_partner_id');
    await prefs.remove('active_order_partner_image');

    AlarmService.startCustomerOrderListeningService(
      baseUrl: ApiConfig.baseUrl,
      orderId: newOrderId,
    );
    AlarmService.requestBatteryOptimizationExemption();
    _startOrderPolling(newOrderId);

    setState(() {
      showDeliveryDetails = true;
      showCancelButtonContainer = true;
      _showOrderForm = false;
    });
    scrollToBottom();
  }

  Widget _buildDropdown({StateSetter? setSheetState}) {
    final displayAddress = _deliveryLocationController.text.trim().isNotEmpty
        ? _deliveryLocationController.text.trim()
        : (_currentAddressFull.isNotEmpty ? _currentAddressFull : "Detecting live GPS location...");

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddressScreen()),
          );
          await _loadSavedLocation();
          if (setSheetState != null) {
            setSheetState(() {});
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.location_on_rounded, color: Color(0xFFEA580C), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Flexible(
                          child: Text(
                            'Delivery Location',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.gps_fixed_rounded, size: 9, color: Color(0xFF15803D)),
                              SizedBox(width: 3),
                              Text(
                                "Live GPS",
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      displayAddress,
                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.my_location_rounded, color: AppColors.primary, size: 19),
                tooltip: "Re-detect exact live location",
                onPressed: () => _requestLiveLocation(forceOverrideAddress: true),
              ),
              const Icon(Icons.keyboard_arrow_right_rounded, color: AppColors.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContainer() {
    if (!hasRiderAccepted || isSearchingRider) {
      return BikeRoadSearchingAnimation(
        onCancel: _showCancelConfirmationDialog,
      );
    }
    return _buildAssignedPartnerContainer();
  }

  void _startOrderPolling(String orderId) {
    _orderSearchStartTime ??= DateTime.now();
    _allBusyHitCount = 0;
    _searchRiderTimer?.cancel();
    _searchRiderTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) async {
      if (_isPollingRider) return;
      _isPollingRider = true;
      try {
        final response = await http.get(ApiConfig.orderById(orderId)).timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final order = data['order'];
          if (order != null) {
            final st = (order['status']?.toString() ?? '').toLowerCase();
            if (st == 'cancelled') {
              timer.cancel();
              AlarmService.stopCustomerOrderListeningService();
              final reason = order['cancel_reason'] ?? 'Order was cancelled';
              final p = await SharedPreferences.getInstance();
              await p.setBool('has_active_order', false);
              await p.setString('active_order_status', 'cancelled');
              await p.remove('active_order_id');
              if (mounted) {
                setState(() {
                  isSearchingRider = false;
                  hasRiderAccepted = false;
                  showDeliveryDetails = false;
                  showCancelButtonContainer = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.cancel_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text("Order cancelled: $reason")),
                      ],
                    ),
                    backgroundColor: AppColors.danger,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
              return;
            }

            if (st == 'delivered' || st == 'completed') {
              timer.cancel();
              AlarmService.stopCustomerOrderListeningService();
              final curOId = (order['order_id'] ?? orderId).toString();
              final p = await SharedPreferences.getInstance();

              // Decrement biryani remaining stock count ONLY AFTER delivery is completed
              final bool alreadyReduced = p.getBool('biryani_reduced_$curOId') ?? false;
              if (!alreadyReduced) {
                await p.setBool('biryani_reduced_$curOId', true);
                final itemStr = (order['item_name'] ?? p.getString('active_order_item') ?? '').toString().toLowerCase();
                if (itemStr.contains('biryani') || itemStr.contains('briyani')) {
                  final int qty = int.tryParse(order['quantity']?.toString() ?? '') ??
                                  int.tryParse(p.getString('active_order_quantity') ?? '') ?? 1;
                  if (_remainingBiryaniCount > 1) {
                    setState(() {
                      _remainingBiryaniCount = max(1, _remainingBiryaniCount - qty);
                    });
                    await p.setInt('remaining_biryani_count', _remainingBiryaniCount);
                  }
                }
              }

              final bool alreadyNotified = p.getBool('has_notified_delivered_$curOId') ?? false;
              if (!alreadyNotified) {
                await p.setBool('has_notified_delivered_$curOId', true);
                final pName = (order['partner_name'] != null && order['partner_name'].toString().trim().isNotEmpty)
                    ? order['partner_name'].toString().trim()
                    : 'Delivery Partner';
                await AppNotificationService.showOrderDeliveredCustomerNotification(
                  orderId: curOId,
                  partnerName: pName,
                );
              }
              await p.setBool('has_active_order', false);
              await p.remove('active_order_id');
              await p.setString('active_order_status', 'delivered');
              await p.setBool('has_claimed_first_offer', true);
              if (mounted) {
                setState(() {
                  _hasClaimedFirstOffer = true;
                  isSearchingRider = false;
                  hasRiderAccepted = false;
                  showDeliveryDetails = false;
                  showCancelButtonContainer = false;
                });

                final num? bGrand = order['grand_total'] ?? order['budget'];
                final double finalTot = (bGrand != null && bGrand > 0) ? bGrand.toDouble() : 0.0;
                final num? bFood = order['item_total'];
                final num? bTip = order['tip_amount'];
                final String payMethod = order['payment_method']?.toString() ?? 'Payment Successful';

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FullScreenPaymentSuccessScreen(
                      orderId: curOId,
                      totalAmount: finalTot,
                      foodPrice: bFood?.toDouble(),
                      tipAmount: bTip?.toDouble(),
                      paymentMethod: payMethod,
                      isDeliveryPartner: false,
                    ),
                  ),
                );
              }
              return;
            }

            final isAccepted = (st == 'accepted' ||
                st == 'purchasing_food' ||
                st == 'bill_sent' ||
                st == 'picked_up' ||
                st == 'in_transit');

            if (isAccepted) {
              final pId = (order['partner_id'] ?? '').toString().trim();
              String pName = (order['partner_name'] != null && order['partner_name'].toString().trim().isNotEmpty)
                  ? order['partner_name'].toString().trim()
                  : 'Delivery Partner';
              String pPhone = (order['partner_phone'] != null && order['partner_phone'].toString().trim().isNotEmpty)
                  ? order['partner_phone'].toString().trim()
                  : '';
              final pPic = (order['partner_profile_picture'] != null && order['partner_profile_picture'].toString().trim().isNotEmpty)
                  ? order['partner_profile_picture'].toString().trim()
                  : (order['partner_photo_url'] ?? (pId.isNotEmpty ? '${ApiConfig.baseUrl}/api/deliveryperson/photo/$pId' : null));
              final pOtp = (order['cod_otp'] ?? '').toString();

              final p = await SharedPreferences.getInstance();
              if (pName.isNotEmpty && p.getString('active_order_partner_name') != pName) await p.setString('active_order_partner_name', pName);
              if (pPhone.isNotEmpty && p.getString('active_order_partner_phone') != pPhone) await p.setString('active_order_partner_phone', pPhone);
              if (pId.isNotEmpty && p.getString('active_order_partner_id') != pId) await p.setString('active_order_partner_id', pId);
              if (pPic != null && pPic.isNotEmpty && p.getString('active_order_partner_image') != pPic) await p.setString('active_order_partner_image', pPic);
              if (pOtp.isNotEmpty && p.getString('active_cod_otp') != pOtp) await p.setString('active_cod_otp', pOtp);
              if (p.getString('active_order_status') != order['status']) await p.setString('active_order_status', order['status']);
              if (p.getBool('active_order_partner_accepted') != true) await p.setBool('active_order_partner_accepted', true);
              final orderBillUrl = (order['bill_image_url'] ?? '').toString();
              List<String> bImages = [];
              if (order['bill_images'] is List) {
                bImages = (order['bill_images'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
              }
              if (bImages.isNotEmpty) {
                await p.setStringList('order_${order['order_id']}_bill_images', bImages);
                await p.setStringList('active_order_bill_images', bImages);
                await p.setString('order_${order['order_id']}_bill_image', bImages.first);
                await p.setString('active_order_bill_image', bImages.first);
              } else if (orderBillUrl.isNotEmpty) {
                await p.setString('order_${order['order_id']}_bill_image', orderBillUrl);
                await p.setString('active_order_bill_image', orderBillUrl);
                await p.setStringList('order_${order['order_id']}_bill_images', [orderBillUrl]);
                await p.setStringList('active_order_bill_images', [orderBillUrl]);
              }

              final effectiveBillImgs = bImages.isNotEmpty
                  ? bImages
                  : (orderBillUrl.isNotEmpty
                      ? [orderBillUrl]
                      : (p.getStringList('order_${order['order_id']}_bill_images') ?? <String>[]));
              final bool billImgsChanged = effectiveBillImgs.isNotEmpty &&
                  (effectiveBillImgs.length != _orderBillImages.length ||
                   (_orderBillImages.isNotEmpty && effectiveBillImgs.first != _orderBillImages.first));

              final curOId = (order['order_id'] ?? orderId).toString();
              final bool alreadyNotified = p.getBool('has_notified_partner_accepted_$curOId') ?? false;
              if (!alreadyNotified) {
                await p.setBool('has_notified_partner_accepted_$curOId', true);
                await AppNotificationService.showOrderAcceptedNotification(
                  orderId: curOId,
                  partnerName: pName,
                  partnerPhone: pPhone,
                );
              }

              final bool hasBill = (st == 'bill_sent') &&
                  ((order['bill_confirmed'] == true) ||
                   orderBillUrl.isNotEmpty ||
                   bImages.isNotEmpty);
              if (hasBill) {
                final bool alreadyNotifiedBill =
                    p.getBool('has_notified_bill_ack_$curOId') ?? false;
                if (!alreadyNotifiedBill) {
                  await p.setBool('has_notified_bill_ack_$curOId', true);
                  final num? gTot = order['grand_total'];
                  final List? oItems = order['items'] is List ? order['items'] : null;
                  await AppNotificationService.showBillAcknowledgementNotification(
                    orderId: curOId,
                    partnerName: pName,
                    grandTotal: gTot?.toDouble(),
                    itemCount: oItems?.length,
                  );
                }
              }

              final String payStatus = (order['payment_status'] ?? '').toString().toLowerCase().trim();
              final bool isPaid = payStatus == 'paid' || payStatus == 'success' || order['is_paid'] == true;
              if (isPaid) {
                final bool alreadyNotifiedPayment =
                    p.getBool('has_notified_payment_success_$curOId') ?? false;
                if (!alreadyNotifiedPayment) {
                  await p.setBool('has_notified_payment_success_$curOId', true);
                  final num? gTot = order['grand_total'] ?? order['total_amount'];
                  final String pMethod = (order['payment_method'] ?? 'Online').toString();
                  final String codOtp = (order['cod_otp'] ?? pOtp).toString();
                  await AppNotificationService.showPaymentSuccessNotification(
                    orderId: curOId,
                    amount: (gTot?.toDouble()) ?? 0.0,
                    otp: codOtp,
                    partnerName: pName,
                    paymentMethod: pMethod,
                  );
                }
              }

              if (mounted) {
                final bool wasSearching = isSearchingRider;
                final bool hasChanged = wasSearching ||
                    !showDeliveryDetails ||
                    !hasRiderAccepted ||
                    assignedPartnerName != pName ||
                    assignedPartnerPhone != pPhone ||
                    (pId.isNotEmpty && assignedPartnerId != pId) ||
                    (pPic != null && pPic.isNotEmpty && assignedPartnerProfileImage != pPic) ||
                    (pOtp.isNotEmpty && assignedOrderOtp != pOtp) ||
                    billImgsChanged;

                if (hasChanged) {
                  setState(() {
                    showDeliveryDetails = true;
                    isSearchingRider = false;
                    hasRiderAccepted = true;
                    showCancelButtonContainer = false;
                    assignedPartnerName = pName;
                    assignedPartnerPhone = pPhone;
                    if (pId.isNotEmpty) assignedPartnerId = pId;
                    if (pPic != null && pPic.isNotEmpty) assignedPartnerProfileImage = pPic;
                    if (pOtp.isNotEmpty) assignedOrderOtp = pOtp;
                    if (effectiveBillImgs.isNotEmpty) {
                      _orderBillImages = effectiveBillImgs;
                    }
                  });
                }
                if (wasSearching) {
                  _startRiderLocationPolling();
                  _startOrderChatPolling();
                  _fetchTrackingRoadRoute();
                }
              }
            } else {
              // Partner has NOT accepted yet. Check delivery partner availability conditions:
              // 1. All online delivery partners are busy on deliveries -> immediate alert & cancel
              // 2. No delivery partner is online -> wait 45s, then alert & cancel
              // 3. Online delivery partners exist but no one accepted -> wait 5 minutes (300s), then alert & cancel

              DateTime orderCreatedAt = DateTime.now();
              if (order['created_at'] != null) {
                final parsed = DateTime.tryParse(order['created_at'].toString());
                if (parsed != null) orderCreatedAt = parsed.toLocal();
              } else if (_orderSearchStartTime != null) {
                orderCreatedAt = _orderSearchStartTime!;
              }

              final int elapsedSec = DateTime.now().difference(orderCreatedAt).inSeconds;

              final partnerStats = (data['partner_stats'] as Map<String, dynamic>?) ?? {};
              final bool zeroOnline = partnerStats['zero_online'] == true;
              final bool allBusy = partnerStats['all_busy'] == true;
              final String? assignedPartner = order['current_assigned_partner_id']?.toString().trim();
              final bool hasAssignedPartner = assignedPartner != null && assignedPartner.isNotEmpty;

              // 🛑 If order is actively offered to an assigned delivery partner, DO NOT cancel for allBusy or zeroOnline!
              // The assigned delivery partner has their 2-minute acceptance window to accept the order!
              if (!hasAssignedPartner) {
                if (allBusy) {
                  _allBusyHitCount++;
                  if (_allBusyHitCount >= 6 && elapsedSec >= 20) {
                    timer.cancel();
                    await _handleNoDeliveryPartnerAvailable(
                      orderId: orderId,
                      reason: 'all_busy',
                      title: 'All Delivery Partners Busy',
                      message: 'All our delivery partners are currently busy with ongoing deliveries. Please try again in a little while.',
                    );
                    return;
                  }
                } else {
                  _allBusyHitCount = 0;
                }

                if (zeroOnline) {
                  if (elapsedSec >= 45) {
                    timer.cancel();
                    await _handleNoDeliveryPartnerAvailable(
                      orderId: orderId,
                      reason: 'zero_online',
                      title: 'No Delivery Partners Online',
                      message: 'No delivery partners are currently online in your area. Please try again in a little while.',
                    );
                    return;
                  }
                }
              } else {
                _allBusyHitCount = 0;
              }

              if (elapsedSec >= 300) {
                timer.cancel();
                await _handleNoDeliveryPartnerAvailable(
                  orderId: orderId,
                  reason: 'no_partner_accepted_5min',
                  title: 'Delivery Partners Unavailable',
                  message: 'None of our delivery partners were able to accept your order right now. Please try again in a little while.',
                );
                return;
              }
            }
          }
        }
      } catch (err) {
        debugPrint("Order status polling error: $err");
      } finally {
        _isPollingRider = false;
      }
    });
  }

  Future<void> _handleNoDeliveryPartnerAvailable({
    required String orderId,
    required String reason,
    required String title,
    required String message,
  }) async {
    _searchRiderTimer?.cancel();
    AlarmService.stopCustomerOrderListeningService();

    final prefs = await SharedPreferences.getInstance();
    final String uId = prefs.getString('user_id') ?? prefs.getString('mobile_number') ?? '';
    final String cName = prefs.getString('active_order_customer_name') ?? prefs.getString('user_name') ?? 'Customer';
    final String cPhone = prefs.getString('active_order_customer_phone') ?? prefs.getString('mobile_number') ?? '';

    // 1. Cancel active order in backend
    try {
      await http.post(
        ApiConfig.orderCancel,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'order_id': orderId,
          'cancel_reason': message,
          'cancelled_by': 'system_no_partner',
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint("Auto cancel error: $e");
    }

    // 2. Register as waiting customer so they get notified when partner is available
    try {
      await http.post(
        ApiConfig.orderWaitingCustomer,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': uId,
          'customer_name': cName,
          'customer_phone': cPhone,
          'reason': reason,
          'order_id': orderId,
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint("Register waiting customer error: $e");
    }

    // 3. Clear active order state in SharedPreferences
    await prefs.setBool('has_active_order', false);
    await prefs.setString('active_order_status', 'cancelled');
    await prefs.setBool('active_order_partner_accepted', false);
    await prefs.remove('active_order_id');
    await _checkFirstTimeOfferStatus(forceServerCheck: true);

    // 4. Update UI & show dialog
    if (mounted) {
      setState(() {
        isSearchingRider = false;
        hasRiderAccepted = false;
        showDeliveryDetails = false;
        showCancelButtonContainer = false;
      });

      _showPartnerUnavailableDialog(title: title, message: message);
    }
  }

  void _showPartnerUnavailableDialog({
    required String title,
    required String message,
  }) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFFB74D), width: 1.5),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.delivery_dining_outlined,
                      color: Color(0xFFE65100),
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 13.5,
                    height: 1.5,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.notifications_active_outlined, size: 16, color: Color(0xFF2563EB)),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          "We'll notify you automatically when a partner is available.",
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 11.5,
                            color: Color(0xFF334155),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      "Okay, Got it",
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAssignedPartnerAvatar() {
    String? img = assignedPartnerProfileImage?.trim();
    if ((img == null || img.isEmpty) && assignedPartnerId.isNotEmpty) {
      img = '${ApiConfig.baseUrl}/api/deliveryperson/photo/$assignedPartnerId';
    }
    if (img != null && img.isNotEmpty) {
      if (img.startsWith('/')) {
        img = '${ApiConfig.baseUrl}$img';
      }
      if (img.startsWith('http://') || img.startsWith('https://')) {
        return Image.network(
          img,
          cacheWidth: 200,
          fit: BoxFit.cover,
          width: 56,
          height: 56,
          errorBuilder: (_, __, ___) => _buildFallbackPartnerAvatar(),
        );
      } else if (img.startsWith('file:') || img.contains('\\') || (!img.contains('/') && File(img).existsSync())) {
        final f = File(img);
        if (f.existsSync()) {
          return Image.file(
            f,
            fit: BoxFit.cover,
            width: 56,
            height: 56,
            errorBuilder: (_, __, ___) => _buildFallbackPartnerAvatar(),
          );
        }
      }
      // 🖼️ Base64 Image Decoder (supports both raw base64 and data:image URI strings)
      try {
        final b64 = img.contains(',') ? img.split(',').last.trim() : img;
        final bytes = base64Decode(b64);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: 56,
          height: 56,
          errorBuilder: (_, __, ___) => _buildFallbackPartnerAvatar(),
        );
      } catch (_) {}
    }
    return _buildFallbackPartnerAvatar();
  }

  Widget _buildFallbackPartnerAvatar() {
    final initial = assignedPartnerName.trim().isNotEmpty
        ? assignedPartnerName.trim().substring(0, 1).toUpperCase()
        : '';
    return Container(
      color: AppColors.primaryLight,
      alignment: Alignment.center,
      child: initial.isNotEmpty
          ? Text(
              initial,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryDark,
              ),
            )
          : const Icon(Icons.person_rounded, color: AppColors.primaryDark, size: 28),
    );
  }

  // Assigned delivery partner with live GPS map tracking
  Widget _buildAssignedPartnerContainer() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.subtleShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF16A34A), width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: _buildAssignedPartnerAvatar(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (assignedPartnerName.isNotEmpty && assignedPartnerName != 'Delivery Partner')
                          ? assignedPartnerName
                          : 'Delivery Partner',
                      style: AppTypography.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        ...List.generate(
                          5,
                          (_) => const Icon(
                            Icons.star_rounded,
                            color: AppColors.warning,
                            size: 15,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          "4.9",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    if (assignedPartnerPhone.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        assignedPartnerPhone,
                        style: const TextStyle(fontSize: 12, color: AppColors.primaryDark, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primaryLight,
                  foregroundColor: AppColors.primary,
                ),
                icon: const Icon(Icons.phone_rounded, size: 20),
                tooltip: 'Call Delivery Partner',
                onPressed: () => _callDeliveryPartner(assignedPartnerPhone),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFEF3C7),
                  foregroundColor: const Color(0xFFD97706),
                ),
                icon: const Icon(Icons.chat_bubble_rounded, size: 20),
                tooltip: 'Chat with Delivery Partner',
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  final curOrderId = prefs.getString('active_order_id') ?? 'ORD-8492';
                  if (!mounted) return;
                  OrderChatSheet.show(
                    context,
                    orderId: curOrderId,
                    senderRole: 'customer',
                    otherPartyName: assignedPartnerName,
                    otherPartyPhone: assignedPartnerPhone,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Live Google Maps GPS Tracking
          Container(
            height: 175,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  RepaintBoundary(
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _customerLocation,
                        zoom: 15.0,
                      ),
                      onMapCreated: (ctrl) {
                        _trackingMapController = ctrl;
                        _fitTrackingMapBounds();
                      },
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      markers: {
                        Marker(
                          markerId: const MarkerId('rider'),
                          position: _riderLocation,
                          infoWindow: InfoWindow(title: '$assignedPartnerName (Rider)'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                        ),
                        Marker(
                          markerId: const MarkerId('destination'),
                          position: _customerLocation,
                          infoWindow: const InfoWindow(title: 'Delivery Address (You)'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        ),
                      },
                      polylines: {
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: _trackingRoutePoints.isNotEmpty ? _trackingRoutePoints : [
                            _riderLocation,
                            _customerLocation,
                          ],
                          color: AppColors.primaryDark,
                          width: 4,
                        ),
                      },
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.navigation_rounded, color: AppColors.primaryDark, size: 14),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                "Live GPS • ${_formatRiderDistance()}",
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.primarySubtle,
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              "TOP REVIEW: \"He is a polite and fast delivery partner. Food was warm and delivered right on time!\"",
              style: TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _callDeliveryPartner(assignedPartnerPhone),
              icon: const Icon(Icons.call_rounded, color: Colors.white, size: 18),
              label: Text(
                assignedPartnerPhone.isNotEmpty
                    ? 'Call $assignedPartnerName ($assignedPartnerPhone)'
                    : 'Call $assignedPartnerName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          if (_orderBillImages.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildRestaurantBillReceiptsSection(),
          ],
          const SizedBox(height: 10),
          // View Delivery Bill & Make Payment Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PaymentPage()),
                );
              },
              icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
              label: const Text(
                'Track Live Order & View Bill',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildInOrderChatCard(),
        ],
      ),
    );
  }

  Widget _buildInOrderChatCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with open full chat button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chat_bubble_rounded, size: 16, color: Color(0xFFD97706)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Chat with $assignedPartnerName",
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        "Direct message for address or instructions",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final curOrderId = prefs.getString('active_order_id') ?? 'ORD-8492';
                    if (!mounted) return;
                    OrderChatSheet.show(
                      context,
                      orderId: curOrderId,
                      senderRole: 'customer',
                      otherPartyName: assignedPartnerName,
                      otherPartyPhone: assignedPartnerPhone,
                    );
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.primary),
                  label: const Text("Full Chat", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ),
              ],
            ),
          ),

          // Message Preview List (shows last 3 messages)
          if (_inOrderChatMessages.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _inOrderChatMessages.length > 3 ? 3 : _inOrderChatMessages.length,
                itemBuilder: (context, idx) {
                  final startIndex = _inOrderChatMessages.length > 3
                      ? _inOrderChatMessages.length - 3
                      : 0;
                  final msg = _inOrderChatMessages[startIndex + idx];
                  final isMe = msg['sender'] == 'customer';
                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
                      decoration: BoxDecoration(
                        color: isMe ? AppColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: isMe ? null : Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          if (!isMe)
                            Text(
                              assignedPartnerName,
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                            ),
                          Text(
                            msg['text']?.toString() ?? '',
                            style: TextStyle(
                              color: isMe ? Colors.white : AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            msg['time']?.toString() ?? '',
                            style: TextStyle(
                              color: isMe ? Colors.white70 : AppColors.textSecondary,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text(
                "💬 No messages yet. Say hi or give delivery landmarks!",
                style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontStyle: FontStyle.italic),
              ),
            ),

          // Quick Chat Input Box
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(15)),
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: TextField(
                      controller: _chatMsgController,
                      style: const TextStyle(fontSize: 13),
                      onSubmitted: (_) => _sendCustomerInOrderMessage(),
                      decoration: const InputDecoration(
                        hintText: "Type a message to delivery partner...",
                        hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(38, 38),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  onPressed: _sendCustomerInOrderMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFullReceiptDialog(String path) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF334155), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFF1E293B),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.receipt_long_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Restaurant Bill Receipt",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              // Interactive Pinch-to-zoom Bill Preview
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
                ),
                child: InteractiveViewer(
                  panEnabled: true,
                  boundaryMargin: const EdgeInsets.all(20),
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(
                    child: _buildBillReceiptWidget(path, fit: BoxFit.contain),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBillReceiptWidget(String path, {BoxFit fit = BoxFit.cover}) {
    if (path.isEmpty) return const SizedBox();
    if (File(path).existsSync()) {
      return Image.file(File(path), fit: fit);
    }
    if (path.startsWith('data:image')) {
      try {
        final commaIdx = path.indexOf(',');
        final base64Str = commaIdx != -1 ? path.substring(commaIdx + 1) : path;
        return Image.memory(base64Decode(base64Str), fit: fit);
      } catch (_) {}
    }
    return Image.network(
      path,
      cacheWidth: 800,
      fit: fit,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 40),
      ),
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
    );
  }

  Widget _buildRestaurantBillReceiptsSection() {
    if (_orderBillImages.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, size: 18, color: AppColors.primaryDark),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _orderBillImages.length > 1
                            ? "Restaurant Bills (${_orderBillImages.length} attached)"
                            : "Restaurant Bill Receipt",
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (_orderBillImages.length == 1)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: const Color(0xFFEFF6FF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  onPressed: () => _showFullReceiptDialog(_orderBillImages.first),
                  icon: const Icon(Icons.fullscreen_rounded, size: 16, color: AppColors.primaryDark),
                  label: const Text("View Full", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_orderBillImages.length == 1)
            GestureDetector(
              onTap: () => _showFullReceiptDialog(_orderBillImages.first),
              child: Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildBillReceiptWidget(_orderBillImages.first, fit: BoxFit.contain),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.zoom_in_rounded, color: Colors.white, size: 15),
                              SizedBox(width: 5),
                              Text(
                                "Tap to expand & inspect full receipt",
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _orderBillImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, idx) {
                  final imgUrl = _orderBillImages[idx];
                  return GestureDetector(
                    onTap: () => _showFullReceiptDialog(imgUrl),
                    child: Container(
                      width: 145,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildBillReceiptWidget(imgUrl, fit: BoxFit.contain),
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  "Bill #${idx + 1}",
                                  style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                color: Colors.black.withValues(alpha: 0.6),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.zoom_in_rounded, color: Colors.white, size: 12),
                                    SizedBox(width: 4),
                                    Text("Tap to zoom", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _sendCustomerInOrderMessage() async {
    final text = _chatMsgController.text.trim();
    if (text.isEmpty) return;
    _chatMsgController.clear();
    final prefs = await SharedPreferences.getInstance();
    final curOrderId = prefs.getString('active_order_id') ?? 'ORD-8492';
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$minute $ampm';

    final myName = prefs.getString('user_name') ?? 'Customer';
    final newMsg = {
      'sender': 'customer',
      'sender_name': myName,
      'text': text,
      'time': timeStr,
      'timestamp': DateTime.now().toIso8601String(),
    };

    setState(() {
      _inOrderChatMessages.add(newMsg);
    });

    try {
      final res = await http.post(
        ApiConfig.orderSendMessage(curOrderId),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(newMsg),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List remoteList = data['messages'] ?? [];
        if (mounted && remoteList.isNotEmpty) {
          setState(() {
            _inOrderChatMessages = remoteList.map((e) => Map<String, dynamic>.from(e)).toList();
          });
        }
      }
    } catch (_) {}
  }

  Widget _buildWaitingHotelsShowcase() {
    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF142B4A).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFEDD5)),
                    ),
                    child: const Icon(Icons.storefront_rounded, color: Color(0xFFEA580C), size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Partner Kitchens in Kumbakonam",
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        "Orders are prepared fresh at certified spots",
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${_kPartnerHotels.length} SPOTS",
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Split-card carousel (Carousel 2)
          const _WaitingHotelsCarousel(),
        ],
      ),
    );
  }

  Widget _buildCancelOrderContainer() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.subtleShadow,
      ),
      child: Column(
        children: [
          const Text(
            "Need to cancel this order?",
            style: AppTypography.cardTitle,
          ),
          const SizedBox(height: 4),
          const Text(
            "You can cancel before food preparation starts.",
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _showCancelConfirmationDialog,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Cancel Order', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
            ),
          ),
        ],
      ),
    );
  }

  void _showCancelConfirmationDialog() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Are you sure?', style: AppTypography.cardTitle),
            content: const Text('Do you really want to cancel your ongoing delivery?'),
            actions: [
              TextButton(
                child: const Text('No, Keep Order', style: TextStyle(color: AppColors.textSecondary)),
                onPressed: () => Navigator.pop(context),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showReasonDialog();
                },
                child: const Text('Yes, Cancel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
    );
  }

  void _showReasonDialog() {
    String selectedReason = "Placed order by mistake";
    final TextEditingController reasonController = TextEditingController();
    final List<String> reasons = [
      "Placed order by mistake",
      "Wait time is too long",
      "Wrong delivery location / items",
      "Change of mind",
      "Other reason",
    ];

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.cancel_rounded, color: AppColors.danger, size: 22),
                SizedBox(width: 8),
                Text('Reason for cancellation', style: AppTypography.cardTitle),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Please select a reason for cancelling your order:",
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  ...reasons.map((r) {
                    final isSel = selectedReason == r;
                    return InkWell(
                      onTap: () {
                        setDialogState(() {
                          selectedReason = r;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSel ? const Color(0xFFFEE2E2) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSel ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0),
                            width: isSel ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                              size: 18,
                              color: isSel ? const Color(0xFFDC2626) : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                r,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                  color: isSel ? const Color(0xFF991B1B) : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (selectedReason == "Other reason") ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Enter specific reason...',
                        hintStyle: const TextStyle(fontSize: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Back', style: TextStyle(color: AppColors.textSecondary)),
                onPressed: () => Navigator.pop(dlgCtx),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () async {
                  final finalReason = selectedReason == "Other reason" && reasonController.text.trim().isNotEmpty
                      ? reasonController.text.trim()
                      : selectedReason;
                  Navigator.pop(dlgCtx);

                  final prefs = await SharedPreferences.getInstance();
                  final curOrderId = prefs.getString('active_order_id') ?? 'ORD-8492';

                  try {
                    final response = await http.post(
                      ApiConfig.orderCancel,
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'order_id': curOrderId,
                        'cancel_reason': finalReason,
                        'cancelled_by': 'customer',
                      }),
                    );
                    if (response.statusCode == 400) {
                      final data = jsonDecode(response.body);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(data['error'] ?? 'Order cannot be cancelled.'),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                      }
                      return;
                    }
                  } catch (e) {
                    debugPrint("Order cancel backend error: $e");
                  }

                  await prefs.setBool('has_active_order', false);
                  await prefs.setString('active_order_status', 'cancelled');
                  await prefs.setBool('active_order_partner_accepted', false);
                  await prefs.remove('active_order_id');

                  _searchRiderTimer?.cancel();
                  await _checkFirstTimeOfferStatus(forceServerCheck: true);

                  if (mounted) {
                    setState(() {
                      showCancelButtonContainer = false;
                      showDeliveryDetails = false;
                      isSearchingRider = false;
                      hasRiderAccepted = false;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.cancel_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Order $curOrderId cancelled: $finalReason')),
                          ],
                        ),
                        backgroundColor: AppColors.danger,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class NextPage extends StatelessWidget {
  const NextPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Delivery Partner Call', style: AppTypography.screenHeading),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_in_talk_rounded, size: 54, color: AppColors.primaryDark),
              ),
              const SizedBox(height: 20),
              const Text(
                'Connecting to Delivery Partner...',
                style: AppTypography.cardTitle,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your delivery partner has been notified.',
                textAlign: TextAlign.center,
                style: AppTypography.secondary,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Back to Home', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Delivery Partner Searching Card with Partner Spotlight Carousel (Carousel 1)
class BikeRoadSearchingAnimation extends StatefulWidget {
  final VoidCallback? onCancel;
  const BikeRoadSearchingAnimation({super.key, this.onCancel});

  @override
  State<BikeRoadSearchingAnimation> createState() => _BikeRoadSearchingAnimationState();
}

class _BikeRoadSearchingAnimationState extends State<BikeRoadSearchingAnimation> {
  late PageController _spotlightController;
  Timer? _spotlightTimer;
  int _spotlightIndex = 0;

  @override
  void initState() {
    super.initState();
    _spotlightController = PageController();
    _spotlightTimer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (!mounted) return;
      if (_HomePageState._kPartnerHotels.isEmpty) return;
      final next = (_spotlightIndex + 1) % _HomePageState._kPartnerHotels.length;
      _spotlightController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _spotlightTimer?.cancel();
    _spotlightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Partner Spotlight Carousel (Replaces the bike scene)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 165,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
              ),
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _spotlightController,
                    itemCount: _HomePageState._kPartnerHotels.length,
                    onPageChanged: (idx) => setState(() => _spotlightIndex = idx),
                    itemBuilder: (context, index) {
                      final hotel = _HomePageState._kPartnerHotels[index];
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            hotel['image'] as String,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                          ),
                          // Dual gradient overlay for text readability
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.65),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.88),
                                ],
                                stops: const [0.0, 0.35, 1.0],
                              ),
                            ),
                          ),
                          // Top Live Radar Tag & Rating
                          Positioned(
                            top: 10,
                            left: 12,
                            right: 12,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (hotel['color'] as Color).withValues(alpha: 0.90),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.25),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.verified_rounded, color: Colors.white, size: 12),
                                      const SizedBox(width: 4),
                                      Text(
                                        hotel['badge'] as String,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.70),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 12),
                                      const SizedBox(width: 3),
                                      Text(
                                        "${hotel['rating']} ★",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Bottom Hotel Information
                          Positioned(
                            bottom: 12,
                            left: 12,
                            right: 12,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        hotel['name'] as String,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.3,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black,
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on_rounded, color: Color(0xFFFDE68A), size: 11),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: Text(
                                              "${hotel['location']} • ${hotel['specialty']}",
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFFF1F5F9),
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white38),
                                  ),
                                  child: Text(
                                    hotel['prepTime'] as String,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  // Dots indicator inside
                  Positioned(
                    bottom: 6,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_HomePageState._kPartnerHotels.length, (i) {
                        final isActive = _spotlightIndex == i;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 3,
                          width: isActive ? 14 : 4,
                          decoration: BoxDecoration(
                            color: isActive ? Colors.white : Colors.white38,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Status Heading
          const Text(
            "Matching Closest Delivery Partner...",
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            "Routing order to the closest delivery partner in Kumbakonam. Automatically forwards to the next closest partner if unanswered within 2 minutes.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
          ),
          const SizedBox(height: 10),

          // Linear loading indicator
          const SizedBox(
            width: 140,
            child: LinearProgressIndicator(
              backgroundColor: AppColors.primaryLight,
              color: AppColors.primary,
              minHeight: 3.5,
            ),
          ),
          const SizedBox(height: 10),

          // Live Waiting Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.primarySubtle,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_tethering_rounded, color: AppColors.primary, size: 15),
                SizedBox(width: 7),
                Text(
                  "Waiting for Delivery Partner Acceptance",
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),

          // Quick Cancel Order button right inside the card
          if (widget.onCancel != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.cancel_outlined, size: 16, color: AppColors.danger),
                label: const Text(
                  "Cancel Order",
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.2),
                  backgroundColor: const Color(0xFFFEF2F2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Split-card Waiting Hotels Carousel (Carousel 2)
class _WaitingHotelsCarousel extends StatefulWidget {
  const _WaitingHotelsCarousel();

  @override
  State<_WaitingHotelsCarousel> createState() => _WaitingHotelsCarouselState();
}

class _WaitingHotelsCarouselState extends State<_WaitingHotelsCarousel> {
  late PageController _pageController;
  Timer? _timer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _timer = Timer.periodic(const Duration(milliseconds: 3800), (_) {
      if (!mounted) return;
      if (_HomePageState._kPartnerHotels.isEmpty) return;
      final next = (_currentIndex + 1) % _HomePageState._kPartnerHotels.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 114,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _HomePageState._kPartnerHotels.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (context, index) {
              final hotel = _HomePageState._kPartnerHotels[index];
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                ),
                child: Row(
                  children: [
                    // Left: Food Photo with rating badge
                    ClipRRect(
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
                      child: Stack(
                        children: [
                          SizedBox(
                            width: 110,
                            height: double.infinity,
                            child: Image.asset(
                              hotel['image'] as String,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 11),
                                  const SizedBox(width: 2),
                                  Text(
                                    hotel['rating'] as String,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Right: Hotel Information
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (hotel['color'] as Color).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: (hotel['color'] as Color).withValues(alpha: 0.40),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    hotel['badge'] as String,
                                    style: TextStyle(
                                      color: hotel['color'] as Color,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    const Icon(Icons.flash_on_rounded, size: 11, color: Color(0xFFEA580C)),
                                    const SizedBox(width: 2),
                                    Text(
                                      hotel['prepTime'] as String,
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              hotel['name'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              hotel['specialty'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFD97706),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, size: 11, color: Color(0xFF64748B)),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    hotel['location'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_HomePageState._kPartnerHotels.length, (idx) {
            final isActive = _currentIndex == idx;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              height: 3.5,
              width: isActive ? 14 : 4,
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFEA580C) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Top-Level 1024x571 Aspect-Ratio Lazy Loading Shimmer Skeleton for Sliding Banners
// -----------------------------------------------------------------------------
class _SlidingBannerLazyLoader extends StatefulWidget {
  const _SlidingBannerLazyLoader();

  @override
  State<_SlidingBannerLazyLoader> createState() => _SlidingBannerLazyLoaderState();
}

class _SlidingBannerLazyLoaderState extends State<_SlidingBannerLazyLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 1024 / 571,
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(_animation.value - 1.0, -0.3),
                        end: Alignment(_animation.value, 0.3),
                        colors: const [
                          Color(0xFF1E293B),
                          Color(0xFF334155),
                          Color(0xFF475569),
                          Color(0xFF334155),
                          Color(0xFF1E293B),
                        ],
                        stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_offer_rounded,
                            size: 30,
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 6,
                            width: 80,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Dots placeholder
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (idx) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              height: 4,
              width: idx == 0 ? 16 : 5,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ],
    );
  }
}


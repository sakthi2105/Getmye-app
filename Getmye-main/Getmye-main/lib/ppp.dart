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
import 'widgets/customer_bottom_nav_bar.dart';
import 'theme/app_theme.dart';

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

class _HomePageState extends State<HomePage> {
  bool showDeliveryDetails = false;
  bool showCancelButtonContainer = false;
  bool isVegOnly = false;
  String _currentAddressShort = "Current Location";
  String _currentAddressFull = "Fetching live GPS location...";

  bool isSearchingRider = false;
  bool hasRiderAccepted = false;
  String assignedPartnerName = "";
  String assignedPartnerPhone = "";
  String assignedPartnerId = "";
  String assignedOrderOtp = "";
  String? assignedPartnerProfileImage;
  double _riderDistanceMeters = 0.0;
  List<LatLng> _trackingRoutePoints = [];

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
      return "Arrived at your doorstep!";
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

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _itemController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final TextEditingController _chatMsgController = TextEditingController();
  final TextEditingController _customLocationTextController = TextEditingController();

  // Promotional Banner Carousel Controller & Timer
  late PageController _bannerPageController;
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;

  final List<Map<String, dynamic>> _carouselBanners = [
    {
      'image': 'assets/banner_biryani_crushing.jpg',
      'fallback': 'assets/banner_biryani_crushing.jpg',
      'title': 'Chicken Biryani',
      'tag': 'CRUSHING OFFER',
      'originalPrice': '150',
      'offerPrice': '49',
      'item': 'Chicken Biryani',
      'budget': '49',
      'isAnyDeal': false,
      'icon': Icons.restaurant_rounded,
      'color': Color(0xFFEA580C),
    },
    {
      'image': 'assets/banner_shawarma_crushing.jpg',
      'fallback': 'assets/banner_shawarma_crushing.jpg',
      'title': 'Hot & Spicy Chicken Shawarma',
      'tag': 'CRUSHING OFFER',
      'originalPrice': '110',
      'offerPrice': '30',
      'item': 'Chicken Shawarma',
      'budget': '30',
      'isAnyDeal': false,
      'icon': Icons.fastfood_rounded,
      'color': Color(0xFFDC2626),
    },
    {
      'image': 'assets/banner_momos_crushing.jpg',
      'fallback': 'assets/banner_momos_crushing.jpg',
      'title': 'Hot & Steamy Momos',
      'tag': 'CRUSHING OFFER',
      'originalPrice': '120',
      'offerPrice': '39',
      'item': 'Hot & Steamy Momos',
      'budget': '39',
      'isAnyDeal': false,
      'icon': Icons.soup_kitchen_rounded,
      'color': Color(0xFFD97706),
    },
  ];

  @override
  void initState() {
    super.initState();
    _bannerPageController = PageController();
    _loadSavedLocation();
    _startBannerAutoSlide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptLocationService();
    });
  }

  // 🛰️ Requirement: "app kull avanthathum 2 perukum location on pana solanum"
  Future<void> _checkAndPromptLocationService() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && mounted) {
        await _showTurnOnGPSDialog(
          title: "Turn On GPS Location",
          message: "Please turn ON your device location (GPS) to accurately detect your delivery address and locate delivery partners.",
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever && mounted) {
        await _showTurnOnGPSDialog(
          title: "Location Permission Required",
          message: "Location permission is disabled for Getmye. Please enable it in device settings to place orders.",
          isPermissionSettings: true,
        );
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        await _requestLiveLocation(silent: true, forceOverrideAddress: false);
      }
    } catch (e) {
      debugPrint("Customer location service check error: $e");
    }
  }

  Future<void> _showTurnOnGPSDialog({
    required String title,
    required String message,
    bool isPermissionSettings = false,
  }) async {
    return showDialog<void>(
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
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) _checkAndPromptLocationService();
              });
            },
          ),
        ],
      ),
    );
  }

  void _startBannerAutoSlide() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_bannerPageController.hasClients) {
        int nextPage = (_currentBannerIndex + 1) % _carouselBanners.length;
        _bannerPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  Future<void> _loadSavedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final shortA = prefs.getString('customer_address_short');
    final fullA = prefs.getString('customer_address_full');
    final lat = prefs.getDouble('customer_latitude');
    final lng = prefs.getDouble('customer_longitude');

    if (shortA != null && shortA.isNotEmpty) {
      setState(() {
        _currentAddressShort = shortA;
        _currentAddressFull = (fullA != null && fullA.isNotEmpty) ? fullA : shortA;
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

      if (mounted) {
        setState(() {
          showDeliveryDetails = true;
          hasRiderAccepted = isAccepted;
          isSearchingRider = !isAccepted;
          if (isAccepted) {
            showCancelButtonContainer = false;
          }
          assignedPartnerName = isAccepted ? pName : '';
          assignedPartnerPhone = isAccepted ? pPhone : '';
          assignedPartnerId = isAccepted ? pId : '';
          if (pPic != null && pPic.isNotEmpty) assignedPartnerProfileImage = pPic;
          if (pOtp.isNotEmpty) assignedOrderOtp = pOtp;
        });
      }

      if (isAccepted) {
        _startRiderLocationPolling();
        _startOrderChatPolling();
        _fetchTrackingRoadRoute();
      }
      _startOrderPolling(curOrderId);
    } else {
      // Server confirmed NO active order (or clean startup) - clear all local stale state!
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

    // Refresh live device GPS position in background without wiping user's saved/selected address text
    await _requestLiveLocation(
      silent: true,
      forceOverrideAddress: false,
    );
  }

  Future<void> _requestLiveLocation({bool silent = false, bool forceOverrideAddress = false}) async {
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
        // Fast instant fix from last known position
        try {
          position = await Geolocator.getLastKnownPosition();
        } catch (_) {}

        // Live fix
        try {
          final livePos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 4),
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

        final existingShort = prefs.getString('customer_address_short');
        final hasCustomAddress = existingShort != null &&
            existingShort.isNotEmpty &&
            existingShort != "Current Location" &&
            !existingShort.toLowerCase().contains("matthi");

        if (!hasCustomAddress || forceOverrideAddress) {
          String shortA = "Current Location";
          String fullA = "Live GPS Location (${curPos.latitude.toStringAsFixed(4)}, ${curPos.longitude.toStringAsFixed(4)})";

          try {
            final geoRes = await http.get(
              Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${curPos.latitude}&lon=${curPos.longitude}'),
              headers: {'User-Agent': 'GetmyeApp/1.0 (contact@getmye.com)'},
            ).timeout(const Duration(seconds: 4));

            if (geoRes.statusCode == 200) {
              final geoData = jsonDecode(geoRes.body);
              final address = geoData['address'];
              if (address != null) {
                String road = address['road'] ?? address['neighbourhood'] ?? address['residential'] ?? '';
                final suburb = address['suburb'] ?? '';
                final city = address['city'] ?? address['town'] ?? address['village'] ?? address['state_district'] ?? '';

                // 🛑 Fix for "Matthi": Filter out obscure hamlet tag 'Matthi' if city is known
                if (road.isEmpty) {
                  if (suburb.isNotEmpty && !suburb.toLowerCase().contains('matthi')) {
                    road = suburb;
                  } else {
                    road = city.isNotEmpty ? city : 'Current Location';
                  }
                }

                if (road.isNotEmpty && city.isNotEmpty && road != city) {
                  shortA = '$road, $city';
                } else if (road.isNotEmpty) {
                  shortA = road;
                } else if (city.isNotEmpty) {
                  shortA = city;
                }

                String cleanFull = geoData['display_name'] ?? fullA;
                if (cleanFull.startsWith('Matthi, ')) {
                  cleanFull = cleanFull.replaceFirst('Matthi, ', '');
                }
                fullA = cleanFull;
              }
            }
          } catch (_) {}

          await prefs.setString('customer_address_short', shortA);
          await prefs.setString('customer_address_full', fullA);
          await prefs.setString('active_order_customer_address', fullA);

          if (mounted) {
            setState(() {
              _currentAddressShort = shortA;
              _currentAddressFull = fullA;
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
    _inOrderChatTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
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
        if (mounted) {
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
            setState(() {
              _riderLocation = LatLng(lat, lng);
              _riderDistanceMeters = dist;
            });
            if (locChanged) {
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
              child: Text("${banner['title']} deal applied! $priceText"),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          350,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
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

  final List<Map<String, dynamic>> _quickCravings = [
    {'name': 'Chicken Biryani', 'budget': '49', 'icon': '🍗', 'isVeg': false},
    {'name': 'Chicken Shawarma', 'budget': '30', 'icon': '🌯', 'isVeg': false},
    {'name': 'Dosa with Sambar', 'budget': '60', 'icon': '🥞', 'isVeg': true},
    {'name': 'Paneer Butter Masala', 'budget': '120', 'icon': '🍛', 'isVeg': true},
    {'name': 'Chicken 65', 'budget': '110', 'icon': '🍗', 'isVeg': false},
    {'name': 'Fresh Mango Juice', 'budget': '50', 'icon': '🥤', 'isVeg': true},
    {'name': 'Veg Hakka Noodles', 'budget': '80', 'icon': '🍜', 'isVeg': true},
    {'name': 'Mushroom Biryani', 'budget': '95', 'icon': '🍄', 'isVeg': true},
  ];

  List<Map<String, dynamic>> get _filteredCravings {
    return _quickCravings.where((dish) {
      if (isVegOnly && dish['isVeg'] != true) return false;
      return true;
    }).toList();
  }

  @override
  void dispose() {
    _searchRiderTimer?.cancel();
    _riderTrackingTimer?.cancel();
    _bannerTimer?.cancel();
    _inOrderChatTimer?.cancel();
    _bannerPageController.dispose();
    _itemController.dispose();
    _budgetController.dispose();
    _chatMsgController.dispose();
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
                                          final shortA = city.isNotEmpty ? city : line1;
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
        body: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Wine Burgundy Section extending smoothly into status bar without overlap
              _buildWineHeader(context),

              // Main Body Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Quick Cravings Suggestions Chips & Order Form Card (vanishes when order placed)
                        if (!showDeliveryDetails) ...[
                          _buildQuickCravings(),
                          const SizedBox(height: 20),
                          _buildOrderFormCard(),
                          const SizedBox(height: 20),
                        ],

                        // Delivery Partner Card (when Order Now is pressed)
                        if (showDeliveryDetails) _buildExpandedContainer(),

                        // Cancel Order Container
                        if (showDeliveryDetails || showCancelButtonContainer) ...[
                          const SizedBox(height: 16),
                          _buildCancelOrderContainer(),
                        ],

                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: const CustomerBottomNavBar(currentIndex: 0),
      ),
    ),
  );
}

  // Top Wine Header
  Widget _buildWineHeader(BuildContext context) {
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
      ),
      padding: EdgeInsets.only(
        top: topPadding + 10,
        left: 16,
        right: 16,
        bottom: 22,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Location and Profile Row
              _buildLocationAndProfileRow(),
              const SizedBox(height: 14),

              // 2. Interactive Auto-Sliding Offers Carousel
              _buildOffersCarouselBanner(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationAndProfileRow() {
    return Row(
      children: [
        // Brand Logo
        Container(
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
                    Text(
                      _currentAddressShort,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
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
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
          onPressed: _showTopMenu,
          tooltip: "More Options",
        ),
      ],
    );
  }

  Widget _buildOffersCarouselBanner() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
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
                    child: Image.asset(
                      banner['image'] as String,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => Image.asset(
                        banner['fallback'] as String,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
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
                color: isActive ? const Color(0xFFFFD700) : Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ],
    );
  }



  // Quick Cravings Suggestions Chips
  Widget _buildQuickCravings() {
    final cravings = _filteredCravings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isVegOnly ? "Pure Veg Delights 🌱" : "Quick Cravings",
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            if (isVegOnly)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text("VEG ONLY ACTIVE", style: TextStyle(color: AppColors.primaryDark, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 10),
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
            child: Row(
              children: cravings.map((dish) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: Text(dish['icon'] as String, style: const TextStyle(fontSize: 14)),
                    label: Text('${dish['name']} • ₹${dish['budget']}'),
                    backgroundColor: Colors.white,
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    side: const BorderSide(color: AppColors.border, width: 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onPressed: () {
                      setState(() {
                        _itemController.text = dish['name'] as String;
                        _budgetController.text = dish['budget'] as String;
                      });
                      scrollToBottom();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  // Custom Food Order Form Card
  Widget _buildOrderFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: AppColors.subtleShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.restaurant_rounded, color: AppColors.primaryDark, size: 20),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Order Anything You Crave",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                  Text(
                    "Enter food item & budget to order instantly",
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildTextField('Item name (e.g. Chicken Biryani)', TextInputType.text, _itemController, Icons.fastfood_outlined),
          const SizedBox(height: 14),
          _buildTextField('Budget (₹)', TextInputType.number, _budgetController, Icons.currency_rupee_rounded),
          const SizedBox(height: 14),
          _buildDropdown(),
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
                final custAddr = _currentAddressFull.isNotEmpty
                    ? _currentAddressFull
                    : "Current Delivery Location";
                final budgetVal = double.tryParse(_budgetController.text.trim()) ?? 150.0;

                // Show searching immediately with clean partner state
                setState(() {
                  showDeliveryDetails = true;
                  isSearchingRider = true;
                  hasRiderAccepted = false;
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

                // ⚡ Fast: Use live GPS coordinates without blocking delay
                final orderLat = _customerLocation.latitude;
                final orderLng = _customerLocation.longitude;

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
                      'budget': budgetVal,
                      'cod_otp': customerFixedOtp,
                      'customer_latitude': orderLat,
                      'customer_longitude': orderLng,
                    }),
                  ).timeout(const Duration(seconds: 6));
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
                    final errMsg = data['error'] ?? data['message'] ?? 'Failed to create order on server';
                    if (mounted) {
                      setState(() {
                        isSearchingRider = false;
                        showDeliveryDetails = true;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(errMsg),
                          backgroundColor: AppColors.danger,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
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
                await prefs.remove('order_${newOrderId}_chat_messages'); // Reset chat for fresh new order
                await prefs.setString('active_order_item', itemText);
                await prefs.setString('active_order_budget', _budgetController.text.trim());
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
                await prefs.remove('active_order_partner_pic');

                _startOrderPolling(newOrderId);
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

  Widget _buildTextField(String label, TextInputType type, TextEditingController controller, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: TextField(
        controller: controller,
        keyboardType: type,
        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: AppColors.primaryDark, size: 20),
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

  Widget _buildDropdown() {
    final profileAddress = _currentAddressFull.isNotEmpty ? _currentAddressFull : "Current Delivery Location";

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
          _loadSavedLocation();
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.location_on_rounded, color: Color(0xFFEA580C), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Delivery Location (From Profile)',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profileAddress,
                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "Profile",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.edit_location_alt_outlined, color: AppColors.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContainer() {
    if (!hasRiderAccepted || isSearchingRider) {
      return const BikeRoadSearchingAnimation();
    }
    return _buildAssignedPartnerContainer();
  }

  void _startOrderPolling(String orderId) {
    _searchRiderTimer?.cancel();
    _searchRiderTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
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
              if (pName.isNotEmpty) await p.setString('active_order_partner_name', pName);
              if (pPhone.isNotEmpty) await p.setString('active_order_partner_phone', pPhone);
              if (pId.isNotEmpty) await p.setString('active_order_partner_id', pId);
              if (pPic != null && pPic.isNotEmpty) await p.setString('active_order_partner_image', pPic);
              if (pOtp.isNotEmpty) await p.setString('active_cod_otp', pOtp);
              await p.setString('active_order_status', order['status']);
              await p.setBool('active_order_partner_accepted', true);

              if (mounted) {
                final bool wasSearching = isSearchingRider;
                final bool hasChanged = wasSearching ||
                    !showDeliveryDetails ||
                    !hasRiderAccepted ||
                    assignedPartnerName != pName ||
                    assignedPartnerPhone != pPhone ||
                    (pId.isNotEmpty && assignedPartnerId != pId) ||
                    (pPic != null && pPic.isNotEmpty && assignedPartnerProfileImage != pPic) ||
                    (pOtp.isNotEmpty && assignedOrderOtp != pOtp);

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
                  });
                }
                if (wasSearching) {
                  _startRiderLocationPolling();
                  _startOrderChatPolling();
                  _fetchTrackingRoadRoute();
                }
              }
            } else if (st == 'delivered') {
              timer.cancel();
              final p = await SharedPreferences.getInstance();
              await p.setBool('has_active_order', false);
              await p.setString('active_order_status', 'delivered');
              await p.remove('active_order_id');
              if (mounted) {
                setState(() {
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
                      orderId: orderId,
                      totalAmount: finalTot,
                      foodPrice: bFood?.toDouble(),
                      tipAmount: bTip?.toDouble(),
                      paymentMethod: payMethod,
                      isDeliveryPartner: false,
                    ),
                  ),
                );
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

          // Live ETA and Delivery Status Banner (Full width, responsive, never overflows)
          Builder(
            builder: (context) {
              final statusText = _formatRiderDistance();
              final isArrived = statusText.toLowerCase().contains("arrived");
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isArrived ? const Color(0xFFDCFCE7) : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isArrived ? const Color(0xFF86EFAC) : const Color(0xFFBBF7D0),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isArrived ? Icons.home_rounded : Icons.directions_bike_rounded,
                      size: 18,
                      color: const Color(0xFF15803D),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusText,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF15803D),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF15803D),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isArrived ? "ARRIVED" : "ON THE WAY",
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
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
                  GoogleMap(
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

          // Prominent Delivery OTP Card for customer
          if (assignedOrderOtp.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFD97706),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.key_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "DELIVERY OTP",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Color(0xFF92400E),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Share this code with partner to receive delivery",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF78350F),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD97706), width: 1.5),
                    ),
                    child: Text(
                      assignedOrderOtp,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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

/// Animated Bike Riding on Road Loader
class BikeRoadSearchingAnimation extends StatefulWidget {
  const BikeRoadSearchingAnimation({super.key});

  @override
  State<BikeRoadSearchingAnimation> createState() => _BikeRoadSearchingAnimationState();
}

class _BikeRoadSearchingAnimationState extends State<BikeRoadSearchingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _roadController;

  @override
  void initState() {
    super.initState();
    _roadController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _roadController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
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
          // Animated Road & Bike Scene
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 165,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
              ),
              child: AnimatedBuilder(
                animation: _roadController,
                builder: (context, child) {
                  final progress = _roadController.value;
                  final bikeBounce = sin(progress * 2 * pi * 3) * 2.0;

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Full 3D Delivery Boy Bike Riding on Road
                      Positioned.fill(
                        child: Transform.translate(
                          offset: Offset(0, bikeBounce),
                          child: Image.asset(
                            'assets/delivery_bike_road.png',
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            errorBuilder: (ctx, err, stack) => Image.asset(
                              'assets/delivery_boy_toon.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),

                      // Gradient Overlay for badge contrast
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.5),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.6),
                              ],
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                      ),

                      // Top Live Status Pill
                      Positioned(
                        top: 10,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF34D399), width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.radar_rounded, size: 13, color: Color(0xFF34D399)),
                              SizedBox(width: 5),
                              Text(
                                "RADAR DISPATCHING • NEARBY",
                                style: TextStyle(
                                  color: Color(0xFF34D399),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bottom Asphalt & Moving Lane Divider
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 24,
                        child: Container(
                          color: const Color(0xFF18181B).withValues(alpha: 0.9),
                          child: CustomPaint(
                            size: const Size(double.infinity, 4),
                            painter: _RoadStripesPainter(progress: progress),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Status Heading
          const Text(
            "Searching & Notifying Delivery Partner...",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            "Connecting with active riders near you. Waiting for partner to click 'Accept Order'...",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 12),

          // Linear loading indicator
          const SizedBox(
            width: 150,
            child: LinearProgressIndicator(
              backgroundColor: AppColors.primaryLight,
              color: AppColors.primary,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 14),

          // Live Waiting Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primarySubtle,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_tethering_rounded, color: AppColors.primary, size: 16),
                SizedBox(width: 8),
                Text(
                  "Waiting for Delivery Partner Acceptance",
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadStripesPainter extends CustomPainter {
  final double progress;
  _RoadStripesPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFBBF24) // Yellow road divider lines
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const dashWidth = 24.0;
    const dashSpace = 16.0;
    const totalCycle = dashWidth + dashSpace;
    final offset = -progress * totalCycle;

    double startX = offset;
    while (startX < size.width) {
      final x1 = max(0.0, startX);
      final x2 = min(size.width, startX + dashWidth);
      if (x2 > 0 && x1 < size.width) {
        canvas.drawLine(Offset(x1, size.height / 2), Offset(x2, size.height / 2), paint);
      }
      startX += totalCycle;
    }
  }

  @override
  bool shouldRepaint(covariant _RoadStripesPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}


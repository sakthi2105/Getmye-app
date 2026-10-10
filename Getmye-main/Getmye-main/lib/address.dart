import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'ppp.dart';
import 'theme/app_theme.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AddressScreen(),
    );
  }
}

// -------------------- Address Screen --------------------
class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key});
  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  List<dynamic> addresses = [];
  bool _isLoading = false;
  bool _isDetectingGPS = false;
  String _activeAddressShort = "Current Location";
  String _activeAddressFull = "Detecting delivery address...";
  String? _activeAddId;

  @override
  void initState() {
    super.initState();
    _loadActiveAddressFromPrefs();
    _fetchAddresses();
  }

  Future<void> _loadActiveAddressFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final shortA = prefs.getString('customer_address_short');
    final fullA = prefs.getString('customer_address_full');
    final activeId = prefs.getString('active_delivery_add_id');
    if (mounted && shortA != null && shortA.isNotEmpty) {
      setState(() {
        _activeAddressShort = shortA;
        _activeAddressFull = fullA ?? shortA;
        _activeAddId = activeId;
      });
    }
  }

  Future<void> _fetchAddresses() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null || userId.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final res = await http.get(ApiConfig.addressList(userId));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['addresses'] is List) {
          final list = data['addresses'] as List;
          setState(() {
            addresses = list;
          });

          // If no active address is set, use the default or first one
          if (list.isNotEmpty && _activeAddressFull == "Detecting delivery address...") {
            final def = list.firstWhere(
              (a) => a['is_default'] == true,
              orElse: () => list.first,
            );
            await _selectAddressAsActive(Map<String, dynamic>.from(def), notify: false);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Fetch address error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 📍 Detect live GPS location, reverse geocode, and save as active delivery address
  Future<void> _detectAndSaveCurrentGPSLocation() async {
    setState(() => _isDetectingGPS = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Location permission is permanently denied. Please enable in app settings."),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 6),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Could not retrieve GPS signal. Please try again or enter address manually."),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final lat = position.latitude;
      final lng = position.longitude;

      String road = "Current Location";
      String city = "Live Location";
      String state = "Tamil Nadu";
      String pincode = "";
      String fullDisplayName = "Live GPS Location ($lat, $lng)";

      try {
        final geoRes = await http.get(
          Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng'),
          headers: {'User-Agent': 'GetmyeApp/1.0 (contact@getmye.com)'},
        ).timeout(const Duration(seconds: 5));

        if (geoRes.statusCode == 200) {
          final geoData = jsonDecode(geoRes.body);
          final address = geoData['address'];
          if (address != null) {
            road = address['road'] ?? address['suburb'] ?? address['neighbourhood'] ?? address['quarter'] ?? 'Current Location';
            city = address['city'] ?? address['town'] ?? address['village'] ?? address['county'] ?? address['state_district'] ?? 'Live Location';
            state = address['state'] ?? 'Tamil Nadu';
            pincode = address['postcode'] ?? '';
            fullDisplayName = geoData['display_name'] ?? "$road, $city, $state $pincode";
          }
        }
      } catch (_) {}

      final shortA = (road != "Current Location" && city != "Live Location") ? "$road, $city" : (road != "Current Location" ? road : city);
      final fullA = fullDisplayName;

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');

      // Update SharedPreferences immediately
      await prefs.setString('customer_address_short', shortA);
      await prefs.setString('customer_address_full', fullA);
      await prefs.setString('active_order_customer_address', fullA);
      await prefs.setDouble('customer_latitude', lat);
      await prefs.setDouble('customer_longitude', lng);
      await prefs.remove('active_delivery_add_id');

      // Also save to MongoDB if logged in
      if (userId != null && userId.isNotEmpty) {
        try {
          await http.post(
            ApiConfig.addressAdd,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'line1': road,
              'line2': 'Live GPS Location',
              'city': city,
              'state': state,
              'country': 'India',
              'pincode': pincode,
              'latitude': lat,
              'longitude': lng,
              'is_default': true,
            }),
          );
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _activeAddressShort = shortA;
          _activeAddressFull = fullA;
          _activeAddId = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text("📍 Current location saved & set as Active: $shortA")),
              ],
            ),
            backgroundColor: const Color(0xFF047857),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        _fetchAddresses();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error fetching current location: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isDetectingGPS = false);
    }
  }

  // 🎯 Set an existing address as Active Delivery Address
  Future<void> _selectAddressAsActive(Map<String, dynamic> addr, {bool notify = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final shortA = (addr['city'] != null && addr['city'].toString().isNotEmpty)
        ? addr['city'].toString()
        : (addr['line1'] ?? 'Home').toString();

    final parts = [
      addr['line1'],
      addr['line2'],
      addr['city'],
      addr['state'],
      if (addr['pincode'] != null && addr['pincode'].toString().isNotEmpty) "- ${addr['pincode']}"
    ].where((p) => p != null && p.toString().trim().isNotEmpty).join(', ');

    final fullA = parts.isNotEmpty ? parts : shortA;
    final addId = addr['add_id']?.toString();

    await prefs.setString('customer_address_short', shortA);
    await prefs.setString('customer_address_full', fullA);
    await prefs.setString('active_order_customer_address', fullA);
    if (addId != null) {
      await prefs.setString('active_delivery_add_id', addId);
    }

    if (addr['latitude'] != null && addr['longitude'] != null) {
      await prefs.setDouble('customer_latitude', (addr['latitude'] as num).toDouble());
      await prefs.setDouble('customer_longitude', (addr['longitude'] as num).toDouble());
    }

    final userId = prefs.getString('user_id');
    if (userId != null && addId != null) {
      try {
        await http.post(
          Uri.parse('${ApiConfig.baseUrl}/api/address/set-default'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'add_id': addId, 'user_id': userId}),
        );
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _activeAddressShort = shortA;
        _activeAddressFull = fullA;
        _activeAddId = addId;
      });

      if (notify) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text("Active delivery address set to: $shortA")),
              ],
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _deleteAddress(String addId) async {
    try {
      final res = await http.delete(ApiConfig.addressDelete(addId));
      if (res.statusCode == 200) {
        if (_activeAddId == addId) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('active_delivery_add_id');
        }
        _fetchAddresses();
      }
    } catch (_) {}
  }

  void _showDeleteConfirm(String addId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text("Delete Address?", style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text("Are you sure you want to delete this saved address?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _deleteAddress(addId);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleBackNavigation() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
            onPressed: _handleBackNavigation,
          ),
          title: const Text("My Delivery Addresses", style: AppTypography.screenHeading),
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
              tooltip: "Refresh Addresses",
              onPressed: _fetchAddresses,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 🌟 Active Delivery Location Hero Card
            _buildActiveLocationHeroCard(),
            const SizedBox(height: 18),

            // ⚡ Quick Option 1: Use Current Location Button
            _buildCurrentLocationActionCard(),
            const SizedBox(height: 12),

            // ✍️ Quick Option 2: Enter Location Manually Button
            _buildManualAddressActionCard(),
            const SizedBox(height: 24),

            // Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Saved Addresses",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                Text(
                  "${addresses.length} saved",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Saved Addresses List
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (addresses.isEmpty)
              _buildEmptyStateCard()
            else
              ...addresses.map((addr) => _buildAddressItemCard(Map<String, dynamic>.from(addr))),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // Active Delivery Location Hero Banner
  Widget _buildActiveLocationHeroCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0C1B30), // Deep Midnight Navy
            Color(0xFF142B4A), // Primary Navy Blue
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 14),
                    SizedBox(width: 4),
                    Text(
                      "ACTIVE FOR ORDERS",
                      style: TextStyle(
                        color: Color(0xFF34D399),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.local_shipping_rounded, color: Colors.white70, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _activeAddressShort,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _activeAddressFull,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  // 📍 Action Card: Detect and Save Current Location (GPS)
  Widget _buildCurrentLocationActionCard() {
    return InkWell(
      onTap: _isDetectingGPS ? null : _detectAndSaveCurrentGPSLocation,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.5), width: 1.5),
          boxShadow: AppColors.subtleShadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isDetectingGPS
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF2563EB)),
                    )
                  : const Icon(Icons.my_location_rounded, color: Color(0xFF2563EB), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        "Use Current Location",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          "GPS",
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _isDetectingGPS ? "Detecting high-precision GPS..." : "Auto-detect & save your spot via phone satellite",
                    style: const TextStyle(fontSize: 12, color: Color(0xFF60A5FA), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF93C5FD)),
          ],
        ),
      ),
    );
  }

  // ✍️ Action Card: Enter Address Manually
  Widget _buildManualAddressActionCard() {
    return InkWell(
      onTap: () async {
        final added = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EditAddressPage(address: {})),
        );
        if (added == true) {
          _fetchAddresses();
          _loadActiveAddressFromPrefs();
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.subtleShadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add_location_alt_rounded, color: AppColors.primaryDark, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Enter Address Manually",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    "Type flat no, street, landmark, city & pincode",
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  // Saved Address Item Card
  Widget _buildAddressItemCard(Map<String, dynamic> addr) {
    final addId = addr['add_id']?.toString();
    final isSelected = (_activeAddId != null && _activeAddId == addId) ||
        (_activeAddressFull.contains(addr['line1'] ?? '') && addr['line1'] != null && addr['line1'].toString().isNotEmpty);

    return InkWell(
      onTap: () => _selectAddressAsActive(addr),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : AppColors.subtleShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primaryLight : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.home_rounded,
                    color: isSelected ? AppColors.primaryDark : AppColors.textSecondary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    addr['line1'] ?? 'Address',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF047857), size: 12),
                        SizedBox(width: 4),
                        Text(
                          "Selected",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF047857)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (addr['line2'] != null && addr['line2'].toString().trim().isNotEmpty) ...[
              Text(
                addr['line2'],
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              "${addr['city'] ?? ''}, ${addr['state'] ?? ''}${addr['pincode'] != null && addr['pincode'].toString().isNotEmpty ? ' - ${addr['pincode']}' : ''}",
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isSelected ? "Tap another address to switch" : "Tap card to select as delivery address",
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? const Color(0xFF047857) : AppColors.textMuted,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      icon: const Icon(Icons.edit_outlined, size: 15, color: AppColors.primary),
                      label: const Text("Edit", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                      onPressed: () async {
                        final updated = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => EditAddressPage(address: addr)),
                        );
                        if (updated == true) {
                          _fetchAddresses();
                          _loadActiveAddressFromPrefs();
                        }
                      },
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      icon: const Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.danger),
                      label: const Text("Delete", style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 12)),
                      onPressed: () => _showDeleteConfirm(addr['add_id']),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: const [
          Icon(Icons.location_off_rounded, color: AppColors.textMuted, size: 48),
          SizedBox(height: 12),
          Text(
            "No saved addresses yet",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          SizedBox(height: 6),
          Text(
            "Tap 'Use Current Location' or 'Enter Address Manually' above to save your first delivery location.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// -------------------- Edit Address Page --------------------
class EditAddressPage extends StatefulWidget {
  final Map<String, dynamic> address;
  const EditAddressPage({super.key, required this.address});
  @override
  State<EditAddressPage> createState() => _EditAddressPageState();
}

class _EditAddressPageState extends State<EditAddressPage> {
  final c1 = TextEditingController(); // Flat/House/Building
  final c2 = TextEditingController(); // Street/Landmark
  final c3 = TextEditingController(); // City
  final c4 = TextEditingController(); // District
  final c5 = TextEditingController(); // State
  final c6 = TextEditingController(); // Country
  final c7 = TextEditingController(); // Pincode

  bool _setAsActive = true;
  bool _isAutoFillingGPS = false;
  double? _latitude;
  double? _longitude;

  bool get isEdit => widget.address['add_id'] != null;

  @override
  void initState() {
    super.initState();
    c1.text = widget.address['line1'] ?? '';
    c2.text = widget.address['line2'] ?? '';
    c3.text = widget.address['city'] ?? '';
    c4.text = widget.address['district'] ?? '';
    c5.text = widget.address['state'] ?? 'Tamil Nadu';
    c6.text = widget.address['country'] ?? 'India';
    c7.text = widget.address['pincode'] ?? '';
    if (widget.address['latitude'] != null) {
      _latitude = (widget.address['latitude'] as num).toDouble();
    }
    if (widget.address['longitude'] != null) {
      _longitude = (widget.address['longitude'] as num).toDouble();
    }
  }

  @override
  void dispose() {
    c1.dispose();
    c2.dispose();
    c3.dispose();
    c4.dispose();
    c5.dispose();
    c6.dispose();
    c7.dispose();
    super.dispose();
  }

  // 📍 One-click GPS auto-fill for the manual form
  Future<void> _autoFillFromCurrentGPS() async {
    setState(() => _isAutoFillingGPS = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position != null) {
        _latitude = position.latitude;
        _longitude = position.longitude;

        try {
          final res = await http.get(
            Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}'),
            headers: {'User-Agent': 'GetmyeApp/1.0 (contact@getmye.com)'},
          ).timeout(const Duration(seconds: 5));

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final addr = data['address'];
            if (addr != null) {
              final road = addr['road'] ?? addr['suburb'] ?? addr['neighbourhood'] ?? '';
              final landmark = addr['quarter'] ?? addr['suburb'] ?? '';
              final city = addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['county'] ?? '';
              final dist = addr['state_district'] ?? '';
              final state = addr['state'] ?? 'Tamil Nadu';
              final pin = addr['postcode'] ?? '';

              setState(() {
                if (road.isNotEmpty) c1.text = road;
                if (landmark.isNotEmpty) c2.text = landmark;
                if (city.isNotEmpty) c3.text = city;
                if (dist.isNotEmpty) c4.text = dist;
                if (state.isNotEmpty) c5.text = state;
                if (pin.isNotEmpty) c7.text = pin;
              });

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("📍 Auto-filled fields from current GPS location!"),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("GPS auto-fill error: $e");
    } finally {
      if (mounted) setState(() => _isAutoFillingGPS = false);
    }
  }

  Future<void> _save() async {
    final line1Val = c1.text.trim();
    final cityVal = c3.text.trim();

    if (line1Val.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter House/Flat No or Street Name"),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to save addresses')),
      );
      return;
    }

    final body = {
      'user_id': userId,
      'line1': line1Val,
      'line2': c2.text.trim(),
      'city': cityVal.isNotEmpty ? cityVal : line1Val,
      'district': c4.text.trim(),
      'state': c5.text.trim().isNotEmpty ? c5.text.trim() : 'Tamil Nadu',
      'country': c6.text.trim().isNotEmpty ? c6.text.trim() : 'India',
      'pincode': c7.text.trim(),
      'latitude': _latitude,
      'longitude': _longitude,
      'is_default': _setAsActive,
    };

    if (isEdit) body['add_id'] = widget.address['add_id'];

    final url = isEdit ? ApiConfig.addressUpdate : ApiConfig.addressAdd;

    try {
      final res = await (isEdit
          ? http.put(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          : http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)));

      if (res.statusCode == 200) {
        final shortA = cityVal.isNotEmpty ? cityVal : line1Val;
        final fullA = [
          line1Val,
          c2.text.trim(),
          cityVal,
          c5.text.trim(),
          if (c7.text.trim().isNotEmpty) "- ${c7.text.trim()}"
        ].where((s) => s.isNotEmpty).join(', ');

        if (_setAsActive) {
          await prefs.setString('customer_address_short', shortA);
          await prefs.setString('customer_address_full', fullA);
          await prefs.setString('active_order_customer_address', fullA);
          if (_latitude != null) await prefs.setDouble('customer_latitude', _latitude!);
          if (_longitude != null) await prefs.setDouble('customer_longitude', _longitude!);
          if (isEdit && widget.address['add_id'] != null) {
            await prefs.setString('active_delivery_add_id', widget.address['add_id'].toString());
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isEdit ? "Address updated successfully!" : "Address saved successfully!"),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save address: ${res.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving address: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(isEdit ? 'Edit Address' : 'Enter Delivery Location', style: AppTypography.screenHeading),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 📍 One-Click GPS Auto-Fill Helper Card
          InkWell(
            onTap: _isAutoFillingGPS ? null : _autoFillFromCurrentGPS,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF93C5FD)),
              ),
              child: Row(
                children: [
                  _isAutoFillingGPS
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
                        )
                      : const Icon(Icons.my_location_rounded, color: Color(0xFF2563EB), size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Detect & Auto-fill from Current Location",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1E40AF)),
                        ),
                        Text(
                          "Pulls your live GPS road, city & pincode into the form",
                          style: TextStyle(fontSize: 11, color: Color(0xFF3B82F6)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          _buildFieldLabel("House / Flat No, Building / Apartment Name *"),
          _buildInputField("e.g. Flat 302, Green Meadows", c1),
          const SizedBox(height: 14),

          _buildFieldLabel("Street Name / Road / Area *"),
          _buildInputField("e.g. 5th Cross Road, Gandhipuram", c2),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel("City / Town *"),
                    _buildInputField("e.g. Coimbatore", c3),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel("Pincode"),
                    _buildInputField("e.g. 641012", c7, isNumber: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel("District"),
                    _buildInputField("e.g. Coimbatore", c4),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel("State"),
                    _buildInputField("Tamil Nadu", c5),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Checkbox: Set as active delivery address
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _setAsActive,
                  activeColor: AppColors.primary,
                  onChanged: (val) => setState(() => _setAsActive = val ?? true),
                ),
                const Expanded(
                  child: Text(
                    "Set as my Active Delivery Address for orders",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 1,
              ),
              child: Text(
                isEdit ? 'Update Address' : 'Save & Select Delivery Address',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      ),
    );
  }

  Widget _buildInputField(String hint, TextEditingController c, {bool isNumber = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: c,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}

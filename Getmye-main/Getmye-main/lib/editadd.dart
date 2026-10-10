import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'widgets/customer_bottom_nav_bar.dart';
import 'theme/app_theme.dart';

class EditAddressPage extends StatefulWidget {
  final Map<String, dynamic> address;
  const EditAddressPage({super.key, required this.address});

  @override
  State<EditAddressPage> createState() => _EditAddressPageState();
}

class _EditAddressPageState extends State<EditAddressPage> {
  final addressLine1Controller = TextEditingController();
  final addressLine2Controller = TextEditingController();
  final cityController = TextEditingController();
  final districtController = TextEditingController();
  final stateController = TextEditingController();
  final countryController = TextEditingController();
  final pincodeController = TextEditingController();

  double? _latitude;
  double? _longitude;
  bool _isAutoFillingGPS = false;
  bool _setAsActive = true;

  bool get isEdit => widget.address['add_id'] != null;

  @override
  void initState() {
    super.initState();
    // pre-fill if editing
    addressLine1Controller.text = widget.address['line1'] ?? '';
    addressLine2Controller.text = widget.address['line2'] ?? '';
    cityController.text = widget.address['city'] ?? '';
    districtController.text = widget.address['district'] ?? '';
    stateController.text = widget.address['state'] ?? 'Tamil Nadu';
    countryController.text = widget.address['country'] ?? 'India';
    pincodeController.text = widget.address['pincode'] ?? '';
    if (widget.address['latitude'] != null) {
      _latitude = (widget.address['latitude'] as num).toDouble();
    }
    if (widget.address['longitude'] != null) {
      _longitude = (widget.address['longitude'] as num).toDouble();
    }
  }

  Future<void> _autoFillFromCurrentGPS() async {
    setState(() => _isAutoFillingGPS = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission permanently denied. Enable in app settings.')),
          );
        }
        return;
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 6),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not acquire GPS signal. Please enter address manually.')),
          );
        }
        return;
      }

      _latitude = pos.latitude;
      _longitude = pos.longitude;

      final res = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${pos.latitude}&lon=${pos.longitude}'),
        headers: {'User-Agent': 'GetmyeApp/1.0 (contact@getmye.com)'},
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final addr = data['address'];
        if (addr != null && mounted) {
          final road = addr['road'] ?? addr['suburb'] ?? addr['neighbourhood'] ?? addr['quarter'] ?? '';
          final city = addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['county'] ?? addr['state_district'] ?? '';
          final state = addr['state'] ?? 'Tamil Nadu';
          final postcode = addr['postcode'] ?? '';

          setState(() {
            if (road.isNotEmpty) addressLine1Controller.text = road;
            if (city.isNotEmpty) {
              cityController.text = city;
              districtController.text = city;
            }
            if (state.isNotEmpty) stateController.text = state;
            if (postcode.isNotEmpty) pincodeController.text = postcode;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📍 Auto-filled address details from current GPS location!'),
              backgroundColor: Color(0xFF047857),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS Auto-fill error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAutoFillingGPS = false);
    }
  }

  Future<void> _saveAddress() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final userId = prefs.getString('user_id');
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User ID not found. Please login again.')),
      );
      return;
    }

    final l1 = addressLine1Controller.text.trim();
    if (l1.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Address Line 1 / Street name')),
      );
      return;
    }

    final url = isEdit ? ApiConfig.addressUpdate : ApiConfig.addressAdd;

    final body = {
      'user_id': userId,
      'line1': l1,
      'line2': addressLine2Controller.text.trim(),
      'city': cityController.text.trim().isNotEmpty ? cityController.text.trim() : l1,
      'district': districtController.text.trim(),
      'state': stateController.text.trim().isNotEmpty ? stateController.text.trim() : 'Tamil Nadu',
      'country': countryController.text.trim().isNotEmpty ? countryController.text.trim() : 'India',
      'pincode': pincodeController.text.trim(),
      'latitude': _latitude,
      'longitude': _longitude,
      'is_default': _setAsActive,
    };

    if (isEdit) body['add_id'] = widget.address['add_id'];

    try {
      final response = await (isEdit
          ? http.put(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          : http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)));

      if (response.statusCode == 200) {
        final shortA = cityController.text.trim().isNotEmpty ? cityController.text.trim() : l1;
        final fullA = [
          l1,
          addressLine2Controller.text.trim(),
          cityController.text.trim(),
          stateController.text.trim(),
          if (pincodeController.text.trim().isNotEmpty) "- ${pincodeController.text.trim()}"
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
              content: Text(isEdit ? 'Address updated' : 'Address added & set as active'),
              backgroundColor: AppColors.primary,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF17211B)),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              isEdit ? "Edit Address" : "Enter Delivery Address",
              style: const TextStyle(color: Color(0xFF17211B), fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 📍 Auto-fill from GPS Helper Card
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
                                  "Pulls your live GPS road, city & pincode into form",
                                  style: TextStyle(fontSize: 11, color: Color(0xFF3B82F6)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildInputField("Address Line 1 (House No, Flat, Street) *", addressLine1Controller),
                  const SizedBox(height: 14),
                  _buildInputField("Address Line 2 (Area, Landmark)", addressLine2Controller),
                  const SizedBox(height: 14),
                  _buildInputField("City / Town *", cityController),
                  const SizedBox(height: 14),
                  _buildInputField("District", districtController),
                  const SizedBox(height: 14),
                  _buildInputField("State", stateController),
                  const SizedBox(height: 14),
                  _buildInputField("Country", countryController),
                  const SizedBox(height: 14),
                  _buildInputField("Pincode", pincodeController, isNumber: true),
                  const SizedBox(height: 16),

                  // Set as active toggle
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

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saveAddress,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        isEdit ? "Save Changes" : "Save & Set Delivery Address",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const CustomerBottomNavBar(currentIndex: 1),
    );
  }

  Widget _buildInputField(String hint, TextEditingController controller, {bool isNumber = false}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5EAE6)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF6B756D)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

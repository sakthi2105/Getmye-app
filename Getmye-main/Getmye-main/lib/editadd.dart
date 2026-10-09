import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/ppp.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/profile.dart';
import 'package:flutter_application_1/pay.dart';
import 'package:flutter_application_1/options.dart';
import 'widgets/customer_bottom_nav_bar.dart';

class EditAddressPage extends StatefulWidget {
  final Map<String, dynamic> address; // note: dynamic to support add_id etc.
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

  bool get isEdit => widget.address['add_id'] != null;

  @override
  void initState() {
    super.initState();
    // pre-fill if editing
    addressLine1Controller.text = widget.address['line1'] ?? '';
    addressLine2Controller.text = widget.address['line2'] ?? '';
    cityController.text = widget.address['city'] ?? '';
    districtController.text = widget.address['district'] ?? '';
    stateController.text = widget.address['state'] ?? '';
    countryController.text = widget.address['country'] ?? '';
    pincodeController.text = widget.address['pincode'] ?? '';
  }

  Future<void> _saveAddress() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User ID not found. Please login again.')),
      );
      return;
    }

    final url = isEdit
        ? Uri.parse('http://192.168.29.196:5000/api/address/update')
        : Uri.parse('http://192.168.29.196:5000/api/address/add');

    final body = {
      'user_id': userId,
      'line1': addressLine1Controller.text,
      'line2': addressLine2Controller.text,
      'city': cityController.text,
      'district': districtController.text,
      'state': stateController.text,
      'country': countryController.text,
      'pincode': pincodeController.text,
    };

    if (isEdit) body['add_id'] = widget.address['add_id'];

    try {
      final response = await (isEdit
          ? http.put(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          : http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)));

      print('Response: ${response.body}');
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEdit ? 'Address updated' : 'Address added')),
        );
        Navigator.pop(context, true); // return true to refresh list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${response.body}')),
        );
      }
    } catch (e) {
      print('❌ Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              isEdit ? "Edit Address" : "Add New Address",
              style: const TextStyle(color: Color(0xFF17211B), fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildInputField("Address Line 1 (House, Street)", addressLine1Controller),
                  const SizedBox(height: 14),
                  _buildInputField("Address Line 2 (Area, Landmark)", addressLine2Controller),
                  const SizedBox(height: 14),
                  _buildInputField("City", cityController),
                  const SizedBox(height: 14),
                  _buildInputField("District", districtController),
                  const SizedBox(height: 14),
                  _buildInputField("State", stateController),
                  const SizedBox(height: 14),
                  _buildInputField("Country", countryController),
                  const SizedBox(height: 14),
                  _buildInputField("Pincode", pincodeController, isNumber: true),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saveAddress,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        isEdit ? "Save Changes" : "Add Address",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
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

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// main entry
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AddressScreen(),
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

  @override
  void initState() {
    super.initState();
    _fetchAddresses();
  }

 Future<void> _fetchAddresses() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id');
  if (userId == null) return;

  try {
    final url = Uri.parse('http://192.168.29.196:5000/api/address/list?user_id=$userId');
    final res = await http.get(url);
    print('Response body: ${res.body}');

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
        if (data is Map && data['addresses'] is List) {
          setState(() {
            addresses = data['addresses'];
          });
          if (addresses.isNotEmpty) {
            final first = addresses.first;
            final shortA = (first['city'] ?? first['district'] ?? first['line1'] ?? 'Home').toString();
            final fullA = "${first['line1'] ?? ''}, ${first['line2'] ?? ''}, ${first['city'] ?? ''}, ${first['state'] ?? ''} - ${first['pincode'] ?? ''}";
            await prefs.setString('customer_address_short', shortA);
            await prefs.setString('customer_address_full', fullA);
          }
          print('Fetched addresses: $addresses');
      } else {
        print('Unexpected data format: $data');
        setState(() {
          addresses = [];
        });
      }
    } else {
      print('Fetch failed: ${res.body}');
    }
  } catch (e) {
    print('❌ Fetch error: $e');
  }
}


  Future<void> _deleteAddress(String addId) async {
    try {
      final url = Uri.parse('http://192.168.29.196:5000/api/address/delete/$addId');
      final res = await http.delete(url);
      if (res.statusCode == 200) {
        _fetchAddresses();
      } else {
        print('Delete failed: ${res.body}');
      }
    } catch (e) {
      print('❌ Delete error: $e');
    }
  }

  void _showDeleteConfirm(String addId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Delete Address"),
        content: Text("Are you sure you want to delete this address?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAddress(addId);
            },
            child: Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _shareAddress(Map<String, dynamic> address) {
    final text = "${address['line1']}, ${address['city']}, ${address['state']}";
    print('📤 Share: $text');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pretend sharing: $text')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: const Text("My Addresses", style: TextStyle(color: Color(0xFF17211B), fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF17211B)),
      ),
      body: addresses.isEmpty
          ? const Center(
              child: Text(
                'No saved addresses yet',
                style: TextStyle(color: Color(0xFF6B756D), fontSize: 14),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: addresses.length,
              itemBuilder: (context, index) {
                final addr = addresses[index];
                return InkWell(
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final shortA = (addr['city'] ?? addr['district'] ?? addr['line1'] ?? 'Home').toString();
                    final fullA = "${addr['line1'] ?? ''}, ${addr['line2'] ?? ''}, ${addr['city'] ?? ''}, ${addr['state'] ?? ''} - ${addr['pincode'] ?? ''}";
                    await prefs.setString('customer_address_short', shortA);
                    await prefs.setString('customer_address_full', fullA);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Selected as delivery address: $shortA"),
                          backgroundColor: const Color(0xFF15803D),
                        ),
                      );
                    }
                  },
                  child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5EAE6)),
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
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.home_rounded, color: Color(0xFF15803D), size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              addr['line1'] ?? '',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF17211B)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${addr['city'] ?? ''}, ${addr['state'] ?? ''}",
                        style: const TextStyle(fontSize: 13, color: Color(0xFF6B756D)),
                      ),
                      Text(
                        "Pincode: ${addr['pincode'] ?? ''}",
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6B756D)),
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1, color: Color(0xFFE5EAE6)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF15803D)),
                            label: const Text("Edit", style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w700)),
                            onPressed: () async {
                              final updated = await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => EditAddressPage(address: addr)),
                              );
                              if (updated == true) {
                                _fetchAddresses();
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                            label: const Text("Delete", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
                            onPressed: () => _showDeleteConfirm(addr['add_id']),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF22C55E),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Address', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        onPressed: () async {
          final added = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EditAddressPage(address: {})),
          );
          if (added == true) {
            _fetchAddresses();
          }
        },
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
  final c1 = TextEditingController(), c2 = TextEditingController(),
      c3 = TextEditingController(), c4 = TextEditingController(),
      c5 = TextEditingController(), c6 = TextEditingController(), c7 = TextEditingController();

  bool get isEdit => widget.address['add_id'] != null;

  @override
  void initState() {
    super.initState();
    c1.text = widget.address['line1'] ?? '';
    c2.text = widget.address['line2'] ?? '';
    c3.text = widget.address['city'] ?? '';
    c4.text = widget.address['district'] ?? '';
    c5.text = widget.address['state'] ?? '';
    c6.text = widget.address['country'] ?? '';
    c7.text = widget.address['pincode'] ?? '';
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null) return;

    final body = {
      'user_id': userId,
      'line1': c1.text,
      'line2': c2.text,
      'city': c3.text,
      'district': c4.text,
      'state': c5.text,
      'country': c6.text,
      'pincode': c7.text,
    };
    if (isEdit) body['add_id'] = widget.address['add_id'];

    final url = isEdit
        ? Uri.parse('http://192.168.29.196:5000/api/address/update')
        : Uri.parse('http://192.168.29.196:5000/api/address/add');

    final res = await (isEdit
        ? http.put(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        : http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)));

    if (res.statusCode == 200) {
      final shortA = c3.text.trim().isNotEmpty ? c3.text.trim() : c1.text.trim();
      final fullA = "${c1.text.trim()}, ${c2.text.trim()}, ${c3.text.trim()}, ${c5.text.trim()} - ${c7.text.trim()}";
      await prefs.setString('customer_address_short', shortA);
      await prefs.setString('customer_address_full', fullA);
      if (mounted) Navigator.pop(context, true);
    } else {
      debugPrint('Failed: ${res.body}');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Address' : 'Add Address', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF17211B))),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF17211B)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field("Line 1 (House/Flat, Street)", c1), const SizedBox(height: 12),
          _field("Line 2 (Landmark, Area)", c2), const SizedBox(height: 12),
          _field("City", c3), const SizedBox(height: 12),
          _field("District", c4), const SizedBox(height: 12),
          _field("State", c5), const SizedBox(height: 12),
          _field("Country", c6), const SizedBox(height: 12),
          _field("Pincode", c7, isNumber: true), const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              isEdit ? 'Update Address' : 'Save Address',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String hint, TextEditingController c, {bool isNumber = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5EAE6)),
      ),
      child: TextField(
        controller: c,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

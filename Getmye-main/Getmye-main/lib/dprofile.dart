import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_application_1/homed.dart';
import 'api_config.dart';
import 'widgets/delivery_bottom_nav_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'dlogin.dart';

// ignore: camel_case_types
class dEditProfilePage extends StatefulWidget {
  const dEditProfilePage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _dEditProfilePageState createState() => _dEditProfilePageState();
}

// ignore: camel_case_types
class _dEditProfilePageState extends State<dEditProfilePage> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController addressController = TextEditingController();

  String? _profileImagePath;
  String? _profileBase64;
  String bankAccount = "";
  String bankName = "";
  String bankIFSC = "";
  String bankBranch = "";

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    addressController.dispose();
    super.dispose();
  }

  /// Load persisted profile details from SharedPreferences & backend
  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      nameController.text = prefs.getString('d_name') ?? '';
      phoneController.text = prefs.getString('d_phone') ?? '';
      emailController.text = prefs.getString('d_email') ?? '';
      addressController.text = prefs.getString('d_address') ?? '';
      _profileImagePath = prefs.getString('d_profile_image');
      _profileBase64 = prefs.getString('d_profile_picture_base64');

      bankAccount = prefs.getString('d_bank_account') ?? '';
      bankName = prefs.getString('d_bank_name') ?? '';
      bankIFSC = prefs.getString('d_bank_ifsc') ?? '';
      bankBranch = prefs.getString('d_bank_branch') ?? '';
    });

    final dId = prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? phoneController.text.trim();
    if (dId.isNotEmpty && (_profileImagePath == null || !File(_profileImagePath!).existsSync())) {
      try {
        final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/deliveryperson/$dId'));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final b64 = data['profile_picture']?.toString();
          if (b64 != null && b64.isNotEmpty && mounted) {
            await prefs.setString('d_profile_picture_base64', b64);
            setState(() {
              _profileBase64 = b64;
            });
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _syncProfileToBackend(String? base64Img) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pId = prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? '';
      final phone = phoneController.text.trim().isNotEmpty ? phoneController.text.trim() : (prefs.getString('d_phone') ?? '');
      await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/deliveryperson/update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'dp_id': pId,
          'mobile_number': phone,
          'name': nameController.text.trim(),
          'email': emailController.text.trim(),
          'address': addressController.text.trim(),
          if (base64Img != null) 'profile_picture_base64': base64Img,
        }),
      );
    } catch (_) {}
  }

  /// Save profile details to SharedPreferences and sync to backend
  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('d_name', nameController.text.trim());
    await prefs.setString('d_phone', phoneController.text.trim());
    await prefs.setString('d_email', emailController.text.trim());
    await prefs.setString('d_address', addressController.text.trim());

    await prefs.setString('d_bank_account', bankAccount);
    await prefs.setString('d_bank_name', bankName);
    await prefs.setString('d_bank_ifsc', bankIFSC);
    await prefs.setString('d_bank_branch', bankBranch);

    String? b64 = _profileBase64;
    if (_profileImagePath != null && File(_profileImagePath!).existsSync()) {
      try {
        final bytes = await File(_profileImagePath!).readAsBytes();
        b64 = base64Encode(bytes);
        await prefs.setString('d_profile_picture_base64', b64);
      } catch (_) {}
    }
    _syncProfileToBackend(b64);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text("Profile updated successfully!"),
            ],
          ),
          backgroundColor: AppColors.primaryDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _showBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Update Profile Photo",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                title: const Text("Open Camera"),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final picker = ImagePicker();
                    final photo = await picker.pickImage(source: ImageSource.camera);
                    if (photo != null) {
                      final bytes = await photo.readAsBytes();
                      final b64 = base64Encode(bytes);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('d_profile_image', photo.path);
                      await prefs.setString('d_profile_picture_base64', b64);
                      setState(() {
                        _profileImagePath = photo.path;
                        _profileBase64 = b64;
                      });
                      _syncProfileToBackend(b64);
                    }
                  } catch (e) {
                    debugPrint("Camera error: $e");
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                title: const Text("Open Gallery"),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final picker = ImagePicker();
                    final photo = await picker.pickImage(source: ImageSource.gallery);
                    if (photo != null) {
                      final bytes = await photo.readAsBytes();
                      final b64 = base64Encode(bytes);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('d_profile_image', photo.path);
                      await prefs.setString('d_profile_picture_base64', b64);
                      setState(() {
                        _profileImagePath = photo.path;
                        _profileBase64 = b64;
                      });
                      _syncProfileToBackend(b64);
                    }
                  } catch (e) {
                    debugPrint("Gallery error: $e");
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBankDetailsPopup() {
    TextEditingController accountController = TextEditingController(text: bankAccount);
    TextEditingController ifscController = TextEditingController(text: bankIFSC);
    TextEditingController bankNameController = TextEditingController(text: bankName);
    TextEditingController branchController = TextEditingController(text: bankBranch);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Edit Bank Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: accountController,
                  decoration: const InputDecoration(
                    labelText: "Bank Account Number",
                    hintText: "Enter account number",
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ifscController,
                  decoration: const InputDecoration(
                    labelText: "Bank IFSC Code",
                    hintText: "e.g. SBIN0001234",
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bankNameController,
                  decoration: const InputDecoration(
                    labelText: "Bank Name",
                    hintText: "e.g. State Bank of India",
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: branchController,
                  decoration: const InputDecoration(
                    labelText: "Bank Branch",
                    hintText: "e.g. Main Branch, City Center",
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("Save"),
              onPressed: () {
                setState(() {
                  bankAccount = accountController.text.trim();
                  bankIFSC = ifscController.text.trim();
                  bankName = bankNameController.text.trim();
                  bankBranch = branchController.text.trim();
                });
                _saveProfile();
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _handleBackNavigation() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
        (route) => false,
      );
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: AppColors.danger, size: 22),
              SizedBox(width: 8),
              Text('Partner Sign Out', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            ],
          ),
          content: const Text('Are you sure you want to sign out from your Delivery Partner console?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('is_logged_in', false);
                await prefs.remove('account_type');
                await prefs.remove('d_id');
                await prefs.remove('active_order_partner_id');
                await prefs.remove('d_name');
                await prefs.remove('d_phone');
                await prefs.remove('d_email');
                await prefs.remove('d_address');
                await prefs.setBool('d_is_online', false);
                await prefs.remove('d_profile_image');
                await prefs.remove('d_profile_picture_base64');
                await prefs.remove('active_order_id');
                await prefs.remove('active_order_customer_name');
                await prefs.remove('active_order_partner_name');

                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const DeliveryPersonLoginPage()),
                  (route) => false,
                );
              },
              child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
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
          title: const Text(
            "Delivery Profile",
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 22),
              tooltip: "Logout",
              onPressed: _showLogoutDialog,
            ),
          ],
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              GestureDetector(
                onTap: _showBottomSheet,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: AppColors.primaryLight,
                        backgroundImage: (_profileImagePath != null && File(_profileImagePath!).existsSync())
                            ? FileImage(File(_profileImagePath!)) as ImageProvider
                            : (_profileBase64 != null && _profileBase64!.isNotEmpty)
                                ? MemoryImage(base64Decode(_profileBase64!)) as ImageProvider
                                : const AssetImage('assets/delivery_boy_toon.png') as ImageProvider,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(right: 4, bottom: 4),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                        onPressed: _showBottomSheet,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Tap photo to change",
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 20),

            // Input Fields with Placeholders
            _buildTextField("Name", "Enter your full name (e.g. Karthi)", nameController, Icons.person_outline_rounded),
            _buildTextField("Phone Number", "Enter your mobile number (e.g. 9876543210)", phoneController, Icons.phone_outlined),
            _buildTextField("Email", "Enter your email (e.g. karthi@email.com)", emailController, Icons.email_outlined),
            _buildTextField("Address", "Enter your full address", addressController, Icons.location_on_outlined),

            const SizedBox(height: 10),

            // Bank Details Tile
            GestureDetector(
              onTap: _showBankDetailsPopup,
              child: Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Bank Details",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (bankAccount.isNotEmpty)
                              Text(
                                "$bankName • $bankAccount",
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              )
                            else
                              const Text(
                                "Tap to add bank account",
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Save Changes Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 1,
                ),
                onPressed: _saveProfile,
                child: const Text(
                  "Save Changes",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Logout Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  backgroundColor: const Color(0xFFFEF2F2),
                ),
                icon: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 20),
                label: const Text(
                  "Logout from Partner Console",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.danger),
                ),
                onPressed: _showLogoutDialog,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
      bottomNavigationBar: const DeliveryBottomNavBar(currentIndex: 0),
      ),
    );
  }

  Widget _buildTextField(String label, String placeholder, TextEditingController controller, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: placeholder,
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.normal),
          prefixIcon: Icon(icon, color: AppColors.primaryDark, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }
}

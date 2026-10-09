import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_application_1/homed.dart';
import 'widgets/delivery_bottom_nav_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';

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

  /// Load persisted profile details from SharedPreferences
  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      nameController.text = prefs.getString('d_name') ?? '';
      phoneController.text = prefs.getString('d_phone') ?? '';
      emailController.text = prefs.getString('d_email') ?? '';
      addressController.text = prefs.getString('d_address') ?? '';
      _profileImagePath = prefs.getString('d_profile_image');

      bankAccount = prefs.getString('d_bank_account') ?? '';
      bankName = prefs.getString('d_bank_name') ?? '';
      bankIFSC = prefs.getString('d_bank_ifsc') ?? '';
      bankBranch = prefs.getString('d_bank_branch') ?? '';
    });
  }

  /// Save profile details to SharedPreferences
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
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('d_profile_image', photo.path);
                      setState(() {
                        _profileImagePath = photo.path;
                      });
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
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('d_profile_image', photo.path);
                      setState(() {
                        _profileImagePath = photo.path;
                      });
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
          (route) => false,
        );
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
                (route) => false,
              );
            },
          ),
          title: const Text(
            "Delivery Profile",
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
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
                            : const NetworkImage(
                                "https://m.media-amazon.com/images/I/41p+wBs+RmL.AC_UY1100.jpg",
                              ),
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

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'address.dart';
import 'api_config.dart';
import 'editp.dart';
import 'history.dart';
import 'main.dart';
import 'widgets/customer_bottom_nav_bar.dart';
import 'theme/app_theme.dart';
import 'ppp.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String name = 'Customer';
  String mobileNumber = '';
  String? profilePictureUrl;
  String? _profileImagePath;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final mobile = prefs.getString('mobile_number') ?? '';
    final storedName = prefs.getString('user_name');
    final localImgPath = prefs.getString('profile_image_path');
    final storedPic = prefs.getString('profile_picture_url');

    if (mounted) {
      setState(() {
        if (storedName != null && storedName.isNotEmpty) name = storedName;
        mobileNumber = mobile;
        if (localImgPath != null && localImgPath.isNotEmpty && File(localImgPath).existsSync()) {
          _profileImagePath = localImgPath;
        }
        if (storedPic != null && storedPic.isNotEmpty) profilePictureUrl = storedPic;
      });
    }

    if (mobile.isEmpty) return;

    try {
      setState(() => _isLoading = true);
      final response = await http.get(
        ApiConfig.profileByMobile(mobile),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            if (data['name'] != null && data['name'].toString().isNotEmpty) {
              name = data['name'];
            }
            if (data['mobile_number'] != null && data['mobile_number'].toString().isNotEmpty) {
              mobileNumber = data['mobile_number'];
            }
            if (data['profile_picture'] != null && data['profile_picture'].toString().isNotEmpty) {
              profilePictureUrl = data['profile_picture'];
            }
          });

          await prefs.setString('user_name', name);
          if (profilePictureUrl != null) {
            await prefs.setString('profile_picture_url', profilePictureUrl!);
          }
        }
      }
    } catch (e) {
      debugPrint('Profile API notice: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickProfileImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_image_path', picked.path);
        if (mounted) {
          setState(() {
            _profileImagePath = picked.path;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile picture updated successfully!'),
              backgroundColor: AppColors.primary,
              duration: Duration(seconds: 2),
            ),
          );
        }

        // Sync to backend if mobile number is available
        if (mobileNumber.isNotEmpty) {
          try {
            var request = http.MultipartRequest('PUT', ApiConfig.profileUpdate);
            request.fields['mobile_number'] = mobileNumber;
            request.files.add(await http.MultipartFile.fromPath('profile_picture', picked.path));
            await request.send().timeout(const Duration(seconds: 8));
          } catch (e) {
            debugPrint("Backend avatar upload note: $e");
          }
        }
      }
    } catch (e) {
      debugPrint("Error picking profile image: $e");
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Wrap(
            children: [
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEFF6FF),
                  child: Icon(Icons.camera_alt_rounded, color: Color(0xFF2563EB)),
                ),
                title: const Text('Take Photo with Camera', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _pickProfileImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF0FDF4),
                  child: Icon(Icons.photo_library_rounded, color: Color(0xFF16A34A)),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _pickProfileImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  ImageProvider? _getAvatarProvider() {
    if (_profileImagePath != null && _profileImagePath!.isNotEmpty) {
      final f = File(_profileImagePath!);
      if (f.existsSync()) return FileImage(f);
    }
    if (profilePictureUrl != null && profilePictureUrl!.isNotEmpty) {
      final val = profilePictureUrl!.trim();
      if (val.startsWith('/') || val.startsWith('C:') || val.contains('\\')) {
        final f = File(val);
        if (f.existsSync()) return FileImage(f);
      }
      if (val.startsWith('data:image')) {
        try {
          final comma = val.indexOf(',');
          if (comma != -1) {
            return MemoryImage(base64Decode(val.substring(comma + 1).trim()));
          }
        } catch (_) {}
      }
      if (!val.startsWith('http://') && !val.startsWith('https://')) {
        try {
          final bytes = base64Decode(val);
          if (bytes.isNotEmpty) return MemoryImage(bytes);
        } catch (_) {}
      }
      if (val.startsWith('http://') || val.startsWith('https://')) {
        return NetworkImage(val);
      }
    }
    return null;
  }

  void _handleBackNavigation() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
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
    final avatarProvider = _getAvatarProvider();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
            onPressed: _handleBackNavigation,
          ),
          centerTitle: true,
          title: const Text('My Profile', style: AppTypography.screenHeading),
        ),
      body: Column(
        children: [
          if (_isLoading)
            const LinearProgressIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.primaryLight,
              minHeight: 2,
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Header Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppColors.subtleShadow,
                    ),
                    child: Row(
                      children: [
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            GestureDetector(
                              onTap: _showImagePickerOptions,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.primary, width: 2),
                                ),
                                child: CircleAvatar(
                                  radius: 34,
                                  backgroundColor: AppColors.primaryLight,
                                  backgroundImage: avatarProvider,
                                  child: avatarProvider == null
                                      ? Text(
                                          name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                          style: const TextStyle(
                                            fontSize: 26,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primaryDark,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _showImagePickerOptions,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: AppTypography.cardTitle.copyWith(fontSize: 18),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                mobileNumber.isNotEmpty ? '+91 $mobileNumber' : 'Mobile unlinked',
                                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'ACTIVE MEMBER',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryDark,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Actions List
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppColors.subtleShadow,
                    ),
                    child: Column(
                      children: [
                        _buildMenuTile(
                          icon: Icons.edit_outlined,
                          title: 'Edit Profile',
                          subtitle: 'Update your personal details',
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const EditProfilePage()),
                            );
                            _loadProfileData();
                          },
                        ),
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.location_on_outlined,
                          title: 'My Address',
                          subtitle: 'Manage delivery addresses',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AddressScreen()),
                          ),
                        ),
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.history_rounded,
                          title: 'Order History',
                          subtitle: 'View previous orders & receipts',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => OrderHistoryPage(order: const {})),
                          ),
                        ),
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.logout_rounded,
                          title: 'Logout',
                          subtitle: 'Sign out from this account',
                          isDanger: true,
                          onTap: () => _showLogoutDialog(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const CustomerBottomNavBar(currentIndex: 1),
    ),
  );
}

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: isDanger ? const Color(0xFFFEE2E2) : AppColors.primaryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: isDanger ? AppColors.danger : AppColors.primaryDark,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isDanger ? AppColors.danger : AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final nav = Navigator.of(context);
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        final dialogNav = Navigator.of(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Sign Out', style: AppTypography.cardTitle),
          content: const Text('Are you sure you want to sign out from your Getmye account?'),
          actions: [
            TextButton(
              onPressed: () => dialogNav.pop(),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('is_logged_in', false);
                await prefs.remove('account_type');
                await prefs.remove('user_id');
                await prefs.remove('user_name');
                await prefs.remove('user_email');
                await prefs.remove('mobile_number');
                await prefs.remove('active_order_id');
                await prefs.remove('has_active_order');
                await prefs.remove('active_order_partner_name');
                await prefs.remove('active_order_customer_name');
                if (!mounted) return;
                dialogNav.pop();
                nav.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              },
              child: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}

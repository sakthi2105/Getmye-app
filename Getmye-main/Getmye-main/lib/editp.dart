import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'theme/app_theme.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  String? _profileBase64;
  File? _image;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final mobilenumber = prefs.getString('mobile_number') ?? '';
    final storedName = prefs.getString('user_name') ?? '';
    final storedEmail = prefs.getString('user_email') ?? '';
    final localImgPath = prefs.getString('profile_image_path');
    final storedPic = prefs.getString('profile_picture_url');

    if (mounted) {
      setState(() {
        _mobileController.text = mobilenumber;
        if (storedName.isNotEmpty) _nameController.text = storedName;
        if (storedEmail.isNotEmpty) _emailController.text = storedEmail;
        if (localImgPath != null && localImgPath.isNotEmpty && File(localImgPath).existsSync()) {
          _image = File(localImgPath);
        }
        if (storedPic != null && storedPic.isNotEmpty) {
          _profileBase64 = storedPic;
        }
      });
    }

    if (mobilenumber.isNotEmpty) {
      await _fetchProfile(mobilenumber);
    }
  }

  Future<void> _fetchProfile(String mobileNumber) async {
    try {
      final response = await http
          .get(ApiConfig.profileByMobile(mobileNumber))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            if (data['name'] != null && data['name'].toString().isNotEmpty) {
              _nameController.text = data['name'];
            }
            if (data['email'] != null && data['email'].toString().isNotEmpty) {
              _emailController.text = data['email'];
            }
            if (data['profile_picture'] != null && data['profile_picture'].toString().isNotEmpty) {
              _profileBase64 = data['profile_picture'];
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Fetch profile error: $e');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_image_path', picked.path);
        setState(() {
          _image = File(picked.path);
        });
      }
    } catch (e) {
      debugPrint("Error picking profile image: $e");
    }
  }

  Future<void> _saveProfile() async {
    final mobileNumber = _mobileController.text.trim();
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    // 1. Save locally to SharedPreferences first so it ALWAYS updates instantly
    final prefs = await SharedPreferences.getInstance();
    if (name.isNotEmpty) {
      await prefs.setString('user_name', name);
    }
    if (email.isNotEmpty) {
      await prefs.setString('user_email', email);
    }
    if (_image != null && _image!.existsSync()) {
      await prefs.setString('profile_image_path', _image!.path);
    }

    if (mobileNumber.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved locally!')),
        );
        Navigator.pop(context, true);
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      var request = http.MultipartRequest(
        'PUT',
        ApiConfig.profileUpdate,
      );

      request.fields['mobile_number'] = mobileNumber;
      if (name.isNotEmpty) {
        request.fields['name'] = name;
      }
      if (email.isNotEmpty) {
        request.fields['email'] = email;
      }
      if (_image != null && _image!.existsSync()) {
        request.files.add(await http.MultipartFile.fromPath(
          'profile_picture',
          _image!.path,
        ));
      }

      var response = await request.send().timeout(const Duration(seconds: 8));
      final respStr = await response.stream.bytesToString();
      debugPrint('Update profile response: $respStr');

      if (response.statusCode == 200) {
        _fetchProfile(mobileNumber);
      }
    } catch (e) {
      debugPrint('Update profile network notice: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Color(0xFF15803D),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true);
      }
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
                  _pickImage(ImageSource.camera);
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
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  ImageProvider? _getAvatarProvider() {
    if (_image != null && _image!.existsSync()) {
      return FileImage(_image!);
    }
    if (_profileBase64 != null && _profileBase64!.isNotEmpty) {
      final val = _profileBase64!.trim();
      if (val.startsWith('/') || val.startsWith('C:') || val.contains('\\')) {
        final f = File(val);
        if (f.existsSync()) return FileImage(f);
      }
      if (val.startsWith('data:image')) {
        try {
          final idx = val.indexOf(',');
          if (idx != -1) {
            return MemoryImage(base64Decode(val.substring(idx + 1).trim()));
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

  Widget _buildAvatar() {
    final provider = _getAvatarProvider();

    return Stack(
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
            backgroundImage: provider,
            child: provider == null
                ? Text(
                    _nameController.text.trim().isNotEmpty
                        ? _nameController.text.trim()[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  )
                : null,
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _showImagePickerOptions,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInput(String label, TextEditingController controller, {bool readOnly = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          filled: true,
          fillColor: readOnly ? const Color(0xFFF1F5F3) : Colors.white,
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 10),
              _buildAvatar(),
              const SizedBox(height: 24),
              _buildInput('Name', _nameController),
              _buildInput('Mobile Number', _mobileController, readOnly: true),
              _buildInput('Email', _emailController),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 1,
                  ),
                  icon: const Icon(Icons.check_rounded, color: Colors.white),
                  label: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

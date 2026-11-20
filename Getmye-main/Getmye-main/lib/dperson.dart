import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/homed.dart';
import 'api_config.dart';
import 'theme/app_theme.dart';
import 'ppp.dart';

class DeliveryPersonDetailsPage extends StatefulWidget {
  const DeliveryPersonDetailsPage({super.key});

  @override
  State<DeliveryPersonDetailsPage> createState() =>
      _DeliveryPersonDetailsPageState();
}

class _DeliveryPersonDetailsPageState
    extends State<DeliveryPersonDetailsPage> {
  final _formKey = GlobalKey<FormState>();

  // Text controllers
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final emailController = TextEditingController();
  final addressController = TextEditingController();
  final aadhaarController = TextEditingController();
  final pancardController = TextEditingController();
  final bankAccountController = TextEditingController();
  final bankNameController = TextEditingController();
  final branchController = TextEditingController();
  final ifscController = TextEditingController();
  final micrController = TextEditingController();

  // Images
  File? aadhaarImage;
  File? personImage;
  File? pancardImage;

  final ImagePicker _picker = ImagePicker();
  bool _isSubmitting = false;
  String _selectedTimeSlot = "10:00 AM";

  Future<void> _pickImage(String type) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        if (type == 'aadhaar') aadhaarImage = File(image.path);
        else if (type == 'person') personImage = File(image.path);
        else if (type == 'pancard') pancardImage = File(image.path);
      });
    }
  }

  bool isFormValid() {
    return nameController.text.isNotEmpty &&
        phoneController.text.length == 10 &&
        emailController.text.isNotEmpty &&
        addressController.text.isNotEmpty &&
        aadhaarController.text.length == 12 &&
        pancardController.text.length == 10 &&
        bankAccountController.text.isNotEmpty &&
        bankNameController.text.isNotEmpty &&
        branchController.text.isNotEmpty &&
        ifscController.text.isNotEmpty &&
        micrController.text.isNotEmpty &&
        aadhaarImage != null &&
        personImage != null &&
        pancardImage != null;
  }

  Future<bool> _submitToBackend() async {
    setState(() => _isSubmitting = true);
    var uri = ApiConfig.partnerAdd;
    var request = http.MultipartRequest('POST', uri);

    // Add text fields
    request.fields['mobile_number'] = phoneController.text.trim();
    request.fields['password'] = passwordController.text.trim().isNotEmpty ? passwordController.text.trim() : '123456';
    request.fields['name'] = nameController.text.trim();
    request.fields['email'] = emailController.text.trim();
    request.fields['address'] = addressController.text.trim();
    request.fields['aadhar_number'] = aadhaarController.text.trim();
    request.fields['pancard_number'] = pancardController.text.trim();
    request.fields['know_your_partner_status'] = 'completed';
    request.fields['dp_status'] = 'online';
    request.fields['bank_name'] = bankNameController.text.trim();
    request.fields['branch_name'] = branchController.text.trim();
    request.fields['bank_account_number'] = bankAccountController.text.trim();
    request.fields['ifsc_code'] = ifscController.text.trim();
    request.fields['micr_code'] = micrController.text.trim();
    request.fields['linked_number'] = phoneController.text.trim();
    request.fields['verification_time_slot'] = _selectedTimeSlot;

    // Add files
    if (personImage != null) {
      request.files.add(await http.MultipartFile.fromPath('personImage', personImage!.path));
    }
    if (aadhaarImage != null) {
      request.files.add(await http.MultipartFile.fromPath('aadhaarImage', aadhaarImage!.path));
    }
    if (pancardImage != null) {
      request.files.add(await http.MultipartFile.fromPath('pancardImage', pancardImage!.path));
    }

    try {
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        // Clear all old stale cache completely for fresh partner session
        await prefs.clear();

        String dpId = 'DP001';
        try {
          final data = jsonDecode(response.body);
          if (data['dp_id'] != null) dpId = data['dp_id'].toString();
        } catch (_) {}

        await prefs.setString('d_id', dpId);
        await prefs.setString('active_order_partner_id', dpId);
        await prefs.setString('d_name', nameController.text.trim());
        await prefs.setString('d_phone', phoneController.text.trim());
        await prefs.setString('d_email', emailController.text.trim());
        await prefs.setString('d_address', addressController.text.trim());
        await prefs.setString('d_bank_name', bankNameController.text.trim());
        await prefs.setString('d_bank_account', bankAccountController.text.trim());
        await prefs.setString('d_bank_ifsc', ifscController.text.trim());
        await prefs.setString('d_bank_branch', branchController.text.trim());
        await prefs.setBool('d_is_online', true);
        await prefs.setBool('is_logged_in', true);
        await prefs.setString('account_type', 'partner');
        if (personImage != null) {
          await prefs.setString('d_profile_image', personImage!.path);
        }

        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registration successful! Registered delivery person details saved.'),
              backgroundColor: AppColors.primaryDark,
            ),
          );
        }
        return true;
      } else {
        String errMsg = 'Upload failed: ${response.statusCode}';
        try {
          final data = jsonDecode(response.body);
          if (data['message'] != null) errMsg = data['message'];
          if (data['error'] != null) errMsg = data['error'];
        } catch (_) {}
        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errMsg), backgroundColor: AppColors.danger),
          );
        }
        return false;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
      return false;
    }
  }

  Widget _buildEditableField(String label, TextEditingController controller,
      {int? maxLength, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SizedBox(height: 5),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType ?? TextInputType.text,
            maxLength: maxLength,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              counterText: "", // hide default counter
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker(String title, File? imageFile, String type) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SizedBox(height: 10),
          GestureDetector(
            onTap: () => _pickImage(type),
            child: Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: imageFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(imageFile, fit: BoxFit.cover),
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt, size: 50, color: Colors.grey),
                          SizedBox(height: 10),
                          Text("Tap to upload", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
            ),
          ),
          Divider(),
        ],
      ),
    );
  }

  void _showConfirmationDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Confirm Details", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Please select a time slot and read instructions before confirming.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: _selectedTimeSlot,
                decoration: InputDecoration(
                  labelText: "Select a Time Slot",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: const [
                  DropdownMenuItem(value: "10:00 AM", child: Text("10:00 AM")),
                  DropdownMenuItem(value: "12:00 PM", child: Text("12:00 PM")),
                  DropdownMenuItem(value: "3:00 PM", child: Text("3:00 PM")),
                  DropdownMenuItem(value: "6:00 PM", child: Text("6:00 PM")),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => _selectedTimeSlot = val);
                    setState(() => _selectedTimeSlot = val);
                  }
                },
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  "Instructions:\n1. Ensure all details are correct.\n2. Carry Aadhaar & PAN card.\n3. Arrive on time for verification.",
                  style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(dialogCtx),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("Submit"),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final success = await _submitToBackend();
                if (success && mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Form(
          key: _formKey,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.white,
                pinned: true,
                floating: true,
                elevation: 0,
                iconTheme: const IconThemeData(color: AppColors.textPrimary),
                title: const Text(
                  "Delivery Partner Details",
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _handleBackNavigation,
                ),
              ),
            SliverList(
              delegate: SliverChildListDelegate([
                _buildEditableField("Name", nameController),
                _buildEditableField("Phone Number", phoneController, maxLength: 10, keyboardType: TextInputType.phone),
                _buildEditableField("Set Password", passwordController),
                _buildEditableField("Email", emailController, keyboardType: TextInputType.emailAddress),
                _buildEditableField("Address", addressController),
                _buildEditableField("Aadhaar Number", aadhaarController, maxLength: 12, keyboardType: TextInputType.number),
                _buildEditableField("PAN Card Number", pancardController, maxLength: 10, keyboardType: TextInputType.text),
                _buildImagePicker("Aadhaar Photo", aadhaarImage, 'aadhaar'),
                _buildImagePicker("PAN Card Photo", pancardImage, 'pancard'),
                _buildImagePicker("Person Photo", personImage, 'person'),
                const Divider(thickness: 1),
              ]),
            ),
            SliverAppBar(
              backgroundColor: AppColors.primaryLight,
              pinned: true,
              automaticallyImplyLeading: false,
              title: const Text(
                "Bank Details",
                style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            SliverList(
              delegate: SliverChildListDelegate([
                _buildEditableField("Bank Account Number", bankAccountController),
                _buildEditableField("Bank Name", bankNameController),
                _buildEditableField("Branch", branchController),
                _buildEditableField("IFSC Code", ifscController),
                _buildEditableField("MICR Code", micrController),
              ]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isFormValid() && !_isSubmitting ? AppColors.primary : Colors.grey.shade300,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: isFormValid() && !_isSubmitting ? _showConfirmationDialog : null,
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    "Confirm",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
          ),
        ),
      ),
    ),
  );
}
}

import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

class AdminDashboardPage extends StatelessWidget {
  // Example static list of delivery persons (replace with API data)
  final List<Map<String, String>> deliveryPersons = [
    {
      'name': 'Ravi Kumar',
      'mobile': '9876543210',
      'email': 'ravi@example.com',
      'aadhaar': '1234-5678-9012',
      'aadhaarPic': 'https://via.placeholder.com/100', // replace with real URL
      'pan': 'ABCDE1234F',
      'panPic': 'https://via.placeholder.com/100',
    },
    {
      'name': 'Sita Sharma',
      'mobile': '8765432109',
      'email': 'sita@example.com',
      'aadhaar': '2345-6789-0123',
      'aadhaarPic': 'https://via.placeholder.com/100',
      'pan': 'FGHIJ5678K',
      'panPic': 'https://via.placeholder.com/100',
    },
    // Add more...
  ];

  AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin Dashboard', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: deliveryPersons.map((person) {
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person['name'] ?? '',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildInfoItem('Mobile', person['mobile']!)),
                        Expanded(child: _buildInfoItem('Email', person['email']!)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoItem('Aadhaar No.', person['aadhaar']!),
                        ),
                        Image.network(
                          person['aadhaarPic']!,
                          cacheWidth: 300,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoItem('PAN No.', person['pan']!),
                        ),
                        Image.network(
                          person['panPic']!,
                          cacheWidth: 300,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          _startVideoCall(context, person['name']!);
                        },
                        icon: const Icon(Icons.video_call),
                        label: const Text('Video Call'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildInfoItem(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$title: $value',
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  void _startVideoCall(BuildContext context, String personName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Start Video Call'),
        content: Text('Starting video call with $personName...'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

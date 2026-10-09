import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Delivery Page',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const DeliveryPage(),
    );
  }
}

class DeliveryPage extends StatefulWidget {
  const DeliveryPage({super.key});

  @override
  State<DeliveryPage> createState() => _DeliveryPageState();
}

class _DeliveryPageState extends State<DeliveryPage> {
  void _showCancelReasonDialog() {
    TextEditingController reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Cancel Order"),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: "Enter reason",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Reason submitted: ${reasonController.text}"),
                  backgroundColor: AppColors.primaryDark,
                ),
              );
            },
            child: const Text("Submit"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: Text("Delivery Details", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            centerTitle: true,
            pinned: true,
            iconTheme: IconThemeData(color: AppColors.textPrimary),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Card(
                elevation: 2,
                color: Colors.white,
                margin: const EdgeInsets.all(20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Customer Delivery Details",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 10),
                      const ListTile(
                        title: Text("Item Name"),
                        subtitle: Text("Boat Rockerz 255 Pro+"),
                      ),
                      const ListTile(
                        title: Text("Budget"),
                        subtitle: Text("₹1,499"),
                      ),
                      const ListTile(
                        title: Text("Location"),
                        subtitle: Text("Koramangala, Bangalore"),
                      ),
                      const Divider(),
                      const Text(
                        "Delivery Person",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 10),
                      ListTile(
                        leading: const CircleAvatar(
                          backgroundImage: NetworkImage(
                            'https://randomuser.me/api/portraits/men/45.jpg',
                          ),
                          radius: 26,
                        ),
                        title: const Text("Ravi Kumar", style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("Total Deliveries: 320"),
                            Text("Rating: ⭐ 4.7 (150 reviews)"),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          onPressed: _showCancelReasonDialog,
                          child: const Text("Cancel Order", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

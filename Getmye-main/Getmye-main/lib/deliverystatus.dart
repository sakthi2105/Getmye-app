import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/ondeliver.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_swipe_button/flutter_swipe_button.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker/image_picker.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MaterialApp(home: DeliveryStatusPage(), debugShowCheckedModeBanner: false));
}

class DeliveryStatusPage extends StatefulWidget {
  const DeliveryStatusPage({super.key});

  @override
  _DeliveryStatusPageState createState() => _DeliveryStatusPageState();
}

class _DeliveryStatusPageState extends State<DeliveryStatusPage> {
  bool isOrderAccepted = false;
  bool isSwipeDisabled = false;
  bool isOrderDeclined = false;

  final List<TextEditingController> itemControllers = [TextEditingController(text: "Biriyani")];
  final List<TextEditingController> quantityControllers = [TextEditingController(text: "1")];
  final List<TextEditingController> priceControllers = [TextEditingController(text: "250")];
  final List<TextEditingController> hotelNameControllers = [TextEditingController(text: "Karthi Restaurant")];

  double getTotalAmount() {
    double total = 0.0;
    for (int i = 0; i < priceControllers.length; i++) {
      int quantity = int.tryParse(quantityControllers[i].text) ?? 0;
      double price = double.tryParse(priceControllers[i].text) ?? 0.0;
      total += quantity * price;
    }
    return total;
  }

  void _handleOrderSwipe(bool isAccepted) {
    setState(() {
      isOrderAccepted = isAccepted;
      isSwipeDisabled = true;
      isOrderDeclined = !isAccepted;
    });

    if (!isAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order Declined")));
    }
  }

  void _addNewRow() {
    setState(() {
      itemControllers.add(TextEditingController());
      hotelNameControllers.add(TextEditingController());
      quantityControllers.add(TextEditingController());
      priceControllers.add(TextEditingController());
    });
  }

  void _handleReadyForDelivery() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const OrderStatusPage()));
  }

  void _handleCallButtonTap() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const CallPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Delivery Status", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 10.0), // Move FAB up by 10 pixels
        child: FloatingActionButton(
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.call, color: Colors.white),
          onPressed: _handleCallButtonTap,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (!isOrderDeclined) ...[
              const Text("Order Preference", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ...List.generate(itemControllers.length, (index) {
                String foodName = itemControllers[index].text.trim();
                String budget = priceControllers[index].text.trim();

                if (foodName.isNotEmpty && budget.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(child: Text(foodName, style: const TextStyle(fontSize: 16))),
                        const SizedBox(width: 10),
                        Text("₹$budget", style: const TextStyle(fontSize: 16)),
                      ],
                    ),
                  );
                } else {
                  return const SizedBox.shrink();
                }
              }),
              const SizedBox(height: 20),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.location_on, color: Colors.red),
                  title: Text("123 Main Street, Chennai"),
                  subtitle: Text("Expected delivery in 30 mins"),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (!isSwipeDisabled) ...[
              SwipeButton.expand(
                thumb: const Icon(Icons.delivery_dining, color: Colors.white),
                activeThumbColor: AppColors.primary,
                activeTrackColor: Colors.white,
                borderRadius: BorderRadius.circular(10),
                onSwipe: () => _handleOrderSwipe(true),
                child: const Text("Swipe to Accept"),
              ),
              const SizedBox(height: 20),
              SwipeButton.expand(
                thumb: const Icon(Icons.cancel, color: Colors.black),
                activeThumbColor: Colors.red,
                activeTrackColor: Colors.white,
                borderRadius: BorderRadius.circular(10),
                onSwipe: () => _handleOrderSwipe(false),
                child: const Text("Swipe to Decline"),
              ),
            ],
            if (isOrderAccepted && !isOrderDeclined) ...[
              const SizedBox(height: 20),
              const Text("Input Order Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text("Food Name")),
                    DataColumn(label: Text("Hotel Name")),
                    DataColumn(label: Text("Quantity")),
                    DataColumn(label: Text("Price")),
                  ],
                  rows: List<DataRow>.generate(itemControllers.length, (index) {
                    return DataRow(
                      cells: [
                        DataCell(TextField(controller: itemControllers[index], decoration: const InputDecoration(hintText: "Food Name"))),
                        DataCell(TextField(controller: hotelNameControllers[index], decoration: const InputDecoration(hintText: "Hotel Name"))),
                        DataCell(TextField(
                          controller: quantityControllers[index],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: "Quantity"),
                          onChanged: (_) => setState(() {}),
                        )),
                        DataCell(TextField(
                          controller: priceControllers[index],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: "Price (₹)"),
                          onChanged: (_) => setState(() {}),
                        )),
                      ],
                    );
                  }),
                ),
              ),
              IconButton(icon: const Icon(Icons.add_circle, color: AppColors.primary), onPressed: _addNewRow),
              const SizedBox(height: 20),
              Text("Total Amount: ₹${getTotalAmount().toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              OrderDetailsSection(onReadyToDeliver: _handleReadyForDelivery),
            ],
          ],
        ),
      ),
    );
  }
}

class OrderDetailsSection extends StatefulWidget {
  final VoidCallback onReadyToDeliver;

  const OrderDetailsSection({super.key, required this.onReadyToDeliver});

  @override
  _OrderDetailsSectionState createState() => _OrderDetailsSectionState();
}

class _OrderDetailsSectionState extends State<OrderDetailsSection> {
  bool isDeliveryReadySwiped = false;
  XFile? billImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _takePhoto() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        billImage = image;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text("Scan QR Code to Pay Bill"),
          onPressed: () {
            // Implement QR scanner here
          },
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          icon: const Icon(Icons.camera_alt),
          label: const Text("Upload Food Bill"),
          onPressed: _takePhoto,
        ),
        if (billImage != null)
          Image.file(
            File(billImage!.path),
            width: 200,
            height: 200,
            fit: BoxFit.cover,
          ),
        const SizedBox(height: 20),
        if (!isDeliveryReadySwiped)
          SwipeButton.expand(
            thumb: const Icon(Icons.delivery_dining, color: Colors.white),
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
            onSwipe: () {
              setState(() {
                isDeliveryReadySwiped = true;
              });
              widget.onReadyToDeliver();
            },
            child: const Text("Swipe to Ready for Delivery"),
          ),
      ],
    );
  }
}

// Placeholder call page
class CallPage extends StatelessWidget {
  const CallPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Connecting to Customer", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: const Center(
        child: Text(
          "Calling customer...",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

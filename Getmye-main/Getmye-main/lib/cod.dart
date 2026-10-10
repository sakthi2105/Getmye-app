import 'package:flutter/material.dart';
import 'services/upi_payment_service.dart';
import 'theme/app_theme.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'COD Settlement',
      theme: AppTheme.lightTheme,
      home: CodPage(),
    );
  }
}

class CodPage extends StatefulWidget {
  @override
  _CodPageState createState() => _CodPageState();
}

class _CodPageState extends State<CodPage> {
  final List<Order> orders = [
    Order(
        orderId: 'ORD123',
        foodItem: 'Biryani',
        tips: 20.0,
        deliveryCharge: 30.0,
        foodPrice: 150.0),
    Order(
        orderId: 'ORD124',
        foodItem: 'Dosa',
        tips: 10.0,
        deliveryCharge: 25.0,
        foodPrice: 100.0),
    Order(
        orderId: 'ORD125',
        foodItem: 'Pizza',
        tips: 15.0,
        deliveryCharge: 35.0,
        foodPrice: 200.0),
  ];

  double get totalAmount => orders
      .where((order) => order.isSelected)
      .fold(0.0, (sum, order) => sum + order.foodPrice + order.deliveryCharge);

  void _showPaymentOptions() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Payment Method'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.account_balance_wallet, color: Colors.blue),
                title: const Text('Google Pay (GPay)'),
                subtitle: const Text('To: sivaprakashsivaprakash421@okaxis'),
                onTap: () {
                  Navigator.of(context).pop();
                  UpiPaymentService.openGooglePay(context, amount: totalAmount);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.phone_android_rounded, color: Colors.deepPurple),
                title: const Text('PhonePe UPI'),
                subtitle: const Text('To: sivaprakashsivaprakash421@okaxis'),
                onTap: () {
                  Navigator.of(context).pop();
                  UpiPaymentService.openPhonePe(context, amount: totalAmount);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrderItem(Order order) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order ID: ${order.orderId}',
                    style: const TextStyle(
                        fontSize: 16.0, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Text('Food: ${order.foodItem} - ₹${order.foodPrice}'),
                Text('Tips: ₹${order.tips}'),
                Text('Delivery Charges: ₹${order.deliveryCharge}'),
                const Divider(),
                Text(
                  'Total (Excl. Tips): ₹${(order.foodPrice + order.deliveryCharge).toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                ),
              ],
            ),
          ),
          Checkbox(
            activeColor: AppColors.primary,
            value: order.isSelected,
            onChanged: (bool? value) {
              setState(() {
                order.isSelected = value!;
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('COD Settlement', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: orders.map((order) => _buildOrderItem(order)).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 1,
              ),
              onPressed: totalAmount > 0 ? _showPaymentOptions : null,
              child: Text(
                'Pay ₹${totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Order {
  final String orderId;
  final String foodItem;
  final double tips;
  final double deliveryCharge;
  final double foodPrice;
  bool isSelected;

  Order({
    required this.orderId,
    required this.foodItem,
    required this.tips,
    required this.deliveryCharge,
    required this.foodPrice,
    this.isSelected = false,
  });
}

class PaymentPage extends StatelessWidget {
  final String method;
  final Color color;

  PaymentPage({required this.method, required this.color});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$method Payment'),
        backgroundColor: color,
      ),
      body: Center(
        child: Text(
          'Proceed with $method',
          style: TextStyle(fontSize: 24.0),
        ),
      ),
    );
  }
}

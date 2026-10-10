import 'package:flutter/material.dart';
import 'dart:async';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OrderStatusPage(),
    );
  }
}

class OrderStatusPage extends StatefulWidget {
  const OrderStatusPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _OrderStatusPageState createState() => _OrderStatusPageState();
}

class _OrderStatusPageState extends State<OrderStatusPage> {
  int remainingMeters = 500;
  bool showOtpSection = false;
  bool showGreenOverlay = false;
  bool orderCompleted = false;
  bool otpFilled = false;
  List<TextEditingController> otpControllers =
      List.generate(4, (index) => TextEditingController());

  @override
  void initState() {
    super.initState();
    startAutoDecrement();
  }

  void startAutoDecrement() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingMeters > 0) {
        setState(() {
          remainingMeters -= 50;
        });
      } else {
        timer.cancel();
        Future.delayed(const Duration(seconds: 1), showDeliveryAlert);
      }
    });
  }

  void showDeliveryAlert() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Order Arrived"),
          content:
              const Text("Your order location is here, deliver the order."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  showOtpSection = true;
                });
              },
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  void completeOrder() {
    setState(() {
      showGreenOverlay = true;
    });
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        showGreenOverlay = false;
        orderCompleted = true;
      });
    });
  }

  void handleOtpInput(int index, String value) {
    if (value.isNotEmpty && index < 3) {
      FocusScope.of(context).nextFocus();
    } else if (value.isEmpty && index > 0) {
      FocusScope.of(context).previousFocus();
    }
    checkOtpFilled();
  }

  void checkOtpFilled() {
    bool isFilled =
        otpControllers.every((controller) => controller.text.isNotEmpty);
    setState(() {
      otpFilled = isFilled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          "Order Status",
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 380,
                  child: Image.network(
                    "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTPTm3kVakwk3BN3YVYofc44AgGvlf-SQ_n0uT2FhAjPfYiR3otuamVB7cwNnNwyE9iITI&usqp=CAU",
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.all(16.0),
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        "Remaining Distance: $remainingMeters meters",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!showOtpSection)
                        Center(
                          child: ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12.0, horizontal: 24.0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                            ),
                            child: const Text(
                              "OTP Verification",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (showOtpSection)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.all(16.0),
                    padding: const EdgeInsets.all(20.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10.0,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "Enter Delivery OTP",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (index) {
                            return Container(
                              margin: const EdgeInsets.all(6.0),
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                border: Border.all(color: AppColors.primary, width: 1.5),
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              child: Center(
                                child: TextField(
                                  controller: otpControllers[index],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  maxLength: 1,
                                  onChanged: (value) =>
                                      handleOtpInput(index, value),
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                  decoration: const InputDecoration(
                                    counterText: '',
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: otpFilled ? completeOrder : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  otpFilled ? AppColors.primary : Colors.grey.shade300,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                            ),
                            child: const Text(
                              "Finish Delivery",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ),
          ],
        ),
        if (showGreenOverlay)
            AnimatedOpacity(
              opacity: showGreenOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 500),
              child: Container(
                color: AppColors.primary.withValues(alpha: 0.95),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.white, size: 100),
                      SizedBox(height: 16),
                      Text(
                        "Order delivered",
                        style: TextStyle(
                          fontSize: 24,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

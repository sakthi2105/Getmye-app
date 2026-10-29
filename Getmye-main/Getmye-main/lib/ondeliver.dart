import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'delivery_bill_flow.dart' show clearDeliveryPartnerActiveOrder;
import 'homed.dart';
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
  final String? orderId;
  const OrderStatusPage({super.key, this.orderId});

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

  // 15-Minute Wait Timer & Customer Unavailable Cancellation
  int _cancelTimerSeconds = 15 * 60; // 900 seconds (15 minutes)
  Timer? _fifteenMinuteTimer;
  bool _canCancel = false;
  bool _isCancelling = false;
  String? _currentOrderId;

  @override
  void initState() {
    super.initState();
    _currentOrderId = widget.orderId;
    startAutoDecrement();
  }

  @override
  void dispose() {
    _fifteenMinuteTimer?.cancel();
    for (final c in otpControllers) {
      c.dispose();
    }
    super.dispose();
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
                _initArrivalWaitTimer();
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

  Future<void> _initArrivalWaitTimer() async {
    final prefs = await SharedPreferences.getInstance();
    _currentOrderId = widget.orderId ?? prefs.getString('partner_active_order_id') ?? prefs.getString('active_order_id') ?? '';
    final partnerId = prefs.getString('d_id') ?? prefs.getString('partner_id') ?? '';

    if (_currentOrderId != null && _currentOrderId!.isNotEmpty) {
      try {
        final res = await http.post(
          ApiConfig.orderArrivedAtLocation,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'order_id': _currentOrderId,
            'partner_id': partnerId,
          }),
        ).timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final remaining = (data['seconds_remaining'] as num?)?.toInt() ?? (15 * 60);
          final canCancel = data['can_cancel'] as bool? ?? (remaining <= 0);
          if (mounted) {
            setState(() {
              _cancelTimerSeconds = remaining;
              _canCancel = canCancel;
            });
          }
        }
      } catch (_) {}
    }

    _fifteenMinuteTimer?.cancel();
    _fifteenMinuteTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cancelTimerSeconds > 0) {
        if (mounted) {
          setState(() {
            _cancelTimerSeconds--;
            if (_cancelTimerSeconds <= 0) {
              _canCancel = true;
              timer.cancel();
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _canCancel = true;
          });
        }
        timer.cancel();
      }
    });
  }

  String _formatWaitTimer(int totalSecs) {
    final m = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final s = (totalSecs % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  void _showCancelConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 26),
            SizedBox(width: 8),
            Text("Cancel Order", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          "Customer unavailable. Do you want to cancel this order?",
          style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Go Back", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _executeCancelOrder();
            },
            child: const Text("Confirm Cancellation", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _executeCancelOrder() async {
    setState(() => _isCancelling = true);
    final prefs = await SharedPreferences.getInstance();
    final orderId = _currentOrderId ?? prefs.getString('partner_active_order_id') ?? prefs.getString('active_order_id') ?? '';
    final partnerId = prefs.getString('d_id') ?? prefs.getString('partner_id') ?? '';

    if (orderId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No active order found to cancel.")),
      );
      setState(() => _isCancelling = false);
      return;
    }

    try {
      final res = await http.post(
        ApiConfig.orderCancel,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'order_id': orderId,
          'cancelled_by': 'partner',
          'cancel_reason': 'Customer unavailable',
          'partner_id': partnerId,
        }),
      ).timeout(const Duration(seconds: 8));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        await clearDeliveryPartnerActiveOrder(orderId: orderId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Order cancelled: Customer unavailable. You are now available for new orders."),
            backgroundColor: Color(0xFF15803D),
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
          (route) => false,
        );
      } else {
        final errorMsg = data['error'] ?? "Failed to cancel order";
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Network error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
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
                    cacheWidth: 600,
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
                        const SizedBox(height: 18),
                        const Divider(height: 1, thickness: 1),
                        const SizedBox(height: 14),

                        // 15-minute Customer Wait Timer Banner
                        if (!_canCancel) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.timer_outlined, size: 18, color: Color(0xFFB45309)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Customer wait time: ${_formatWaitTimer(_cancelTimerSeconds)} remaining before cancellation is allowed.",
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],

                        // Cancel Order Button (Dim & disabled for 15 minutes, active red afterwards)
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _canCancel && !_isCancelling ? _showCancelConfirmationDialog : null,
                            icon: _isCancelling
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)))
                                : Icon(
                                    Icons.cancel_outlined,
                                    color: _canCancel ? const Color(0xFFDC2626) : Colors.grey.shade400,
                                    size: 20,
                                  ),
                            label: Text(
                              _canCancel
                                  ? "Cancel Order (Customer Unavailable)"
                                  : "Cancel Order (Available in ${_formatWaitTimer(_cancelTimerSeconds)})",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: _canCancel ? const Color(0xFFDC2626) : Colors.grey.shade400,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _canCancel ? const Color(0xFFDC2626) : Colors.grey.shade400,
                              side: BorderSide(
                                color: _canCancel ? const Color(0xFFDC2626) : Colors.grey.shade300,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: 24.0 + MediaQuery.paddingOf(context).bottom),
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

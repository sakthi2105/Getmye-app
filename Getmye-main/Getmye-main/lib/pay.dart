import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_config.dart';
import 'delivery_bill_flow.dart';
import 'services/order_chat_sheet.dart';
import 'services/route_service.dart';
import 'services/upi_payment_service.dart';
import 'ppp.dart';
import 'theme/app_theme.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  _PaymentPageState createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  bool _isPaymentSuccessShown = false;
  bool hasActiveOrder = false;
  bool isPartnerAccepted = false;
  bool isFoodPurchased = false;
  bool isBillSent = false;
  String orderStatus = 'pending';
  String orderId = "ORD-8492";
  String itemName = "Chicken Rice";
  String customerName = "Customer";
  String customerAddress = "Live Delivery Location";
  String partnerName = "Karthi (Partner)";
  String partnerPhone = "+91 98765 43210";
  String? partnerId;
  String? partnerProfilePicture;
  String? activeOtp;
  String paymentMethod = "Cash on Delivery (COD)";
  bool isOnlinePaid = false;

  List<Map<String, dynamic>> billItems = [];
  double itemTotal = 120.0;
  double deliveryEarnings = 0.0; // Delivery charges removed as requested
  double tipAmount = 0.0;
  String? uploadedBillImageUrl;
  Timer? _pollTimer;
  GoogleMapController? _mapController;

  // Live Tracking coordinates & Road Route
  LatLng _partnerLocation = const LatLng(10.9620, 79.3860);
  LatLng _customerLocation = const LatLng(10.9601, 79.3845);
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;
  bool _isPollingBackend = false;

  Future<void> _fetchRoadRoute() async {
    if (_isLoadingRoute) return;
    _isLoadingRoute = true;
    try {
      final points = await RouteService.getRoadRoute(_partnerLocation, _customerLocation);
      if (mounted && points.isNotEmpty) {
        setState(() {
          _routePoints = points;
        });
      }
    } catch (_) {
    } finally {
      _isLoadingRoute = false;
    }
  }

  void _fitMapBounds() {
    if (_mapController == null) return;
    try {
      final southwest = LatLng(
        min(_partnerLocation.latitude, _customerLocation.latitude),
        min(_partnerLocation.longitude, _customerLocation.longitude),
      );
      final northeast = LatLng(
        max(_partnerLocation.latitude, _customerLocation.latitude),
        max(_partnerLocation.longitude, _customerLocation.longitude),
      );
      final bounds = LatLngBounds(southwest: southwest, northeast: northeast);
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
    } catch (_) {
      _mapController?.animateCamera(CameraUpdate.newLatLng(_partnerLocation));
    }
  }

  double get totalAmount => itemTotal + deliveryEarnings + tipAmount;

  @override
  void initState() {
    super.initState();
    _loadInitialPrefs();
    _pollFromBackend();
    // Poll real backend MongoDB API every 1.5 seconds for real multi-device sync
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _pollFromBackend();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString('active_order_id');
    final activeItem = prefs.getString('active_order_item');
    final pName = prefs.getString('active_order_partner_name') ?? prefs.getString('d_name') ?? "Karthi (Partner)";
    final pPhone = prefs.getString('active_order_partner_phone') ?? prefs.getString('d_phone') ?? "+91 98765 43210";
    String cAddress = prefs.getString('active_order_customer_address') ?? prefs.getString('customer_address_full') ?? "Live Delivery Location";
    final savedOtp = prefs.getString('active_cod_otp');
    final savedMethod = prefs.getString('payment_method');
    final onlinePaid = prefs.getBool('is_online_paid') ?? false;

    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        setState(() {
          _customerLocation = LatLng(pos.latitude, pos.longitude);
        });
      }
    } catch (_) {}

    final savedBillImg = prefs.getString('order_${activeId ?? orderId}_bill_image');
    final savedTip = prefs.getDouble('order_${activeId ?? orderId}_tip') ?? 0.0;

    final activeStatus = prefs.getString('active_order_status');
    final isDone = activeStatus == 'delivered' || activeStatus == 'completed';
    final hasOrder = (prefs.getBool('has_active_order') ?? false) && activeId != null && !isDone;
    final accepted = (prefs.getBool('active_order_partner_accepted') ?? false) && !isDone;

    if (mounted) {
      setState(() {
        hasActiveOrder = hasOrder;
        isPartnerAccepted = accepted;
        if (activeId != null) orderId = activeId;
        if (activeItem != null) itemName = activeItem;
        partnerName = pName;
        final savedPartnerPic = prefs.getString('active_order_partner_pic') ?? prefs.getString('d_profile_picture_base64');
        final savedPartnerId = prefs.getString('active_order_partner_id') ?? prefs.getString('d_id');
        if (savedPartnerPic != null) partnerProfilePicture = savedPartnerPic;
        if (savedPartnerId != null) partnerId = savedPartnerId;
        partnerPhone = pPhone;
        customerAddress = cAddress;
        if (savedOtp != null && savedOtp.isNotEmpty) activeOtp = savedOtp;
        if (savedMethod != null) paymentMethod = savedMethod;
        isOnlinePaid = onlinePaid;
        uploadedBillImageUrl = savedBillImg;
        if (savedTip > 0) tipAmount = savedTip;
      });
      _fetchRoadRoute();
    }
  }

  Future<void> _pollFromBackend() async {
    if (_isPollingBackend) return;
    _isPollingBackend = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentOrderId = prefs.getString('active_order_id');
      final activeStatus = prefs.getString('active_order_status');

      // If there is no active order or order is already delivered, do not poll past order
      if (currentOrderId == null || activeStatus == 'delivered' || activeStatus == 'completed' || !hasActiveOrder) {
        if (mounted && hasActiveOrder) {
          setState(() {
            hasActiveOrder = false;
          });
        }
        return;
      }

      // 1. Fetch Order Status from backend MongoDB
      String? orderBillImg;
      try {
        final orderRes = await http.get(ApiConfig.orderById(currentOrderId)).timeout(const Duration(seconds: 2));
      if (orderRes.statusCode == 200) {
        final orderData = jsonDecode(orderRes.body);
        final order = orderData['order'];
        if (order != null) {
          final status = order['status'] ?? 'pending';
          final pName = order['partner_name'] ?? partnerName;
          final pPhone = order['partner_phone'] ?? partnerPhone;
          final dAddr = order['delivery_address'] ?? customerAddress;
          final iName = order['item_name'] ?? itemName;
          final num gTot = order['grand_total'] ?? 0;
          final bOtp = order['cod_otp']?.toString();
          final bMethod = order['payment_method']?.toString();
          final bPayStatus = order['payment_status']?.toString();
          orderBillImg = order['bill_image_url']?.toString();

          final oldStatus = orderStatus;

          // If order is cancelled:
          if (status == 'cancelled') {
            await prefs.setBool('has_active_order', false);
            await prefs.remove('active_order_id');
            await prefs.setString('active_order_status', 'cancelled');
            if (mounted) {
              setState(() {
                hasActiveOrder = false;
                orderStatus = 'cancelled';
              });
            }
            return;
          }

          // If order is completed/delivered:
          if (status == 'delivered' || status == 'completed') {
            await prefs.setBool('has_active_order', false);
            await prefs.remove('active_order_id');
            await prefs.setString('active_order_status', 'delivered');

            if (oldStatus != 'delivered' && !_isPaymentSuccessShown) {
              _isPaymentSuccessShown = true;
              _pollTimer?.cancel();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FullScreenPaymentSuccessScreen(
                      orderId: currentOrderId,
                      totalAmount: totalAmount > 0 ? totalAmount : (gTot.toDouble()),
                      paymentMethod: paymentMethod.isNotEmpty ? paymentMethod : "Payment Successful",
                      isDeliveryPartner: false,
                    ),
                  ),
                );
              }
            } else {
              if (mounted) {
                setState(() {
                  hasActiveOrder = false;
                  orderStatus = 'delivered';
                });
              }
            }
            return;
          }

          // Order chat messages are tracked globally and deduplicated via AppNotificationService

          if (mounted) {
            setState(() {
              orderStatus = status;
              orderId = currentOrderId;
              itemName = iName;
              customerAddress = dAddr;
              partnerName = pName;
              partnerPhone = pPhone;
              hasActiveOrder = true;
              isPartnerAccepted = status != 'pending';
              isFoodPurchased = status == 'purchasing_food' || status == 'bill_sent' || status == 'in_transit' || status == 'delivered';
              if (status == 'bill_sent' || status == 'in_transit' || status == 'delivered') {
                isBillSent = true;
              }
              if (gTot > 0 && billItems.isEmpty) {
                itemTotal = gTot.toDouble();
              }
              if (bOtp != null && bOtp.isNotEmpty) {
                activeOtp = bOtp;
              }
              if (bMethod != null && bMethod.isNotEmpty) {
                paymentMethod = bMethod;
              }
              if (bPayStatus == 'paid' || bPayStatus == 'success' || (bMethod != null && bMethod.contains('UPI'))) {
                isOnlinePaid = true;
              }
              final pId = order['partner_id']?.toString();
              if (pId != null && pId.isNotEmpty) {
                partnerId = pId;
                prefs.setString('active_order_partner_id', pId);
              }
              final pPic = order['partner_profile_picture']?.toString();
              if (pPic != null && pPic.isNotEmpty) {
                partnerProfilePicture = pPic;
                prefs.setString('active_order_partner_pic', pPic);
              }
              if (orderBillImg != null && orderBillImg.isNotEmpty) {
                uploadedBillImageUrl = orderBillImg;
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error polling order from backend: $e");
    }

    // 2. Fetch Bill Data from backend MongoDB
    try {
      final billRes = await http.get(ApiConfig.billByOrder(currentOrderId)).timeout(const Duration(seconds: 2));
      if (billRes.statusCode == 200) {
        final billData = jsonDecode(billRes.body);
        final bill = billData['bill'];
        if (bill != null) {
          final List rawItems = bill['items'] ?? [];
          final double subTot = (bill['item_total'] as num?)?.toDouble() ?? 120.0;
          final double tip = (bill['tip_amount'] as num?)?.toDouble() ?? 0.0;
          final savedTip = prefs.getDouble('order_${currentOrderId}_tip') ?? tipAmount;
          final effectiveTip = savedTip > 0 ? savedTip : tip;
          final String shop = bill['shop_name'] ?? 'Restaurant';
          final String? billImg = bill['bill_image_url'] ?? orderBillImg ?? prefs.getString('order_${currentOrderId}_bill_image');

          final parsedItems = rawItems.map((e) => {
            'name': e['name'] ?? 'Item',
            'hotel': shop,
            'price': (e['price'] as num?)?.toDouble() ?? 0.0,
            'quantity': (e['quantity'] as num?)?.toInt() ?? 1,
          }).toList();

          if (mounted) {
            setState(() {
              isBillSent = true;
              billItems = parsedItems;
              itemTotal = subTot;
              deliveryEarnings = 0.0;
              tipAmount = effectiveTip;
              uploadedBillImageUrl = billImg;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error polling bill from backend: $e");
    }

    // 3. Fetch Live Tracking Location from backend using dynamic partner ID
    try {
      final effectivePid = partnerId ?? prefs.getString('active_order_partner_id') ?? 'DP001';
      final locRes = await http.get(ApiConfig.trackingByPartner(effectivePid)).timeout(const Duration(seconds: 2));
      if (locRes.statusCode == 200) {
        final locData = jsonDecode(locRes.body);
        final loc = locData['location'];
        if (loc != null && loc['latitude'] != null && loc['longitude'] != null) {
          final newLoc = LatLng(
            (loc['latitude'] as num).toDouble(),
            (loc['longitude'] as num).toDouble(),
          );
          if (mounted && (_partnerLocation.latitude != newLoc.latitude || _partnerLocation.longitude != newLoc.longitude)) {
            setState(() {
              _partnerLocation = newLoc;
            });
            _fitMapBounds();
            _fetchRoadRoute();
          }
        }
      }
    } catch (e) {
      debugPrint("Error polling tracking from backend: $e");
    }
  } finally {
    _isPollingBackend = false;
  }
}

  void _showPaymentOptions() {
    final payAmount = totalAmount > 0 ? totalAmount : 195.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 14,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Choose Payment Method", style: AppTypography.screenHeading),
                          SizedBox(height: 2),
                          Text("Select any payment app on this device or COD", style: AppTypography.secondary),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "₹ ${payAmount.toStringAsFixed(0)}",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Primary Hero Button: Pay via Any UPI App (Opens Device's Native App Chooser)
                InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleDirectOnlinePayment("Device UPI App", payAmount);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.apps_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "⚡ Pay via Any UPI App",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "Choose any installed payment app on this phone",
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            "Choose App",
                            style: TextStyle(
                              color: Color(0xFF4F46E5),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    "POPULAR PAYMENT APPS ON THIS DEVICE",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                // Direct Apps List
                _buildPaymentAppTile(
                  title: "Google Pay (GPay)",
                  subtitle: "Fast UPI payment via Google Pay",
                  icon: Icons.account_balance_wallet_rounded,
                  color: const Color(0xFF2563EB),
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleDirectOnlinePayment("Google Pay", payAmount);
                  },
                ),
                const Divider(height: 1, indent: 56),

                _buildPaymentAppTile(
                  title: "PhonePe UPI",
                  subtitle: "Instant UPI payment via PhonePe",
                  icon: Icons.phone_android_rounded,
                  color: const Color(0xFF7C3AED),
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleDirectOnlinePayment("PhonePe", payAmount);
                  },
                ),
                const Divider(height: 1, indent: 56),

                _buildPaymentAppTile(
                  title: "Paytm UPI",
                  subtitle: "Pay using Paytm Wallet / UPI",
                  icon: Icons.account_balance_rounded,
                  color: const Color(0xFF0284C7),
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleDirectOnlinePayment("Paytm", payAmount);
                  },
                ),
                const Divider(height: 1, indent: 56),

                _buildPaymentAppTile(
                  title: "Scan QR Code / Copy UPI ID",
                  subtitle: "Scan QR with any app or copy VPA",
                  icon: Icons.qr_code_2_rounded,
                  color: const Color(0xFFEA580C),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showQrCodeDialog(payAmount);
                  },
                ),

                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    "CASH AT DOORSTEP",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Cash on Delivery (COD) Option
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.payments_rounded, color: Color(0xFFB45309), size: 24),
                    ),
                    title: const Text(
                      "Cash on Delivery (COD)",
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                    ),
                    subtitle: const Text(
                      "Pay cash at delivery • Generates verification OTP",
                      style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        "Select COD",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _handleCodSelection();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentAppTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }

  Future<void> _handleDirectOnlinePayment(String appName, double amount) async {
    // 1. Launch the payment app or Android system app chooser
    if (appName == "Google Pay") {
      await UpiPaymentService.openGooglePay(context, amount: amount, note: 'Order $orderId');
    } else if (appName == "PhonePe") {
      await UpiPaymentService.openPhonePe(context, amount: amount, note: 'Order $orderId');
    } else if (appName == "Paytm") {
      await UpiPaymentService.openPaytm(context, amount: amount, note: 'Order $orderId');
    } else {
      await UpiPaymentService.openAnyUpi(context, amount: amount, note: 'Order $orderId');
    }

    if (!mounted) return;

    // 2. Show post-payment confirmation sheet to confirm and generate delivery OTP
    _showPaymentConfirmationDialog(appName, amount);
  }

  void _showPaymentConfirmationDialog(String appName, double amount) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (BuildContext sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(10)),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
                  ),
                  child: const Icon(Icons.payment_rounded, size: 36, color: Color(0xFF059669)),
                ),
                const SizedBox(height: 14),
                Text(
                  "Paying via $appName",
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  "Amount: ₹${amount.toStringAsFixed(0)}",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Once you have completed the payment in your app, tap the button below to get your Delivery Verification OTP.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF047857),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
                    label: const Text(
                      "✓ I Have Completed Payment",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _confirmOnlinePayment(appName, amount);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.textPrimary),
                        label: const Text(
                          "Re-open App",
                          style: TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          _handleDirectOnlinePayment(appName, amount);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFF59E0B)),
                          backgroundColor: const Color(0xFFFEF3C7).withValues(alpha: 0.3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.payments_rounded, size: 16, color: Color(0xFFB45309)),
                        label: const Text(
                          "Pay COD Instead",
                          style: TextStyle(fontSize: 13, color: Color(0xFFB45309), fontWeight: FontWeight.w800),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          _handleCodSelection();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmOnlinePayment(String appName, double amount) async {
    final random = Random();
    final onlineOtp = (1000 + random.nextInt(9000)).toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_cod_otp', onlineOtp);
    await prefs.setString('payment_method', appName);
    await prefs.setBool('is_online_paid', true);
    await prefs.setBool('is_cod_selected', false);

    setState(() {
      activeOtp = onlineOtp;
      paymentMethod = appName;
      isOnlinePaid = true;
    });

    // Sync to MongoDB backend so delivery partner can verify OTP
    try {
      await http.post(
        ApiConfig.orderUpdateStatus,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'order_id': orderId,
          'cod_otp': onlineOtp,
          'payment_method': appName,
          'payment_status': 'paid',
        }),
      );
    } catch (_) {}

    if (!mounted) return;

    // Show success dialog with delivery OTP
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 28),
            SizedBox(width: 8),
            Text("Payment Received!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Paid ₹${amount.toStringAsFixed(0)} via $appName.",
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),
            const Text(
              "Share this 4-digit Delivery OTP with your delivery partner when they arrive to receive your food:",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
              ),
              child: Text(
                onlineOtp,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                  color: Color(0xFF047857),
                ),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF047857),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Track Delivery"),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCodSelection() async {
    final random = Random();
    final codOtp = (1000 + random.nextInt(9000)).toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_cod_otp', codOtp);
    await prefs.setString('payment_method', 'Cash on Delivery (COD)');
    await prefs.setBool('is_cod_selected', true);
    await prefs.setBool('is_online_paid', false);

    setState(() {
      activeOtp = codOtp;
      paymentMethod = 'Cash on Delivery (COD)';
      isOnlinePaid = false;
    });

    // Sync OTP to backend MongoDB so Delivery Partner on Device 2 can verify it
    http.post(
      ApiConfig.orderUpdateStatus,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'order_id': orderId,
        'cod_otp': codOtp,
        'payment_method': 'Cash on Delivery (COD)',
        'payment_status': 'pending',
      }),
    ).catchError((_) => http.Response('', 500));

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Color(0xFFB45309)),
            SizedBox(width: 8),
            Text("Your COD OTP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Share this 4-digit OTP with your delivery partner once you pay cash to receive food:"),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                codOtp,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 8, color: Color(0xFFB45309)),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK, I Will Share OTP"),
          ),
        ],
      ),
    );
  }

  void _showQrCodeDialog(double amount) {
    final qrUrl = UpiPaymentService.getQrCodeUrl(amount: amount, note: 'Order $orderId');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.qr_code_2_rounded, color: Color(0xFFEA580C), size: 26),
            SizedBox(width: 8),
            Text("Scan to Pay", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                qrUrl,
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey[200],
                  child: const Center(child: Text("Could not load QR")),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Pay ₹${amount.toStringAsFixed(0)}",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: UpiPaymentService.defaultVpa));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('UPI ID copied to clipboard!'),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        UpiPaymentService.defaultVpa,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy_rounded, size: 14, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF047857),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _confirmOnlinePayment("UPI QR Code", amount);
            },
            child: const Text("I Have Paid"),
          ),
        ],
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
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Order Tracking & Bill", style: AppTypography.screenHeading),
              Text(
                orderId,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
            onPressed: _handleBackNavigation,
          ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: 'Refresh Status',
            onPressed: _pollFromBackend,
          ),
        ],
      ),
      body: (!hasActiveOrder || orderStatus == 'delivered' || orderStatus == 'completed' || orderStatus == 'cancelled')
          ? _buildTryNewOrderView()
          : (!isPartnerAccepted
              ? _buildWaitingForPartnerView()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Order Status Badge Card
                      _buildOrderStatusHeaderCard(),
                      const SizedBox(height: 16),

                      // Delivery Verification OTP Card (Shown whenever activeOtp exists)
                      if (activeOtp != null && activeOtp!.isNotEmpty) ...[
                        _buildDeliveryOtpCard(),
                        const SizedBox(height: 16),
                      ],

                      // LIVE LOCATION MAP (Customer tracks delivery person's live location)
                      _buildLiveLocationMapCard(),
                      const SizedBox(height: 16),

                      // Delivery Partner Profile Card
                      _buildDeliveryPartnerInfoCard(),
                      const SizedBox(height: 16),

                      // Order Steps Timeline
                      _buildOrderTimelineCard(),
                      const SizedBox(height: 16),

                      // CONDITIONAL BILL CONTAINER
                      if (!isBillSent)
                        _buildWaitingForBillCard()
                      else
                        _buildBillDetailsCard(),

                      const SizedBox(height: 100),
                    ],
                  ),
                )),
      bottomNavigationBar: (hasActiveOrder && isPartnerAccepted && isBillSent) ? _buildPayBottomBar() : null,
    ),
  );
}

  // Customer cancels active order
  Future<void> _cancelOrderFromCustomer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Cancel Order?", style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text("Do you really want to cancel this order? Nearby delivery partners will be notified immediately."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Keep Order", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Yes, Cancel", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    String selectedReason = "Placed order by mistake";
    final TextEditingController reasonController = TextEditingController();
    final List<String> reasons = [
      "Placed order by mistake",
      "Wait time is too long",
      "Wrong delivery location / items",
      "Change of mind",
      "Other reason",
    ];

    if (!mounted) return;
    final reasonConfirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.cancel_rounded, color: AppColors.danger, size: 22),
                SizedBox(width: 8),
                Text('Reason for cancellation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Please select why you want to cancel:",
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  ...reasons.map((r) {
                    final isSel = selectedReason == r;
                    return InkWell(
                      onTap: () {
                        setDialogState(() {
                          selectedReason = r;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSel ? const Color(0xFFFEE2E2) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSel ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0),
                            width: isSel ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                              size: 18,
                              color: isSel ? const Color(0xFFDC2626) : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                r,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                  color: isSel ? const Color(0xFF991B1B) : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (selectedReason == "Other reason") ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Enter specific reason...',
                        hintStyle: const TextStyle(fontSize: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Back', style: TextStyle(color: AppColors.textSecondary)),
                onPressed: () => Navigator.pop(dlgCtx, false),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Confirm Cancel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.pop(dlgCtx, true),
              ),
            ],
          );
        },
      ),
    );

    if (reasonConfirmed != true) return;

    final finalReason = selectedReason == "Other reason" && reasonController.text.trim().isNotEmpty
        ? reasonController.text.trim()
        : selectedReason;

    try {
      await http.post(
        ApiConfig.orderCancel,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'order_id': orderId,
          'cancel_reason': finalReason,
          'cancelled_by': 'customer',
        }),
      );
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_active_order', false);
    await prefs.remove('active_order_id');
    await prefs.setString('active_order_status', 'cancelled');
    await prefs.setBool('active_order_partner_accepted', false);

    if (mounted) {
      setState(() {
        hasActiveOrder = false;
        orderStatus = 'cancelled';
        isPartnerAccepted = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cancel_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text("Order $orderId cancelled successfully.")),
            ],
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // 1. Banner State: Try a New Order (Shown before order placed or after order is delivered/completed/cancelled)
  Widget _buildTryNewOrderView() {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFEF3C7), // warm amber tint
                      Color(0xFFFFEDD5), // warm orange tint
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFFDBA74).withValues(alpha: 0.6), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF97316).withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEA580C),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text(
                            "Superfast Delivery",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEA580C).withValues(alpha: 0.18),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.fastfood_rounded,
                        size: 44,
                        color: Color(0xFFEA580C),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Try a New Order",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Craving your favorite dishes?\nExplore tasty meals from top restaurants and get them delivered to your doorstep!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFeatureBadge("⚡ Hot Food"),
                        _buildFeatureBadge("🛵 Free Delivery"),
                        _buildFeatureBadge("📍 Live GPS"),
                      ],
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.restaurant_rounded, size: 20),
                        label: const Text(
                          "Order Now",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => const HomePage()),
                            (route) => false,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDBA74).withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFFC2410C),
        ),
      ),
    );
  }

  // 2. Waiting State: Order Placed, Waiting for Partner to Accept
  Widget _buildWaitingForPartnerView() {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFBFDBFE), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Center(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.5,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Connecting to your delivery person...",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Order $orderId placed successfully!\nSearching and connecting to a nearby delivery partner...",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // Item and Address summary card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.restaurant_rounded, color: Color(0xFFD97706), size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Food Ordered", style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(itemName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20, thickness: 0.8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.location_on_rounded, color: AppColors.primaryDark, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Delivery Address", style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                customerAddress,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Info banner with Expanded so it never overflows
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textSecondary),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Rider details & tracking map will appear once partner accepts",
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Cancel Order button
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: _cancelOrderFromCustomer,
                  icon: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.danger),
                  label: const Text(
                    "Cancel Order",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.danger),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    backgroundColor: const Color(0xFFFEF2F2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Status Header
  Widget _buildOrderStatusHeaderCard() {
    Color bg;
    Color fg;
    String statusText;
    IconData icon;

    if (orderStatus == 'delivered') {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF15803D);
      statusText = "Order Delivered • Payment Verified";
      icon = Icons.check_circle_rounded;
    } else if (orderStatus == 'in_transit' || (isBillSent && orderStatus != 'delivered')) {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF15803D);
      statusText = "Bill Ready • Out for Delivery";
      icon = Icons.two_wheeler_rounded;
    } else if (orderStatus == 'purchasing_food') {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFB45309);
      statusText = "Partner Purchasing Food at Restaurant";
      icon = Icons.shopping_basket_rounded;
    } else if (isPartnerAccepted) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFB45309);
      statusText = "Delivery Partner Connected • Heading to Shop";
      icon = Icons.storefront_rounded;
    } else {
      bg = const Color(0xFFEFF6FF);
      fg = const Color(0xFF2563EB);
      statusText = "Connecting Delivery Partner...";
      icon = Icons.hourglass_top_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(fontWeight: FontWeight.w800, color: fg, fontSize: 13),
                ),
                Text(
                  "Item: $itemName",
                  style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Delivery Verification OTP Card (Shown for both Online and COD payments)
  Widget _buildDeliveryOtpCard() {
    final otpToShow = activeOtp ?? "----";
    final isPaid = isOnlinePaid;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPaid
              ? [const Color(0xFF047857), const Color(0xFF059669)]
              : [const Color(0xFFB45309), const Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isPaid ? const Color(0xFF047857) : const Color(0xFFD97706)).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(isPaid ? Icons.verified_user_rounded : Icons.vpn_key_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isPaid ? "ONLINE DELIVERY OTP" : "COD DELIVERY OTP",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isPaid ? "Paid Online" : "Pay Cash",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            "Share this OTP with your delivery partner when they arrive to complete delivery:",
            style: TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              otpToShow,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
                color: isPaid ? const Color(0xFF047857) : const Color(0xFFB45309),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Live Location GPS Tracking Map Card
  Widget _buildLiveLocationMapCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.subtleShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.location_on_rounded, color: Color(0xFFEA580C), size: 20),
                    SizedBox(width: 6),
                    Text(
                      "Delivery Person Live Location",
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.radar_rounded, color: AppColors.primary, size: 12),
                      SizedBox(width: 4),
                      Text(
                        "LIVE GPS",
                        style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Real Interactive Google Map with Delivery Person's Live GPS Coordinates
          SizedBox(
            height: 220,
            width: double.infinity,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _partnerLocation,
                    zoom: 14.5,
                  ),
                  markers: {
                    Marker(
                      markerId: const MarkerId('rider'),
                      position: _partnerLocation,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                      infoWindow: InfoWindow(
                        title: '$partnerName (Rider)',
                        snippet: orderStatus == 'in_transit' ? 'On the way to you' : 'Live Partner Location',
                      ),
                    ),
                    Marker(
                      markerId: const MarkerId('destination'),
                      position: _customerLocation,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                      infoWindow: InfoWindow(
                        title: 'Your Delivery Location',
                        snippet: customerAddress,
                      ),
                    ),
                  },
                  polylines: {
                    Polyline(
                      polylineId: const PolylineId('route'),
                      points: _routePoints.isNotEmpty
                          ? _routePoints
                          : [
                              _partnerLocation,
                              _customerLocation,
                            ],
                      color: AppColors.primary,
                      width: 5,
                    ),
                  },
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  onMapCreated: (ctrl) {
                    _mapController = ctrl;
                    _fitMapBounds();
                  },
                ),

                // Floating Live ETA Badge
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.two_wheeler_rounded, color: Color(0xFF047857), size: 16),
                        const SizedBox(width: 6),
                        Text(
                          orderStatus == 'in_transit'
                              ? "Out for Delivery • Live Road Route"
                              : (isPartnerAccepted ? "Partner Connected • Live GPS" : "Connecting Partner..."),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),

                // Destination Address bottom bar
                Positioned(
                  bottom: 8,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded, color: Color(0xFFDC2626), size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            customerAddress,
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerAvatarImage() {
    if (partnerProfilePicture != null && partnerProfilePicture!.isNotEmpty) {
      final img = partnerProfilePicture!.trim();
      if (img.startsWith('http')) {
        return Image.network(
          img,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackPartnerAvatar(),
        );
      } else if (img.startsWith('/') || img.contains('\\') || img.startsWith('file:')) {
        final f = File(img);
        if (f.existsSync()) {
          return Image.file(
            f,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackPartnerAvatar(),
          );
        }
      }
      try {
        final b64 = img.contains(',') ? img.split(',').last.trim() : img;
        final bytes = base64Decode(b64);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackPartnerAvatar(),
        );
      } catch (_) {}
    }
    return _buildFallbackPartnerAvatar();
  }

  Widget _buildFallbackPartnerAvatar() {
    return Image.asset(
      'assets/delivery_boy_toon.png',
      fit: BoxFit.cover,
      errorBuilder: (ctx, err, stack) => const Icon(Icons.person, color: Color(0xFF047857), size: 36),
    );
  }

  // Delivery Partner Information Card
  Widget _buildDeliveryPartnerInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.subtleShadow,
      ),
      child: Row(
        children: [
          // Partner Profile Avatar
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF10B981), width: 2),
            ),
            child: ClipOval(
              child: _buildPartnerAvatarImage(),
            ),
          ),
          const SizedBox(width: 14),

          // Partner Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  partnerName,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                const Text(
                  "⭐ 4.9 (128 deliveries) • Hero Splendor",
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  partnerPhone,
                  style: const TextStyle(fontSize: 12, color: AppColors.primaryDark, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),

          // Call Button
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
              foregroundColor: AppColors.primary,
            ),
            icon: const Icon(Icons.phone_rounded, size: 20),
            tooltip: 'Call Partner',
            onPressed: () async {
              final cleanPhone = partnerPhone.replaceAll(RegExp(r'[^0-9+]'), '');
              final uri = Uri.parse('tel:$cleanPhone');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Could not launch dialer for $partnerPhone"),
                      backgroundColor: const Color(0xFFDC2626),
                    ),
                  );
                }
              }
            },
          ),
          const SizedBox(width: 8),
          // Chat Button
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFFEF3C7),
              foregroundColor: const Color(0xFFD97706),
            ),
            icon: const Icon(Icons.chat_bubble_rounded, size: 20),
            tooltip: 'Chat with Partner',
            onPressed: () {
              OrderChatSheet.show(
                context,
                orderId: orderId,
                senderRole: 'customer',
                otherPartyName: partnerName,
                otherPartyPhone: partnerPhone,
              );
            },
          ),
        ],
      ),
    );
  }

  // Stepper Timeline (Activity-Driven Milestones)
  Widget _buildOrderTimelineCard() {
    final bool s2Done = isPartnerAccepted;
    final bool s3Done = orderStatus == 'bill_sent' || orderStatus == 'in_transit' || orderStatus == 'delivered';
    final bool s4Done = isBillSent || orderStatus == 'in_transit' || orderStatus == 'delivered';
    final bool s5Done = orderStatus == 'delivered';
    final bool s6Done = orderStatus == 'delivered';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Live Delivery Progress", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 12),
          _buildStepRow(1, "Order Placed", "Item: $itemName", isDone: true),
          _buildStepRow(
            2,
            "Partner Connected",
            s2Done ? "$partnerName accepted your order" : "Waiting for nearby delivery partner to accept...",
            isDone: s2Done,
            isCurrent: !s2Done,
          ),
          _buildStepRow(
            3,
            "Purchasing Food at Restaurant",
            s3Done
                ? "Items purchased from store ✓"
                : (orderStatus == 'purchasing_food' ? "Partner is currently at restaurant purchasing food" : "Partner heading to food stall"),
            isDone: s3Done,
            isCurrent: !s3Done && s2Done,
          ),
          _buildStepRow(
            4,
            "Food Purchased & Bill Uploaded",
            s4Done ? "Verified Bill: ₹${totalAmount.toStringAsFixed(0)} uploaded ✓" : "Waiting for partner to upload purchase bill...",
            isDone: s4Done,
            isCurrent: !s4Done && (orderStatus == 'purchasing_food' || orderStatus == 'accepted'),
          ),
          _buildStepRow(
            5,
            "Out for Delivery",
            s5Done
                ? "Delivered to your address ✓"
                : (orderStatus == 'in_transit' ? "Partner on the way to your location" : "Ready for dispatch"),
            isDone: s5Done,
            isCurrent: !s5Done && (orderStatus == 'in_transit' || isBillSent),
          ),
          _buildStepRow(
            6,
            "Delivered & Verified",
            s6Done ? "Order delivered successfully! 🎉" : "Pending food arrival & OTP verification",
            isDone: s6Done,
            isCurrent: s6Done,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(int number, String title, String subtitle, {bool isDone = false, bool isCurrent = false, bool isLast = false}) {
    Color color = isDone ? const Color(0xFF15803D) : (isCurrent ? const Color(0xFFEA580C) : const Color(0xFF9CA3AF));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isDone ? const Color(0xFFDCFCE7) : (isCurrent ? const Color(0xFFFFEDD5) : const Color(0xFFF3F4F6)),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.5),
              ),
              child: Center(
                child: isDone
                    ? Icon(Icons.check, size: 14, color: color)
                    : Text(
                        "$number",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                      ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 24,
                color: isDone ? const Color(0xFF86EFAC) : const Color(0xFFE5E7EB),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: isDone || isCurrent ? AppColors.textPrimary : AppColors.textSecondary)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // WAITING CARD (When delivery person has NOT clicked Proceed Bill yet)
  Widget _buildWaitingForBillCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFFEF3C7),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_top_rounded, color: Color(0xFFB45309), size: 36),
          ),
          const SizedBox(height: 14),
          const Text(
            "Waiting for Delivery Partner's Purchase Bill",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            "$partnerName is currently at the local store/restaurant purchasing your requested food ($itemName). Once the partner uploads the purchase receipt and taps 'Proceed Bill', the official bill will immediately show here for you to verify and pay!",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          const SizedBox(
            width: 140,
            child: LinearProgressIndicator(
              backgroundColor: Color(0xFFFEF3C7),
              color: Color(0xFFD97706),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD97706)),
                ),
                const SizedBox(width: 8),
                Text(
                  "Real-time synced with $partnerName's device",
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // OFFICIAL VERIFIED BILL CARD (Shown ONLY after partner clicks Proceed Bill)
  Widget _buildBillDetailsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF10B981), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Official Purchase Bill",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primary),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    "VERIFIED",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Items Purchased by Partner:",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                ...billItems.map((it) {
                  final name = it['name'] ?? 'Item';
                  final hotel = it['hotel'] ?? 'Local Shop';
                  final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                  final qty = (it['quantity'] as num?)?.toInt() ?? 1;
                  return _buildBillItem("$qty× $name", hotel, price * qty);
                }),
                const Divider(thickness: 1, height: 24),
                _buildRow("Item Subtotal", "₹ ${itemTotal.toStringAsFixed(0)}"),
                const SizedBox(height: 6),
                _buildRow("Delivery Charges", "FREE (₹0)"),
                if (tipAmount > 0) ...[
                  const SizedBox(height: 6),
                  _buildRow("Delivery Tip", "₹ ${tipAmount.toStringAsFixed(0)}", isTip: true),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Total Payable",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                    ),
                    Text(
                      "₹ ${totalAmount.toStringAsFixed(0)}",
                      style: AppTypography.price.copyWith(fontSize: 22, color: AppColors.primaryDark),
                    ),
                  ],
                ),
                // Uploaded Food Bill Receipt (ONLY shown if delivery partner actually uploaded one for this order)
                if (uploadedBillImageUrl != null && uploadedBillImageUrl!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.receipt_rounded, size: 18, color: AppColors.primaryDark),
                          SizedBox(width: 6),
                          Text(
                            "Uploaded Shop Bill Receipt",
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () => _showFullReceiptDialog(uploadedBillImageUrl!),
                        icon: const Icon(Icons.fullscreen_rounded, size: 16, color: AppColors.primaryDark),
                        label: const Text("View Full", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _showFullReceiptDialog(uploadedBillImageUrl!),
                    child: Container(
                      height: 160,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildBillReceiptWidget(uploadedBillImageUrl!),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Tip Chips
                const Text("Add Rider Tip (Optional):", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [10.0, 20.0, 30.0, 50.0].map((t) {
                    final isSelected = tipAmount == t;
                    return ChoiceChip(
                      label: Text("₹${t.toInt()}"),
                      selected: isSelected,
                      selectedColor: AppColors.primaryLight,
                      backgroundColor: AppColors.background,
                      labelStyle: TextStyle(
                        color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 12,
                      ),
                      side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      onSelected: (val) async {
                        final newTip = val ? t : 0.0;
                        setState(() => tipAmount = newTip);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setDouble('order_${orderId}_tip', newTip);
                        try {
                          await http.post(
                            ApiConfig.billTip,
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode({
                              'order_id': orderId,
                              'tip_amount': newTip,
                            }),
                          );
                        } catch (_) {}
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillReceiptWidget(String pathOrUrl) {
    if (pathOrUrl.startsWith('data:image')) {
      final commaIndex = pathOrUrl.indexOf(',');
      final base64Data = commaIndex != -1 ? pathOrUrl.substring(commaIndex + 1) : pathOrUrl;
      return Image.memory(
        base64Decode(base64Data),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, size: 36, color: AppColors.textMuted)),
      );
    } else if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return Image.network(
        pathOrUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, size: 36, color: AppColors.textMuted)),
      );
    } else {
      final file = File(pathOrUrl);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, size: 36, color: AppColors.textMuted)),
        );
      }
      return const Center(child: Icon(Icons.receipt_long_rounded, size: 36, color: AppColors.textMuted));
    }
  }

  void _showFullReceiptDialog(String pathOrUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildBillReceiptWidget(pathOrUrl),
              ),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  // Bottom Navigation Pay Button
  Widget _buildPayBottomBar() {
    final payAmount = totalAmount > 0 ? totalAmount : 195.0;
    final isPaid = isOnlinePaid;
    final isCod = (activeOtp != null && activeOtp!.isNotEmpty && !isPaid);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: AppColors.border, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _showPaymentOptions,
          style: ElevatedButton.styleFrom(
            backgroundColor: isPaid
                ? const Color(0xFF047857)
                : (isCod ? const Color(0xFFB45309) : AppColors.primary),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isPaid ? Icons.check_circle_rounded : (isCod ? Icons.vpn_key_rounded : Icons.payment_rounded),
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isPaid
                    ? "Payment Done • View OTP"
                    : (isCod ? "COD Selected • Change / Pay" : "Proceed to Pay"),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text(
                "•  ₹ ${payAmount.toStringAsFixed(0)}",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isTip = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isTip ? AppColors.primaryDark : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildBillItem(String name, String hotel, double price) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text(hotel, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          Text("₹ ${price.toStringAsFixed(0)}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}


// GPay Page
class GPayPage extends StatefulWidget {
  final double amount;
  final String orderId;
  const GPayPage({super.key, this.amount = 195.0, this.orderId = "ORD-8492"});

  @override
  State<GPayPage> createState() => _GPayPageState();
}

class _GPayPageState extends State<GPayPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpiPaymentService.openGooglePay(context, amount: widget.amount);
    });
  }

  void _handleBackNavigation() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PaymentPage()),
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
        appBar: AppBar(
          title: const Text("Google Pay UPI", style: AppTypography.screenHeading),
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: _handleBackNavigation,
          ),
        ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.account_balance_wallet_rounded, size: 58, color: Color(0xFF2563EB)),
              ),
              Text("Pay ₹${widget.amount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: UpiPaymentService.defaultVpa));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('UPI ID copied: ${UpiPaymentService.defaultVpa}'),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_user_rounded, size: 16, color: Color(0xFF2563EB)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          "To UPI: ${UpiPaymentService.defaultVpa}",
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF2563EB)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text("Connecting to Google Pay app...", style: AppTypography.cardTitle),
              const SizedBox(height: 6),
              const Text(
                "If the Google Pay app does not open automatically, please tap the button below.",
                textAlign: TextAlign.center,
                style: AppTypography.secondary,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    UpiPaymentService.openGooglePay(context, amount: widget.amount);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 1,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                  label: const Text("Open Google Pay App", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () async {
                    final random = Random();
                    final onlineOtp = (1000 + random.nextInt(9000)).toString();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('active_cod_otp', onlineOtp);
                    await prefs.setString('payment_method', 'Google Pay UPI');
                    await prefs.setBool('is_online_paid', true);

                    // Sync to MongoDB
                    try {
                      await http.post(
                        ApiConfig.orderUpdateStatus,
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'order_id': widget.orderId,
                          'cod_otp': onlineOtp,
                          'payment_method': 'Google Pay UPI',
                          'payment_status': 'paid',
                        }),
                      );
                    } catch (_) {}

                    if (!context.mounted) return;
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: const Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 28),
                            SizedBox(width: 8),
                            Text("Payment Received!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Paid ₹${widget.amount.toStringAsFixed(0)} via Google Pay UPI.",
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              "Tell this 4-digit Delivery OTP to your delivery partner when they arrive to complete delivery:",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
                              ),
                              child: Text(
                                onlineOtp,
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 8,
                                  color: Color(0xFF047857),
                                ),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF047857),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.pop(context, true);
                            },
                            child: const Text("Track Delivery"),
                          ),
                        ],
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text("I Have Completed Payment", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

// PhonePe Page
class PhonePePage extends StatefulWidget {
  final double amount;
  final String orderId;
  const PhonePePage({super.key, this.amount = 195.0, this.orderId = "ORD-8492"});

  @override
  State<PhonePePage> createState() => _PhonePePageState();
}

class _PhonePePageState extends State<PhonePePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpiPaymentService.openPhonePe(context, amount: widget.amount);
    });
  }

  void _handleBackNavigation() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PaymentPage()),
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
        appBar: AppBar(
          title: const Text("PhonePe UPI", style: AppTypography.screenHeading),
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: _handleBackNavigation,
          ),
        ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_android_rounded, size: 58, color: Color(0xFF7C3AED)),
              ),
              Text("Pay ₹${widget.amount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: UpiPaymentService.defaultVpa));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('UPI ID copied: ${UpiPaymentService.defaultVpa}'),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_user_rounded, size: 16, color: Color(0xFF7C3AED)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          "To UPI: ${UpiPaymentService.defaultVpa}",
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF6D28D9)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF7C3AED)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text("Connecting to PhonePe app...", style: AppTypography.cardTitle),
              const SizedBox(height: 6),
              const Text(
                "If PhonePe does not open automatically, please tap the button below.",
                textAlign: TextAlign.center,
                style: AppTypography.secondary,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    UpiPaymentService.openPhonePe(context, amount: widget.amount);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 1,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                  label: const Text("Open PhonePe App", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () async {
                    final random = Random();
                    final onlineOtp = (1000 + random.nextInt(9000)).toString();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('active_cod_otp', onlineOtp);
                    await prefs.setString('payment_method', 'PhonePe UPI');
                    await prefs.setBool('is_online_paid', true);

                    // Sync to MongoDB
                    try {
                      await http.post(
                        ApiConfig.orderUpdateStatus,
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'order_id': widget.orderId,
                          'cod_otp': onlineOtp,
                          'payment_method': 'PhonePe UPI',
                          'payment_status': 'paid',
                        }),
                      );
                    } catch (_) {}

                    if (!context.mounted) return;
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: const Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 28),
                            SizedBox(width: 8),
                            Text("Payment Received!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Paid ₹${widget.amount.toStringAsFixed(0)} via PhonePe UPI.",
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              "Tell this 4-digit Delivery OTP to your delivery partner when they arrive to complete delivery:",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
                              ),
                              child: Text(
                                onlineOtp,
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 8,
                                  color: Color(0xFF047857),
                                ),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF047857),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.pop(context, true);
                            },
                            child: const Text("Track Delivery"),
                          ),
                        ],
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text("I Have Completed Payment", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

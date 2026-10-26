import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api_config.dart';
import '../homed.dart';
import '../services/alarm_service.dart';
import '../services/app_notification_service.dart';

/// Popup dialog shown to the Delivery Person right after accepting an order.
/// Includes:
/// 1. Call Customer button
/// 2. Price range input box with quick suggestions
/// 3. Send to Customer button
/// 4. Waiting state that polls for customer acknowledgement
/// 5. Automatically completes when customer accepts so the caller can open the Order & Bill page
class DeliveryPartnerPriceRangeDialog extends StatefulWidget {
  final String orderId;
  final String customerName;
  final String customerPhone;
  final String itemName;
  final String budget;

  const DeliveryPartnerPriceRangeDialog({
    super.key,
    required this.orderId,
    required this.customerName,
    required this.customerPhone,
    required this.itemName,
    required this.budget,
  });

  @override
  State<DeliveryPartnerPriceRangeDialog> createState() =>
      _DeliveryPartnerPriceRangeDialogState();
}

class _DeliveryPartnerPriceRangeDialogState
    extends State<DeliveryPartnerPriceRangeDialog> {
  late TextEditingController _priceRangeController;
  bool _isSending = false;
  bool _isSent = false;
  bool _isCustomerAccepted = false;
  Timer? _statusCheckTimer;
  String? _errorMessage;

  final List<String> _quickRanges = [
    '100 - 200',
    '200 - 300',
    '300 - 500',
    '500 - 800',
  ];

  @override
  void initState() {
    super.initState();
    final double? b = double.tryParse(widget.budget);
    if (b != null && b > 0) {
      final int minB = (b * 0.9).round();
      final int maxB = (b * 1.2).round();
      _priceRangeController = TextEditingController(text: '$minB - $maxB');
    } else {
      _priceRangeController = TextEditingController(text: '150 - 250');
    }
    _checkInitialOrderStatus();
  }

  Future<void> _checkInitialOrderStatus() async {
    try {
      final res = await http.get(ApiConfig.orderById(widget.orderId)).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final order = data['order'];
        if (order != null) {
          final String prStatus = (order['price_range_status'] ?? '').toString().toLowerCase();
          final String pr = (order['price_range'] ?? '').toString();
          final String ordStatus = (order['status'] ?? '').toString().toLowerCase();
          final String assignedPartnerId = (order['partner_id'] ?? '').toString().toLowerCase();
          final List declinedList = (order['declined_partners'] as List?)
              ?.map((e) => e.toString().toLowerCase().trim())
              .toList() ?? [];

          final prefs = await SharedPreferences.getInstance();
          final myPId = (prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? 'dp001')
              .trim()
              .toLowerCase();
          final numPart = myPId.replaceAll(RegExp(r'[^0-9]'), '');
          final bool isDeclinedForMe = declinedList.contains(myPId) ||
              (numPart.isNotEmpty && declinedList.any((d) => d.contains(numPart)));

          if (ordStatus == 'cancelled') {
            if (mounted) {
              await _handleOrderCancelledOrReassigned(wasReassigned: false);
            }
            return;
          }

          if (isDeclinedForMe ||
              (assignedPartnerId.isNotEmpty &&
                  assignedPartnerId != myPId &&
                  (numPart.isEmpty || !assignedPartnerId.contains(numPart)))) {
            if (mounted) {
              await _handleOrderCancelledOrReassigned(wasReassigned: true);
            }
            return;
          }

          if (prStatus == 'accepted') {
            if (mounted) {
              setState(() {
                _isCustomerAccepted = true;
              });
              await Future.delayed(const Duration(milliseconds: 600));
              if (mounted) {
                Navigator.of(context).pop(true);
              }
            }
          } else if (prStatus == 'pending' && pr.isNotEmpty) {
            if (mounted) {
              setState(() {
                _priceRangeController.text = pr;
                _isSent = true;
              });
              _startPollingCustomerResponse();
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _handleOrderCancelledOrReassigned({required bool wasReassigned}) async {
    _statusCheckTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('partner_active_order_id');
      await prefs.remove('active_order_id');
      await prefs.remove('active_order_status');
      await prefs.remove('active_order_customer_name');
      await prefs.remove('active_order_customer_phone');
      await prefs.remove('active_order_customer_address');
      await prefs.remove('active_order_item');
      await prefs.remove('active_order_budget');
      await prefs.remove('active_order_bill_sent');
      await prefs.remove('active_order_food_purchased');
      await prefs.remove('active_order_partner_accepted');
      await prefs.remove('active_order_restaurant');
      await prefs.remove('active_order_grand_total');

      final curDeclined = prefs.getStringList('partner_declined_order_ids') ?? [];
      if (!curDeclined.contains(widget.orderId)) {
        curDeclined.add(widget.orderId);
        await prefs.setStringList('partner_declined_order_ids', curDeclined);
      }

      AlarmService.silenceOrder(widget.orderId);
      AlarmService.stopAlarm();
      AppNotificationService.cancelNotification(999);
    } catch (e) {
      debugPrint('Error cleaning up active order state: $e');
    }

    if (mounted) {
      // Cleanly navigate to DeliveryHomePage, removing all open dialogs and screens
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DeliveryHomePage()),
        (route) => false,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasReassigned
                ? "Customer requested another delivery person. Order cancelled and removed."
                : "Customer stopped/cancelled this order.",
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    _priceRangeController.dispose();
    super.dispose();
  }

  Future<void> _makeCustomerCall() async {
    final cleanPhone = widget.customerPhone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer phone number is not available')),
      );
      return;
    }
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error launching call: $e');
    }
  }

  Future<void> _sendPriceRange() async {
    final rangeText = _priceRangeController.text.trim();
    if (rangeText.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter estimated price range';
      });
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      final res = await http.post(
        ApiConfig.orderSendPriceRange,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'order_id': widget.orderId,
          'price_range': rangeText,
        }),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        if (mounted) {
          setState(() {
            _isSending = false;
            _isSent = true;
          });
          _startPollingCustomerResponse();
        }
      } else {
        if (mounted) {
          setState(() {
            _isSending = false;
            _errorMessage = 'Failed to send price range. Please try again.';
          });
        }
      }
    } catch (e) {
      debugPrint('Error sending price range: $e');
      if (mounted) {
        setState(() {
          _isSending = false;
          _errorMessage = 'Network error: $e';
        });
      }
    }
  }

  void _startPollingCustomerResponse() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final res = await http
            .get(ApiConfig.orderById(widget.orderId))
            .timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final order = data['order'];
          if (order != null) {
            final String prStatus = (order['price_range_status'] ?? '').toString().toLowerCase();
            final String ordStatus = (order['status'] ?? '').toString().toLowerCase();
            final String assignedPartnerId = (order['partner_id'] ?? '').toString().toLowerCase();
            final List declinedList = (order['declined_partners'] as List?)
                ?.map((e) => e.toString().toLowerCase().trim())
                .toList() ?? [];

            final prefs = await SharedPreferences.getInstance();
            final myPId = (prefs.getString('d_id') ?? prefs.getString('active_order_partner_id') ?? 'dp001')
                .trim()
                .toLowerCase();
            final numPart = myPId.replaceAll(RegExp(r'[^0-9]'), '');

            final bool isDeclinedForMe = declinedList.contains(myPId) ||
                (numPart.isNotEmpty && declinedList.any((d) => d.contains(numPart)));

            if (prStatus == 'accepted') {
              timer.cancel();
              final notifKey = 'partner_notified_ack_acc_${widget.orderId}';
              if (prefs.getBool(notifKey) != true) {
                await prefs.setBool(notifKey, true);
                await AppNotificationService.showCustomerAckResponseNotification(
                  orderId: widget.orderId,
                  isAccepted: true,
                );
              }
              if (mounted) {
                setState(() {
                  _isCustomerAccepted = true;
                });
                await Future.delayed(const Duration(milliseconds: 900));
                if (mounted) {
                  Navigator.of(context).pop(true);
                }
              }
            } else if (ordStatus == 'cancelled') {
              timer.cancel();
              final notifKey = 'partner_notified_ack_dec_${widget.orderId}';
              if (prefs.getBool(notifKey) != true) {
                await prefs.setBool(notifKey, true);
                await AppNotificationService.showCustomerAckResponseNotification(
                  orderId: widget.orderId,
                  isAccepted: false,
                  reason: order['cancel_reason'] ?? 'Order stopped by customer',
                );
              }
              if (mounted) {
                await _handleOrderCancelledOrReassigned(wasReassigned: false);
              }
            } else if (isDeclinedForMe ||
                (ordStatus == 'pending' && _isSent) ||
                (assignedPartnerId.isNotEmpty &&
                    assignedPartnerId != myPId &&
                    (numPart.isEmpty || !assignedPartnerId.contains(numPart))) ||
                (assignedPartnerId.isEmpty && ordStatus != 'accepted')) {
              timer.cancel();
              final notifKey = 'partner_notified_ack_dec_${widget.orderId}';
              if (prefs.getBool(notifKey) != true) {
                await prefs.setBool(notifKey, true);
                await AppNotificationService.showCustomerAckResponseNotification(
                  orderId: widget.orderId,
                  isAccepted: false,
                  reason: 'Customer declined price range and requested another delivery partner',
                );
              }
              if (mounted) {
                await _handleOrderCancelledOrReassigned(wasReassigned: true);
              }
            } else if (prStatus == 'rejected') {
              timer.cancel();
              final notifKey = 'partner_notified_ack_dec_${widget.orderId}';
              if (prefs.getBool(notifKey) != true) {
                await prefs.setBool(notifKey, true);
                await AppNotificationService.showCustomerAckResponseNotification(
                  orderId: widget.orderId,
                  isAccepted: false,
                  reason: 'Customer declined this price range',
                );
              }
              if (mounted) {
                setState(() {
                  _errorMessage = 'Customer declined this price range. Please call customer to renegotiate.';
                  _isSent = false;
                });
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Polling error: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please wait for customer approval before continuing."),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: _isSent ? _buildWaitingView() : _buildInputView(),
          ),
        ),
      ),
    );
  }

  Widget _buildInputView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.handshake_rounded,
                color: Color(0xFF16A34A),
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Order Accepted!",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  Text(
                    "Order ID: #${widget.orderId}",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Customer Info Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.person_rounded, size: 20, color: Color(0xFF374151)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.customerName.isNotEmpty ? widget.customerName : 'Customer',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shopping_bag_outlined, size: 18, color: Color(0xFF6B7280)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.itemName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF4B5563),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Call Customer Button
        ElevatedButton.icon(
          onPressed: _makeCustomerCall,
          icon: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 20),
          label: Text(
            widget.customerPhone.isNotEmpty
                ? "Call Customer (${widget.customerPhone})"
                : "Call Customer",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Divider with hint
        Row(
          children: [
            Expanded(child: Divider(color: Colors.grey.shade300)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                "PRICE ACKNOWLEDGEMENT",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Expanded(child: Divider(color: Colors.grey.shade300)),
          ],
        ),
        const SizedBox(height: 14),

        // Price Range Input Box
        const Text(
          "Enter Price Range (₹)",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _priceRangeController,
          keyboardType: TextInputType.text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
          decoration: InputDecoration(
            prefixText: "₹ ",
            prefixStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF16A34A),
            ),
            hintText: "e.g. 150 - 250",
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF16A34A), width: 2),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Quick Range Chips
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _quickRanges.map((range) {
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() {
                  _priceRangeController.text = range;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _priceRangeController.text == range
                      ? const Color(0xFF16A34A).withValues(alpha: 0.15)
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _priceRangeController.text == range
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Text(
                  "₹$range",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _priceRangeController.text == range
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF4B5563),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: const TextStyle(
              color: Color(0xFFDC2626),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Send to Customer Button
        ElevatedButton(
          onPressed: _isSending ? null : _sendPriceRange,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _isSending
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_rounded, size: 18, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      "Send to Customer",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildWaitingView() {
    if (_isCustomerAccepted) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF16A34A),
              size: 54,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "Customer Accepted!",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Opening order & bill page...",
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 68,
                height: 68,
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    const Color(0xFF2563EB),
                  ),
                ),
              ),
              const Icon(
                Icons.hourglass_top_rounded,
                color: Color(0xFF2563EB),
                size: 30,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Waiting for Customer Acknowledgement",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Estimated Range Sent: ",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E40AF),
                ),
              ),
              Text(
                "₹${_priceRangeController.text}",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E3A8A),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Customer is reviewing the price range in their app. Once they accept, this page will automatically open the Bill page.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),

        // Option to call customer again
        OutlinedButton.icon(
          onPressed: _makeCustomerCall,
          icon: const Icon(Icons.phone_rounded, size: 18, color: Color(0xFF16A34A)),
          label: const Text(
            "Call Customer Again",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF16A34A),
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 14),

        // Locked notice: strictly locked until customer approves
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 18, color: Color(0xFF4B5563)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Order & Customer Bill page is locked until customer approves the price range.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF374151),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Popup dialog shown to the Customer when the Delivery Partner sends the estimated price range.
/// Customer can accept:
/// - Sends acknowledgement to backend
/// - Navigates customer to the Order Tracking page
class CustomerPriceRangeDialog extends StatefulWidget {
  final String orderId;
  final String partnerName;
  final String partnerPhone;
  final String? partnerPhoto;
  final String priceRange;
  final VoidCallback onAccepted;
  final VoidCallback onFindAnotherPartner;
  final VoidCallback onStopOrder;
  final VoidCallback? onDeclined;

  const CustomerPriceRangeDialog({
    super.key,
    required this.orderId,
    required this.partnerName,
    required this.partnerPhone,
    this.partnerPhoto,
    required this.priceRange,
    required this.onAccepted,
    required this.onFindAnotherPartner,
    required this.onStopOrder,
    this.onDeclined,
  });

  @override
  State<CustomerPriceRangeDialog> createState() =>
      _CustomerPriceRangeDialogState();
}

class _CustomerPriceRangeDialogState extends State<CustomerPriceRangeDialog> {
  bool _isResponding = false;

  Future<void> _respond(String action) async {
    setState(() {
      _isResponding = true;
    });

    try {
      await http.post(
        ApiConfig.orderRespondPriceRange,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'order_id': widget.orderId,
          'action': action,
        }),
      ).timeout(const Duration(seconds: 5));

      if (mounted) {
        Navigator.of(context).pop();
        if (action == 'accept') {
          widget.onAccepted();
        } else {
          widget.onDeclined?.call();
        }
      }
    } catch (e) {
      debugPrint("Error responding to price range: $e");
      if (mounted) {
        Navigator.of(context).pop();
        if (action == 'accept') {
          widget.onAccepted();
        }
      }
    }
  }

  void _showDeclineOptionsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (optCtx) {
        bool optLoading = false;
        String? loadingAction;
        return StatefulBuilder(
          builder: (context, setOptState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.do_not_disturb_on_rounded, color: Color(0xFFDC2626), size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            "Price Range Declined",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Estimated price ₹${widget.priceRange} was declined. How would you like to proceed?",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Button 1: Find Another Delivery Partner
                    ElevatedButton.icon(
                      onPressed: optLoading
                          ? null
                          : () async {
                              setOptState(() {
                                optLoading = true;
                                loadingAction = 'find_another';
                              });
                              try {
                                await http.post(
                                  ApiConfig.orderRespondPriceRange,
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode({
                                    'order_id': widget.orderId,
                                    'action': 'find_another',
                                  }),
                                ).timeout(const Duration(seconds: 5));
                              } catch (e) {
                                debugPrint("Error finding another partner: $e");
                              }
                              if (context.mounted) {
                                Navigator.of(optCtx).pop(); // close decline options
                                Navigator.of(context).pop(); // close price range dialog
                                widget.onFindAnotherPartner();
                              }
                            },
                      icon: (optLoading && loadingAction == 'find_another')
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                            )
                          : const Icon(Icons.person_search_rounded, color: Colors.white, size: 20),
                      label: const Text(
                        "Find Another Delivery Partner",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Button 2: Stop Order
                    ElevatedButton.icon(
                      onPressed: optLoading
                          ? null
                          : () async {
                              setOptState(() {
                                optLoading = true;
                                loadingAction = 'stop_order';
                              });
                              try {
                                await http.post(
                                  ApiConfig.orderRespondPriceRange,
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode({
                                    'order_id': widget.orderId,
                                    'action': 'stop_order',
                                  }),
                                ).timeout(const Duration(seconds: 5));
                              } catch (e) {
                                debugPrint("Error stopping order: $e");
                              }
                              if (context.mounted) {
                                Navigator.of(optCtx).pop(); // close decline options
                                Navigator.of(context).pop(); // close price range dialog
                                widget.onStopOrder();
                              }
                            },
                      icon: (optLoading && loadingAction == 'stop_order')
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                            )
                          : const Icon(Icons.highlight_off_rounded, color: Colors.white, size: 20),
                      label: const Text(
                        "Stop Order",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Button 3: Cancel (Go back to Delivery Partner Acknowledgement popup)
                    OutlinedButton(
                      onPressed: optLoading
                          ? null
                          : () {
                              Navigator.of(optCtx).pop(); // closes only this options modal
                            },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        "Cancel",
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _callPartner() async {
    final cleanPhone = widget.partnerPhone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isNotEmpty) {
      await launchUrl(Uri.parse('tel:$cleanPhone'), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Badge
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 16, color: Color(0xFFD97706)),
                    SizedBox(width: 4),
                    Text(
                      "Delivery Partner Acknowledgement",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            const Text(
              "Estimated Price Range",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Your delivery partner has reviewed your order and estimated the following price range:",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),

            // Price Range Highlight Card
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    "ESTIMATED BUDGET",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF15803D),
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "₹ ${widget.priceRange}",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF14532D),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Partner details row
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF16A34A).withValues(alpha: 0.15),
                    backgroundImage: (widget.partnerPhoto != null && widget.partnerPhoto!.isNotEmpty)
                        ? ResizeImage(NetworkImage(widget.partnerPhoto!), width: 120)
                        : null,
                    child: (widget.partnerPhoto == null || widget.partnerPhoto!.isEmpty)
                        ? const Icon(Icons.two_wheeler_rounded, color: Color(0xFF16A34A), size: 22)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.partnerName.isNotEmpty ? widget.partnerName : 'Delivery Partner',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const Text(
                          "Ready to purchase items",
                          style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  ),
                  if (widget.partnerPhone.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.phone_rounded, color: Color(0xFF16A34A)),
                      onPressed: _callPartner,
                      tooltip: "Call Partner",
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Action Buttons
            ElevatedButton(
              onPressed: _isResponding ? null : () => _respond('accept'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isResponding
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Accept & Track Order",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),

            TextButton(
              onPressed: _isResponding ? null : _showDeclineOptionsDialog,
              child: Text(
                "Decline Price Range",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
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

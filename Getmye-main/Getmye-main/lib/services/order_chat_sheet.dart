import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api_config.dart';
import '../theme/app_theme.dart';
import 'app_notification_service.dart';

class OrderChatSheet extends StatefulWidget {
  final String orderId;
  final String senderRole; // 'customer' or 'partner'
  final String otherPartyName;
  final String? otherPartyPhone;

  const OrderChatSheet({
    super.key,
    required this.orderId,
    this.senderRole = 'partner',
    this.otherPartyName = 'Customer',
    this.otherPartyPhone,
  });

  static void show(
    BuildContext context, {
    required String orderId,
    String senderRole = 'partner',
    String? otherPartyName,
    String? otherPartyPhone,
    String? partnerName,
    String? customerName,
  }) {
    final effectiveRole = senderRole;
    final effectiveOtherName = otherPartyName ??
        (effectiveRole == 'partner'
            ? (customerName ?? 'Customer')
            : (partnerName ?? 'Delivery Partner'));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OrderChatSheet(
        orderId: orderId,
        senderRole: effectiveRole,
        otherPartyName: effectiveOtherName,
        otherPartyPhone: otherPartyPhone,
      ),
    );
  }

  @override
  State<OrderChatSheet> createState() => _OrderChatSheetState();
}

class _OrderChatSheetState extends State<OrderChatSheet> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  Timer? _pollTimer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    AppNotificationService.isChatOpen = true;
    AppNotificationService.activeChatOrderId = widget.orderId;
    _loadLocalMessages();
    _fetchRemoteMessages();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _fetchRemoteMessages();
    });
  }

  @override
  void dispose() {
    AppNotificationService.isChatOpen = false;
    AppNotificationService.activeChatOrderId = null;
    _pollTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatCurrentTime() {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  Future<void> _loadLocalMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'order_${widget.orderId}_chat_messages';
      final raw = prefs.getString(key);
      if (raw != null) {
        final List list = jsonDecode(raw);
        if (mounted) {
          setState(() {
            _messages.clear();
            _messages.addAll(list.map((e) => Map<String, dynamic>.from(e)));
            _isLoading = false;
          });
          _scrollToBottom();
        }
      } else {
        if (mounted) {
          setState(() {
            _messages.clear();
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveLocalMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'order_${widget.orderId}_chat_messages';
      await prefs.setString(key, jsonEncode(_messages));
      await prefs.setInt('global_last_seen_msg_count_${widget.orderId}', _messages.length);
      await prefs.setInt('global_last_seen_msg_count_${widget.senderRole}_${widget.orderId}', _messages.length);
    } catch (_) {}
  }

  Future<void> _fetchRemoteMessages() async {
    try {
      final res = await http.get(ApiConfig.orderMessages(widget.orderId)).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List remoteList = data['messages'] ?? [];
        if (mounted) {
          final mapped = remoteList.map((e) => Map<String, dynamic>.from(e)).toList();
          final hadChange = _messages.length != mapped.length;



          setState(() {
            _messages.clear();
            _messages.addAll(mapped);
            _isLoading = false;
          });
          _saveLocalMessages();
          if (hadChange) {
            _scrollToBottom();
          }
        }
      } else {
        if (mounted && _isLoading) {
          setState(() => _isLoading = false);
        }
      }
    } catch (_) {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final String myName = widget.senderRole == 'customer'
        ? (prefs.getString('name') ?? prefs.getString('user_name') ?? 'Customer')
        : (prefs.getString('d_name') ?? prefs.getString('partner_name') ?? 'Delivery Partner');

    final timeStr = _formatCurrentTime();
    final newMsg = {
      'sender': widget.senderRole,
      'sender_name': myName,
      'text': text,
      'time': timeStr,
      'timestamp': DateTime.now().toIso8601String(),
    };

    setState(() {
      _messages.add(newMsg);
      _msgController.clear();
    });
    _saveLocalMessages();
    _scrollToBottom();

    try {
      final res = await http.post(
        ApiConfig.orderSendMessage(widget.orderId),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(newMsg),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List remoteList = data['messages'] ?? [];
        if (mounted && remoteList.isNotEmpty) {
          setState(() {
            _messages.clear();
            _messages.addAll(remoteList.map((e) => Map<String, dynamic>.from(e)));
          });
          _saveLocalMessages();
          _scrollToBottom();
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isCustomer = widget.senderRole == 'customer';

    return Container(
      height: MediaQuery.of(context).size.height * 0.75 + bottomInset,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.5)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(
                    widget.otherPartyName.trim().isNotEmpty
                        ? widget.otherPartyName.trim().substring(0, 1).toUpperCase()
                        : (isCustomer ? 'D' : 'C'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCustomer
                            ? widget.otherPartyName
                            : "${widget.otherPartyName} (Customer)",
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        "Order #${widget.orderId} • Live Order Chat",
                        style: const TextStyle(fontSize: 11, color: AppColors.primaryDark, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Messages List
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primaryDark, size: 30),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              "No messages yet for this order",
                              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isCustomer
                                  ? "Say hi or share landmarks with your delivery partner!"
                                  : "Ask for location updates or give delivery ETA!",
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['sender'] == widget.senderRole;
                          final time = msg['time'] ?? '';

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(
                                color: isMe ? AppColors.primary : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 16),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  if (!isMe) ...[
                                    Text(
                                      msg['sender_name']?.toString().isNotEmpty == true
                                          ? msg['sender_name'].toString()
                                          : (widget.senderRole == 'customer' ? 'Delivery Partner' : 'Customer'),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primaryDark,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                  ],
                                  Text(
                                    msg['text']?.toString() ?? '',
                                    style: TextStyle(
                                      color: isMe ? Colors.white : AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        time,
                                        style: TextStyle(
                                          color: isMe ? Colors.white70 : AppColors.textSecondary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.done_all_rounded, color: Colors.white70, size: 12),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Message Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFF1F5F9), width: 1.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: TextField(
                      controller: _msgController,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: "Type a message...",
                        hintStyle: TextStyle(fontSize: 13, color: AppColors.textMuted),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.send_rounded, size: 20),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

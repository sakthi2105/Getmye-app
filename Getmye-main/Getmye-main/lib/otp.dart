import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/ppp.dart';
import 'api_config.dart';
import 'services/app_notification_service.dart';
import 'theme/app_theme.dart';

class OtpScreen extends StatefulWidget {
  final String mobileNumber;
  final String? otpFromBackend;

  const OtpScreen({super.key, required this.mobileNumber, required this.otpFromBackend});

  @override
  _OtpScreenState createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  late Timer _timer;
  int _remainingTime = 30;
  bool _isButtonEnabled = false;
  String? _currentOtpFromBackend;
  List<String> otpValues = ['', '', '', '', '', ''];
  List<FocusNode> focusNodes = List.generate(6, (index) => FocusNode());

  @override
  void initState() {
    super.initState();
    _currentOtpFromBackend = widget.otpFromBackend;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_remainingTime > 0) {
            _remainingTime--;
          } else {
            _timer.cancel();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    for (var node in focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onOtpChanged(String value, int index) {
    if (value.isNotEmpty && index < 5) {
      FocusScope.of(context).requestFocus(focusNodes[index + 1]);
    } else if (value.isEmpty && index > 0) {
      FocusScope.of(context).requestFocus(focusNodes[index - 1]);
    }
    setState(() {
      otpValues[index] = value;
      _isButtonEnabled = otpValues.every((element) => element.isNotEmpty);
    });
  }

  void _onOtpSubmit() async {
    String enteredOtp = otpValues.join();
    final expectedOtp = _currentOtpFromBackend ?? widget.otpFromBackend;

    bool isValid = (expectedOtp != null && enteredOtp == expectedOtp);

    // Also verify directly against database via backend API
    if (!isValid) {
      try {
        final res = await http.post(
          ApiConfig.profileVerifyOtp,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'mobile_number': widget.mobileNumber,
            'otp': enteredOtp,
          }),
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['success'] == true) {
            isValid = true;
          }
        }
      } catch (_) {}
    }

    if (isValid) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text("Invalid OTP! Please enter the exact OTP sent to your mobile number."),
                ),
              ],
            ),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _remainingTime = 30;
      _startTimer();
      otpValues = ['', '', '', '', '', ''];
      for (var node in focusNodes) {
        node.unfocus();
      }
    });

    try {
      final response = await http.post(
        ApiConfig.profile,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'mobile_number': widget.mobileNumber}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newOtp = data['otp']?.toString();
        if (newOtp != null) {
          await AppNotificationService.showOtpNotification(newOtp, targetMobile: widget.mobileNumber);
          setState(() {
            _currentOtpFromBackend = newOtp;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("A new OTP was dispatched to +91 ${widget.mobileNumber}"),
                backgroundColor: const Color(0xFF15803D),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Error resending OTP: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icon Header
                  Center(
                    child: Container(
                      height: 64,
                      width: 64,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.primarySubtle, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.mark_email_read_outlined,
                        size: 32,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Typography
                  const Text(
                    'Verify Code',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                      children: [
                        const TextSpan(text: 'Enter the 6-digit code sent to\n'),
                        TextSpan(
                          text: '+91 ${widget.mobileNumber}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // OTP Input Boxes Card
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: List.generate(6, (index) {
                            final hasValue = otpValues[index].isNotEmpty;
                            return Expanded(
                              child: Container(
                                height: 52,
                                margin: EdgeInsets.only(
                                  left: index == 0 ? 0 : 3,
                                  right: index == 5 ? 0 : 3,
                                ),
                                decoration: BoxDecoration(
                                  color: hasValue ? AppColors.primaryLight : AppColors.background,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: hasValue ? AppColors.primary : AppColors.border,
                                    width: hasValue ? 1.8 : 1.2,
                                  ),
                                ),
                                child: Center(
                                  child: TextField(
                                    focusNode: focusNodes[index],
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    maxLength: 1,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    onChanged: (value) => _onOtpChanged(value, index),
                                    decoration: const InputDecoration(
                                      counterText: '',
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      filled: false,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 24),

                        // Timer Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.timer_outlined,
                                size: 16,
                                color: AppColors.primaryDark,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '00:${_remainingTime.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Submit Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isButtonEnabled ? _onOtpSubmit : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: AppColors.border,
                              disabledForegroundColor: AppColors.textMuted,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Verify & Proceed',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Resend Action
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Didn't receive the code? ",
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      TextButton(
                        onPressed: _remainingTime == 0 ? _resendOtp : null,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: AppColors.primaryDark,
                        ),
                        child: Text(
                          'Resend OTP',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _remainingTime == 0
                                ? AppColors.primaryDark
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DeltrockApp {}

class NextPage extends StatelessWidget {
  const NextPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home Page'),
      ),
      body: Center(
        child: Text(
          'Welcome to the next page!',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}

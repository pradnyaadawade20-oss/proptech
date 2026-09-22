import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/route_names.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _sendOtp() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }
    if (_phoneController.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 10-digit phone number')),
      );
      return;
    }
    context.push(
      RouteNames.otpVerification,
      extra: {'name': _nameController.text.trim(), 'phone': _phoneController.text.trim()},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xxl),
              Text('Welcome to PropTech', style: AppTextStyles.h1),
              const SizedBox(height: AppSpacing.xs),
              Text('Enter your details to continue', style: AppTextStyles.bodyMedium),
              const SizedBox(height: AppSpacing.xl),
              AppTextField(
                hint: 'Full name',
                controller: _nameController,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                hint: 'Phone number',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                prefixIcon: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('+91', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Send OTP',
                onPressed: _sendOtp,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
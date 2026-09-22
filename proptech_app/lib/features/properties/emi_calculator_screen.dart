import 'dart:math';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';

/// EMI Calculator — computes monthly EMI, total interest, and total
/// payment for a given loan amount, interest rate, and tenure.
class EmiCalculatorScreen extends StatefulWidget {
  final double? initialLoanAmount;

  const EmiCalculatorScreen({super.key, this.initialLoanAmount});

  @override
  State<EmiCalculatorScreen> createState() => _EmiCalculatorScreenState();
}

class _EmiCalculatorScreenState extends State<EmiCalculatorScreen> {
  late double _loanAmount;
  double _interestRate = 8.5; // annual %
  double _tenureYears = 20;

  static const double _minLoan = 100000;
  static const double _maxLoan = 20000000;

  @override
  void initState() {
    super.initState();
    _loanAmount = (widget.initialLoanAmount ?? 5000000).clamp(_minLoan, _maxLoan);
  }

  double get _monthlyEmi {
    final principal = _loanAmount;
    final monthlyRate = _interestRate / 12 / 100;
    final months = (_tenureYears * 12).round();
    if (monthlyRate == 0) return principal / months;
    final factor = pow(1 + monthlyRate, months);
    return (principal * monthlyRate * factor) / (factor - 1);
  }

  double get _totalPayment => _monthlyEmi * (_tenureYears * 12).round();

  double get _totalInterest => _totalPayment - _loanAmount;

  String _formatCurrency(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)} L';
    return '₹${v.toStringAsFixed(0)}';
  }

  String _formatFull(double v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final posFromEnd = s.length - i;
      if (i != 0 && posFromEnd % 2 == 0 && posFromEnd != s.length) {
        if (posFromEnd == 3 || (posFromEnd > 3 && (posFromEnd - 3) % 2 == 0)) {
          buf.write(',');
        }
      }
      buf.write(s[i]);
    }
    return '₹$buf';
  }

  static const Color _cream = Color(0xFFFBEBD3);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.calculate_outlined, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('EMI Calculator', style: AppTextStyles.h3),
          ],
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Plan your\nhome loan EMI',
            style: AppTextStyles.h1.copyWith(height: 1.2),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Adjust the loan amount, interest rate and tenure to estimate your monthly payout.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          _resultCard(),
          const SizedBox(height: AppSpacing.lg),
          _sliderCard(
            label: 'Loan Amount',
            value: _formatCurrency(_loanAmount),
            slider: Slider(
              value: _loanAmount,
              min: _minLoan,
              max: _maxLoan,
              divisions: 199,
              activeColor: AppColors.primary,
              onChanged: (v) => setState(() => _loanAmount = v),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _sliderCard(
            label: 'Interest Rate',
            value: '${_interestRate.toStringAsFixed(2)}%',
            slider: Slider(
              value: _interestRate,
              min: 5,
              max: 15,
              divisions: 200,
              activeColor: AppColors.primary,
              onChanged: (v) => setState(() => _interestRate = v),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _sliderCard(
            label: 'Loan Tenure',
            value: '${_tenureYears.toStringAsFixed(0)} yrs',
            slider: Slider(
              value: _tenureYears,
              min: 1,
              max: 30,
              divisions: 29,
              activeColor: AppColors.primary,
              onChanged: (v) => setState(() => _tenureYears = v),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _breakdownCard(),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _resultCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        children: [
          Text(
            'Monthly EMI',
            style: AppTextStyles.bodyMedium.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _formatFull(_monthlyEmi),
            style: AppTextStyles.h1.copyWith(color: Colors.white, fontSize: 32),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _cream,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              'for ${_tenureYears.toStringAsFixed(0)} years @ ${_interestRate.toStringAsFixed(2)}%',
              style: AppTextStyles.caption.copyWith(color: AppColors.primaryDark, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sliderCard({required String label, required String value, required Widget slider}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: AppTextStyles.bodyMedium),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(value, style: AppTextStyles.h3.copyWith(fontSize: 14, color: AppColors.primaryDark)),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: slider,
          ),
        ],
      ),
    );
  }

  Widget _breakdownCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _cream,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        children: [
          _breakdownRow('Principal Amount', _formatFull(_loanAmount)),
          const Divider(height: AppSpacing.lg, color: AppColors.primaryDark),
          _breakdownRow('Total Interest', _formatFull(_totalInterest)),
          const Divider(height: AppSpacing.lg, color: AppColors.primaryDark),
          _breakdownRow('Total Payment', _formatFull(_totalPayment), bold: true),
        ],
      ),
    );
  }

  Widget _breakdownRow(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primaryDark)),
        Text(
          value,
          style: bold
              ? AppTextStyles.h3.copyWith(fontSize: 15, color: AppColors.primaryDark)
              : AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600, color: AppColors.primaryDark),
        ),
      ],
    );
  }
}
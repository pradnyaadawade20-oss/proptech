import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import 'agreement_service.dart';

/// Step 1: tenant (or owner) requests a rental/sale agreement for a property.
/// On confirm, this creates the Agreement (status = requested) via the
/// backend and takes the user straight to the draft screen.
class AgreementRequestScreen extends StatefulWidget {
  final String propertyId;
  final String propertyTitle;
  final String propertyImageUrl;
  final String counterpartyName; // the other party (owner if tenant is requesting, etc.)
  final String ownerId;
  final String tenantId;

  const AgreementRequestScreen({
    super.key,
    required this.propertyId,
    required this.propertyTitle,
    required this.propertyImageUrl,
    required this.counterpartyName,
    required this.ownerId,
    required this.tenantId,
  });

  @override
  State<AgreementRequestScreen> createState() => _AgreementRequestScreenState();
}

class _AgreementRequestScreenState extends State<AgreementRequestScreen> {
  bool _submitting = false;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final agreement = await AgreementService.instance.create(
        propertyId: widget.propertyId,
        ownerId: widget.ownerId,
        tenantId: widget.tenantId,
      );
      if (!mounted) return;
      // Replace this screen with the draft screen so back doesn't re-submit.
      context.pushReplacement(
        RouteNames.agreementDraft.replaceFirst(':id', agreement.id),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send request: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text('Request Agreement', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        widget.propertyImageUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 64,
                          height: 64,
                          color: AppColors.surfaceSoft,
                          child: const Icon(Icons.home_outlined, color: AppColors.textHint),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.propertyTitle,
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text('With ${widget.counterpartyName}',
                              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'What happens next',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 12),
              _step('1', 'The owner prepares the agreement draft — rent, deposit, and terms.'),
              _step('2', 'You review the draft and can request changes.'),
              _step('3', 'Both parties sign electronically — draw or type your signature.'),
              _step('4', 'Once both sign, the agreement is completed and available to download.'),
              const Spacer(),
              AppButton(
                label: 'Send Agreement Request',
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primaryLight,
            child: Text(number, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
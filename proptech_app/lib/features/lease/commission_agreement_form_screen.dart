import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/api/token_store.dart';
import '../agreement/signature_screen.dart';
import '../profile/profile_service.dart';
import '../properties/property.dart';
import '../properties/property_service.dart';
import 'commission_service.dart';
import 'lease_widgets.dart';

/// Broker: after the visit, when the tenant is interested, create the commission agreement and sign it.
class CommissionAgreementFormScreen extends StatefulWidget {
  const CommissionAgreementFormScreen({super.key});

  @override
  State<CommissionAgreementFormScreen> createState() => _CommissionAgreementFormScreenState();
}

class _CommissionAgreementFormScreenState extends State<CommissionAgreementFormScreen> {
  final _email = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  List<Property> _properties = const [];
  String? _propertyId;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final userId = await TokenStore.instance.getUserId();
      if (userId == null) throw Exception('Please log in again.');
      final all = await PropertyService.instance.getByOwner(userId);
      final mine = all.where((p) => p.postedBy == 'broker').toList();
      if (!mounted) return;
      setState(() {
        _properties = mine;
        _propertyId = mine.length == 1 ? mine.first.id : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final amount = double.tryParse(_amount.text.trim());
    if (_propertyId == null) return snack(context, 'Choose the property.', error: true);
    if (!email.contains('@') || !email.contains('.')) return snack(context, "Enter the tenant's email.", error: true);
    if (amount == null || amount < 1) return snack(context, 'Enter the commission amount.', error: true);

    setState(() => _saving = true);
    String myName = '';
    try {
      myName = (await ProfileService.instance.getMyProfile()).name;
    } catch (_) {}
    if (!mounted) return;
    setState(() => _saving = false);

    final sign = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(builder: (_) => SignatureScreen(agreementId: 'new', signerName: myName)),
    );
    if (sign == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await CommissionService.instance.create(
        propertyId: _propertyId!,
        tenantEmail: email,
        amount: amount,
        note: _note.text.trim(),
        signatureType: sign['signatureType']!,
        signatureData: sign['signatureData']!,
      );
      if (!mounted) return;
      snack(context, 'Sent to the tenant. They can now review and sign it.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      snack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary);
    return Scaffold(
      appBar: AppBar(title: const Text('New commission agreement')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_loadError!)))
              : _properties.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('You have no broker listings yet. Post a property first.', textAlign: TextAlign.center, style: hint),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        Text(
                          'Create this after the visit, when the tenant is interested. The tenant signs it first, then can '
                          'request the rental agreement. The commission is paid in the app after the rental agreement is signed.',
                          style: hint,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        DropdownButtonFormField<String>(
                          value: _propertyId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Property'),
                          items: [
                            for (final p in _properties)
                              DropdownMenuItem(value: p.id, child: Text('${p.title} - ${p.location}', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setState(() => _propertyId = v),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: "Tenant's email",
                            helperText: 'The tenant must have signed up on PropTech with this email.',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _amount,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Commission (₹)', prefixText: '₹ '),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _note,
                          maxLength: 200,
                          decoration: const InputDecoration(labelText: 'Note (optional)'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _submit,
                          icon: const Icon(Icons.draw_outlined, size: 18),
                          label: const Text('Review & sign'),
                        ),
                      ],
                    ),
    );
  }
}
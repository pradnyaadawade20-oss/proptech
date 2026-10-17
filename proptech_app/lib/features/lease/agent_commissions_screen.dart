import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/session/user_session.dart';
import 'commission_agreement_form_screen.dart';
import 'commission_agreement_screen.dart';
import 'commission_service.dart';
import 'lease_widgets.dart';

/// "Commission agreements": brokers see the ones they sent (and can create new), tenants see the ones
/// sent to them (to sign). Tap one to open it.
class CommissionAgreementsScreen extends StatefulWidget {
  const CommissionAgreementsScreen({super.key});

  @override
  State<CommissionAgreementsScreen> createState() => _CommissionAgreementsScreenState();
}

class _CommissionAgreementsScreenState extends State<CommissionAgreementsScreen> {
  late Future<List<CommissionAgreement>> _future = CommissionService.instance.list();

  void _reload() => setState(() => _future = CommissionService.instance.list());

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isBroker = UserSession.instance.currentRole.value == UserRole.broker;
    return Scaffold(
      appBar: AppBar(title: const Text('Commission agreements')),
      floatingActionButton: isBroker
          ? FloatingActionButton.extended(
              onPressed: () => _open(const CommissionAgreementFormScreen()),
              icon: const Icon(Icons.add),
              label: const Text('New'),
            )
          : null,
      body: FutureBuilder<List<CommissionAgreement>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(snap.error.toString().replaceFirst('Exception: ', ''))));
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  isBroker
                      ? 'Nothing here yet. After a visit, when the tenant is interested, tap New to create a commission agreement.'
                      : 'No commission agreements yet. If a broker listing needs one, the agent will send it to you here.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final c = items[i];
                final other = c.isAgent ? 'Tenant: ${c.tenantName}' : 'Agent: ${c.agentName}';
                final needsMe = c.isTenant && c.status == 'sent';
                final color = c.paid ? AppColors.success : (needsMe ? AppColors.warning : AppColors.textSecondary);
                return InkWell(
                  onTap: () => _open(CommissionAgreementScreen(id: c.id)),
                  child: SectionCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.propertyTitle, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(other, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Text(inr(c.amount), style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            needsMe ? 'Needs your signature' : c.statusLabel,
                            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                      ]),
                    ]),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
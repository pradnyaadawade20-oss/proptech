import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/widgets/safe_network_image.dart';
import 'lease_activity_tab.dart';
import 'lease_deposit_tab.dart';
import 'lease_models.dart';
import 'lease_photos_tab.dart';
import 'lease_rent_tab.dart';
import 'lease_service.dart';
import 'lease_widgets.dart';

/// One lease: Overview / Rent / Deposit / Photos / Activity.
/// Route: /lease/:id (also the target of lease/rent/deposit push notifications).
class LeaseDetailScreen extends StatefulWidget {
  final String leaseId;
  const LeaseDetailScreen({super.key, required this.leaseId});

  @override
  State<LeaseDetailScreen> createState() => _LeaseDetailScreenState();
}

class _LeaseDetailScreenState extends State<LeaseDetailScreen> {
  Lease? _lease;
  String _role = '';
  String? _error;
  int _rev = 0; // bumped on every reload so the tabs refetch their data

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (l, role) = await LeaseService.instance.getLease(widget.leaseId);
      if (!mounted) return;
      setState(() {
        _lease = l;
        _role = role;
        _error = null;
        _rev++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lease = _lease;
    if (lease == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lease')),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _load, child: const Text('Retry')),
                  ]),
                ),
        ),
      );
    }

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(lease.propertyTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Rent'),
              Tab(text: 'Deposit'),
              Tab(text: 'Photos'),
              Tab(text: 'Activity'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(lease: lease, role: _role, onChanged: _load),
            LeaseRentTab(key: ValueKey('rent$_rev'), lease: lease, role: _role, onChanged: _load),
            LeaseDepositTab(key: ValueKey('dep$_rev'), lease: lease, role: _role, onChanged: _load),
            LeasePhotosTab(key: ValueKey('pho$_rev'), lease: lease, role: _role, onChanged: _load),
            LeaseActivityTab(key: ValueKey('act$_rev'), lease: lease),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Overview
// ======================================================================

class _OverviewTab extends StatelessWidget {
  final Lease lease;
  final String role;
  final Future<void> Function() onChanged;
  const _OverviewTab({required this.lease, required this.role, required this.onChanged});

  bool get _tenant => role == 'tenant';
  bool get _owner => role == 'owner';

  String get _img =>
      lease.propertyImageUrl.startsWith('/') ? '${LeaseService.instance.baseUrl}${lease.propertyImageUrl}' : lease.propertyImageUrl;

  String _noticeOpensOn() {
    final end = DateTime.tryParse(lease.endDate);
    if (end == null) return '';
    return fmtDate(ymd(end.subtract(const Duration(days: 90))));
  }

  Future<void> _requestRenewal(BuildContext context) async {
    if (!await confirmDialog(context, 'Request renewal', 'Ask ${lease.ownerName} to renew this lease?', yes: 'Send request')) return;
    if (!context.mounted) return;
    if (await runGuarded(context, () => LeaseService.instance.requestRenewal(lease.id), success: 'Renewal requested')) {
      await onChanged();
    }
  }

  Future<void> _giveNotice(BuildContext context) async {
    final now = DateTime.now();
    final date = await askDate(context, first: now, last: now.add(const Duration(days: 730)), initial: DateTime.tryParse(lease.endDate));
    if (date == null || !context.mounted) return;
    if (!await confirmDialog(context, 'Give notice', 'Tell ${lease.ownerName} you will move out on ${fmtDate(date)}?', yes: 'Give notice')) return;
    if (!context.mounted) return;
    if (await runGuarded(context, () => LeaseService.instance.giveNotice(lease.id, date), success: 'Notice sent')) {
      await onChanged();
    }
  }

  Future<void> _confirmMoveIn(BuildContext context) async {
    if (!await confirmDialog(
      context,
      'Confirm move-in',
      'This locks the move-in photos. They will be used to compare the condition when you move out. Continue?',
      yes: 'Confirm',
    )) return;
    if (!context.mounted) return;
    if (await runGuarded(context, () => LeaseService.instance.confirmMoveIn(lease.id), success: 'Move-in confirmed')) {
      await onChanged();
    }
  }

  Future<void> _respondRenewal(BuildContext context, bool accept) async {
    double? rent;
    int? months;
    if (accept) {
      final terms = await showDialog<({double? rent, int? months})>(
        context: context,
        builder: (_) => _RenewalTermsDialog(currentRent: lease.monthlyRent),
      );
      if (terms == null || !context.mounted) return;
      rent = terms.rent;
      months = terms.months;
    } else if (!await confirmDialog(context, 'Decline renewal', 'The tenant will be asked to plan the move-out.', yes: 'Decline')) {
      return;
    }
    if (!context.mounted) return;
    String? newAgreement;
    final ok = await runGuarded(context, () async {
      newAgreement = await LeaseService.instance.respondRenewal(lease.id, accept, rent: rent, months: months);
    }, success: accept ? 'Renewal accepted. A new agreement was created.' : 'Renewal declined');
    if (ok) {
      await onChanged();
      if (accept && newAgreement != null && context.mounted) context.push('/agreement/$newAgreement/status');
    }
  }

  Future<void> _completeMoveOut(BuildContext context) async {
    if (!await confirmDialog(
      context,
      'Confirm move-out',
      'Confirm the tenant has moved out. You need at least one move-out photo first. The property becomes available again.',
      yes: 'Confirm',
    )) return;
    if (!context.mounted) return;
    if (await runGuarded(context, () => LeaseService.instance.completeMoveOut(lease.id), success: 'Move-out confirmed')) {
      await onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cap = lease.monthlyRent * 0.10;
    final newAgr = lease.renewedAgreementId;

    return RefreshIndicator(
      onRefresh: onChanged,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: SafeNetworkImage(_img, width: double.infinity, height: 150),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(child: Text(lease.propertyTitle, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600))),
            StatusPill.status(lease.status),
          ]),
          const SizedBox(height: AppSpacing.md),

          // ---- banners
          if (lease.overdueCount > 0)
            InfoBanner('${lease.overdueCount} rent payment${lease.overdueCount > 1 ? 's are' : ' is'} overdue. Check the Rent tab.',
                color: AppColors.error, icon: Icons.warning_amber_rounded),
          if (lease.status == 'notice_given')
            InfoBanner('Move-out is planned for ${fmtDate(lease.moveOutDate)}.', color: AppColors.warning, icon: Icons.logout),
          if (lease.status == 'moved_out')
            const InfoBanner('The tenant has moved out. The deposit settlement is in progress.', color: AppColors.success, icon: Icons.check_circle_outline),
          if (lease.renewalStatus == 'renew_requested')
            InfoBanner(_owner ? '${lease.tenantName} asked to renew this lease.' : 'Renewal requested. Waiting for ${lease.ownerName} to respond.',
                color: AppColors.warning, icon: Icons.autorenew),
          if (lease.renewalStatus == 'renew_declined')
            const InfoBanner('Renewal was declined. Please plan the move-out.', color: AppColors.error, icon: Icons.event_busy),
          if (lease.renewalStatus == 'renew_accepted')
            const InfoBanner('Renewal accepted. A new agreement has been created for signing.', color: AppColors.success, icon: Icons.verified_outlined),
          if (_tenant && lease.status == 'active' && lease.moveInConfirmedAt == null)
            InfoBanner('Review the move-in photos (Photos tab) and confirm the condition of the property.', icon: Icons.photo_camera_outlined),

          // ---- terms
          SectionCard(
            title: 'Lease terms',
            child: Column(children: [
              InfoRow('Monthly rent', inr(lease.monthlyRent)),
              InfoRow('Security deposit', lease.securityDeposit > 0 ? inr(lease.securityDeposit) : 'None'),
              InfoRow('Start date', fmtDate(lease.startDate)),
              InfoRow('End date', fmtDate(lease.endDate)),
              if (lease.status == 'active')
                InfoRow('Time left', lease.daysToExpiry < 0 ? 'Ended' : '${lease.daysToExpiry} days'),
              InfoRow('Grace period', '${lease.graceDays} days'),
              InfoRow('Late fee', '${inr(lease.lateFeePerDay)}/day (max ${inr(cap)})'),
              if (lease.nextDueDate != null) InfoRow('Next rent due', fmtDate(lease.nextDueDate)),
            ]),
          ),
          SectionCard(
            title: 'Parties',
            child: Column(children: [
              InfoRow('Owner', lease.ownerName + (_owner ? ' (you)' : '')),
              InfoRow('Tenant', lease.tenantName + (_tenant ? ' (you)' : '')),
            ]),
          ),

          // ---- actions
          ..._actions(context, newAgr),

          OutlinedButton.icon(
            onPressed: () => context.push('/agreement/${lease.agreementId}/status'),
            icon: const Icon(Icons.description_outlined),
            label: const Text('View rental agreement'),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context, String? newAgr) {
    final out = <Widget>[];
    Widget btn(String label, VoidCallback onTap, {bool outlined = false, Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: outlined
                ? OutlinedButton(onPressed: onTap, child: Text(label))
                : ElevatedButton(
                    onPressed: onTap,
                    style: color == null ? null : ElevatedButton.styleFrom(backgroundColor: color),
                    child: Text(label)),
          ),
        );

    if (_tenant) {
      if (lease.status == 'active' && lease.moveInConfirmedAt == null) {
        out.add(btn('Confirm move-in condition', () => _confirmMoveIn(context)));
      }
      if (lease.status == 'active' && (lease.renewalStatus == 'none' || lease.renewalStatus == 'renew_declined')) {
        if (lease.daysToExpiry <= 90) {
          if (lease.renewalStatus == 'none') out.add(btn('Request renewal', () => _requestRenewal(context)));
          out.add(btn('Give notice / move out', () => _giveNotice(context), outlined: true));
        } else {
          out.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Renewal and move-out notice open on ${_noticeOpensOn()} (90 days before the lease ends).',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
          ));
        }
      }
    }

    if (_owner) {
      if (lease.renewalStatus == 'renew_requested') {
        out.add(btn('Accept renewal', () => _respondRenewal(context, true)));
        out.add(btn('Decline renewal', () => _respondRenewal(context, false), outlined: true));
      }
      if (lease.status == 'notice_given') {
        out.add(btn('Confirm tenant has moved out', () => _completeMoveOut(context)));
      }
    }

    if (lease.renewalStatus == 'renew_accepted' && newAgr != null && newAgr.isNotEmpty) {
      out.add(btn('Open new agreement', () => context.push('/agreement/$newAgr/status')));
    }
    return out;
  }
}

class _RenewalTermsDialog extends StatefulWidget {
  final double currentRent;
  const _RenewalTermsDialog({required this.currentRent});

  @override
  State<_RenewalTermsDialog> createState() => _RenewalTermsDialogState();
}

class _RenewalTermsDialogState extends State<_RenewalTermsDialog> {
  late final _rent = TextEditingController(text: widget.currentRent.toStringAsFixed(0));
  final _months = TextEditingController(text: '11');

  @override
  void dispose() {
    _rent.dispose();
    _months.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renewal terms'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _rent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'New monthly rent (₹)')),
        const SizedBox(height: 8),
        TextField(controller: _months, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duration (months)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final r = double.tryParse(_rent.text.trim());
            final m = int.tryParse(_months.text.trim());
            if (r == null || r <= 0 || m == null || m <= 0) return;
            Navigator.pop(context, (rent: r, months: m));
          },
          child: const Text('Accept'),
        ),
      ],
    );
  }
}
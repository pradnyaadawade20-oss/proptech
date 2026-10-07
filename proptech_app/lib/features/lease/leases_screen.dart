import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/widgets/safe_network_image.dart';
import 'lease_models.dart';
import 'lease_service.dart';
import 'lease_widgets.dart';

/// "My Leases" — every lease where the user is owner or tenant.
class LeasesScreen extends StatefulWidget {
  const LeasesScreen({super.key});

  @override
  State<LeasesScreen> createState() => _LeasesScreenState();
}

class _LeasesScreenState extends State<LeasesScreen> {
  late Future<List<Lease>> _future = LeaseService.instance.myLeases();

  Future<void> _reload() async {
    setState(() => _future = LeaseService.instance.myLeases());
    await _future.catchError((_) => <Lease>[]);
  }

  String _img(String u) => u.startsWith('/') ? '${LeaseService.instance.baseUrl}$u' : u;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Leases')),
      body: FutureBuilder<List<Lease>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(snap.error.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _reload, child: const Text('Retry')),
                ]),
              ),
            );
          }
          final leases = snap.data ?? [];
          if (leases.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No leases yet.\nOnce both parties sign a rental agreement, the lease appears here.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: leases.length,
              itemBuilder: (_, i) => _LeaseCard(
                lease: leases[i],
                image: _img(leases[i].propertyImageUrl),
                onTap: () async {
                  await context.push('/lease/${leases[i].id}');
                  if (mounted) _reload();
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LeaseCard extends StatelessWidget {
  final Lease lease;
  final String image;
  final VoidCallback onTap;
  const _LeaseCard({required this.lease, required this.image, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
            child: SafeNetworkImage(image, width: double.infinity, height: 130),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(lease.propertyTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                StatusPill.status(lease.status),
              ]),
              const SizedBox(height: 6),
              Text('${inr(lease.monthlyRent)} / month  •  ${fmtDate(lease.startDate)} to ${fmtDate(lease.endDate)}',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text('Owner: ${lease.ownerName}   Tenant: ${lease.tenantName}',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (lease.overdueCount > 0) StatusPill('${lease.overdueCount} overdue', AppColors.error),
                if (lease.nextDueDate != null && lease.overdueCount == 0)
                  StatusPill('Next rent ${fmtDate(lease.nextDueDate)}', AppColors.primary),
                if (lease.depositStatus.isNotEmpty) StatusPill('Deposit: ${prettify(lease.depositStatus)}', statusColor(lease.depositStatus)),
                if (lease.status == 'active' && lease.daysToExpiry <= 90 && lease.daysToExpiry >= 0)
                  StatusPill('Ends in ${lease.daysToExpiry} days', AppColors.warning),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
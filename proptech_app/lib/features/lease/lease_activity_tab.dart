import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'lease_models.dart';
import 'lease_service.dart';
import 'lease_widgets.dart';

class LeaseActivityTab extends StatefulWidget {
  final Lease lease;
  const LeaseActivityTab({super.key, required this.lease});

  @override
  State<LeaseActivityTab> createState() => _LeaseActivityTabState();
}

class _LeaseActivityTabState extends State<LeaseActivityTab> {
  late final Future<List<LeaseEvent>> _future = LeaseService.instance.events(widget.lease.id);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LeaseEvent>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return Center(child: Text(snap.error.toString().replaceFirst('Exception: ', '')));
        final events = snap.data ?? [];
        if (events.isEmpty) {
          return Center(child: Text('No activity yet.', style: GoogleFonts.inter(color: AppColors.textSecondary)));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: events.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final e = events[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primaryLight,
                child: Icon(Icons.history, size: 16, color: AppColors.primary),
              ),
              title: Text(prettify(e.event), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(
                [if (e.detail.isNotEmpty) e.detail, '${e.actorName.isEmpty ? 'System' : e.actorName} • ${fmtDateTime(e.createdAt)}'].join('\n'),
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
              ),
              isThreeLine: e.detail.isNotEmpty,
            );
          },
        );
      },
    );
  }
}
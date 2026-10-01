import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'visit.dart';
import 'visit_service.dart';

class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key});

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen> {
  late Future<List<Visit>> _future;

  /// Ids of visits requested on properties I own (I can confirm / complete
  /// those). Everything else in the list is a visit I booked myself.
  final Set<String> _ownerVisitIds = {};
  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// Visits on properties I own (visit requests) followed by visits I booked.
  Future<List<Visit>> _load() async {
    final results = await Future.wait([
      VisitService.instance.getVisits(asOwner: true),
      VisitService.instance.getVisits(),
    ]);
    _ownerVisitIds
      ..clear()
      ..addAll(results[0].map((v) => v.id));
    final all = [...results[0], ...results[1]];
    final seen = <String>{};
    final unique = all.where((v) => seen.add(v.id)).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return unique;
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future.catchError((_) => <Visit>[]);
  }

  Future<void> _changeStatus(Visit visit, VisitStatus status) async {
    if (status == VisitStatus.cancelled) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancel this visit?'),
          content: Text('The visit to ${visit.propertyTitle} will be cancelled and the other person will be notified.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, cancel')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyIds.add(visit.id));
    try {
      await VisitService.instance.updateStatus(visit.id, status);
      messenger.showSnackBar(SnackBar(content: Text('Visit marked as ${status.name}')));
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not update visit: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(visit.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visit Requests')),
      body: FutureBuilder<List<Visit>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(snapshot.error.toString().replaceFirst('Exception: ', '')),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            );
          }
          final visits = snapshot.data ?? [];
          if (visits.isEmpty) {
            return const Center(child: Text('No visit requests yet'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: visits.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final v = visits[index];
                return _VisitCard(
                  visit: v,
                  isOwner: _ownerVisitIds.contains(v.id),
                  busy: _busyIds.contains(v.id),
                  onChangeStatus: (s) => _changeStatus(v, s),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  final Visit visit;
  final bool isOwner;
  final bool busy;
  final ValueChanged<VisitStatus> onChangeStatus;
  const _VisitCard({
    required this.visit,
    required this.isOwner,
    required this.busy,
    required this.onChangeStatus,
  });

  Color _statusColor(VisitStatus status) {
    switch (status) {
      case VisitStatus.pending:
        return Colors.orange;
      case VisitStatus.confirmed:
        return Colors.blue;
      case VisitStatus.completed:
        return Colors.green;
      case VisitStatus.cancelled:
        return Colors.red;
    }
  }

  String _statusLabel(VisitStatus status) {
    switch (status) {
      case VisitStatus.pending:
        return 'Pending';
      case VisitStatus.confirmed:
        return 'Confirmed';
      case VisitStatus.completed:
        return 'Completed';
      case VisitStatus.cancelled:
        return 'Cancelled';
    }
  }

  String _dateTime(BuildContext context) {
    final d = visit.scheduledAt;
    final time = TimeOfDay.fromDateTime(d).format(context);
    return '${d.day}/${d.month}/${d.year}, $time';
  }

  /// Owner: confirm / decline a pending request, then mark it completed.
  /// Visitor: can only cancel their own booking.
  List<Widget> _actions() {
    final s = visit.status;
    if (s == VisitStatus.completed || s == VisitStatus.cancelled) return const [];

    if (isOwner) {
      if (s == VisitStatus.pending) {
        return [
          OutlinedButton(
            onPressed: busy ? null : () => onChangeStatus(VisitStatus.cancelled),
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: busy ? null : () => onChangeStatus(VisitStatus.confirmed),
            child: const Text('Confirm'),
          ),
        ];
      }
      // confirmed
      return [
        OutlinedButton(
          onPressed: busy ? null : () => onChangeStatus(VisitStatus.cancelled),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: busy ? null : () => onChangeStatus(VisitStatus.completed),
          child: const Text('Mark completed'),
        ),
      ];
    }

    return [
      OutlinedButton(
        onPressed: busy ? null : () => onChangeStatus(VisitStatus.cancelled),
        child: const Text('Cancel visit'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                child: visit.propertyImageUrl.isEmpty
                    ? Container(
                        width: 64,
                        height: 64,
                        color: AppColors.divider,
                        child: const Icon(Icons.home_outlined),
                      )
                    : Image.network(
                        visit.propertyImageUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 64,
                          height: 64,
                          color: AppColors.divider,
                          child: const Icon(Icons.home_outlined),
                        ),
                      ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(visit.propertyTitle, style: AppTextStyles.h3.copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      isOwner ? 'Visitor: ${visit.visitorName}' : 'Booked by you',
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(_dateTime(context), style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(visit.status).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  _statusLabel(visit.status),
                  style: AppTextStyles.caption.copyWith(color: _statusColor(visit.status)),
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  actions[i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
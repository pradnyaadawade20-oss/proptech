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
              itemBuilder: (context, index) => _VisitCard(visit: visits[index]),
            ),
          );
        },
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  final Visit visit;
  const _VisitCard({required this.visit});

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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
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
                Text('Visitor: ${visit.visitorName}', style: AppTextStyles.bodySmall),
                const SizedBox(height: 4),
                Text(
                  '${visit.scheduledAt.day}/${visit.scheduledAt.month}/${visit.scheduledAt.year}',
                  style: AppTextStyles.bodySmall,
                ),
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
    );
  }
}
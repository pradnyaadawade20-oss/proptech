import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'visit.dart';
import 'visit_feedback_sheet.dart';
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
  setState(() {
    _future = _load();
  });
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

  Future<void> _reschedule(Visit visit) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: visit.scheduledAt.isAfter(now) ? visit.scheduledAt : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      helpText: 'Select new date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(visit.scheduledAt),
      helpText: 'Select new time',
    );
    if (time == null || !mounted) return;

    final newTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final messenger = ScaffoldMessenger.of(context);
    if (!newTime.isAfter(now.add(const Duration(minutes: 15)))) {
      messenger.showSnackBar(const SnackBar(content: Text('Please pick a time in the future')));
      return;
    }
    if (newTime == visit.scheduledAt) {
      messenger.showSnackBar(const SnackBar(content: Text('That is the same time as the current booking')));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reschedule visit?'),
        content: Text(
          '${visit.propertyTitle}\n'
          'New time: ${newTime.day}/${newTime.month}/${newTime.year}, ${time.format(ctx)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busyIds.add(visit.id));
    try {
      await VisitService.instance.reschedule(visit.id, newTime);
      messenger.showSnackBar(const SnackBar(content: Text('Visit rescheduled')));
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not reschedule: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(visit.id));
    }
  }

  /// Owner types the OTP the buyer shows at the visit.
  Future<void> _verifyOtp(Visit visit) async {
    final controller = TextEditingController();
    String? error;
    bool loading = false;
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Verify visitor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ask ${visit.visitorName.isEmpty ? 'the visitor' : visit.visitorName} for the 6-digit OTP shown in their app.'),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: AppTextStyles.h3.copyWith(fontSize: 24, letterSpacing: 8),
                decoration: InputDecoration(counterText: '', hintText: '------', errorText: error),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      final code = controller.text.trim();
                      if (code.length != 6) {
                        setLocal(() => error = 'Enter the 6-digit OTP');
                        return;
                      }
                      setLocal(() {
                        loading = true;
                        error = null;
                      });
                      try {
                        await VisitService.instance.verifyOtp(visit.id, code);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setLocal(() {
                          loading = false;
                          error = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Verify'),
            ),
          ],
        ),
      ),
    );
    if (verified == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Visitor verified. Visit marked as completed.')),
      );
      await _refresh();
    }
  }

  Future<void> _giveFeedback(Visit visit) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
      ),
      builder: (_) => VisitFeedbackSheet(visit: visit),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks! Your feedback was shared with the owner.')),
      );
      await _refresh();
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
                  onFeedback: () => _giveFeedback(v),
                  onReschedule: () => _reschedule(v),
                  onVerifyOtp: () => _verifyOtp(v),
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
  final VoidCallback onFeedback;
  final VoidCallback onReschedule;
  final VoidCallback onVerifyOtp;
  const _VisitCard({
    required this.visit,
    required this.isOwner,
    required this.busy,
    required this.onChangeStatus,
    required this.onFeedback,
    required this.onReschedule,
    required this.onVerifyOtp,
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

    final reschedule = visit.canReschedule
        ? OutlinedButton(
            onPressed: busy ? null : onReschedule,
            child: const Text('Reschedule'),
          )
        : null;

    if (isOwner) {
      if (s == VisitStatus.pending) {
        return [
          OutlinedButton(
            onPressed: busy ? null : () => onChangeStatus(VisitStatus.cancelled),
            child: const Text('Decline'),
          ),
          if (reschedule != null) reschedule,
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
        if (reschedule != null) reschedule,
        ElevatedButton.icon(
          onPressed: busy ? null : onVerifyOtp,
          icon: const Icon(Icons.verified_user_outlined, size: 18),
          label: const Text('Verify OTP'),
        ),
      ];
    }

    return [
      OutlinedButton(
        onPressed: busy ? null : () => onChangeStatus(VisitStatus.cancelled),
        child: const Text('Cancel visit'),
      ),
      if (reschedule != null) reschedule,
    ];
  }

  /// Buyer: the OTP to tell the owner at the visit (proves who they are).
  Widget _otpSection(BuildContext context) {
    if (visit.otpPending) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm + 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_clock_outlined, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Your visit OTP will appear here after you visit the property (from ${_dateTime(context)}). Share it with the owner then.',
                style: AppTextStyles.bodySmall,
              ),
            ),
          ],
        ),
      );
    }
    if (visit.otpCode.isEmpty) {
      return Text(
        'Your visit OTP is not available (expired). Reschedule the visit to get a new one.',
        style: AppTextStyles.bodySmall,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        children: [
          Text('Your visit OTP', style: AppTextStyles.caption),
          const SizedBox(height: 4),
          Text(
            visit.otpCode,
            style: AppTextStyles.h3.copyWith(fontSize: 28, letterSpacing: 8, color: AppColors.primary),
          ),
          const SizedBox(height: 4),
          Text(
            'Tell this OTP to the owner to confirm that you visited the property.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    );
  }

  /// Visitor: give / edit feedback. Owner: sees what the visitor said.
  Widget _feedbackSection() {
    if (!visit.hasFeedback) {
      if (isOwner) {
        return Text('Waiting for visitor feedback', style: AppTextStyles.bodySmall);
      }
      return OutlinedButton.icon(
        onPressed: onFeedback,
        icon: const Icon(Icons.rate_review_outlined, size: 20),
        label: const Text('How was the visit?'),
      );
    }
    final color = feedbackColor(visit.feedbackInterest);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(feedbackIcon(visit.feedbackInterest), size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOwner ? 'Visitor: ${feedbackLabel(visit.feedbackInterest)}' : 'You: ${feedbackLabel(visit.feedbackInterest)}',
                  style: AppTextStyles.bodyMedium.copyWith(color: color, fontWeight: FontWeight.w600),
                ),
                if (visit.feedbackNote.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(visit.feedbackNote, style: AppTextStyles.bodySmall),
                ],
              ],
            ),
          ),
          if (!isOwner)
            TextButton(onPressed: onFeedback, child: const Text('Edit')),
        ],
      ),
    );
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
          InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            onTap: visit.propertyId.isEmpty
                ? null
                : () => context.push(
                      '/property/${visit.propertyId}',
                      extra: VisitContext(visit: visit, isOwner: isOwner),
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
                    Text(
                      isOwner ? 'Visitor: ${visit.visitorName}' : 'Booked by you',
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(_dateTime(context), style: AppTextStyles.bodySmall),
                    if (visit.rescheduleCount > 0)
                      Text('Rescheduled', style: AppTextStyles.caption.copyWith(color: Colors.orange)),
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
          ),
          if (!isOwner && visit.status == VisitStatus.confirmed) ...[
            const SizedBox(height: AppSpacing.sm),
            _otpSection(context),
          ],
          if (visit.status == VisitStatus.completed) ...[
            const SizedBox(height: AppSpacing.sm),
            _feedbackSection(),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'lead.dart';
import 'lead_service.dart';

const _tabs = <(String label, String status)>[
  ('All', ''),
  ('New', 'new'),
  ('Contacted', 'contacted'),
  ('Visited', 'visited'),
  ('Closed', 'closed'),
];

/// Owner / Broker "Leads" inbox: everyone who enquired on my properties.
class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ScrollController _scroll = ScrollController();

  final List<Lead> _leads = [];
  LeadCounts _counts = const LeadCounts();
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  String get _status => _tabs[_tabController.index].$2;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) _load();
      });
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final page = await LeadService.instance.getMyLeads(status: _status, page: 1);
      if (!mounted) return;
      setState(() {
        _leads
          ..clear()
          ..addAll(page.items);
        _counts = page.counts;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await LeadService.instance.getMyLeads(status: _status, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _page++;
        _leads.addAll(page.items);
        _hasMore = page.hasMore;
      });
    } catch (_) {
      // keep what we have; user can scroll again to retry
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _setStatus(Lead lead, String status) async {
    if (lead.status == status) return;
    try {
      await LeadService.instance.updateStatus(lead.id, status);
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _call(Lead lead) async {
    if (lead.phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: lead.phone.replaceAll(RegExp(r'[^0-9+]'), ''));
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open dialer for ${lead.phone}')));
      return;
    }
    if (lead.status == 'new') _setStatus(lead, 'contacted');
  }

  void _chat(Lead lead) {
    context.push('/chats/${lead.buyerId}?propertyId=${lead.propertyId}');
    if (lead.status == 'new') _setStatus(lead, 'contacted');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leads'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final t in _tabs) Tab(text: '${t.$1} (${_counts.forStatus(t.$2)})'),
          ],
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.bodyMedium),
              const SizedBox(height: AppSpacing.sm),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_leads.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            const Icon(Icons.people_outline, size: 56, color: AppColors.textHint),
            const SizedBox(height: AppSpacing.sm),
            Center(child: Text('No leads here yet', style: AppTextStyles.h3)),
            const SizedBox(height: 4),
            Center(
              child: Text('When someone contacts you about a property, it shows up here.',
                  style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _leads.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) {
          if (i >= _leads.length) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final lead = _leads[i];
          return _LeadCard(
            lead: lead,
            onCall: () => _call(lead),
            onChat: () => _chat(lead),
            onStatus: (s) => _setStatus(lead, s),
            onOpenProperty: () => context.push('/property/${lead.propertyId}'),
          );
        },
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  final Lead lead;
  final VoidCallback onCall;
  final VoidCallback onChat;
  final VoidCallback onOpenProperty;
  final ValueChanged<String> onStatus;
  const _LeadCard({
    required this.lead,
    required this.onCall,
    required this.onChat,
    required this.onStatus,
    required this.onOpenProperty,
  });

  static Color _statusColor(String s) {
    switch (s) {
      case 'new':
        return AppColors.primary;
      case 'contacted':
        return AppColors.warning;
      case 'visited':
        return AppColors.secondary;
      default:
        return AppColors.textSecondary;
    }
  }

  static String _sourceLabel(String s) {
    switch (s) {
      case 'call':
        return 'Called';
      case 'chat':
        return 'Chatted';
      case 'visit':
        return 'Booked visit';
      default:
        return 'Enquiry';
    }
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(lead.status);
    final name = lead.name.isNotEmpty ? lead.name : 'Unknown buyer';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: lead.status == 'new' ? AppColors.primary.withOpacity(0.4) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primaryLight,
                child: Text(name[0].toUpperCase(), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
                    if (lead.phone.isNotEmpty) Text(lead.phone, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Change status',
                onSelected: onStatus,
                itemBuilder: (_) => [
                  for (final s in const ['new', 'contacted', 'visited', 'closed'])
                    CheckedPopupMenuItem(
                      value: s,
                      checked: lead.status == s,
                      child: Text('${s[0].toUpperCase()}${s.substring(1)}'),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${lead.status[0].toUpperCase()}${lead.status.substring(1)}',
                          style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
                      Icon(Icons.arrow_drop_down, size: 18, color: color),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          InkWell(
            onTap: onOpenProperty,
            child: Row(
              children: [
                const Icon(Icons.home_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(lead.propertyTitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary)),
                ),
              ],
            ),
          ),
          if (lead.message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(lead.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySmall),
          ],
          const SizedBox(height: 6),
          Text('${_sourceLabel(lead.source)} • ${_ago(lead.updatedAt)}', style: AppTextStyles.caption),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: lead.phone.isEmpty ? null : onCall,
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Chat'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
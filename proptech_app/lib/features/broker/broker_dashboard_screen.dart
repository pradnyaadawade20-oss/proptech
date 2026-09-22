import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../auth/role_switcher_sheet.dart';
import '../owner/dashboard_service.dart';
import '../owner/owner_stats.dart';

/// Broker's home screen. Structurally mirrors OwnerDashboardScreen since
/// a broker manages listings the same way an owner does — the difference
/// is the listings belong to clients, and brokers get lead/subscription
/// tools instead of a single owner's property count.
class BrokerDashboardScreen extends StatefulWidget {
  const BrokerDashboardScreen({super.key});

  @override
  State<BrokerDashboardScreen> createState() => _BrokerDashboardScreenState();
}

class _BrokerDashboardScreenState extends State<BrokerDashboardScreen> {
  late Future<OwnerStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = DashboardService.instance.getDashboardStats();
  }

  void _retry() {
    setState(() {
      _statsFuture = DashboardService.instance.getDashboardStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
            title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hey Rahul Sharma 👋', style: AppTextStyles.h3),
            Text(
              'Manage clients, listings & leads',
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          _RoundIconButton(
            icon: Icons.swap_horiz,
            tooltip: 'Switch role',
            onPressed: () => showRoleSwitcherSheet(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          _RoundIconButton(
            icon: Icons.notifications_none,
            badgeCount: 3,
            onPressed: () => context.push(RouteNames.profileStandalone),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: FutureBuilder<OwnerStats>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.textHint, size: 40),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Could not load dashboard.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ElevatedButton(onPressed: _retry, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final stats = snapshot.data!;
          return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // ---------------- Client Listings hero card ----------------
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: const BoxDecoration(color: AppColors.primaryDark),
              child: Stack(
                children: [
                  Positioned(
                    right: -AppSpacing.md,
                    top: -AppSpacing.md,
                    bottom: -AppSpacing.md,
                    child: Opacity(
                      opacity: 0.55,
                      child: Image.network(
                        'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=500',
                        width: 260,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            AppColors.primaryDark,
                            AppColors.primaryDark.withValues(alpha: 0.55),
                            AppColors.primaryDark.withValues(alpha: 0.05),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Client Listings',
                            style: AppTextStyles.bodyMedium.copyWith(color: Colors.white70),
                          ),
                          GestureDetector(
                            onTap: () => context.push(RouteNames.myProperties),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'View All Listings',
                                    style: AppTextStyles.bodySmall.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(Icons.chevron_right, color: Colors.white, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${stats.totalProperties}', style: AppTextStyles.h1.copyWith(color: Colors.white, fontSize: 40)),
                      Text('Total Listings', style: AppTextStyles.bodySmall.copyWith(color: Colors.white70)),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          _StatPill(
                            icon: Icons.home_outlined,
                            iconBg: AppColors.primaryLight,
                            label: 'Available',
                            value: stats.available,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _StatPill(
                            icon: Icons.vpn_key_outlined,
                            iconBg: const Color(0xFFE8D39A),
                            label: 'Rented',
                            value: stats.rented,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _StatPill(
                            icon: Icons.sell_outlined,
                            iconBg: const Color(0xFFD6D3F0),
                            label: 'Sold',
                            value: stats.sold,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ---------------- Free Plan banner ----------------
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Color(0xFFE8D39A), shape: BoxShape.circle),
                  child: const Icon(Icons.workspace_premium_outlined, color: AppColors.primaryDark, size: 20),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Free Plan', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                      Text('3 of 3 listings used', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    'Unlock more features & grow your business.',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton(
                  onPressed: () {
                    // Placeholder — wire to a subscription/upgrade screen later.
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
                  ),
                  child: const Text('Upgrade Plan'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ---------------- Active Leads / Visits metrics ----------------
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.people_outline,
                  iconBg: AppColors.primaryLight,
                  value: '${stats.activeLeads}',
                  label: 'Active Leads',
                  trendLabel: '+3 new this week',
                  trendColor: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MetricCard(
                  icon: Icons.event_outlined,
                  iconBg: const Color(0xFFF1E6C8),
                  value: '${stats.visitsThisWeek}',
                  label: 'Visits This Week',
                  trendLabel: '+1 vs last week',
                  trendColor: const Color(0xFFC17A1F),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ---------------- Quick Actions ----------------
                  // ---------------- Quick Actions ----------------
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Quick Actions', style: AppTextStyles.h3),
              GestureDetector(
                onTap: () {},
                child: Text(
                  'View All',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1.3,
            children: [
              _ActionGridTile(
                icon: Icons.add_home_outlined,
                title: 'Add Client\nProperty',
                subtitle: 'List a property on behalf of a client',
                onTap: () => context.push(RouteNames.addProperty),
              ),
              _ActionGridTile(
                icon: Icons.apartment_outlined,
                title: 'My Listings',
                subtitle: 'View and manage all client listings',
                onTap: () => context.push(RouteNames.myProperties),
              ),
              _ActionGridTile(
                icon: Icons.event_available_outlined,
                title: 'Visit Requests',
                subtitle: 'Accept, reject or reschedule visits',
                onTap: () => context.push(RouteNames.myVisits),
              ),
              _ActionGridTile(
                icon: Icons.chat_bubble_outline,
                title: 'Leads / Chats',
                subtitle: 'Talk to interested buyers/tenants',
                onTap: () => context.push(RouteNames.chatListStandalone),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ---------------- Your Performance ----------------
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: 0.9,
                    child: Icon(Icons.assessment_outlined, size: 72, color: AppColors.primary.withValues(alpha: 0.15)),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your Performance', style: AppTextStyles.h3),
                    Text(
                      'Track your progress this month',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Row(
                      children: [
                        Expanded(
                          child: _PerformanceStat(
                            icon: Icons.bar_chart,
                            value: '18',
                            label: 'Total Inquiries',
                            trend: '+12%',
                          ),
                        ),
                        Expanded(
                          child: _PerformanceStat(
                            icon: Icons.attach_money,
                            value: '6',
                            label: 'Deals Closed',
                            trend: '+8%',
                          ),
                        ),
                        Expanded(
                          child: _PerformanceStat(
                            icon: Icons.track_changes_outlined,
                            value: '92%',
                            label: 'Response Rate',
                            trend: '+5%',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ---------------- Upgrade to Pro strip ----------------
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: const Color(0xFFF1E6C8),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Color(0xFFE8D39A), shape: BoxShape.circle),
                  child: const Icon(Icons.star, color: AppColors.primaryDark, size: 18),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upgrade to Pro', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        'Get unlimited listings, premium visibility and more.',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton(
                  onPressed: () {
                    // Placeholder — wire to a subscription/upgrade screen later.
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Explore Plans'),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
        },
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final int? badgeCount;

  const _RoundIconButton({required this.icon, required this.onPressed, this.tooltip, this.badgeCount});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(icon, color: AppColors.textPrimary),
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        if (badgeCount != null && badgeCount! > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: Text(
                '$badgeCount',
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String label;
  final int value;
  const _StatPill({required this.icon, required this.iconBg, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, size: 14, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 6),
            Text('$value', style: AppTextStyles.h3.copyWith(color: Colors.white)),
            Text(label, style: AppTextStyles.caption.copyWith(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String value;
  final String label;
  final String trendLabel;
  final Color trendColor;
  const _MetricCard({
    required this.icon,
    required this.iconBg,
    required this.value,
    required this.label,
    required this.trendLabel,
    required this.trendColor,
  });

  @override
  Widget build(BuildContext context) {
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
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.primaryDark, size: 18),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(value, style: AppTextStyles.h2),
          Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(
            trendLabel,
            style: AppTextStyles.caption.copyWith(color: trendColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _PerformanceStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String trend;
  const _PerformanceStat({required this.icon, required this.value, required this.label, required this.trend});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(color: AppColors.primaryDark, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 14),
        ),
        const SizedBox(height: 6),
        Text(value, style: AppTextStyles.h3),
        Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
        Text(trend, style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primaryDark, size: 18),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: const Icon(Icons.chevron_right, color: AppColors.textHint, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
class _ActionGridTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionGridTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                  child: Icon(icon, color: AppColors.primaryDark, size: 18),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textHint, size: 16),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
              maxLines: 2,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
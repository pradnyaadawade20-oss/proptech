import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import 'landlord_service.dart';

/// Home-screen banner for owners: "A broker invited you". Shows nothing when there is no open invitation.
class InviteBanner extends StatefulWidget {
  const InviteBanner({super.key});

  @override
  State<InviteBanner> createState() => _InviteBannerState();
}

class _InviteBannerState extends State<InviteBanner> {
  int _count = 0;
  String _title = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await LandlordService.instance.myInvites();
      final open = all.where((i) => i.status == 'pending').toList();
      if (!mounted) return;
      setState(() {
        _count = open.length;
        _title = open.isEmpty ? '' : open.first.propertyTitle;
      });
    } catch (_) {
      // no banner if the check fails
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await context.push(RouteNames.landlordInvites);
          if (mounted) _load();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            const Icon(Icons.handshake_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _count == 1 ? 'A broker invited you' : '$_count broker invitations waiting',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary),
                ),
                const SizedBox(height: 2),
                Text(
                  _count == 1 && _title.isNotEmpty ? 'Review "$_title" and accept' : 'Tap to review and accept',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right, color: AppColors.primary),
          ]),
        ),
      ),
    );
  }
}
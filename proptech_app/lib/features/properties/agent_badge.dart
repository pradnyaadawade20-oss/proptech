import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';

/// "Listed by Agent" label for broker listings (no mention of commission here).
class AgentBadge extends StatelessWidget {
  const AgentBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.badge_outlined, size: 15, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          'Listed by Agent',
          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.primary),
        ),
      ]),
    );
  }
}
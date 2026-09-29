import 'package:flutter/material.dart';

/// Central color palette for the whole app — Minimal White + Navy/Professional Blue theme.
/// Change values here to re-theme the entire app.
class AppColors {
  AppColors._();
  static const Color primary = Color(0xFF15558A); // deep navy blue — buttons, active tabs, links
  static const Color primaryDark = Color(0xFF123F67); // headings / strong highlights
  static const Color primaryLight = Color(0xFFEAF2FA); // pale blue — chip backgrounds, badges
  static const Color secondary = Color(0xFF2B6FA3); // medium blue — icons / accents
  static const Color background = Color(0xFFFFFFFF); // white
  static const Color surface = Color(0xFFFFFFFF); // cards, inputs
  static const Color surfaceSoft = Color(0xFFF1F6FC); // very light blue sections (search bar, chips)
  static const Color textPrimary = Color(0xFF17202A); // almost black
  static const Color textSecondary = Color(0xFF667085); // cool grey
  static const Color textHint = Color(0xFF9AA5B1);
  static const Color border = Color(0xFFE5EAF0);
  static const Color divider = Color(0xFFEAF2FA);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFC17A1F);
  static const Color error = Color(0xFFD64545);
  static const Color verifiedBadge = Color(0xFF15558A);
}
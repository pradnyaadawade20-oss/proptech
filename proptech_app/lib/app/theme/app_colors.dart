import 'package:flutter/material.dart';

/// Central color palette for the whole app — Deep Teal + Warm Ivory + Champagne theme.
/// Change values here to re-theme the entire app.
class AppColors {
  AppColors._();
  static const Color primary = Color(0xFF075E54); // deep teal — buttons, active tabs
  static const Color primaryDark = Color(0xFF04413A); // headings / strong highlights
  static const Color primaryLight = Color(0xFFB8CEC8); // sage — selected states / badges
  static const Color secondary = Color(0xFFE8D39A); // champagne — accent buttons/highlights
  static const Color background = Color(0xFFFAF9F5); // warm ivory
  static const Color surface = Color(0xFFFFFFFF); // cards, inputs
  static const Color surfaceSoft = Color(0xFFF1EFE7); // subtle ivory sections
  static const Color textPrimary = Color(0xFF18201F); // charcoal
  static const Color textSecondary = Color(0xFF5C6462); // muted charcoal
  static const Color textHint = Color(0xFF97A19E);
  static const Color border = Color(0xFFE4E1D6);
  static const Color divider = Color(0xFFF1EFE7);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFC17A1F);
  static const Color error = Color(0xFFB3452F);
  static const Color verifiedBadge = Color(0xFF075E54);
}
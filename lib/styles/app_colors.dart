import 'package:flutter/material.dart';

class AppColors {
  // Ana Renk Paleti (Electric Sapphire & Deep Obsidian)
  // Ana Renk Paleti (Electric Sapphire & Vibrant Cyan)
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primarySoft = Color(0xFF60A5FA);
  static const Color accent = Color(0xFF38BDF8);
  static const Color accent = Color(0xFF0284C7);
  static const Color accentLight = Color(0xFF38BDF8);
  static const Color cyanNeon = Color(0xFF06B6D4);

  // Semantik Renkler (Canlı Durum Göstergeleri)
  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldLight = Color(0xFF34D399);
  static const Color amber = Color(0xFFF59E0B);
  static const Color amberLight = Color(0xFFFBBF24);
  static const Color rose = Color(0xFFEF4444);
  static const Color roseLight = Color(0xFFF87171);

  // Arka Plan ve Yüzeyler (Deep Luxury Slate)
  // Koyu Tema Arka Plan ve Yüzeyler (Deep Luxury Slate)
  static const Color backgroundTop = Color(0xFF0F172A);
  static const Color backgroundBottom = Color(0xFF020617);
  static const Color surface = Color(0xFF1E293B);
  static const Color surfaceElevated = Color(0xFF27354A);
  static const Color surfaceGlass = Color(0xCC1E293B);
  static const Color surfaceLight = Color(0xFFF8FAFC);

  // Açık Tema Arka Plan ve Yüzeyler (Luminous Fresh Slate & Pure White Glass)
  static const Color lightBackgroundTop = Color(0xFFF8FAFC);
  static const Color lightBackgroundMid = Color(0xFFF1F5F9);
  static const Color lightBackgroundBottom = Color(0xFFE2E8F0);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceLightGlass = Color(0xF5FFFFFF);
  static const Color surfaceLightElevated = Color(0xFFF8FAFC);

  // Tipografi Renkleri
  static const Color textDark = Color(0xFF0F172A);
  static const Color textDarkSecondary = Color(0xFF334155);
  static const Color textLight = Color(0xFFF8FAFC);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textMutedLight = Color(0xFF94A3B8);

  // Lüks Gölgeler ve Parıltılar
  // Gölgeler ve Kenarlıklar
  static const Color shadowDark = Color(0x50000000);
  static const Color shadowSoft = Color(0x253B82F6);
  static const Color shadowGlow = Color(0x3338BDF8);
  static const Color borderGlass = Color(0x26FFFFFF);
  static const Color borderLight = Color(0xFFE2E8F0);

  // Tema Duyarlı Dinamik Renk Yardımcıları (Context Helpers)
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color text(BuildContext context) =>
      isDark(context) ? textLight : textDark;

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? const Color(0xFFCBD5E1) : textDarkSecondary;

  static Color textMutedColor(BuildContext context) =>
      isDark(context) ? textMutedLight : textMuted;

  static Color surfaceColor(BuildContext context) =>
      isDark(context) ? surface : surfaceLight;

  static Color surfaceGlassColor(BuildContext context) =>
      isDark(context) ? surfaceGlass : surfaceLightGlass;

  static Color cardBorderColor(BuildContext context) =>
      isDark(context) ? const Color(0x22FFFFFF) : const Color(0xFFE2E8F0);
}

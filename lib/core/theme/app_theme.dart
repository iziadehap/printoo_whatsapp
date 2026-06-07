import 'package:flutter/material.dart';

class AppColors {
  // Background palette
  static const bgDeep = Color(0xFF0D1117);
  static const bgBase = Color(0xFF121824);
  static const bgSurface = Color(0xFF1A2235);
  static const bgCard = Color(0xFF1E2A42);
  static const bgSidebar = Color(0xFF161D2E);
  static const bgHover = Color(0xFF243050);
  static const bgSelected = Color(0xFF1D3461);

  // Accent / Primary
  static const accent = Color(0xFF10B981); // Soft Emerald
  static const accentGlow = Color(0xFF34D399);
  static const accentDim = Color(0xFF065F46);
  static const accentMint = Color(0xFF00E676);

  // Secondary accents
  static const blue = Color(0xFF3B82F6);
  static const blueDim = Color(0xFF1D4ED8);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);

  // Typography
  static const textPrimary = Color(0xFFE8EDF5);
  static const textSecondary = Color(0xFF9CA3AF);
  static const textMuted = Color(0xFF6B7280);
  static const textAccent = Color(0xFF10B981);

  // Borders
  static const border = Color(0xFF2A3652);
  static const borderActive = Color(0xFF3B5280);

  // Buttons
  static const btnPrimary = Color(0xFF10B981);
  static const btnPrimaryText = Color(0xFF0D1117);
  static const btnSecondary = Color(0xFF1E2A42);
}

class AppTheme {
  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bgBase,
        fontFamily: 'Segoe UI',
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          secondary: AppColors.blue,
          surface: AppColors.bgSurface,
          error: AppColors.red,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          bodyMedium: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          bodySmall: TextStyle(color: AppColors.textMuted, fontSize: 11),
          titleMedium: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600),
          titleSmall: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.bgSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        dropdownMenuTheme: const DropdownMenuThemeData(
          textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 12),
        ),
        dividerColor: AppColors.border,
      );
}

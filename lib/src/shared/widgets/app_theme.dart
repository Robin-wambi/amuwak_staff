import 'package:flutter/material.dart';

import 'package:amuwak_core/amuwak_core.dart';

ThemeData buildAmuwakTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    // Brand-critical overrides only. Let the algorithm derive secondary,
    // surface, and onSurface so the palette stays harmonious.
    primary: AppColors.primary,
    onPrimary: AppColors.dark,
    primaryContainer: AppColors.surfaceBrand,
    onPrimaryContainer: AppColors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: AppTypography.fontFamily,
    scaffoldBackgroundColor: AppColors.background,
    extensions: const <ThemeExtension<dynamic>>[StatusColors.light],
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surfaceBrand,
      foregroundColor: AppColors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.white,
      indicatorColor: AppColors.primary.withValues(alpha: 0.16),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.primary : AppColors.secondaryText,
          size: 24,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: AppTypography.fontFamily,
          color: selected ? AppColors.dark : AppColors.secondaryText,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        );
      }),
    ),
    textTheme: AppTypography.textTheme(),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.dark,
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.field)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.dark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      prefixIconColor: AppColors.primary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.field),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.field),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
  );
}

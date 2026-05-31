import 'package:flutter/material.dart';

const Color amuwakPrimary = Color(0xFFFF6E11); // Sampled logo orange (60% role)
const Color amuwakSurfaceBrand = Color(0xFFC75A0E); // Deep terracotta (30% role)
const Color amuwakDark = Color(0xFF1F1F1F);
const Color amuwakBackground = Color(0xFFFFF8F2);
const Color amuwakWhite = Color(0xFFFFFFFF);

ThemeData buildAmuwakTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: amuwakBackground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: amuwakPrimary,
      primary: amuwakPrimary,
      onPrimary: amuwakDark,
      primaryContainer: amuwakSurfaceBrand,
      onPrimaryContainer: amuwakWhite,
      secondary: amuwakPrimary,
      onSecondary: amuwakWhite,
      surface: amuwakWhite,
      onSurface: amuwakDark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: amuwakSurfaceBrand,
      foregroundColor: amuwakWhite,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: amuwakWhite,
      indicatorColor: amuwakPrimary.withValues(alpha: 0.16),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: isSelected ? amuwakPrimary : Colors.black54,
          size: 24,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return TextStyle(
          color: isSelected ? amuwakDark : Colors.black54,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
        );
      }),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: amuwakDark, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: amuwakDark, fontWeight: FontWeight.bold),
      titleLarge: TextStyle(color: amuwakDark, fontWeight: FontWeight.bold),
      bodyMedium: TextStyle(color: amuwakDark),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: amuwakPrimary,
        foregroundColor: amuwakDark,
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: amuwakPrimary,
      foregroundColor: amuwakDark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: amuwakWhite,
      prefixIconColor: amuwakPrimary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: amuwakPrimary, width: 1.5),
      ),
    ),
  );
}

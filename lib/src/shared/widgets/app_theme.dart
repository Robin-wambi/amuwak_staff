import 'package:flutter/material.dart';

const Color amuwakPrimary = Color(0xFFA85A1F);
const Color amuwakDark = Color(0xFF1F1F1F);
const Color amuwakBackground = Color(0xFFFFF8F2);
const Color amuwakSoftAccent = Color(0xFFF3E0D0);
const Color amuwakWhite = Color(0xFFFFFFFF);

ThemeData buildAmuwakTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: amuwakBackground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: amuwakPrimary,
      primary: amuwakPrimary,
      secondary: amuwakPrimary,
      surface: amuwakWhite,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: amuwakDark,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        color: amuwakDark,
        fontWeight: FontWeight.bold,
      ),
      titleLarge: TextStyle(
        color: amuwakDark,
        fontWeight: FontWeight.bold,
      ),
      bodyMedium: TextStyle(
        color: amuwakDark,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: amuwakPrimary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
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
        borderSide: const BorderSide(
          color: amuwakPrimary,
          width: 1.5,
        ),
      ),
    ),
  );
}

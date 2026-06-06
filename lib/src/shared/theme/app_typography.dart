import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Brand typography: the bundled font family plus a complete Material text
/// ramp.
///
/// The anchors screens already depend on are preserved exactly (titleLarge
/// 21/bold, titleMedium 16/w700, bodySmall 13/secondary, headline*/bodyMedium
/// in charcoal). The remaining slots are filled around them so every Material
/// text role is defined on the brand family instead of falling back to the
/// platform default.
abstract final class AppTypography {
  static const String fontFamily = 'Plus Jakarta Sans';

  static const Color _primary = AppColors.dark;
  static const Color _muted = AppColors.secondaryText;

  static TextStyle _style(
    double size,
    FontWeight weight, {
    Color color = _primary,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  /// The full type ramp. Display/headline sizes carry a slight negative
  /// tracking for a tighter, more intentional look at large sizes.
  static TextTheme textTheme() => TextTheme(
        displayLarge: _style(34, FontWeight.w800, letterSpacing: -0.5),
        displayMedium: _style(30, FontWeight.w800, letterSpacing: -0.5),
        displaySmall: _style(26, FontWeight.w700, letterSpacing: -0.25),
        headlineLarge: _style(24, FontWeight.bold, letterSpacing: -0.25),
        headlineMedium: _style(22, FontWeight.bold),
        headlineSmall: _style(20, FontWeight.w700),
        titleLarge: _style(21, FontWeight.bold),
        titleMedium: _style(16, FontWeight.w700),
        titleSmall: _style(14, FontWeight.w600),
        bodyLarge: _style(16, FontWeight.w500),
        bodyMedium: _style(14, FontWeight.w400),
        bodySmall: _style(13, FontWeight.w400, color: _muted),
        labelLarge: _style(14, FontWeight.w700),
        labelMedium: _style(12, FontWeight.w600),
        labelSmall: _style(11, FontWeight.w600, color: _muted),
      );
}

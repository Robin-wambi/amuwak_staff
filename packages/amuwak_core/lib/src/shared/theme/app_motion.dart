import 'package:flutter/material.dart';

/// Motion scale — the app's single source for animation timing and shaping.
///
/// Sibling to [AppSpacing], [AppElevation], [AppRadii]. Values are kept
/// conservative (sourced from the Material 3 motion spec) because this is a
/// field operations tool: motion must add polish without competing with
/// content or hurting performance.
abstract final class AppMotion {
  /// Press feedback (scale down/up).
  static const Duration fast = Duration(milliseconds: 150);

  /// A single entrance reveal.
  static const Duration medium = Duration(milliseconds: 320);

  /// Count-up total duration.
  static const Duration slow = Duration(milliseconds: 600);

  /// One full cycle of the header gradient sheen.
  static const Duration gradientLoop = Duration(seconds: 6);

  /// Delay between successive sibling reveals.
  static const Duration stagger = Duration(milliseconds: 80);

  /// Standard easing for reveals and press.
  static const Curve standard = Curves.easeOutCubic;

  /// Easing for the gradient lerp.
  static const Curve emphasized = Curves.easeInOut;

  /// Upward slide distance for an entrance reveal (logical px).
  static const double revealOffset = 16;

  /// Scale factor applied while a surface is pressed.
  static const double pressScale = 0.97;
}

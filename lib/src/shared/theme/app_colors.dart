import 'package:flutter/material.dart';

/// Single source of brand and semantic colors. Light theme only.
abstract final class AppColors {
  // Brand palette (60-30-10 roles).
  static const Color primary = Color(0xFFFF6E11); // logo orange (60%)
  static const Color surfaceBrand = Color(0xFFC75A0E); // deep terracotta (30%)
  static const Color dark = Color(0xFF1F1F1F);
  static const Color background = Color(0xFFFFF8F2);
  static const Color white = Color(0xFFFFFFFF);

  // Semantic constants for values currently hardcoded inline across screens.
  /// Muted body/secondary text. Replaces ad hoc `Colors.black54`.
  static const Color secondaryText = Color(0x99000000); // black @ 60%
  /// Hairline border for cards. Replaces `primary.withValues(alpha: 0.18)`.
  static const Color cardBorder = Color(0x2EFF6E11); // primary @ ~18%
}

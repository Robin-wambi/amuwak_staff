import 'dart:ui';

import 'package:amuwak_core/amuwak_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppColors keeps the established brand palette values', () {
    expect(AppColors.primary, const Color(0xFFFF6E11));
    expect(AppColors.surfaceBrand, const Color(0xFFC75A0E));
    expect(AppColors.dark, const Color(0xFF1F1F1F));
    expect(AppColors.background, const Color(0xFFFFF8F2));
    expect(AppColors.white, const Color(0xFFFFFFFF));
  });

  test('AppColors adds semantic constants for the screen sweep', () {
    // Secondary text replaces ad hoc Colors.black54 usage.
    expect(AppColors.secondaryText, isA<Color>());
    // Card hairline replaces the repeated primary @18% border.
    expect(AppColors.cardBorder, isA<Color>());
  });
}

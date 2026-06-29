import 'package:amuwak_staff/src/shared/theme/app_colors.dart';
import 'package:amuwak_staff/src/shared/theme/app_radii.dart';
import 'package:amuwak_staff/src/shared/theme/app_typography.dart';
import 'package:amuwak_staff/src/shared/theme/status_colors.dart';
import 'package:amuwak_staff/src/shared/widgets/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final theme = buildAmuwakTheme();

  test('uses Material 3 and the brand primary', () {
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, AppColors.primary);
  });

  test('secondary is no longer pinned equal to primary', () {
    // The old theme set secondary == primary; the trimmed scheme lets the
    // algorithm derive a distinct secondary.
    expect(theme.colorScheme.secondary, isNot(AppColors.primary));
  });

  test('registers the StatusColors extension', () {
    expect(theme.extension<StatusColors>(), isNotNull);
  });

  test('completes the text ramp used by screens', () {
    expect(theme.textTheme.titleLarge, isNotNull);
    expect(theme.textTheme.headlineMedium, isNotNull);
    expect(theme.textTheme.bodySmall, isNotNull);
  });

  test('applies the brand typeface across the theme', () {
    expect(theme.textTheme.titleMedium?.fontFamily, AppTypography.fontFamily);
    expect(theme.textTheme.bodyMedium?.fontFamily, AppTypography.fontFamily);
  });

  test('card theme uses the card radius', () {
    final shape = theme.cardTheme.shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(AppRadii.card));
  });

  group('navigation bar state-resolved styling', () {
    test('icon colour switches between selected and unselected', () {
      final iconTheme = theme.navigationBarTheme.iconTheme!;
      final selected = iconTheme.resolve({WidgetState.selected})!;
      final unselected = iconTheme.resolve(<WidgetState>{})!;

      expect(selected.color, AppColors.primary);
      expect(unselected.color, AppColors.secondaryText);
      expect(selected.size, 24);
    });

    test('label colour and weight switch between selected and unselected', () {
      final labelStyle = theme.navigationBarTheme.labelTextStyle!;
      final selected = labelStyle.resolve({WidgetState.selected})!;
      final unselected = labelStyle.resolve(<WidgetState>{})!;

      expect(selected.color, AppColors.dark);
      expect(selected.fontWeight, FontWeight.w700);
      expect(unselected.color, AppColors.secondaryText);
      expect(unselected.fontWeight, FontWeight.w600);
      expect(selected.fontFamily, AppTypography.fontFamily);
    });
  });
}

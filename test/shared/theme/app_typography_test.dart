import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/shared/theme/app_colors.dart';
import 'package:amuwak_staff/src/shared/theme/app_typography.dart';

void main() {
  test('exposes the bundled Plus Jakarta Sans family', () {
    expect(AppTypography.fontFamily, 'Plus Jakarta Sans');
  });

  group('textTheme()', () {
    final textTheme = AppTypography.textTheme();

    test('fills every ramp slot', () {
      final styles = <TextStyle?>[
        textTheme.displayLarge,
        textTheme.displayMedium,
        textTheme.displaySmall,
        textTheme.headlineLarge,
        textTheme.headlineMedium,
        textTheme.headlineSmall,
        textTheme.titleLarge,
        textTheme.titleMedium,
        textTheme.titleSmall,
        textTheme.bodyLarge,
        textTheme.bodyMedium,
        textTheme.bodySmall,
        textTheme.labelLarge,
        textTheme.labelMedium,
        textTheme.labelSmall,
      ];
      for (final style in styles) {
        expect(style, isNotNull);
      }
    });

    test('applies the brand family to every slot', () {
      expect(textTheme.displayLarge?.fontFamily, AppTypography.fontFamily);
      expect(textTheme.titleMedium?.fontFamily, AppTypography.fontFamily);
      expect(textTheme.bodySmall?.fontFamily, AppTypography.fontFamily);
      expect(textTheme.labelSmall?.fontFamily, AppTypography.fontFamily);
    });

    test('preserves the size/weight anchors screens already rely on', () {
      expect(textTheme.titleLarge?.fontSize, 21);
      expect(textTheme.titleLarge?.fontWeight, FontWeight.bold);

      expect(textTheme.titleMedium?.fontSize, 16);
      expect(textTheme.titleMedium?.fontWeight, FontWeight.w700);

      expect(textTheme.bodySmall?.fontSize, 13);
      expect(textTheme.bodySmall?.color, AppColors.secondaryText);
    });

    test('escalates size down the ramp (display > headline > title > body)', () {
      expect(textTheme.displayLarge!.fontSize!,
          greaterThan(textTheme.headlineLarge!.fontSize!));
      expect(textTheme.headlineLarge!.fontSize!,
          greaterThan(textTheme.titleLarge!.fontSize!));
      expect(textTheme.titleLarge!.fontSize!,
          greaterThan(textTheme.bodyLarge!.fontSize!));
    });
  });
}

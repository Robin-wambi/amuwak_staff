import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/shared/widgets/app_theme.dart';

void main() {
  group('Amuwak palette constants', () {
    test('amuwakPrimary matches the sampled logo orange (#FF6E11)', () {
      expect(amuwakPrimary, const Color(0xFFFF6E11));
    });

    test('amuwakSurfaceBrand is the deep terracotta for the 30% role', () {
      expect(amuwakSurfaceBrand, const Color(0xFFC75A0E));
    });

    test('amuwakDark, amuwakBackground, amuwakWhite are unchanged', () {
      expect(amuwakDark, const Color(0xFF1F1F1F));
      expect(amuwakBackground, const Color(0xFFFFF8F2));
      expect(amuwakWhite, const Color(0xFFFFFFFF));
    });
  });

  group('buildAmuwakTheme ColorScheme', () {
    final theme = buildAmuwakTheme();

    test('primary is the logo orange', () {
      expect(theme.colorScheme.primary, amuwakPrimary);
    });

    test('onPrimary is dark charcoal for AA contrast on bright orange', () {
      expect(theme.colorScheme.onPrimary, amuwakDark);
    });

    test('primaryContainer is the deep terracotta', () {
      expect(theme.colorScheme.primaryContainer, amuwakSurfaceBrand);
    });

    test('onPrimaryContainer is white for AA contrast on terracotta', () {
      expect(theme.colorScheme.onPrimaryContainer, amuwakWhite);
    });

    test('surface is the white card surface', () {
      expect(theme.colorScheme.surface, amuwakWhite);
    });
  });

  group('component themes', () {
    final theme = buildAmuwakTheme();

    test('AppBar uses the deep terracotta with white foreground', () {
      expect(theme.appBarTheme.backgroundColor, amuwakSurfaceBrand);
      expect(theme.appBarTheme.foregroundColor, amuwakWhite);
      expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
    });

    test('ElevatedButton uses dark text on bright orange (AA contrast)', () {
      final style = theme.elevatedButtonTheme.style;
      expect(style?.backgroundColor?.resolve(<WidgetState>{}), amuwakPrimary);
      expect(style?.foregroundColor?.resolve(<WidgetState>{}), amuwakDark);
    });

    test('FloatingActionButton uses dark icon on bright orange', () {
      expect(theme.floatingActionButtonTheme.backgroundColor, amuwakPrimary);
      expect(theme.floatingActionButtonTheme.foregroundColor, amuwakDark);
    });

    test('NavigationBar uses brand colors for selected destinations', () {
      final navigationTheme = theme.navigationBarTheme;
      const selected = <WidgetState>{WidgetState.selected};
      const unselected = <WidgetState>{};

      expect(navigationTheme.backgroundColor, amuwakWhite);
      expect(
        navigationTheme.indicatorColor,
        amuwakPrimary.withValues(alpha: 0.16),
      );
      expect(navigationTheme.iconTheme?.resolve(selected)?.color, amuwakPrimary);
      expect(
        navigationTheme.iconTheme?.resolve(unselected)?.color,
        Colors.black54,
      );
      expect(
        navigationTheme.labelTextStyle?.resolve(selected)?.fontWeight,
        FontWeight.w700,
      );
    });
  });
}

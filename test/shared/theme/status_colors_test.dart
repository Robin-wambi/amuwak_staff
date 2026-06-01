import 'dart:ui';

import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/shared/theme/status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Composite a possibly-translucent foreground over an opaque background.
Color _composite(Color fg, Color bg) {
  final a = fg.a;
  return Color.from(
    alpha: 1,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const status = StatusColors.light;

  test('of() returns a pair for every OrderStatus', () {
    for (final s in OrderStatus.values) {
      final pair = status.of(s);
      expect(pair.color, isA<Color>());
      expect(pair.onColor, isA<Color>());
    }
  });

  test('chip text passes WCAG 4.5:1 on its tinted background', () {
    const surface = Color(0xFFFFFFFF);
    for (final s in OrderStatus.values) {
      final pair = status.of(s);
      final tint = _composite(pair.color.withValues(alpha: 0.12), surface);
      final ratio = _contrast(pair.onColor, tint);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: '${s.name} chip contrast was $ratio');
    }
  });

  test('StatusColorPair compares by value (== and hashCode)', () {
    // Non-const so Dart can't canonicalize them into one instance — this
    // exercises real value equality, not identity.
    final a = StatusColorPair(Color(0xFF112233), Color(0xFF445566));
    final b = StatusColorPair(Color(0xFF112233), Color(0xFF445566));
    final differentColor = StatusColorPair(Color(0xFF000000), Color(0xFF445566));
    final differentOnColor = StatusColorPair(Color(0xFF112233), Color(0xFF000000));

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
    expect(a, isNot(equals(differentColor)));
    expect(a, isNot(equals(differentOnColor)));
  });

  test('lerp returns a StatusColors and is identity at t=0', () {
    final lerped = status.lerp(status, 0) as StatusColors;
    expect(lerped.of(OrderStatus.completed).color,
        status.of(OrderStatus.completed).color);
  });
}

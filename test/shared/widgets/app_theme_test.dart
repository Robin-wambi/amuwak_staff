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
}

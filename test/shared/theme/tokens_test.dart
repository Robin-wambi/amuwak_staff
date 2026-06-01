import 'package:amuwak_staff/src/shared/theme/app_radii.dart';
import 'package:amuwak_staff/src/shared/theme/app_spacing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppSpacing exposes an ascending 4-based scale', () {
    expect(AppSpacing.xs, 4);
    expect(AppSpacing.sm, 8);
    expect(AppSpacing.md, 12);
    expect(AppSpacing.lg, 16);
    expect(AppSpacing.lg2, 18);
    expect(AppSpacing.xl, 20);
    expect(AppSpacing.xxl, 24);
  });

  test('AppRadii exposes field/card/chip radii', () {
    expect(AppRadii.field, 18);
    expect(AppRadii.card, 22);
    expect(AppRadii.chip, 999);
  });
}

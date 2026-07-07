import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_core/amuwak_core.dart';

void main() {
  test('resting and raised both define shadows', () {
    expect(AppElevation.resting, isNotEmpty);
    expect(AppElevation.raised, isNotEmpty);
  });

  test('shadows are soft and low-opacity (subtle, not heavy)', () {
    for (final shadow in [...AppElevation.resting, ...AppElevation.raised]) {
      expect(shadow.blurRadius, greaterThan(0));
      expect(shadow.color.a, lessThan(0.30));
    }
  });

  double spread(List<BoxShadow> shadows) => shadows
      .map((s) => s.blurRadius + s.color.a * 100)
      .reduce((a, b) => a > b ? a : b);

  test('raised reads as more elevated than resting', () {
    expect(spread(AppElevation.raised), greaterThan(spread(AppElevation.resting)));
  });
}

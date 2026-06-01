import 'package:flutter/material.dart';

import '../../orders/order_status.dart';

/// A status color and the text color to render on its tinted chip background.
@immutable
class StatusColorPair {
  const StatusColorPair(this.color, this.onColor);
  final Color color;
  final Color onColor;

  @override
  bool operator ==(Object other) =>
      other is StatusColorPair &&
      other.color == color &&
      other.onColor == onColor;

  @override
  int get hashCode => Object.hash(color, onColor);
}

/// Theme extension holding order-status colors so screens resolve them from the
/// theme instead of hardcoding hex. `onColor` is verified to pass WCAG 4.5:1 on
/// the chip's 12%-alpha tint (see status_colors_test.dart).
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.pendingPickup,
    required this.inProgress,
    required this.readyForDelivery,
    required this.completed,
  });

  final StatusColorPair pendingPickup;
  final StatusColorPair inProgress;
  final StatusColorPair readyForDelivery;
  final StatusColorPair completed;

  StatusColorPair of(OrderStatus status) => switch (status) {
        OrderStatus.pendingPickup => pendingPickup,
        OrderStatus.inProgress => inProgress,
        OrderStatus.readyForDelivery => readyForDelivery,
        OrderStatus.completed => completed,
      };

  /// The light-theme status palette. `onColor` values are darkened relative to
  /// `color` so 12-pt chip text clears 4.5:1 on the pale tint.
  static const StatusColors light = StatusColors(
    pendingPickup: StatusColorPair(Color(0xFF9A5B00), Color(0xFF6E4000)),
    inProgress: StatusColorPair(Color(0xFF7A4CC2), Color(0xFF5A2EA6)),
    readyForDelivery: StatusColorPair(Color(0xFF0B7285), Color(0xFF075562)),
    completed: StatusColorPair(Color(0xFF2F7D32), Color(0xFF1E5E20)),
  );

  @override
  StatusColors copyWith({
    StatusColorPair? pendingPickup,
    StatusColorPair? inProgress,
    StatusColorPair? readyForDelivery,
    StatusColorPair? completed,
  }) {
    return StatusColors(
      pendingPickup: pendingPickup ?? this.pendingPickup,
      inProgress: inProgress ?? this.inProgress,
      readyForDelivery: readyForDelivery ?? this.readyForDelivery,
      completed: completed ?? this.completed,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    StatusColorPair lerpPair(StatusColorPair a, StatusColorPair b) =>
        StatusColorPair(
          Color.lerp(a.color, b.color, t)!,
          Color.lerp(a.onColor, b.onColor, t)!,
        );
    return StatusColors(
      pendingPickup: lerpPair(pendingPickup, other.pendingPickup),
      inProgress: lerpPair(inProgress, other.inProgress),
      readyForDelivery: lerpPair(readyForDelivery, other.readyForDelivery),
      completed: lerpPair(completed, other.completed),
    );
  }
}

import 'package:flutter/material.dart';

/// Soft, low-opacity shadow tokens — the app's depth scale.
///
/// Replaces the previous flat `elevation: 0` everywhere with two tiers:
/// [resting] for cards sitting on the background, and [raised] for surfaces
/// that float above content (sheets, menus, popovers). Shadows use a charcoal
/// tint at low alpha so they read as gentle depth, never heavy drop-shadows.
abstract final class AppElevation {
  /// Resting surface — standard cards. Subtle two-layer shadow.
  static const List<BoxShadow> resting = [
    BoxShadow(
      color: Color(0x121F1F1F), // charcoal @ ~7%
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x0A1F1F1F), // charcoal @ ~4%
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// Raised surface — sheets, menus, popovers. Deeper and softer.
  static const List<BoxShadow> raised = [
    BoxShadow(
      color: Color(0x261F1F1F), // charcoal @ ~15%
      blurRadius: 20,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Color(0x141F1F1F), // charcoal @ ~8%
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];
}

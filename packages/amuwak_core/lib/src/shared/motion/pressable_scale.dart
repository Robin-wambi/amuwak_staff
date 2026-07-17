import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Wraps a [child] so it scales down slightly while pressed, springing back
/// on release — a tactile, premium press feedback. Owns the tap via a
/// [GestureDetector] (so it behaves correctly inside scrollables: a scroll
/// that wins the gesture arena fires `onTapCancel` and the scale releases).
///
/// Honours the OS reduce-motion setting: when disabled, the scale stays at 1.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final scaled = AnimatedScale(
      scale: (_pressed && !reduceMotion) ? AppMotion.pressScale : 1.0,
      duration: reduceMotion ? Duration.zero : AppMotion.fast,
      curve: AppMotion.standard,
      child: widget.child,
    );

    if (widget.onTap == null) return scaled;

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: scaled,
      ),
    );
  }
}

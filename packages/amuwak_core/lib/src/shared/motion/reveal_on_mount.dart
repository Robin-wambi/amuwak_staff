import 'package:flutter/material.dart';

import 'package:amuwak_core/amuwak_core.dart';

/// Fades a [child] in (0→1) and slides it up ([AppMotion.revealOffset]→0) once,
/// when it first mounts. Pass [delay] to stagger siblings:
/// `RevealOnMount(delay: AppMotion.stagger * index, child: ...)`.
///
/// Honours reduce-motion: the child appears immediately with no animation and
/// no pending timer.
class RevealOnMount extends StatefulWidget {
  const RevealOnMount({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  State<RevealOnMount> createState() => _RevealOnMountState();
}

class _RevealOnMountState extends State<RevealOnMount>
    with TickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
  );

  /// Null when there is no delay (or when reduced motion is active).
  AnimationController? _delay;

  /// Held as a field (not rebuilt in `build`) so the reveal doesn't allocate a
  /// fresh CurvedAnimation on every animation frame.
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _reveal,
    curve: AppMotion.standard,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // Reduce-motion: jump straight to the final frame — no timer, no animation.
    if (MediaQuery.of(context).disableAnimations) {
      _reveal.value = 1.0;
      return;
    }

    if (widget.delay == Duration.zero) {
      _reveal.forward();
    } else {
      // Use an AnimationController as the delay ticker so the Flutter test
      // framework's fake-time pump advances it correctly (Future.delayed does
      // not keep `hasScheduledFrame` alive between pumps).
      _delay = AnimationController(vsync: this, duration: widget.delay)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            _reveal.forward();
          }
        })
        ..forward();
    }
  }

  @override
  void dispose() {
    _delay?.dispose();
    _curved.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When motion is disabled, render the child directly — no Opacity/Transform.
    if (MediaQuery.of(context).disableAnimations) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) {
        return Opacity(
          opacity: _curved.value,
          child: Transform.translate(
            offset: Offset(0, AppMotion.revealOffset * (1 - _curved.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

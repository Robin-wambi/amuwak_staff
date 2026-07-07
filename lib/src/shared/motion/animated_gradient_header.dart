import 'package:flutter/material.dart';

import 'package:amuwak_core/amuwak_core.dart';

/// A brand-coloured header surface with a slow, very subtle gradient sheen that
/// travels diagonally — making the surface feel "alive" without drawing the eye
/// away from content. Drop-in replacement for the dashboard's flat brand header
/// container: keeps the card radius and the soft brand shadow.
///
/// Honours reduce-motion: paints a static gradient frame, and reacts to the
/// preference being toggled at runtime — freezing or resuming the sheen.
class AnimatedGradientHeader extends StatefulWidget {
  const AnimatedGradientHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg2),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  State<AnimatedGradientHeader> createState() => _AnimatedGradientHeaderState();
}

class _AnimatedGradientHeaderState extends State<AnimatedGradientHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.gradientLoop,
  );

  // The sheen travels between the brand terracotta and a slightly lighter
  // terracotta — low contrast, so it reads as a living surface, not a flashy
  // gradient.
  static final Color _base = AppColors.surfaceBrand;
  static final Color _light =
      Color.lerp(AppColors.surfaceBrand, AppColors.white, 0.10)!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // React to runtime reduce-motion toggles: run the sheen only while motion
    // is allowed, freezing on a static frame the moment it isn't. Subscribing
    // to just the disableAnimations aspect avoids needless rebuilds.
    _syncSheen(MediaQuery.disableAnimationsOf(context));
  }

  void _syncSheen(bool reduceMotion) {
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.card);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = AppMotion.emphasized.transform(_controller.value);
        final begin = Color.lerp(_base, _light, t)!;
        final end = Color.lerp(_light, _base, t)!;
        return Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [begin, end],
            ),
            // A brand-tinted shadow (not AppElevation.resting's charcoal) so
            // the coloured header casts a glow in its own hue rather than a
            // neutral drop-shadow.
            boxShadow: [
              BoxShadow(
                color: AppColors.surfaceBrand.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

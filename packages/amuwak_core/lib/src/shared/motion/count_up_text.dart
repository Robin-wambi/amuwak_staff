import 'package:flutter/material.dart';

import 'package:amuwak_core/amuwak_core.dart';

/// Renders an integer [value] that animates up to its target. When [value]
/// changes the tween re-runs from the currently displayed number to the new
/// one (implicit-animation behaviour). Honours reduce-motion (jumps to value).
class CountUpText extends StatelessWidget {
  const CountUpText({super.key, required this.value, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : AppMotion.slow;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: AppMotion.standard,
      builder: (context, animatedValue, _) {
        return Text(animatedValue.round().toString(), style: style);
      },
    );
  }
}

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radii.dart';
import 'app_spacing.dart';

/// The app's standard white container: rounded, hairline-bordered, padded.
/// Replaces the repeated inline `BoxDecoration` card pattern. Optionally
/// tappable via [onTap].
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      side: const BorderSide(color: AppColors.cardBorder),
    );
    final padded = Padding(padding: padding, child: child);
    return Card(
      elevation: 0,
      color: AppColors.white,
      margin: EdgeInsets.zero,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      // Only wrap in an InkWell when the card is actually tappable — a null-tap
      // InkWell is just an inert widget in the tree.
      child: onTap == null ? padded : InkWell(onTap: onTap, child: padded),
    );
  }
}

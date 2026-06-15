import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// One garment shown in the [GarmentStrip]: a bundled illustration plus its
/// human label. Swap [assetPath] for a real photo (png/jpg) later without
/// touching the strip itself.
class Garment {
  const Garment(this.assetPath, this.label);

  final String assetPath;
  final String label;
}

/// Builds the visual for a single [Garment] page. Defaults to rendering the
/// bundled SVG illustration; tests inject a lightweight placeholder so they
/// don't depend on asset loading.
typedef GarmentItemBuilder =
    Widget Function(BuildContext context, Garment garment);

/// A slim, auto-advancing carousel of the garments the team launders, sitting
/// beneath the dashboard header text on the brand gradient. It slides through
/// the garments on a gentle loop to make the header feel alive.
///
/// Honours reduce-motion: when the OS requests reduced motion it shows a static
/// strip (no auto-advance), and it reacts to the preference being toggled at
/// runtime — stopping or resuming the slide accordingly.
class GarmentStrip extends StatefulWidget {
  const GarmentStrip({
    super.key,
    this.itemBuilder,
    this.onPageChanged,
    this.autoAdvanceInterval = const Duration(milliseconds: 2800),
  });

  /// Overrides how each garment page is rendered. Defaults to the bundled SVG.
  final GarmentItemBuilder? itemBuilder;

  /// Notified with the settled page index whenever the carousel moves.
  final ValueChanged<int>? onPageChanged;

  /// How long each garment stays before sliding to the next.
  final Duration autoAdvanceInterval;

  /// The garments shown, in order. First entry renders on first paint.
  static const List<Garment> defaultGarments = [
    Garment('assets/garments/shorts.svg', 'Shorts'),
    Garment('assets/garments/trousers.svg', 'Trousers'),
    Garment('assets/garments/shirt.svg', 'Shirts'),
    Garment('assets/garments/dress.svg', 'Dresses'),
    Garment('assets/garments/jacket.svg', 'Jackets'),
    Garment('assets/garments/socks.svg', 'Socks'),
  ];

  @override
  State<GarmentStrip> createState() => _GarmentStripState();
}

class _GarmentStripState extends State<GarmentStrip> {
  // viewportFraction < 1 lets neighbouring garments peek in, giving the
  // sliding-carousel feel rather than a full-width page flip.
  final PageController _controller = PageController(viewportFraction: 0.46);
  Timer? _timer;
  int _index = 0;
  // +1 while sliding towards the last garment, -1 while sliding back. Ping-pong
  // rather than wrapping, so we never rewind across the whole strip at once.
  int _direction = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // React to runtime reduce-motion toggles: run the timer only while motion
    // is allowed, and stop it (static strip) the moment it isn't. Subscribing
    // to just the disableAnimations aspect avoids needless rebuilds.
    _syncAutoAdvance(MediaQuery.disableAnimationsOf(context));
  }

  void _syncAutoAdvance(bool reduceMotion) {
    if (reduceMotion) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(widget.autoAdvanceInterval, (_) => _advance());
    }
  }

  void _advance() {
    if (!_controller.hasClients) return;
    // Flip direction at either end so the slide reverses instead of rewinding
    // the whole strip back to the start.
    if (_index >= GarmentStrip.defaultGarments.length - 1) {
      _direction = -1;
    } else if (_index <= 0) {
      _direction = 1;
    }
    // Clamp guards against overshooting a boundary if a caller sets an
    // interval shorter than the slide animation, leaving _index lagging.
    _controller.animateToPage(
      (_index + _direction).clamp(0, GarmentStrip.defaultGarments.length - 1),
      duration: AppMotion.medium,
      curve: AppMotion.standard,
    );
  }

  void _onPageChanged(int index) {
    _index = index;
    widget.onPageChanged?.call(index);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.itemBuilder ?? _defaultItem;
    return PageView.builder(
      controller: _controller,
      onPageChanged: _onPageChanged,
      // Decorative auto-advancing strip: it drives itself, so don't let a
      // user drag compete with the surrounding ListView. animateToPage still
      // moves it programmatically.
      physics: const NeverScrollableScrollPhysics(),
      itemCount: GarmentStrip.defaultGarments.length,
      itemBuilder: (context, i) =>
          builder(context, GarmentStrip.defaultGarments[i]),
    );
  }

  /// White rounded card carrying the garment illustration and its label.
  Widget _defaultItem(BuildContext context, Garment garment) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              garment.assetPath,
              height: 40,
              width: 40,
              // The adjacent label already conveys the garment to screen
              // readers; skip the empty image node rather than double-announce.
              excludeFromSemantics: true,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                garment.label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.dark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

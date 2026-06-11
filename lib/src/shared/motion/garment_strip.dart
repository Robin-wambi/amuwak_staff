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
typedef GarmentItemBuilder = Widget Function(
  BuildContext context,
  Garment garment,
);

/// A slim, auto-advancing carousel of the garments the team launders, sitting
/// beneath the dashboard header text on the brand gradient. It slides through
/// the garments on a gentle loop to make the header feel alive.
///
/// Honours reduce-motion: when the OS requests reduced motion it shows a static
/// strip (no auto-advance), mirroring [AnimatedGradientHeader].
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
  bool _started = false;
  int _index = 0;
  // +1 while sliding towards the last garment, -1 while sliding back. Ping-pong
  // rather than wrapping, so we never rewind across the whole strip at once.
  int _direction = 1;

  List<Garment> get _garments => GarmentStrip.defaultGarments;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Static strip when the OS asks for reduced motion.
    if (!MediaQuery.of(context).disableAnimations) {
      _timer = Timer.periodic(widget.autoAdvanceInterval, (_) => _advance());
    }
  }

  void _advance() {
    if (!_controller.hasClients) return;
    // Flip direction at either end so the slide reverses instead of rewinding
    // the whole strip back to the start.
    if (_index >= _garments.length - 1) {
      _direction = -1;
    } else if (_index <= 0) {
      _direction = 1;
    }
    _controller.animateToPage(
      _index + _direction,
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
      itemCount: _garments.length,
      itemBuilder: (context, i) => builder(context, _garments[i]),
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

import 'package:flutter/material.dart';

import '../../shared/theme/app_spacing.dart';
import '../order.dart';
import 'order_card.dart';

/// A standalone, scrollable list of tappable [OrderCard]s with consistent
/// spacing. Shared by the orders tab and the order search results so the
/// card-list rendering (separator, padding, tap wiring) lives in one place.
///
/// Callers that want a section title render their own header above this in a
/// `Column` + `Expanded`, keeping their exact heading style — this widget owns
/// only the list itself, so there is no header/index bookkeeping here.
class OrderCardList extends StatelessWidget {
  const OrderCardList({
    super.key,
    required this.orders,
    required this.onOrderTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final List<LaundryOrder> orders;
  final void Function(LaundryOrder order) onOrderTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final order = orders[index];
        return OrderCard(order: order, onTap: () => onOrderTap(order));
      },
    );
  }
}

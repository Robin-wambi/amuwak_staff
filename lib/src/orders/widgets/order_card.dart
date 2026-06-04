import 'package:flutter/material.dart';

import '../../shared/theme/app_card.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_radii.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/status_colors.dart';
import '../order.dart';

/// A single order summary card: customer name, order code + service type,
/// time/item-count chips, and a status pill. Shared between the dashboard
/// order list and the order search results so both stay visually identical.
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, required this.onTap});

  final LaundryOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusPair = (Theme.of(context).extension<StatusColors>() ??
            StatusColors.light)
        .of(order.status);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.field - 2),
                ),
                child: Icon(
                  Icons.shopping_bag_outlined,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md + 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.customerName,
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs / 2),
                    Text(
                      '${order.orderCode} - ${order.serviceType.label}',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.secondaryText,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg - 2),
          Row(
            children: [
              _OrderInfoChip(
                icon: Icons.access_time_rounded,
                label: order.timeLabel,
              ),
              const SizedBox(width: AppSpacing.sm),
              _OrderInfoChip(
                icon: Icons.inventory_2_outlined,
                label: '${order.itemCount} items',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: statusPair.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.chip),
            ),
            child: Text(
              order.status.label,
              style: TextStyle(
                color: statusPair.onColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderInfoChip extends StatelessWidget {
  const _OrderInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

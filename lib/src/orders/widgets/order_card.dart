import 'package:flutter/material.dart';

import '../../shared/theme/app_card.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_radii.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/status_colors.dart';
import '../order.dart';
import '../order_status.dart';

/// A single order summary card: customer name, order code + service type,
/// time/item-count chips, and a status pill. Shared between the dashboard
/// order list and the order search results so both stay visually identical.
///
/// Contextual CRUD is opt-in via the optional [onEdit], [onDelete], and
/// [onAdvanceStatus] callbacks: supplying any of them adds a long-press actions
/// menu, and [onDelete] additionally enables swipe-to-delete (guarded by a
/// confirm dialog). With none supplied the card is the original tap-only
/// summary, so existing call sites are unaffected.
class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onAdvanceStatus,
  });

  final LaundryOrder order;
  final VoidCallback onTap;

  /// Opens the edit-details flow for this order. Null hides the menu entry.
  final VoidCallback? onEdit;

  /// Soft-deletes this order. Null hides the menu entry and disables swipe.
  final VoidCallback? onDelete;

  /// Advances this order to its next status. Only wired for the single
  /// proof-less transition (in progress → ready for delivery); pickup and
  /// delivery steps need proof capture and route through [onTap] instead.
  final VoidCallback? onAdvanceStatus;

  /// The next status reachable inline without proof capture. Only
  /// `inProgress → readyForDelivery` qualifies — pickup and delivery require
  /// photos / a barcode scan, so they are never advanced from the card.
  OrderStatus? get _quickAdvanceTarget => order.status == OrderStatus.inProgress
      ? OrderStatus.readyForDelivery
      : null;

  /// Label for the proof-gated step a pending/ready order must open Details to
  /// complete (null when the order isn't waiting on a proof step).
  String? get _proofStepLabel => switch (order.status) {
        OrderStatus.pendingPickup => 'Confirm pickup',
        OrderStatus.readyForDelivery => 'Confirm delivery',
        _ => null,
      };

  bool get _hasActionsMenu =>
      onEdit != null || onDelete != null || onAdvanceStatus != null;

  Future<void> _showActionsSheet(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;
    final quickTarget = _quickAdvanceTarget;
    final proofStep = _proofStepLabel;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit details'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onEdit!();
                },
              ),
            // A proof-less advance is offered directly; a proof-gated step
            // routes to the card tap (which opens Details' capture flow) so an
            // order is never marked picked-up/delivered without its proof.
            if (onAdvanceStatus != null && quickTarget != null)
              ListTile(
                leading: const Icon(Icons.arrow_forward_rounded),
                title: Text('Mark as ${quickTarget.label}'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onAdvanceStatus!();
                },
              )
            else if (onAdvanceStatus != null && proofStep != null)
              ListTile(
                leading: const Icon(Icons.qr_code_2_rounded),
                title: Text(proofStep),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onTap();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: colorScheme.error),
                title: Text('Delete',
                    style: TextStyle(color: colorScheme.error)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  if (await _confirmDelete(context)) onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Destructive actions always confirm. Returns true when the rider confirms.
  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete order?'),
        content: Text(
          'Delete order ${order.orderCode}? This hides it from the rider.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    Widget card = _buildCard(context);

    if (_hasActionsMenu) {
      card = GestureDetector(
        onLongPress: () => _showActionsSheet(context),
        child: card,
      );
    }

    if (onDelete != null) {
      card = Dismissible(
        key: ValueKey('order-card-${order.orderId}'),
        direction: DismissDirection.endToStart,
        background: _DeleteSwipeBackground(),
        // Returning false leaves the card in the tree: the soft-delete makes the
        // orders stream re-emit without this order, and the list rebuild removes
        // it. (Letting Dismissible drop it itself would assert until the stream
        // catches up, since the parent list is still the source of truth.)
        confirmDismiss: (_) async {
          if (await _confirmDelete(context)) onDelete!();
          return false;
        },
        child: card,
      );
    }

    return card;
  }

  Widget _buildCard(BuildContext context) {
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

/// The red trailing reveal behind a card as it's swiped left to delete.
class _DeleteSwipeBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Icon(Icons.delete_outline, color: colorScheme.error),
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

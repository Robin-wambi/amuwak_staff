import 'package:flutter/material.dart';

import '../orders/order.dart';
import '../orders/order_list_extensions.dart';
import '../orders/order_status.dart';
import '../shared/format_ugx.dart';
import '../shared/theme/app_card.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_radii.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/theme/status_colors.dart';

class DailyReportScreen extends StatelessWidget {
  const DailyReportScreen({super.key, required this.orders});

  final List<LaundryOrder> orders;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        title: const Text(
          'Daily report',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: DailyReportView(orders: orders),
    );
  }
}

class DailyReportView extends StatelessWidget {
  const DailyReportView({super.key, required this.orders});

  final List<LaundryOrder> orders;

  @override
  Widget build(BuildContext context) {
    final totalOrders = orders.length;
    final pendingPickup = orders.countByStatus(OrderStatus.pendingPickup);
    final inProgress = orders.countByStatus(OrderStatus.inProgress);
    final readyForDelivery = orders.countByStatus(OrderStatus.readyForDelivery);
    final completed = orders.countByStatus(OrderStatus.completed);
    final totalItems = orders.totalItems;
    final pendingWork = totalOrders - completed;
    final earnedRevenue = orders.earnedRevenueUgx;
    final expectedRevenue = orders.expectedRevenueUgx;
    // total == earned + expected by construction (every order is either
    // completed or not), so add them rather than make a third list pass.
    final totalRevenue = earnedRevenue + expectedRevenue;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.white,
                  child: Icon(
                    Icons.bar_chart_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg - 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's report",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Laundry operations summary',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Revenue',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          _RevenueCard(
            earned: earnedRevenue,
            expected: expectedRevenue,
            total: totalRevenue,
            completed: completed,
            pendingWork: pendingWork,
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: _ReportMetricCard(
                  title: 'Orders',
                  value: '$totalOrders',
                  icon: Icons.assignment_outlined,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _ReportMetricCard(
                  title: 'Items',
                  value: '$totalItems',
                  icon: Icons.inventory_2_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _ReportMetricCard(
                  title: OrderStatus.completed.label,
                  value: '$completed',
                  icon: Icons.check_circle_outline_rounded,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _ReportMetricCard(
                  title: 'Pending work',
                  value: '$pendingWork',
                  icon: Icons.pending_actions_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            'Status breakdown',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          _StatusBreakdownCard(
            pendingPickup: pendingPickup,
            inProgress: inProgress,
            readyForDelivery: readyForDelivery,
            completed: completed,
            totalOrders: totalOrders,
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            'Work summary',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          _WorkSummaryCard(
            totalOrders: totalOrders,
            completed: completed,
            pendingWork: pendingWork,
            totalItems: totalItems,
          ),
        ],
      ),
    );
  }
}

class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.field - 3),
            ),
            child: Icon(icon, color: colorScheme.primary),
          ),
          const SizedBox(height: AppSpacing.lg - 2),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.xs / 2),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({
    required this.earned,
    required this.expected,
    required this.total,
    required this.completed,
    required this.pendingWork,
  });

  final int earned;
  final int expected;
  final int total;
  final int completed;
  final int pendingWork;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RevenueRow(
            label: 'Earned',
            subtitle: '$completed completed',
            amountUgx: earned,
          ),
          const SizedBox(height: AppSpacing.lg - 2),
          _RevenueRow(
            label: 'Expected',
            subtitle: '$pendingWork outstanding',
            amountUgx: expected,
          ),
          const Divider(height: AppSpacing.xl),
          _RevenueRow(
            label: 'Total booked',
            amountUgx: total,
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _RevenueRow extends StatelessWidget {
  const _RevenueRow({
    required this.label,
    required this.amountUgx,
    this.subtitle,
    this.emphasized = false,
  });

  final String label;
  final int amountUgx;
  final String? subtitle;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: emphasized ? 16 : 15,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs / 2),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          formatUgx(amountUgx),
          style: TextStyle(
            color: emphasized ? colorScheme.primary : colorScheme.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: emphasized ? 18 : 16,
          ),
        ),
      ],
    );
  }
}

class _StatusBreakdownCard extends StatelessWidget {
  const _StatusBreakdownCard({
    required this.pendingPickup,
    required this.inProgress,
    required this.readyForDelivery,
    required this.completed,
    required this.totalOrders,
  });

  final int pendingPickup;
  final int inProgress;
  final int readyForDelivery;
  final int completed;
  final int totalOrders;

  @override
  Widget build(BuildContext context) {
    final statusColors =
        Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
    return AppCard(
      child: Column(
        children: [
          _StatusRow(
            label: OrderStatus.pendingPickup.label,
            value: pendingPickup,
            total: totalOrders,
            color: statusColors.of(OrderStatus.pendingPickup).color,
          ),
          const SizedBox(height: AppSpacing.lg - 2),
          _StatusRow(
            label: OrderStatus.inProgress.label,
            value: inProgress,
            total: totalOrders,
            color: statusColors.of(OrderStatus.inProgress).color,
          ),
          const SizedBox(height: AppSpacing.lg - 2),
          _StatusRow(
            label: OrderStatus.readyForDelivery.label,
            value: readyForDelivery,
            total: totalOrders,
            color: statusColors.of(OrderStatus.readyForDelivery).color,
          ),
          const SizedBox(height: AppSpacing.lg - 2),
          _StatusRow(
            label: OrderStatus.completed.label,
            value: completed,
            total: totalOrders,
            color: statusColors.of(OrderStatus.completed).color,
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final int value;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : value / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$value/$total',
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.chip),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 9,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _WorkSummaryCard extends StatelessWidget {
  const _WorkSummaryCard({
    required this.totalOrders,
    required this.completed,
    required this.pendingWork,
    required this.totalItems,
  });

  final int totalOrders;
  final int completed;
  final int pendingWork;
  final int totalItems;

  @override
  Widget build(BuildContext context) {
    final message = completed == totalOrders && totalOrders > 0
        ? 'All assigned laundry orders are completed for today.'
        : '$pendingWork orders still need attention before the day is closed.';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.summarize_outlined,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                "Today's progress",
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.dark,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Total items handled today: $totalItems',
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

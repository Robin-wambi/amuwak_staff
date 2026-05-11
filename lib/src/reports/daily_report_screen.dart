import 'package:flutter/material.dart';

import '../orders/order.dart';
import '../orders/order_list_extensions.dart';
import '../orders/order_status.dart';
import '../shared/widgets/app_theme.dart';

class DailyReportScreen extends StatelessWidget {
  const DailyReportScreen({super.key, required this.orders});

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

    return Scaffold(
      backgroundColor: amuwakBackground,
      appBar: AppBar(
        backgroundColor: amuwakBackground,
        foregroundColor: amuwakDark,
        elevation: 0,
        title: const Text(
          'Daily report',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: amuwakPrimary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.bar_chart_rounded,
                      color: amuwakPrimary,
                      size: 30,
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Today's report",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Laundry operations summary',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _ReportMetricCard(
                    title: 'Orders',
                    value: '$totalOrders',
                    icon: Icons.assignment_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ReportMetricCard(
                    title: 'Items',
                    value: '$totalItems',
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ReportMetricCard(
                    title: OrderStatus.completed.label,
                    value: '$completed',
                    icon: Icons.check_circle_outline_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ReportMetricCard(
                    title: 'Pending work',
                    value: '$pendingWork',
                    icon: Icons.pending_actions_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Status breakdown',
              style: TextStyle(
                color: amuwakDark,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _StatusBreakdownCard(
              pendingPickup: pendingPickup,
              inProgress: inProgress,
              readyForDelivery: readyForDelivery,
              completed: completed,
              totalOrders: totalOrders,
            ),
            const SizedBox(height: 24),
            const Text(
              'Work summary',
              style: TextStyle(
                color: amuwakDark,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _WorkSummaryCard(
              totalOrders: totalOrders,
              completed: completed,
              pendingWork: pendingWork,
              totalItems: totalItems,
            ),
          ],
        ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: amuwakWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: amuwakSoftAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: amuwakSoftAccent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: amuwakPrimary),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              color: amuwakDark,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: amuwakWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: amuwakSoftAccent),
      ),
      child: Column(
        children: [
          _StatusRow(
            label: OrderStatus.pendingPickup.label,
            value: pendingPickup,
            total: totalOrders,
            color: OrderStatus.pendingPickup.color,
          ),
          const SizedBox(height: 14),
          _StatusRow(
            label: OrderStatus.inProgress.label,
            value: inProgress,
            total: totalOrders,
            color: OrderStatus.inProgress.color,
          ),
          const SizedBox(height: 14),
          _StatusRow(
            label: OrderStatus.readyForDelivery.label,
            value: readyForDelivery,
            total: totalOrders,
            color: OrderStatus.readyForDelivery.color,
          ),
          const SizedBox(height: 14),
          _StatusRow(
            label: OrderStatus.completed.label,
            value: completed,
            total: totalOrders,
            color: OrderStatus.completed.color,
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
                style: const TextStyle(
                  color: amuwakDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$value/$total',
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 9,
            backgroundColor: amuwakBackground,
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: amuwakWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: amuwakSoftAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.summarize_outlined, color: amuwakPrimary),
              SizedBox(width: 8),
              Text(
                "Today's progress",
                style: TextStyle(
                  color: amuwakDark,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Total items handled today: $totalItems',
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

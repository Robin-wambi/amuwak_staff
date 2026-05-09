import 'package:flutter/material.dart';
import '../shared/widgets/app_theme.dart';

class StaffDashboardScreen extends StatelessWidget {
  const StaffDashboardScreen({super.key});

  static const List<_DashboardOrder> _orders = [
    _DashboardOrder(
      orderId: 'AMW-1024',
      customerName: 'Sarah N.',
      serviceType: 'Wash & Iron',
      status: 'Pending pickup',
      timeLabel: 'Pickup: 10:30 AM',
      itemCount: 8,
    ),
    _DashboardOrder(
      orderId: 'AMW-1025',
      customerName: 'Brian K.',
      serviceType: 'Dry cleaning',
      status: 'In progress',
      timeLabel: 'Due: 2:00 PM',
      itemCount: 3,
    ),
    _DashboardOrder(
      orderId: 'AMW-1026',
      customerName: 'Grace A.',
      serviceType: 'Iron only',
      status: 'Ready for delivery',
      timeLabel: 'Delivery: 4:30 PM',
      itemCount: 6,
    ),
    _DashboardOrder(
      orderId: 'AMW-1027',
      customerName: 'Daniel M.',
      serviceType: 'Wash only',
      status: 'Completed',
      timeLabel: 'Done: 9:15 AM',
      itemCount: 5,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final totalOrders = _orders.length;
    final pendingPickup = _orders
        .where((order) => order.status == 'Pending pickup')
        .length;
    final inProgress = _orders
        .where((order) => order.status == 'In progress')
        .length;
    final readyForDelivery = _orders
        .where((order) => order.status == 'Ready for delivery')
        .length;
    final completed = _orders
        .where((order) => order.status == 'Completed')
        .length;

    return Scaffold(
      backgroundColor: amuwakBackground,
      appBar: AppBar(
        backgroundColor: amuwakBackground,
        foregroundColor: amuwakDark,
        elevation: 0,
        title: const Text(
          'Amuwak Staff',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const _DashboardHeader(),
            const SizedBox(height: 20),
            _SummaryGrid(
              totalOrders: totalOrders,
              pendingPickup: pendingPickup,
              inProgress: inProgress,
              readyForDelivery: readyForDelivery,
              completed: completed,
            ),
            const SizedBox(height: 24),
            const _QuickActions(),
            const SizedBox(height: 24),
            const Text(
              'Assigned orders',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: amuwakDark,
              ),
            ),
            const SizedBox(height: 12),
            for (final order in _orders) ...[
              _OrderCard(order: order),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: amuwakPrimary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: amuwakPrimary.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.local_laundry_service_rounded,
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
                  'Welcome back',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                SizedBox(height: 3),
                Text(
                  'Staff Workspace',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  "Today's laundry operations",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.totalOrders,
    required this.pendingPickup,
    required this.inProgress,
    required this.readyForDelivery,
    required this.completed,
  });

  final int totalOrders;
  final int pendingPickup;
  final int inProgress;
  final int readyForDelivery;
  final int completed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'Assigned',
                value: '$totalOrders',
                icon: Icons.assignment_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Pickup',
                value: '$pendingPickup',
                icon: Icons.local_shipping_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'In progress',
                value: '$inProgress',
                icon: Icons.timelapse_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Ready',
                value: '$readyForDelivery',
                icon: Icons.checkroom_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SummaryCard(
          title: 'Completed today',
          value: '$completed',
          icon: Icons.check_circle_outline_rounded,
          wide: true,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    this.wide = false,
  });

  final String title;
  final String value;
  final IconData icon;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: amuwakWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: amuwakSoftAccent),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: amuwakSoftAccent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: amuwakPrimary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: amuwakDark,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick actions',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: amuwakDark,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'New pickup',
                icon: Icons.add_location_alt_outlined,
                onTap: () {},
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                label: 'Check order',
                icon: Icons.search_rounded,
                onTap: () {},
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                label: 'Report',
                icon: Icons.bar_chart_rounded,
                onTap: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: amuwakWhite,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: amuwakSoftAccent),
          ),
          child: Column(
            children: [
              Icon(icon, color: amuwakPrimary),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: amuwakDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final _DashboardOrder order;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(order.status);

    return Material(
      color: amuwakWhite,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: amuwakSoftAccent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: amuwakSoftAccent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: amuwakPrimary,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.customerName,
                          style: const TextStyle(
                            color: amuwakDark,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${order.orderId} - ${order.serviceType}',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.black38,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.access_time_rounded,
                    label: order.timeLabel,
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.inventory_2_outlined,
                    label: '${order.itemCount} items',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  order.status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Pending pickup':
        return const Color(0xFF9A5B00);
      case 'In progress':
        return const Color(0xFF7A4CC2);
      case 'Ready for delivery':
        return const Color(0xFF0B7285);
      case 'Completed':
        return const Color(0xFF2F7D32);
      default:
        return amuwakPrimary;
    }
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: amuwakBackground,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: amuwakPrimary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
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

class _DashboardOrder {
  const _DashboardOrder({
    required this.orderId,
    required this.customerName,
    required this.serviceType,
    required this.status,
    required this.timeLabel,
    required this.itemCount,
  });

  final String orderId;
  final String customerName;
  final String serviceType;
  final String status;
  final String timeLabel;
  final int itemCount;
}

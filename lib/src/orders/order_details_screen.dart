import 'package:flutter/material.dart';

import '../shared/widgets/app_theme.dart';
import 'order.dart';

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, required this.order});

  final LaundryOrder order;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  late LaundryOrder _order;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  String? _nextStatus(String status) {
    switch (status) {
      case 'Pending pickup':
        return 'In progress';
      case 'In progress':
        return 'Ready for delivery';
      case 'Ready for delivery':
        return 'Completed';
      case 'Completed':
        return null;
      default:
        return null;
    }
  }

  void _updateStatus() {
    final nextStatus = _nextStatus(_order.status);

    if (nextStatus == null) {
      return;
    }

    setState(() {
      _order = _order.copyWith(status: nextStatus);
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Order moved to $nextStatus.')));
  }

  void _handleBackNavigation() {
    Navigator.pop(context, _order);
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(_order.status);
    final nextStatus = _nextStatus(_order.status);
    final isCompleted = nextStatus == null;

    return PopScope<LaundryOrder>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackNavigation();
        }
      },
      child: Scaffold(
        backgroundColor: amuwakBackground,
        appBar: AppBar(
          backgroundColor: amuwakBackground,
          foregroundColor: amuwakDark,
          elevation: 0,
          title: const Text(
            'Order details',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              Navigator.pop(context, _order);
            },
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
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.local_laundry_service_rounded,
                        color: amuwakPrimary,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _order.orderId,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _order.customerName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _order.serviceType,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 10, color: statusColor),
                    const SizedBox(width: 8),
                    Text(
                      _order.status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _DetailsSection(
                title: 'Customer',
                children: [
                  _DetailRow(
                    icon: Icons.person_outline,
                    label: 'Name',
                    value: _order.customerName,
                  ),
                  _DetailRow(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: _order.phone,
                  ),
                  _DetailRow(
                    icon: Icons.location_on_outlined,
                    label: 'Address',
                    value: _order.address,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _DetailsSection(
                title: 'Laundry details',
                children: [
                  _DetailRow(
                    icon: Icons.receipt_long_outlined,
                    label: 'Order ID',
                    value: _order.orderId,
                  ),
                  _DetailRow(
                    icon: Icons.checkroom_outlined,
                    label: 'Service',
                    value: _order.serviceType,
                  ),
                  _DetailRow(
                    icon: Icons.inventory_2_outlined,
                    label: 'Items',
                    value: '${_order.itemCount} items',
                  ),
                  _DetailRow(
                    icon: Icons.access_time_rounded,
                    label: 'Time',
                    value: _order.timeLabel,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _DetailsSection(
                title: 'Notes',
                children: [
                  Text(
                    _order.notes,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: isCompleted ? null : _updateStatus,
                icon: Icon(
                  isCompleted
                      ? Icons.check_circle_outline_rounded
                      : Icons.update_rounded,
                ),
                label: Text(
                  isCompleted ? 'Order completed' : 'Move to $nextStatus',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isCompleted
                    ? 'This order has reached the final status.'
                    : 'This will update the order to the next laundry stage.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black45, fontSize: 13),
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

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: amuwakWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: amuwakSoftAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: amuwakDark,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: amuwakPrimary, size: 21),
          const SizedBox(width: 10),
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: amuwakDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

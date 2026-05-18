import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../notifications/notifications_screen.dart';
import '../orders/new_pickup_screen.dart';
import '../orders/order.dart';
import '../orders/order_details_screen.dart';
import '../orders/order_list_extensions.dart';
import '../orders/order_search_screen.dart';
import '../orders/order_status.dart';
import '../orders/proof/barcode_reader.dart';
import '../orders/proof/proof_photo_storage.dart';
import '../reports/daily_report_screen.dart';
import '../shared/widgets/app_theme.dart';

typedef RetrieveLostPhotoFn = Future<bool> Function();

class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({
    super.key,
    this.retrieveLostPhoto,
  });

  // On Android the OS may kill MainActivity while the camera is open, dropping
  // the photo bytes silently. We check on startup so the rider knows to retry
  // instead of believing the capture succeeded. iOS is a no-op (empty response).
  final RetrieveLostPhotoFn? retrieveLostPhoto;

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  final List<LaundryOrder> _orders = [
    const LaundryOrder(
      orderId: 'AMW-1024',
      customerName: 'Sarah N.',
      serviceType: 'Wash & Iron',
      status: OrderStatus.pendingPickup,
      timeLabel: 'Pickup: 10:30 AM',
      itemCount: 8,
      phone: '+256 700 123 456',
      address: 'Kikoni, near Makerere western gate',
      notes: 'Customer requested careful handling for white shirts.',
    ),
    const LaundryOrder(
      orderId: 'AMW-1025',
      customerName: 'Brian K.',
      serviceType: 'Dry cleaning',
      status: OrderStatus.inProgress,
      timeLabel: 'Due: 2:00 PM',
      itemCount: 3,
      phone: '+256 701 456 789',
      address: 'Wandegeya, opposite main stage',
      notes: 'Suit jacket and trousers. Keep separate from regular wash.',
    ),
    const LaundryOrder(
      orderId: 'AMW-1026',
      customerName: 'Grace A.',
      serviceType: 'Iron only',
      status: OrderStatus.readyForDelivery,
      timeLabel: 'Delivery: 4:30 PM',
      itemCount: 6,
      phone: '+256 702 222 111',
      address: 'Nakulabye, close to Shell',
      notes: 'Call before delivery.',
    ),
    const LaundryOrder(
      orderId: 'AMW-1027',
      customerName: 'Daniel M.',
      serviceType: 'Wash only',
      status: OrderStatus.completed,
      timeLabel: 'Done: 9:15 AM',
      itemCount: 5,
      phone: '+256 703 333 222',
      address: 'Bwaise, main road',
      notes: 'Paid in cash at pickup.',
    ),
  ];

  // Backend deferred per SPEC-000: photos live in memory only. Swap for
  // `createDefaultProofPhotoStorage()` once the upload endpoint is available.
  final ProofPhotoStorage _photoStorage = InMemoryProofPhotoStorage();
  final ImagePicker _imagePicker = ImagePicker();
  final CameraViewBuilder _cameraViewBuilder = mobileScannerCameraViewBuilder();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final retriever = widget.retrieveLostPhoto ?? _defaultRetrieveLostPhoto;
      final lost = await retriever();
      if (!mounted || !lost) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your last photo capture was interrupted. Please retry.',
          ),
        ),
      );
    });
  }

  Future<bool> _defaultRetrieveLostPhoto() async {
    try {
      final response = await _imagePicker.retrieveLostData();
      if (response.isEmpty) return false;
      return response.file != null ||
          (response.files?.isNotEmpty ?? false) ||
          response.exception != null;
    } catch (_) {
      return false;
    }
  }

  Future<List<int>?> _pickPhoto() async {
    final XFile? file = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  void _replaceUpdatedOrder(LaundryOrder updatedOrder) {
    final orderIndex = _orders.indexWhere(
      (order) => order.orderId == updatedOrder.orderId,
    );

    if (orderIndex == -1) {
      return;
    }

    setState(() {
      _orders[orderIndex] = updatedOrder;
    });
  }

  Future<void> _openOrderDetails(LaundryOrder order) async {
    final updatedOrder = await Navigator.of(context).push<LaundryOrder>(
      MaterialPageRoute(
        builder: (_) => OrderDetailsScreen(
          order: order,
          photoStorage: _photoStorage,
          pickPhoto: _pickPhoto,
          cameraViewBuilder: _cameraViewBuilder,
        ),
      ),
    );

    if (!mounted) return;
    if (updatedOrder != null) {
      _replaceUpdatedOrder(updatedOrder);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalOrders = _orders.length;
    final pendingPickup = _orders.countByStatus(OrderStatus.pendingPickup);
    final inProgress = _orders.countByStatus(OrderStatus.inProgress);
    final readyForDelivery = _orders.countByStatus(OrderStatus.readyForDelivery);
    final completed = _orders.countByStatus(OrderStatus.completed);

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
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
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
            _QuickActions(orders: _orders),
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
              _OrderCard(order: order, onTap: () => _openOrderDetails(order)),
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
                title: OrderStatus.pendingPickup.label,
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
                title: OrderStatus.inProgress.label,
                value: '$inProgress',
                icon: Icons.timelapse_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: OrderStatus.readyForDelivery.label,
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
  const _QuickActions({required this.orders});

  final List<LaundryOrder> orders;

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
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const NewPickupScreen()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                label: 'Check order',
                icon: Icons.search_rounded,
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const OrderSearchScreen()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                label: 'Report',
                icon: Icons.bar_chart_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      // Pass a snapshot so the report reflects counts at the
                      // moment it was opened, not later dashboard mutations.
                      builder: (_) => DailyReportScreen(
                        orders: List<LaundryOrder>.from(orders),
                      ),
                    ),
                  );
                },
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
  const _OrderCard({required this.order, required this.onTap});

  final LaundryOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = order.status.color;

    return Material(
      color: amuwakWhite,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
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
                  order.status.label,
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

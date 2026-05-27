import 'package:flutter/material.dart';

import '../shared/widgets/app_theme.dart';
import 'order.dart';
import 'order_status.dart';
import 'proof_event.dart';
import 'proof/barcode_reader.dart';
import 'proof/delivery_capture_screen.dart';
import 'proof/pickup_capture_screen.dart';
import 'proof/proof_photo_storage.dart';
import 'proof/scanner_screen.dart';

DateTime _defaultClock() => DateTime.now();

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({
    super.key,
    required this.order,
    required this.photoStorage,
    required this.pickPhoto,
    required this.cameraViewBuilder,
    this.clock = _defaultClock,
  });

  final LaundryOrder order;
  final ProofPhotoStorage photoStorage;
  final PickPhotoFn pickPhoto;
  final CameraViewBuilder cameraViewBuilder;
  final DateTime Function() clock;

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

  void _advanceStatusDirectly() {
    final nextStatus = _order.status.nextStatus;
    if (nextStatus == null) return;
    setState(() {
      _order = _order.copyWith(status: nextStatus);
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text('Order moved to ${nextStatus.label}.')),
      );
  }


  Future<void> _confirmPickup() async {
    final result = await Navigator.of(context).push<LaundryOrder>(
      MaterialPageRoute(
        builder: (_) => PickupCaptureScreen(
          order: _order,
          photoStorage: widget.photoStorage,
          pickPhoto: widget.pickPhoto,
          clock: widget.clock,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _order = result);
    }
  }

  Future<void> _confirmDelivery() async {
    final scanOk = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          expectedOrderId: _order.orderId,
          cameraViewBuilder: widget.cameraViewBuilder,
        ),
      ),
    );
    if (scanOk != true || !mounted) return;
    final result = await Navigator.of(context).push<LaundryOrder>(
      MaterialPageRoute(
        builder: (_) => DeliveryCaptureScreen(
          order: _order,
          photoStorage: widget.photoStorage,
          pickPhoto: widget.pickPhoto,
          clock: widget.clock,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _order = result);
    }
  }

  void _handleBackNavigation() {
    Navigator.pop(context, _order);
  }

  Widget _buildPrimaryAction() {
    switch (_order.status) {
      case OrderStatus.pendingPickup:
        return ElevatedButton(
          onPressed: _confirmPickup,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_2_rounded),
              SizedBox(width: 8),
              Text('Confirm pickup'),
            ],
          ),
        );
      case OrderStatus.inProgress:
        return ElevatedButton(
          onPressed: _advanceStatusDirectly,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.update_rounded),
              SizedBox(width: 8),
              Text('Move to Ready for delivery'),
            ],
          ),
        );
      case OrderStatus.readyForDelivery:
        return ElevatedButton(
          onPressed: _confirmDelivery,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delivery_dining_rounded),
              SizedBox(width: 8),
              Text('Deliver'),
            ],
          ),
        );
      case OrderStatus.completed:
        return ElevatedButton(
          onPressed: null,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline_rounded),
              SizedBox(width: 8),
              Text('Order completed'),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _order.status.color;

    return PopScope<LaundryOrder>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBackNavigation();
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
            onPressed: _handleBackNavigation,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _OrderHeader(order: _order),
                      const SizedBox(height: 18),
                      _StatusChip(
                          color: statusColor, label: _order.status.label),
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
                            _order.notes.isEmpty ? '—' : _order.notes,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                      if (_order.proofEvents.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _DetailsSection(
                          title: 'History',
                          children: [
                            for (final event in _order.proofEvents)
                              _ProofEventRow(event: event, now: widget.clock()),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: _buildPrimaryAction(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.order});
  final LaundryOrder order;
  @override
  Widget build(BuildContext context) {
    return Container(
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
                  order.orderId,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  order.customerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  order.serviceType,
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
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
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
        border: Border.all(color: amuwakPrimary.withValues(alpha: 0.18)),
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

class _ProofEventRow extends StatelessWidget {
  const _ProofEventRow({required this.event, required this.now});
  final ProofEvent event;
  final DateTime now;

  static const _monthAbbreviations = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _label =>
      event.type == ProofEventType.pickup ? 'Pickup' : 'Delivery';

  String get _timestampText {
    final dt = event.capturedAt;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) return '$hh:$mm';
    return '${dt.day} ${_monthAbbreviations[dt.month - 1]} · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          Icon(
            event.type == ProofEventType.pickup
                ? Icons.qr_code_2_rounded
                : Icons.delivery_dining_rounded,
            color: amuwakPrimary,
            size: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$_label · $_timestampText · ${event.count} items · '
              '${event.photoPaths.length} photo(s)',
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

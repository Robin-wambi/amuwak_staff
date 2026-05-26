import 'package:flutter/material.dart';

import '../data/app_database.dart' show Customer;
import '../shared/widgets/app_theme.dart';
import '../sync/customers_repository.dart';
import '../sync/orders_repository.dart';
import 'geo_services.dart';
import 'new_pickup_result.dart';
import 'order.dart';
import 'order_status.dart';
import 'service_type.dart';

class NewPickupScreen extends StatefulWidget {
  const NewPickupScreen({
    super.key,
    required this.customersRepo,
    required this.ordersRepo,
    required this.actorStaffId,
    required this.clock,
    required this.orderIdGenerator,
    required this.customerIdGenerator,
    required this.geolocate,
    required this.reverseGeocode,
  });

  final CustomersRepository customersRepo;
  final OrdersRepository ordersRepo;
  final String actorStaffId;
  final DateTime Function() clock;
  final String Function() orderIdGenerator;
  final String Function() customerIdGenerator;
  final GeolocateFn geolocate;
  final ReverseGeocodeFn reverseGeocode;

  @override
  State<NewPickupScreen> createState() => _NewPickupScreenState();
}

class _NewPickupScreenState extends State<NewPickupScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(text: '+256 ');
  final _addressController = TextEditingController();
  ServiceType? _serviceType;
  bool _saving = false;

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      _phoneController.text.trim().length >= 9 &&
      _addressController.text.trim().isNotEmpty &&
      _serviceType != null &&
      !_saving;

  Future<void> _onSubmit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final now = widget.clock();
    final customer = Customer(
      id: widget.customerIdGenerator(),
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      notes: null,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );
    try {
      await widget.customersRepo.upsertCustomer(customer);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not save customer. Please try again.')),
      );
      return;
    }
    final orderId = widget.orderIdGenerator();
    final order = LaundryOrder(
      orderId: orderId,
      orderCode: 'AMW-${now.millisecondsSinceEpoch}',
      customerId: customer.id,
      customerName: customer.name,
      phone: customer.phone,
      address: customer.address ?? '',
      serviceType: _serviceType!,
      status: OrderStatus.pendingPickup,
      timeLabel: 'Pickup: now',
      itemCount: 0,
      notes: '',
    );
    try {
      await widget.ordersRepo
          .upsertOrder(order, actorStaffId: widget.actorStaffId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Customer was saved, but the order could not be saved. '
            'Tap Create pickup again to retry.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop<NewPickupResult>(
      context,
      NewPickupResult(orderId: orderId, startPickupNow: true),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: amuwakBackground,
      appBar: AppBar(
        backgroundColor: amuwakBackground,
        foregroundColor: amuwakDark,
        elevation: 0,
        title: const Text('New pickup'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextFormField(
              key: const Key('np_name'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Customer name'),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('np_phone'),
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('np_address'),
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Address'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ServiceType>(
              key: const Key('np_service_type'),
              decoration: const InputDecoration(labelText: 'Service type'),
              value: _serviceType,
              items: ServiceType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) => setState(() => _serviceType = v),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, null),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _canSubmit ? _onSubmit : null,
                    child: const Text('Create pickup'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

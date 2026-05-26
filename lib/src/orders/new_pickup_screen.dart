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

enum _PickupTimeMode { now, scheduled }

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
  final _phoneFocus = FocusNode();
  ServiceType? _serviceType;
  bool _saving = false;
  bool _locating = false;
  String? _matchedCustomerId;
  _PickupTimeMode _pickupMode = _PickupTimeMode.now;
  DateTime? _scheduledFor;

  void _setQuickSchedule(DateTime when) {
    setState(() => _scheduledFor = when);
  }

  Future<void> _pickCustomDateTime() async {
    final now = widget.clock();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;
    setState(() => _scheduledFor = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ));
  }

  @override
  void initState() {
    super.initState();
    _phoneFocus.addListener(_onPhoneFocusChange);
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      _phoneController.text.trim().length >= 9 &&
      _addressController.text.trim().isNotEmpty &&
      _serviceType != null &&
      !_saving;

  String _normalizePhone(String s) =>
      s.replaceAll(RegExp(r'\s+'), '').replaceAll('+', '');

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final loc = await widget.geolocate();
      if (loc == null) return;
      final addr = await widget.reverseGeocode(loc);
      if (addr == null || !mounted) return;
      setState(() => _addressController.text = addr);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _onPhoneFocusChange() async {
    if (_phoneFocus.hasFocus) return;
    final typed = _normalizePhone(_phoneController.text);
    if (typed.length < 9) return;
    final all = await widget.customersRepo.getAll();
    Customer? matched;
    for (final c in all) {
      if (_normalizePhone(c.phone) == typed) {
        matched = c;
        break;
      }
    }
    if (matched == null || !mounted) return;
    await _showCustomerMatchSheet(matched);
  }

  Future<void> _showCustomerMatchSheet(Customer match) async {
    final useIt = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Existing customer found',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Text(match.name, style: const TextStyle(fontSize: 16)),
              if (match.address != null) ...[
                const SizedBox(height: 4),
                Text(match.address!,
                    style: const TextStyle(color: Colors.black54)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Different customer'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Use this customer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (useIt == true && mounted) {
      setState(() {
        _matchedCustomerId = match.id;
        _nameController.text = match.name;
        _addressController.text = match.address ?? '';
      });
    }
  }

  Future<void> _onSubmit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final now = widget.clock();
    final customer = Customer(
      id: _matchedCustomerId ?? widget.customerIdGenerator(),
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
    final scheduled = _scheduledFor;
    final order = LaundryOrder(
      orderId: orderId,
      orderCode: 'AMW-${now.millisecondsSinceEpoch}',
      customerId: customer.id,
      customerName: customer.name,
      phone: customer.phone,
      address: customer.address ?? '',
      serviceType: _serviceType!,
      status: OrderStatus.pendingPickup,
      timeLabel: scheduled == null ? 'Pickup: now' : 'Pickup: $scheduled',
      itemCount: 0,
      notes: '',
      scheduledFor: scheduled,
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
      NewPickupResult(orderId: orderId, startPickupNow: scheduled == null),
    );
  }

  @override
  void dispose() {
    _phoneFocus.removeListener(_onPhoneFocusChange);
    _phoneFocus.dispose();
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
              focusNode: _phoneFocus,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.my_location, size: 18),
                label: const Text('Use my location'),
                onPressed: _locating ? null : _useMyLocation,
              ),
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 12),
            SegmentedButton<_PickupTimeMode>(
              segments: const [
                ButtonSegment(
                    value: _PickupTimeMode.now, label: Text('Pickup now')),
                ButtonSegment(
                    value: _PickupTimeMode.scheduled,
                    label: Text('Schedule for later')),
              ],
              selected: <_PickupTimeMode>{_pickupMode},
              onSelectionChanged: (sel) => setState(() {
                _pickupMode = sel.first;
                if (_pickupMode == _PickupTimeMode.now) _scheduledFor = null;
              }),
            ),
            if (_pickupMode == _PickupTimeMode.scheduled) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('In 1 hour'),
                    selected: false,
                    onSelected: (_) => _setQuickSchedule(
                        widget.clock().add(const Duration(hours: 1))),
                  ),
                  ChoiceChip(
                    label: const Text('Tomorrow morning'),
                    selected: false,
                    onSelected: (_) {
                      final t = widget.clock().add(const Duration(days: 1));
                      _setQuickSchedule(DateTime(t.year, t.month, t.day, 9));
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Tomorrow afternoon'),
                    selected: false,
                    onSelected: (_) {
                      final t = widget.clock().add(const Duration(days: 1));
                      _setQuickSchedule(DateTime(t.year, t.month, t.day, 14));
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Custom…'),
                    selected: false,
                    onSelected: (_) => _pickCustomDateTime(),
                  ),
                ],
              ),
              if (_scheduledFor != null) ...[
                const SizedBox(height: 8),
                Text('Scheduled for: $_scheduledFor',
                    style: const TextStyle(color: Colors.black54)),
              ],
            ],
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_database.dart' show Customer;
import '../shared/format_ugx.dart';
import '../shared/phone.dart';
import '../shared/theme/app_colors.dart';
import '../sync/customers_repository.dart';
import '../sync/orders_repository.dart';
import 'geo_services.dart';
import 'new_pickup_result.dart';
import 'order.dart';
import 'order_status.dart';
import 'service_type.dart';

enum _PickupTimeMode { now, scheduled }

enum _ScheduleChip { inOneHour, tomorrowMorning, tomorrowAfternoon, custom }

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
    required this.defaultRatePerKgUgx,
  });

  final CustomersRepository customersRepo;
  final OrdersRepository ordersRepo;
  final String actorStaffId;
  final DateTime Function() clock;
  final String Function() orderIdGenerator;
  final String Function() customerIdGenerator;
  final GeolocateFn geolocate;
  final ReverseGeocodeFn reverseGeocode;
  final double defaultRatePerKgUgx;

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
  double? _matchedCustomerRate;
  // Cached IDs survive an upsertOrder-fail retry so the rider doesn't
  // create a duplicate customer row by tapping "Create pickup" again.
  String? _pendingCustomerId;
  String? _pendingOrderId;
  String? _pendingOrderCode;
  _PickupTimeMode _pickupMode = _PickupTimeMode.now;
  DateTime? _scheduledFor;
  // Which quick-chip preset is currently selected, if any. Cleared when
  // _scheduledFor changes via a different path (e.g. Custom… picker).
  _ScheduleChip? _selectedChip;
  bool _optionalExpanded = false;
  int _count = 0;
  // Guards against fat-fingering a four-digit item count on the stepper.
  static const _maxItemCount = 99;
  final _notesController = TextEditingController();

  double get _resolvedRate => _matchedCustomerRate ?? widget.defaultRatePerKgUgx;

  void _setQuickSchedule(_ScheduleChip chip, DateTime when) {
    setState(() {
      _scheduledFor = when;
      _selectedChip = chip;
    });
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
    setState(() {
      _scheduledFor = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _selectedChip = _ScheduleChip.custom;
    });
  }

  @override
  void initState() {
    super.initState();
    _phoneFocus.addListener(_onPhoneFocusChange);
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      ugandaNationalDigits(_phoneController.text).length == 9 &&
      _addressController.text.trim().isNotEmpty &&
      _serviceType != null &&
      !_saving;

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final loc = await widget.geolocate();
      if (loc == null) return;
      final addr = await widget.reverseGeocode(loc);
      if (!mounted) return;
      if (addr == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Could not determine address — please type it manually.'),
          ),
        );
        return;
      }
      setState(() => _addressController.text = addr);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _onPhoneFocusChange() async {
    if (_phoneFocus.hasFocus) return;
    final typed = ugandaNationalDigits(_phoneController.text);
    if (typed.length != 9) return;
    // FocusNode.addListener takes a VoidCallback and discards the Future
    // this async listener returns, so a thrown error becomes an unhandled
    // zone error. Catch and surface via SnackBar instead.
    try {
      final all = await widget.customersRepo.getAll();
      Customer? matched;
      for (final c in all) {
        if (ugandaNationalDigits(c.phone) == typed) {
          matched = c;
          break;
        }
      }
      if (matched == null || !mounted) return;
      await _showCustomerMatchSheet(matched);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not check for existing customers.'),
        ),
      );
    }
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
                    style: const TextStyle(color: AppColors.secondaryText)),
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
        _matchedCustomerRate = match.customRatePerKgUgx;
        _nameController.text = match.name;
        _addressController.text = match.address ?? '';
      });
    }
  }

  Future<void> _onSubmit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final now = widget.clock();
    final customerId = _matchedCustomerId ??
        (_pendingCustomerId ??= widget.customerIdGenerator());
    final customer = Customer(
      id: customerId,
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
    final orderId = _pendingOrderId ??= widget.orderIdGenerator();
    // `??=` so a retried submit reuses the first code instead of burning a
    // second value off the server-side counter.
    final String orderCode;
    try {
      orderCode = _pendingOrderCode ??= await widget.ordersRepo.reserveOrderCode();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not reserve an order number. '
                'Check your connection and tap Create pickup again.')),
      );
      return;
    }
    final scheduled = _scheduledFor;
    final order = LaundryOrder(
      orderId: orderId,
      orderCode: orderCode,
      customerId: customer.id,
      customerName: customer.name,
      phone: customer.phone,
      address: customer.address ?? '',
      serviceType: _serviceType!,
      status: OrderStatus.pendingPickup,
      timeLabel: LaundryOrder.computeTimeLabel(
        scheduledFor: scheduled,
        now: widget.clock,
      ),
      itemCount: _count,
      notes: _notesController.text.trim(),
      scheduledFor: scheduled,
      ratePerKgSnapshotUgx: _resolvedRate,
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
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
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
              inputFormatters: const [_UgandaNationalDigitsLimiter()],
              decoration: const InputDecoration(labelText: 'Phone'),
              onChanged: (_) => setState(() {
                _matchedCustomerId = null;
                _matchedCustomerRate = null;
              }),
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Rate: ${formatUgx(_resolvedRate.round())}/kg',
                key: const Key('np_rate'),
                style: const TextStyle(color: AppColors.secondaryText),
              ),
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
                if (_pickupMode == _PickupTimeMode.now) {
                  _scheduledFor = null;
                  _selectedChip = null;
                }
              }),
            ),
            if (_pickupMode == _PickupTimeMode.scheduled) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('In 1 hour'),
                    selected: _selectedChip == _ScheduleChip.inOneHour,
                    onSelected: (_) => _setQuickSchedule(
                        _ScheduleChip.inOneHour,
                        widget.clock().add(const Duration(hours: 1))),
                  ),
                  ChoiceChip(
                    label: const Text('Tomorrow morning'),
                    selected: _selectedChip == _ScheduleChip.tomorrowMorning,
                    onSelected: (_) {
                      final t = widget.clock().add(const Duration(days: 1));
                      _setQuickSchedule(_ScheduleChip.tomorrowMorning,
                          DateTime(t.year, t.month, t.day, 9));
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Tomorrow afternoon'),
                    selected: _selectedChip == _ScheduleChip.tomorrowAfternoon,
                    onSelected: (_) {
                      final t = widget.clock().add(const Duration(days: 1));
                      _setQuickSchedule(_ScheduleChip.tomorrowAfternoon,
                          DateTime(t.year, t.month, t.day, 14));
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Custom…'),
                    selected: _selectedChip == _ScheduleChip.custom,
                    onSelected: (_) => _pickCustomDateTime(),
                  ),
                ],
              ),
              if (_scheduledFor != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Scheduled for: ${LaundryOrder.formatScheduled(_scheduledFor!, now: widget.clock)}',
                  style: const TextStyle(color: AppColors.secondaryText),
                ),
              ],
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: () =>
                  setState(() => _optionalExpanded = !_optionalExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(_optionalExpanded
                        ? Icons.expand_less
                        : Icons.expand_more),
                    const SizedBox(width: 8),
                    Text(
                      'Add optional details',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
            ),
            if (_optionalExpanded) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed:
                        _count > 0 ? () => setState(() => _count--) : null,
                  ),
                  SizedBox(
                    width: 60,
                    child: Text('$_count',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    key: const Key('np_count_inc'),
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _count < _maxItemCount
                        ? () => setState(() => _count++)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('np_notes'),
                controller: _notesController,
                decoration:
                    const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 3,
              ),
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
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create pickup'),
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

/// Blocks edits that would push the phone field past 9 national digits, so a
/// rider can't type more than a complete Ugandan mobile number. Tolerates the
/// `+256 ` prefix and any spacing — the cap is on [ugandaNationalDigits], not
/// raw characters.
class _UgandaNationalDigitsLimiter extends TextInputFormatter {
  const _UgandaNationalDigitsLimiter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (ugandaNationalDigits(newValue.text).length > 9) return oldValue;
    return newValue;
  }
}

import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_database.dart' show Customer;
import '../shared/format_ugx.dart';
import '../shared/phone.dart';
import '../sync/customers_repository.dart';
import '../sync/orders_repository.dart';
import 'geo_services.dart';
import 'new_pickup_result.dart';
import 'order.dart';
import 'order_status.dart';
import 'service_type.dart';

enum _PickupTimeMode { now, scheduled }

enum _ScheduleChip { inOneHour, tomorrowMorning, tomorrowAfternoon, custom }

/// Whether [chosen] is before the start of [now]'s minute — i.e. already in the
/// past for scheduling purposes. Compared at minute granularity so picking the
/// current minute (the time picker yields seconds == 0, while [now] carries
/// real seconds) is treated as valid rather than wrongly rejected.
@visibleForTesting
bool scheduledTimeIsInPast(DateTime chosen, DateTime now) {
  final nowMinute =
      DateTime(now.year, now.month, now.day, now.hour, now.minute);
  return chosen.isBefore(nowMinute);
}

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
  final _addressFocus = FocusNode();
  ServiceType? _serviceType;
  // Distinct previously-used customer addresses, most-common first, for the
  // address field's auto-suggest. Best-effort: empty if the one-shot load fails.
  List<String> _addressSuggestions = const [];
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
  // Mirrors [_count] so the value can be typed directly (tap-to-edit) as well
  // as stepped — NN/g recommends a typable value for counts that can grow past
  // a few taps.
  final _countController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  final _customRateController = TextEditingController();

  /// Steps the item count by [delta], clamped to 0..[_maxItemCount], keeping the
  /// typable field in sync.
  void _changeCount(int delta) {
    final next = (_count + delta).clamp(0, _maxItemCount);
    setState(() {
      _count = next;
      _countController.text = '$next';
      _countController.selection =
          TextSelection.collapsed(offset: _countController.text.length);
    });
  }

  /// Handles a directly-typed item count. Empty/non-numeric reads as 0; a value
  /// over the cap is clamped (and the field corrected) so the persisted count
  /// can't exceed [_maxItemCount].
  void _onCountTyped(String raw) {
    final parsed = raw.trim().isEmpty ? 0 : int.tryParse(raw.trim());
    if (parsed == null) return;
    final clamped = parsed.clamp(0, _maxItemCount);
    setState(() => _count = clamped);
    if (clamped != parsed) {
      _countController.text = '$clamped';
      _countController.selection =
          TextSelection.collapsed(offset: _countController.text.length);
    }
  }

  /// The rate the order will be billed at: a valid typed custom rate wins, then
  /// a matched customer's stored rate, then the global default. Drives the
  /// "Rate:" label so it confirms what will actually be frozen on the order.
  double get _resolvedRate {
    final typed = double.tryParse(_customRateController.text.trim());
    if (typed != null && typed > 0) return typed;
    return _matchedCustomerRate ?? widget.defaultRatePerKgUgx;
  }

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
    final chosen = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    // The time picker has no lower bound, so a rider can land on an earlier
    // time today. Reject a past pickup rather than scheduling into the past.
    // Re-read the clock (the pickers may have been open a while) and compare at
    // minute granularity so picking the current minute isn't falsely rejected.
    if (scheduledTimeIsInPast(chosen, widget.clock())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a pickup time in the future.')),
      );
      return;
    }
    setState(() {
      _scheduledFor = chosen;
      _selectedChip = _ScheduleChip.custom;
    });
  }

  @override
  void initState() {
    super.initState();
    _phoneFocus.addListener(_onPhoneFocusChange);
    _loadAddressSuggestions();
  }

  /// Loads distinct addresses used across customers and orders, ranked by how
  /// often they occur, to feed the address field's auto-suggest. Each source is
  /// best-effort and independent: customer addresses publish first, then orders
  /// augment the ranking, so a slow/failing orders read can't block suggestions
  /// (and a failure in either just logs and leaves that source out).
  Future<void> _loadAddressSuggestions() async {
    final counts = <String, int>{};
    final firstSeen = <String, String>{};

    void tally(String? raw) {
      final addr = raw?.trim();
      if (addr == null || addr.isEmpty) return;
      final key = addr.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
      firstSeen.putIfAbsent(key, () => addr);
    }

    void publish() {
      if (!mounted) return;
      final ranked = counts.keys.toList()
        ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
      setState(() => _addressSuggestions =
          ranked.map((k) => firstSeen[k]!).toList(growable: false));
    }

    // Kick off the orders read alongside the customers read so they overlap.
    final ordersFuture = widget.ordersRepo.watchAll().first;
    try {
      for (final c in await widget.customersRepo.getAll()) {
        tally(c.address);
      }
      publish();
    } catch (e, st) {
      developer.log('Customer address suggestions load failed.',
          name: 'NewPickupScreen', error: e, stackTrace: st);
    }
    try {
      for (final o in await ordersFuture) {
        tally(o.address);
      }
      publish();
    } catch (e, st) {
      developer.log('Order address suggestions load failed.',
          name: 'NewPickupScreen', error: e, stackTrace: st);
    }
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      ugandaNationalDigits(_phoneController.text).length == 9 &&
      _addressController.text.trim().isNotEmpty &&
      _serviceType != null &&
      // In "Schedule for later" mode a time must be chosen, otherwise the order
      // would silently fall back to an immediate pickup (startPickupNow == true).
      (_pickupMode == _PickupTimeMode.now || _scheduledFor != null) &&
      !_saving;

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final loc = await widget.geolocate();
      if (!mounted) return;
      if (loc == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Couldn't get your location — check permissions, or type the "
                'address manually.'),
          ),
        );
        return;
      }
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
    } catch (e, st) {
      developer.log('Customer phone-match lookup failed.',
          name: 'NewPickupScreen', error: e, stackTrace: st);
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
                    style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant)),
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
    final customRateText = _customRateController.text.trim();
    // Round before validating so the persisted rate matches the displayed whole
    // UGX (consistent with the settings screen) and a sub-0.5 input can't slip
    // past the ">0" guard as zero.
    final customRate = customRateText.isEmpty
        ? null
        : double.tryParse(customRateText)?.roundToDouble();
    if (customRateText.isNotEmpty && (customRate == null || customRate <= 0)) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom rate must be greater than 0.')),
      );
      return;
    }
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
      // A typed custom rate is a one-off that bills only this order (via the
      // order snapshot below). For a matched returning customer we never touch
      // their stored standing rate; only a brand-new customer's typed rate
      // establishes one.
      customRatePerKgUgx:
          _matchedCustomerId != null ? _matchedCustomerRate : customRate,
    );
    try {
      await widget.customersRepo.upsertCustomer(customer);
    } catch (e, st) {
      developer.log('upsertCustomer failed during pickup creation.',
          name: 'NewPickupScreen', error: e, stackTrace: st);
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
    } catch (e, st) {
      developer.log('reserveOrderCode failed during pickup creation.',
          name: 'NewPickupScreen', error: e, stackTrace: st);
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
      ratePerKgSnapshotUgx: customRate ?? _resolvedRate,
    );
    try {
      await widget.ordersRepo
          .upsertOrder(order, actorStaffId: widget.actorStaffId);
    } catch (e, st) {
      developer.log('upsertOrder failed during pickup creation.',
          name: 'NewPickupScreen', error: e, stackTrace: st);
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
    _addressFocus.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _countController.dispose();
    _notesController.dispose();
    _customRateController.dispose();
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
            RawAutocomplete<String>(
              // Reuse the existing controller/focus so "Use my location" and the
              // phone-match prefill (which set _addressController.text) keep
              // working and the field stays the source of truth at submit.
              textEditingController: _addressController,
              focusNode: _addressFocus,
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.isEmpty) return const Iterable<String>.empty();
                return _addressSuggestions
                    .where((a) => a.toLowerCase().contains(q))
                    .take(5);
              },
              onSelected: (_) => setState(() {}),
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                return TextFormField(
                  key: const Key('np_address'),
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(labelText: 'Address'),
                  onChanged: (_) => setState(() {}),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          return InkWell(
                            onTap: () => onSelected(option),
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.history, size: 18),
                              title: Text(option),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Rate: ${formatUgx(_resolvedRate.round())}/kg',
                key: const Key('np_rate'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
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
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Number of items',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pieces of clothing to collect — weight is recorded at pickup',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    key: const Key('np_count_dec'),
                    tooltip: 'Fewer items',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _count > 0 ? () => _changeCount(-1) : null,
                  ),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      key: const Key('np_count_field'),
                      controller: _countController,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: _onCountTyped,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: 'items',
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('np_count_inc'),
                    tooltip: 'More items',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed:
                        _count < _maxItemCount ? () => _changeCount(1) : null,
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
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('np_custom_rate'),
                controller: _customRateController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Custom rate (USh/kg)',
                  helperText:
                      'Leave blank to use the default — ${formatUgx(widget.defaultRatePerKgUgx.round())}/kg',
                ),
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

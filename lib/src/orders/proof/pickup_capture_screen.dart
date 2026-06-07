import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/uuid.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_radii.dart';
import '../../shared/theme/app_spacing.dart';
import '../../sync/orders_repository.dart';
import '../../sync/proof_events_repository.dart';
import '../order.dart';
import '../order_status.dart';
import '../proof_event.dart';
import '../pricing/line_item.dart';
import '../pricing/pricing_calculator.dart';
import '../pricing/pricing_inputs.dart';
import '../pricing/pricing_section.dart';
import 'proof_photo_storage.dart';
import 'qr_display_widget.dart';

DateTime _defaultClock() => DateTime.now();

enum _Stage { collecting, showQr }

class PickupCaptureScreen extends StatefulWidget {
  const PickupCaptureScreen({
    super.key,
    required this.order,
    required this.photoStorage,
    required this.pickPhoto,
    required this.ordersRepo,
    required this.proofEventsRepo,
    required this.actorStaffId,
    this.clock = _defaultClock,
    this.proofEventIdGenerator = defaultUuidV7,
  });

  final LaundryOrder order;
  final ProofPhotoStorage photoStorage;
  final PickPhotoFn pickPhoto;
  final DateTime Function() clock;
  final OrdersRepository ordersRepo;
  final ProofEventsRepository proofEventsRepo;
  final String actorStaffId;
  final String Function() proofEventIdGenerator;

  @override
  State<PickupCaptureScreen> createState() => _PickupCaptureScreenState();
}

class _PickupCaptureScreenState extends State<PickupCaptureScreen> {
  _Stage _stage = _Stage.collecting;
  int _count = 0;
  final List<List<int>> _photoBytes = [];
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _estimatedWeightController =
      TextEditingController();
  List<LineItem> _lineItems = [];
  bool _saving = false;
  bool _pickingPhoto = false;

  // Cached across retries so re-tapping "Done" after a downstream failure
  // produces a byte-identical ProofEvent + outbox payload. With the outbox's
  // deterministic dedup key (Plan 4 Task 2) AND the proof_events row's
  // insertOrIgnore on event id, both layers absorb the retry as no-ops —
  // no UI-side `_proofPersisted` flag needed.
  //
  // [_pendingUpdatedAt] is the stable timestamp passed to
  // `ordersRepo.updateStatus(updatedAt:)`. Used in the outbox dedup key for
  // `orders:update:<id>:<updatedAt>`; without it, two retries would mint
  // distinct keys and double-enqueue.
  String? _pendingEventId;
  List<String>? _pendingPhotoPaths;
  DateTime? _pendingCapturedAt;
  DateTime? _pendingUpdatedAt;

  static const int _maxPhotos = 3;

  bool get _canConfirm =>
      _count > 0 && _photoBytes.isNotEmpty && !_saving;

  OrderTotal get _provisionalTotal => recomputeTotal(PricingInputs(
        ratePerKgUgx: widget.order.ratePerKgSnapshotUgx,
        estimatedWeightKg:
            double.tryParse(_estimatedWeightController.text.trim()),
        lineItems: _lineItems,
      ));

  String _pickPhotoErrorMessage(String code) {
    return switch (code) {
      'camera_access_denied' =>
        'Camera permission denied. Enable it in Settings to take photos.',
      'no_available_camera' => 'No camera is available on this device.',
      _ => 'Could not open camera. Please try again.',
    };
  }

  Future<void> _addPhoto() async {
    if (_photoBytes.length >= _maxPhotos || _pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final bytes = await widget.pickPhoto();
      if (!mounted) return;
      if (bytes != null) {
        setState(() {
          _photoBytes.add(bytes);
        });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_pickPhotoErrorMessage(e.code))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open camera. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pickingPhoto = false);
      }
    }
  }

  void _onConfirm() {
    setState(() {
      _stage = _Stage.showQr;
    });
  }

  Future<void> _onDone() async {
    if (_saving) return;
    setState(() => _saving = true);

    // Capture the moment Done was tapped — BEFORE the photo-save loop, which
    // can take seconds on slow flash. `??=` so a retry preserves the first
    // attempt's timestamp.
    _pendingCapturedAt ??= widget.clock();

    // Photo save — cache the paths so retries don't re-save bytes (and don't
    // surface fresh storage errors mid-retry for already-persisted photos).
    final List<String> paths;
    try {
      paths = _pendingPhotoPaths ?? <String>[
        for (var i = 0; i < _photoBytes.length; i++)
          await widget.photoStorage.save(
            orderId: widget.order.orderId,
            type: ProofEventType.pickup,
            index: i,
            bytes: _photoBytes[i],
          ),
      ];
      _pendingPhotoPaths = paths;
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save pickup proof. Please try again.'),
        ),
      );
      return;
    }

    // Generate / reuse the event id ONCE so the proof_events row (and its
    // outbox payload) is byte-identical across retries. `_pendingCapturedAt`
    // is already cached at the top of this method.
    _pendingEventId ??= widget.proofEventIdGenerator();
    final trimmedNotes = _notesController.text.trim();
    final event = ProofEvent(
      id: _pendingEventId!,
      type: ProofEventType.pickup,
      capturedAt: _pendingCapturedAt!,
      count: _count,
      photoPaths: paths,
      notes: trimmedNotes.isEmpty ? null : trimmedNotes,
    );

    try {
      await widget.proofEventsRepo.insertEvent(
        event,
        orderId: widget.order.orderId,
        actorStaffId: widget.actorStaffId,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save pickup proof. Please try again.'),
        ),
      );
      return;
    }

    // Cache the stable updatedAt for the orders-update outbox key so retries
    // dedup at the SQL layer (Plan 4 Task 2).
    _pendingUpdatedAt ??= widget.clock();
    try {
      await widget.ordersRepo.updateStatus(
        widget.order.orderId,
        OrderStatus.inProgress,
        actorStaffId: widget.actorStaffId,
        updatedAt: _pendingUpdatedAt,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pickup proof saved, but status update failed. Tap Done again to '
            'retry.',
          ),
        ),
      );
      return;
    }

    try {
      await widget.ordersRepo.updatePricing(
        widget.order.copyWith(
          status: OrderStatus.inProgress,
          estimatedWeightKg:
              double.tryParse(_estimatedWeightController.text.trim()),
          lineItems: _lineItems,
        ),
        actorStaffId: widget.actorStaffId,
      );
    } catch (e, st) {
      developer.log(
        'updatePricing best-effort failed at pickup; staff can correct on the '
        'details screen.',
        name: 'PickupCaptureScreen',
        error: e,
        stackTrace: st,
      );
    }

    if (!mounted) return;
    Navigator.pop<bool>(context, true);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _estimatedWeightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _Stage.collecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_stage == _Stage.showQr) {
          setState(() => _stage = _Stage.collecting);
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          elevation: 0,
          title: Text(
            _stage == _Stage.collecting ? 'Confirm pickup' : 'Tag the bag',
          ),
        ),
        body: SafeArea(
          child: _stage == _Stage.collecting
              ? _buildCollecting()
              : _buildQrStage(),
        ),
      ),
    );
  }

  Widget _buildCollecting() {
    final provisional = _provisionalTotal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          widget.order.customerName,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          'Expected ${widget.order.itemCount} items · ${widget.order.address}',
          style: const TextStyle(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 20),
        Text(
          'How many items?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const Key('count_decrement'),
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: _count > 0
                  ? () => setState(() => _count--)
                  : null,
            ),
            SizedBox(
              width: 60,
              child: Text(
                '$_count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              key: const Key('count_increment'),
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => setState(() => _count++),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Photos (${_photoBytes.length}/$_maxPhotos)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < _photoBytes.length; i++)
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.field),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(
                  Uint8List.fromList(_photoBytes[i]),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.image_outlined),
                ),
              ),
            if (_photoBytes.length < _maxPhotos && !_pickingPhoto)
              GestureDetector(
                key: const Key('add_photo'),
                onTap: _addPhoto,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    borderRadius: BorderRadius.circular(AppRadii.field),
                  ),
                  child: Icon(
                    Icons.add_a_photo_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Estimated weight (kg)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('pickup_estimated_weight'),
          controller: _estimatedWeightController,
          decoration: const InputDecoration(
            labelText: 'Estimated weight (kg)',
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        Text(
          'Special items',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        LineItemsEditor(
          items: _lineItems,
          onAdd: () async {
            final item = await showAddLineItemSheet(context);
            if (item != null) {
              setState(() => _lineItems = [..._lineItems, item]);
            }
          },
          onRemove: (index) {
            setState(() {
              final updated = List<LineItem>.from(_lineItems);
              updated.removeAt(index);
              _lineItems = updated;
            });
          },
        ),
        const SizedBox(height: 12),
        TotalCard(
          totalUgx: provisional.total,
          isProvisional: provisional.isProvisional,
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const Key('pickup_notes'),
          controller: _notesController,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          key: const Key('pickup_confirm'),
          onPressed: _canConfirm ? _onConfirm : null,
          child: const Text('Confirm with customer'),
        ),
      ],
    );
  }

  Widget _buildQrStage() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            'Tie tag to the bag',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Write order #${widget.order.orderCode} on the bag, or scan this QR.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 24),
          QrDisplayWidget(data: widget.order.orderCode),
          const SizedBox(height: 16),
          Text(
            widget.order.orderCode,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _onDone,
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}

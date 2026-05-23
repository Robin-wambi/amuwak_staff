import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/uuid.dart';
import '../../shared/widgets/app_theme.dart';
import '../../sync/orders_repository.dart';
import '../../sync/proof_events_repository.dart';
import '../order.dart';
import '../order_status.dart';
import '../proof_event.dart';
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
    this.proofEventIdGenerator = defaultUuidV4,
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
  bool _saving = false;
  bool _pickingPhoto = false;

  // Cached across retries so that re-tapping "Done" after a downstream failure
  // (status update threw, photo save threw between repo calls, etc.) doesn't
  // generate a fresh UUID and land a second proof_events row in the DB and
  // outbox.
  //
  // [_pendingEventId] / [_pendingPhotoPaths] / [_pendingCapturedAt] hold the
  // values the FIRST attempt baked into the ProofEvent so the second attempt
  // is byte-identical. [_proofPersisted] short-circuits the proof insert+
  // outbox enqueue on retry, because the repository enqueues with a fresh
  // outbox-mutation UUID each call — a second `insertEvent` would land a
  // duplicate proof_events outbox row even though the proof_events row
  // itself is insertOrIgnore on event id.
  String? _pendingEventId;
  List<String>? _pendingPhotoPaths;
  DateTime? _pendingCapturedAt;
  bool _proofPersisted = false;

  static const int _maxPhotos = 3;

  bool get _canConfirm =>
      _count > 0 && _photoBytes.isNotEmpty && !_saving;

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

    if (!_proofPersisted) {
      try {
        await widget.proofEventsRepo.insertEvent(
          event,
          orderId: widget.order.orderId,
          actorStaffId: widget.actorStaffId,
        );
        _proofPersisted = true;
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
    }

    try {
      await widget.ordersRepo.updateStatus(
        widget.order.orderId,
        OrderStatus.inProgress,
        actorStaffId: widget.actorStaffId,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Distinct message: the proof DID save. Re-tapping Done skips the proof
      // insert entirely (see `_proofPersisted`) and just retries the status
      // flip.
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

    if (!mounted) return;
    Navigator.pop<bool>(context, true);
  }

  @override
  void dispose() {
    _notesController.dispose();
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
        backgroundColor: amuwakBackground,
        appBar: AppBar(
          backgroundColor: amuwakBackground,
          foregroundColor: amuwakDark,
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          widget.order.customerName,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: amuwakDark,
          ),
        ),
        Text(
          'Expected ${widget.order.itemCount} items · ${widget.order.address}',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        const Text(
          'How many items?',
          style: TextStyle(fontWeight: FontWeight.bold, color: amuwakDark),
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
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: amuwakDark,
          ),
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
                  color: amuwakSoftAccent,
                  borderRadius: BorderRadius.circular(10),
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
                    border: Border.all(color: amuwakPrimary),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.add_a_photo_outlined,
                    color: amuwakPrimary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _notesController,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
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
          const Text(
            'Tie tag to the bag',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: amuwakDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Write order #${widget.order.orderId} on the bag, or scan this QR.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 24),
          QrDisplayWidget(data: widget.order.orderId),
          const SizedBox(height: 16),
          Text(
            widget.order.orderId,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: amuwakDark,
            ),
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

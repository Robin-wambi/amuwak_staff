import 'package:flutter/material.dart';

import '../../shared/widgets/app_theme.dart';
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
    this.clock = _defaultClock,
  });

  final LaundryOrder order;
  final ProofPhotoStorage photoStorage;
  final PickPhotoFn pickPhoto;
  final DateTime Function() clock;

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

  static const int _maxPhotos = 3;

  bool get _canConfirm =>
      _count > 0 && _photoBytes.isNotEmpty && !_saving;

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
    try {
      final paths = <String>[];
      for (var i = 0; i < _photoBytes.length; i++) {
        final path = await widget.photoStorage.save(
          orderId: widget.order.orderId,
          type: ProofEventType.pickup,
          index: i,
          bytes: _photoBytes[i],
        );
        paths.add(path);
      }
      final event = ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: widget.clock(),
        count: _count,
        photoPaths: paths,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      final updated = widget.order.copyWith(
        status: OrderStatus.inProgress,
        proofEvents: [...widget.order.proofEvents, event],
      );
      if (!mounted) return;
      Navigator.pop<LaundryOrder>(context, updated);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save pickup proof. Please try again.'),
        ),
      );
    }
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
                child: const Icon(Icons.image_outlined),
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

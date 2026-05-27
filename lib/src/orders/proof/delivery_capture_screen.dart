import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/app_theme.dart';
import '../order.dart';
import '../order_status.dart';
import '../proof_event.dart';
import 'proof_photo_storage.dart';

DateTime _defaultClock() => DateTime.now();

class DeliveryCaptureScreen extends StatefulWidget {
  const DeliveryCaptureScreen({
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
  State<DeliveryCaptureScreen> createState() => _DeliveryCaptureScreenState();
}

class _DeliveryCaptureScreenState extends State<DeliveryCaptureScreen> {
  final List<List<int>> _photoBytes = [];
  final TextEditingController _notesController = TextEditingController();
  bool _saving = false;
  bool _pickingPhoto = false;

  static const int _maxPhotos = 3;

  bool get _canDeliver => _photoBytes.isNotEmpty && !_saving;

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

  Future<void> _markDelivered() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final paths = <String>[];
      for (var i = 0; i < _photoBytes.length; i++) {
        final path = await widget.photoStorage.save(
          orderId: widget.order.orderId,
          type: ProofEventType.delivery,
          index: i,
          bytes: _photoBytes[i],
        );
        paths.add(path);
      }
      final event = ProofEvent(
        type: ProofEventType.delivery,
        capturedAt: widget.clock(),
        count: widget.order.pickupProof?.count ?? widget.order.itemCount,
        photoPaths: paths,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      final updated = widget.order.copyWith(
        status: OrderStatus.completed,
        proofEvents: [...widget.order.proofEvents, event],
      );
      if (!mounted) return;
      Navigator.pop<LaundryOrder>(context, updated);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save delivery proof. Please try again.'),
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
    final pickup = widget.order.pickupProof;
    return Scaffold(
      backgroundColor: amuwakBackground,
      appBar: AppBar(
        backgroundColor: amuwakBackground,
        foregroundColor: amuwakDark,
        elevation: 0,
        title: const Text('Hand over'),
      ),
      body: SafeArea(
        child: ListView(
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
              widget.order.address,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: amuwakWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: amuwakPrimary.withValues(alpha: 0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'From pickup',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: amuwakDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pickup == null
                        ? 'No pickup proof on file.'
                        : 'Pickup count: ${pickup.count}',
                    style: const TextStyle(color: Colors.black87),
                  ),
                  if (pickup != null && pickup.photoPaths.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${pickup.photoPaths.length} photo(s) on file',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Handover photos (${_photoBytes.length}/$_maxPhotos)',
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
                      color: amuwakPrimary.withValues(alpha: 0.12),
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
                    key: const Key('add_handover_photo'),
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
              onPressed: _canDeliver ? _markDelivered : null,
              child: const Text('Mark delivered'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'barcode_reader.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({
    super.key,
    required this.expectedOrderId,
    required this.cameraViewBuilder,
  });

  final String expectedOrderId;
  final CameraViewBuilder cameraViewBuilder;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _showManualEntry = false;
  final TextEditingController _manualController = TextEditingController();
  String? _errorMessage;
  // MobileScanner fires onDetect continuously while a QR code is in view, so
  // we latch on the first matching detection to prevent a second Navigator.pop
  // from firing on a widget that is mid-disposal.
  bool _matched = false;

  // Accepts both the current `AMW-2026-0042` (prefix-year-counter) form and the
  // legacy `AMW-1024` digits-only form, so older printed tags still validate.
  static final RegExp _orderIdPattern =
      RegExp(r'^AMW-(\d{4}-)?\d+$', caseSensitive: false);

  void _handleDetected(String value) {
    if (_matched || !mounted) return;
    final trimmed = value.trim();
    if (trimmed.toUpperCase() == widget.expectedOrderId.toUpperCase()) {
      _matched = true;
      Navigator.pop(context, true);
      return;
    }
    final looksLikeOrderId = _orderIdPattern.hasMatch(trimmed);
    setState(() {
      _errorMessage = looksLikeOrderId
          ? 'This tag belongs to order #$trimmed, not #${widget.expectedOrderId}.'
          : 'This tag does not match order #${widget.expectedOrderId}.';
      if (_showManualEntry) {
        _manualController.clear();
      }
    });
  }

  void _submitManual() {
    _handleDetected(_manualController.text);
  }

  void _toggleManual() {
    setState(() {
      _showManualEntry = !_showManualEntry;
      _errorMessage = null;
      _manualController.clear();
    });
  }

  @override
  void dispose() {
    _manualController.dispose();
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
        title: const Text('Scan order tag'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop<bool>(context, false),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _showManualEntry
                  ? _ManualEntryView(
                      controller: _manualController,
                      onSubmit: _submitManual,
                      errorMessage: _errorMessage,
                    )
                  : widget.cameraViewBuilder(context, _handleDetected),
            ),
            if (!_showManualEntry && _errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: TextButton(
                onPressed: _toggleManual,
                child: Text(
                  _showManualEntry
                      ? 'Use camera instead'
                      : 'Enter order ID instead',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualEntryView extends StatelessWidget {
  const _ManualEntryView({
    required this.controller,
    required this.onSubmit,
    required this.errorMessage,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Order ID written on the bag',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'e.g. AMW-2026-0042',
              border: OutlineInputBorder(),
            ),
            onFieldSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 12),
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                errorMessage!,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ElevatedButton(
            onPressed: onSubmit,
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}

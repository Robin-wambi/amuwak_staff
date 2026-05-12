import 'package:flutter/material.dart';

import '../../shared/widgets/app_theme.dart';
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

  void _handleDetected(String value) {
    final trimmed = value.trim();
    if (trimmed == widget.expectedOrderId) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _errorMessage =
          'This tag belongs to order #$trimmed, not #${widget.expectedOrderId}.';
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
      backgroundColor: amuwakBackground,
      appBar: AppBar(
        backgroundColor: amuwakBackground,
        foregroundColor: amuwakDark,
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
          const Text(
            'Order ID written on the bag',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: amuwakDark,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'e.g. AMW-0421',
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

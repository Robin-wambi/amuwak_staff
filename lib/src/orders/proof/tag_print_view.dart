import 'package:flutter/material.dart';

import '../../printing/label_printer.dart';
import 'printable_tag.dart';

/// The printable bag-tag preview plus a "Print tag" action.
///
/// Reused wherever a tag is produced — at pickup (tag the bag) and as a reprint
/// from the order screen. Owns the pick/connect/print orchestration so callers
/// only supply the order code, customer name, and a [LabelPrinter]. When
/// [labelPrinter] is null the button is hidden and only the preview shows, so a
/// printerless site still sees the tag to copy/scan by hand.
class TagPrintView extends StatefulWidget {
  const TagPrintView({
    super.key,
    required this.orderCode,
    required this.customerName,
    this.labelPrinter,
    this.captureTag = captureTagPng,
    this.qrSize = 220,
    this.buttonKey = const Key('print_tag'),
  });

  final String orderCode;
  final String customerName;
  final LabelPrinter? labelPrinter;

  /// Rasterises the printable tag. Injectable so tests skip real PNG encoding.
  final TagCapturer captureTag;

  final double qrSize;

  /// Key on the print button so screens can target their own instance in tests.
  final Key buttonKey;

  @override
  State<TagPrintView> createState() => _TagPrintViewState();
}

class _TagPrintViewState extends State<TagPrintView> {
  bool _printing = false;

  /// Wraps the on-screen [PrintableTag] so [TagCapturer] rasterises exactly what
  /// is shown.
  final GlobalKey _tagBoundaryKey = GlobalKey();

  Future<void> _onPrintTag() async {
    final printer = widget.labelPrinter;
    if (printer == null || _printing) return;
    setState(() => _printing = true);
    try {
      if (!printer.isConnected) {
        final device = await _pickPrinter(printer);
        if (device == null) return; // cancelled or none paired
        await printer.connect(device);
      }
      final bytes = await widget.captureTag(_tagBoundaryKey);
      await printer.printRaster(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tag sent to printer.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not print the tag: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// Ask the rider which paired printer to use. Returns null if they cancel or
  /// none are paired (in which case we point them at the write/scan fallback).
  Future<PrinterDevice?> _pickPrinter(LabelPrinter printer) async {
    final devices = await printer.discover();
    if (!mounted) return null;
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No paired printer found. Pair one in Bluetooth settings, or write '
            'the order # on the bag.',
          ),
        ),
      );
      return null;
    }
    return showModalBottomSheet<PrinterDevice>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Choose a printer'),
            ),
            for (final device in devices)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(device.name),
                onTap: () => Navigator.pop(context, device),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPrint = widget.labelPrinter != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The on-screen preview IS what prints — captured via _tagBoundaryKey.
        PrintableTag(
          orderCode: widget.orderCode,
          customerName: widget.customerName,
          boundaryKey: _tagBoundaryKey,
          qrSize: widget.qrSize,
        ),
        if (canPrint) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: widget.buttonKey,
            onPressed: _printing ? null : _onPrintTag,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print tag'),
          ),
        ],
      ],
    );
  }
}

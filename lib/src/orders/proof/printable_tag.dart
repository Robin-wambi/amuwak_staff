import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'qr_display_widget.dart';

/// The bag tag laid out for a thermal label printer.
///
/// Always renders black-on-white regardless of the app theme — direct-thermal
/// labels are white stock and the scanner wants maximum contrast. The QR
/// encodes the raw [orderCode] (a static code that decodes with no network) and
/// uses High error correction so a damp or creased label still scans at
/// delivery.
class PrintableTag extends StatelessWidget {
  const PrintableTag({
    super.key,
    required this.orderCode,
    this.customerName,
    this.boundaryKey,
    this.qrSize = 320,
  });

  final String orderCode;

  /// Shown under the code so staff can eyeball the right bag before scanning.
  final String? customerName;

  /// Attached to the wrapping [RepaintBoundary] so [captureTagPng] can rasterise
  /// exactly this subtree.
  final GlobalKey? boundaryKey;

  final double qrSize;

  @override
  Widget build(BuildContext context) {
    final name = customerName?.trim();
    return RepaintBoundary(
      key: boundaryKey,
      child: ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrDisplayWidget(
                data: orderCode,
                size: qrSize,
                errorCorrectionLevel: QrErrorCorrectLevel.H,
              ),
              const SizedBox(height: 12),
              Text(
                orderCode,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
              if (name != null && name.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black, fontSize: 20),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Rasterises the [RepaintBoundary] identified by [boundaryKey] to PNG bytes.
///
/// [pixelRatio] sets the source crispness; the printer adapter resizes the
/// bitmap to the label width, so a high ratio just preserves QR sharpness.
/// Must be called after the boundary has been laid out and painted (one frame
/// after it is inserted into the tree).
Future<Uint8List> captureTagPng({
  required GlobalKey boundaryKey,
  double pixelRatio = 4,
}) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

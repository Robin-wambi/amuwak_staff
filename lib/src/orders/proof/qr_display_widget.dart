import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrDisplayWidget extends StatelessWidget {
  const QrDisplayWidget({
    super.key,
    required this.data,
    this.size = 240,
  });

  final String data;
  final double size;

  /// Quiet-zone padding around the QR modules. Gives scanners a margin to lock
  /// onto and keeps the text fallback clear of the tag edge.
  static const double _padding = 16;

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      backgroundColor: Colors.white,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      padding: const EdgeInsets.all(_padding),
      gapless: true,
      semanticsLabel: 'QR code for order $data',
      errorStateBuilder: (context, error) => SizedBox(
        width: size,
        height: size,
        child: Padding(
          padding: const EdgeInsets.all(_padding),
          child: Center(
            // Scale the code down to fit so even a long order code stays inside
            // the tag box instead of overflowing it.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                data,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

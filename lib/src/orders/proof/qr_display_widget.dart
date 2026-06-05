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

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      backgroundColor: Colors.white,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      padding: const EdgeInsets.all(16),
      gapless: true,
      semanticsLabel: 'QR code for order $data',
      errorStateBuilder: (context, error) => SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            data,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
      ),
    );
  }
}

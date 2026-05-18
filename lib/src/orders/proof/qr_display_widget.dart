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
    );
  }
}

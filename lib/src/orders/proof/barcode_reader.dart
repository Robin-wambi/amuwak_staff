import 'package:flutter/material.dart';

typedef OnBarcodeDetected = void Function(String value);

typedef CameraViewBuilder = Widget Function(
  BuildContext context,
  OnBarcodeDetected onDetected,
);

class FakeCameraView extends StatelessWidget {
  const FakeCameraView({
    super.key,
    required this.scannedValue,
    required this.onDetected,
  });

  final String scannedValue;
  final OnBarcodeDetected onDetected;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => onDetected(scannedValue),
        child: const Text('Simulate scan'),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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

/// Production factory: returns a `CameraViewBuilder` that uses `mobile_scanner`
/// to scan QR codes via the device camera. The first detected barcode's raw
/// value is forwarded to `onDetected`.
CameraViewBuilder mobileScannerCameraViewBuilder() {
  return (context, onDetected) {
    return MobileScanner(
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null) {
            onDetected(value);
            return;
          }
        }
      },
    );
  };
}

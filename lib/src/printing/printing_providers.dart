import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bluetooth_label_printer.dart';
import 'label_printer.dart';
import 'printer_store.dart';

/// The label printer the app drives. A single instance holds the live Bluetooth
/// connection across screens. Tests override this with a fake.
final labelPrinterProvider = Provider<LabelPrinter>(
  (ref) => BluetoothLabelPrinter(),
);

/// Persists the last-connected printer so the rider needn't re-pick it.
final printerStoreProvider = FutureProvider<PrinterStore>(
  (ref) async => PrinterStore(await SharedPreferences.getInstance()),
);

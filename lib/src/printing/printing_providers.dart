import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bluetooth_label_printer.dart';
import 'label_printer.dart';
import 'printer_store.dart';

/// The resolved [SharedPreferences] instance. Overridden in `main()` after
/// `getInstance()` so the rest of the app can read it synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  ),
);

/// The label printer the app drives. A single instance holds the live Bluetooth
/// connection across screens. Tests override this with a fake.
final labelPrinterProvider = Provider<LabelPrinter>(
  (ref) => BluetoothLabelPrinter(),
);

/// Persists the last-connected printer so the rider needn't re-pick it.
final printerStoreProvider = Provider<PrinterStore>(
  (ref) => PrinterStore(ref.watch(sharedPreferencesProvider)),
);

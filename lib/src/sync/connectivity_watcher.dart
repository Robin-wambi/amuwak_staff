import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityWatcher {
  ConnectivityWatcher({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Calls [onOnline] every time the device transitions from offline to online.
  void start({required void Function() onOnline}) {
    _sub?.cancel();
    bool wasOnline = false;
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && !wasOnline) onOnline();
      wasOnline = online;
    });
  }

  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  void dispose() => _sub?.cancel();
}

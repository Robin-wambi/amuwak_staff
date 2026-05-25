import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sync/sync_status.dart';

/// A thin banner shown above the staff dashboard whenever the device is
/// offline or the outbox has pending rows. Hides itself when everything is
/// clean.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncStatusProvider);
    if (s.online && s.pendingCount == 0) {
      return const SizedBox.shrink();
    }
    final bg = !s.online ? Colors.orange.shade100 : Colors.blue.shade100;
    final fg = !s.online ? Colors.orange.shade900 : Colors.blue.shade900;
    final label = !s.online
        ? 'Offline${s.pendingCount > 0 ? " — ${s.pendingCount} pending" : ""}'
        : '${s.pendingCount} pending upload${s.pendingCount == 1 ? "" : "s"}';
    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(!s.online ? Icons.cloud_off : Icons.sync, size: 16, color: fg),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: fg, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

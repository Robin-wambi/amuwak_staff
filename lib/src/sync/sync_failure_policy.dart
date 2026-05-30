import 'dart:async';

/// True when [error] is a transient transport/connectivity failure that we
/// should retry indefinitely WITHOUT counting it toward the dead-letter
/// budget. A rider losing signal must never turn good uploads into errors.
///
/// Deliberately conservative: only transport-layer failures qualify. Anything
/// the server actually responded to (e.g. [PostgrestException]) or any logic
/// error (e.g. [StateError]) is treated as permanent so it can still
/// dead-letter and surface to the rider.
bool isTransientSyncError(Object error) {
  if (error is TimeoutException) return true;
  final type = error.runtimeType.toString();
  if (type == 'SocketException' ||
      type == 'ClientException' ||
      type == 'HttpException' ||
      type == 'HandshakeException') {
    return true;
  }
  final msg = error.toString().toLowerCase();
  return msg.contains('socketexception') ||
      msg.contains('clientexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('connection closed') ||
      msg.contains('connection refused') ||
      msg.contains('connection reset') ||
      msg.contains('connection attempt failed') ||
      msg.contains('network is unreachable') ||
      msg.contains('software caused connection abort') ||
      msg.contains('xmlhttprequest'); // web offline
}

/// Maps a stored raw outbox/pull error string to a short, rider-readable
/// line for the SyncErrorsScreen. Keeps the raw text out of the rider's face
/// while [isTransientSyncError] keeps the underlying engine behaviour correct.
String friendlySyncError(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Could not be saved.';
  final t = raw.toLowerCase();
  if (t.contains('23505') || t.contains('duplicate')) {
    return 'Already saved on the server.';
  }
  if (t.contains('23503') || t.contains('foreign key')) {
    return 'Linked record is missing on the server.';
  }
  if (t.contains('row-level security') ||
      t.contains('42501') ||
      t.contains('permission') ||
      t.contains('403')) {
    return 'Not allowed on the server (permissions).';
  }
  if (t.contains('jwt') ||
      t.contains('401') ||
      t.contains('not authenticated')) {
    return 'Sign-in expired — sign out and back in.';
  }
  if (isTransientSyncError(raw)) {
    return 'Connection problem — will retry automatically.';
  }
  return 'Could not be saved (server rejected it).';
}

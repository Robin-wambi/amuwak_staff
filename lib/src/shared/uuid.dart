import 'package:uuid/uuid.dart';

/// Default UUID **v7** generator used as the production tear-off for every
/// `String Function()` injectable in the orders/proof/sync layers (capture
/// screens, [OrdersRepository], [ProofEventsRepository]). Tests inject
/// deterministic generators of their own.
///
/// v7 leads with a 48-bit millisecond timestamp, so freshly minted ids sort
/// in creation order — this keeps the Postgres B-tree on the `uuid` primary
/// keys append-mostly instead of scattering inserts the way random v4 did.
/// A v7 id is still a valid RFC-4122 UUID, so it drops into the existing
/// `uuid` columns with no schema change.
String defaultUuidV7() => const Uuid().v7();

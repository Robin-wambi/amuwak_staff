import 'package:uuid/uuid.dart';

/// Default UUID v4 generator used as the production tear-off for every
/// `String Function()` injectable in the orders/proof/sync layers (capture
/// screens, [OrdersRepository], [ProofEventsRepository]). Tests inject
/// deterministic generators of their own.
String defaultUuidV4() => const Uuid().v4();

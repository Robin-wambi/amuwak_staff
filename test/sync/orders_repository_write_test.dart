@Skip('Online-only mode: offline outbox-queued write path for OrdersRepository '
    'disabled. This test exercised the local Drift + outbox write path. Original '
    'preserved in git history — restore with the OFFLINE block in '
    'lib/src/sync/orders_repository.dart. Online write payloads are exercised '
    'against Supabase directly (see lib/src/sync/orders_repository.dart).')
library;

import 'package:flutter_test/flutter_test.dart';

void main() {}

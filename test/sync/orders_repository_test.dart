@Skip('Online-only mode: offline-first OrdersRepository (local Drift reads) '
    'disabled. This Drift-path test no longer compiles against the '
    'Supabase-backed repo. Original preserved in git history — restore with the '
    'OFFLINE block in lib/src/sync/orders_repository.dart. Online read/write '
    'mapping is covered by test/sync/supabase_mappers_test.dart.')
library;

import 'package:flutter_test/flutter_test.dart';

void main() {}

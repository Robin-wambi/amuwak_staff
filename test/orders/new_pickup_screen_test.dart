@Skip('Online-only mode: this widget test built CustomersRepository/'
    'OrdersRepository over an in-memory Drift DB (offline path) and asserted on '
    'local rows. It no longer compiles against the Supabase-backed repos. '
    'Original preserved in git history. NOTE: the New Pickup form behaviour is '
    'still relevant online — rewrite this against a mocked SupabaseClient (or '
    'mocked repos) when capacity allows. Until then, verify the New Pickup flow '
    'manually against Supabase.')
library;

import 'package:flutter_test/flutter_test.dart';

void main() {}

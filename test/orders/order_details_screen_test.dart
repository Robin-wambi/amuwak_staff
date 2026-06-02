@Skip('Online-only mode: this widget test built OrdersRepository/'
    'ProofEventsRepository over an in-memory Drift DB (offline path). It no '
    'longer compiles against the Supabase-backed repos. Original preserved in '
    'git history. NOTE: Order Details behaviour (status advance, proof display) '
    'is still relevant online — rewrite against mocked repos when capacity '
    'allows; verify manually against Supabase until then.')
library;

import 'package:flutter_test/flutter_test.dart';

void main() {}

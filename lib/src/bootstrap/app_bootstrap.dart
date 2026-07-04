import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/app_database.dart';
import '../data/orders_seeder.dart';
import 'app_config.dart';
import 'timeout_http_client.dart';

class AppBootstrap {
  const AppBootstrap._();

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    final config = AppConfig.fromEnvironment()..validate();
    // Cap every PostgREST/RPC/Storage/Auth call so a poor or dead network fails
    // fast (TimeoutException) instead of hanging the rider indefinitely. This is
    // the online-only-mode resilience win; it also survives into offline mode,
    // where the puller and any online RPC keep using it.
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.supabaseAnonKey,
      httpClient: TimeoutHttpClient(http.Client()),
    );
    // ONLINE-ONLY: the local Drift database is no longer used at runtime, so we
    // skip opening/seeding it here. Data comes straight from Supabase. Restore
    // the block below (and re-enable the sync orchestrator) to bring offline
    // back:
    //
    //   final db = AppDatabase();
    //   try {
    //     await runSeed(db, OrdersSeeder());
    //   } finally {
    //     await db.close();
    //   }
  }

  /// Test-visible seed entry — accepts an injected DB + seeder so tests
  /// don't have to spin up Supabase. The caller owns the [db] lifecycle.
  static Future<void> runSeed(AppDatabase db, OrdersSeeder seeder) =>
      seeder.seedIfEmpty(db);
}

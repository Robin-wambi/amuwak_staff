import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/app_database.dart';
import '../data/orders_seeder.dart';
import 'app_config.dart';

class AppBootstrap {
  const AppBootstrap._();

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    final config = AppConfig.fromEnvironment()..validate();
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.supabaseAnonKey,
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

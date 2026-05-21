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
    await runSeed(AppDatabase(), OrdersSeeder());
  }

  /// Test-visible seed entry — accepts an injected DB + seeder so tests
  /// don't have to spin up Supabase.
  static Future<void> runSeed(AppDatabase db, OrdersSeeder seeder) =>
      seeder.seedIfEmpty(db);
}

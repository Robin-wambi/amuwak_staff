import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/bootstrap/app_config.dart';

void main() {
  group('AppConfig', () {
    test('holds the url and anon key it was constructed with', () {
      const cfg = AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'eyJ.anon.key',
      );
      expect(cfg.supabaseUrl, 'https://example.supabase.co');
      expect(cfg.supabaseAnonKey, 'eyJ.anon.key');
    });

    test('validate() throws if supabaseUrl is blank', () {
      expect(
        () => const AppConfig(supabaseUrl: '', supabaseAnonKey: 'x').validate(),
        throwsA(isA<StateError>()),
      );
    });

    test('validate() throws if supabaseAnonKey is blank', () {
      expect(
        () => const AppConfig(supabaseUrl: 'x', supabaseAnonKey: '').validate(),
        throwsA(isA<StateError>()),
      );
    });
  });
}

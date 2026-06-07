import 'package:supabase_flutter/supabase_flutter.dart';

import 'pricing_settings.dart';

typedef FetchRows = Future<List<Map<String, dynamic>>> Function();

/// Reads and updates the singleton `pricing_settings` row.
///
/// Reads are one-shot (the row is a singleton; no realtime needed). The settings
/// table is intentionally not in the realtime publication — see migration 0019.
class PricingSettingsRepository {
  PricingSettingsRepository(this._supabase, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        _fetchRowsOverride = null;

  /// Test seam: inject the raw row fetch so unit tests don't mock SupabaseClient.
  PricingSettingsRepository.forTest({required FetchRows fetchRows})
      : _supabase = null,
        _clock = DateTime.now,
        _fetchRowsOverride = fetchRows;

  final SupabaseClient? _supabase;
  final DateTime Function() _clock;
  final FetchRows? _fetchRowsOverride;

  Future<List<Map<String, dynamic>>> _fetchRows() {
    final override = _fetchRowsOverride;
    if (override != null) return override();
    return _supabase!
        .from('pricing_settings')
        .select()
        .limit(1)
        .then((rows) => rows.cast<Map<String, dynamic>>());
  }

  /// Fetches the singleton settings. Throws [StateError] if the row is missing
  /// (corrupted state the singleton index should prevent) so the UI can show
  /// "Pricing settings missing — contact admin." rather than silently defaulting.
  Future<PricingSettings> fetch() async {
    final rows = await _fetchRows();
    if (rows.isEmpty) {
      throw StateError('pricing_settings has no row');
    }
    return PricingSettings.fromSupabase(rows.first);
  }

  /// Updates the global default rate on the singleton row.
  Future<void> updateDefaultRate(double ratePerKgUgx,
      {required String actorStaffId}) async {
    final id = (await fetch()).id;
    await _supabase!.from('pricing_settings').update({
      'default_rate_per_kg_ugx': ratePerKgUgx,
      'updated_at': _clock().toUtc().toIso8601String(),
      'updated_by': actorStaffId,
    }).eq('id', id);
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/repository_providers.dart';
import 'pricing_settings_repository.dart';

final pricingSettingsRepositoryProvider =
    Provider<PricingSettingsRepository>(
  (ref) => PricingSettingsRepository(ref.watch(supabaseClientProvider)),
);

/// The resolved global default rate, used by the new-pickup rate display when a
/// customer has no override. Re-read on invalidation (e.g. after the settings
/// screen saves).
final defaultRatePerKgUgxProvider = FutureProvider<double>(
  (ref) async => (await ref
          .watch(pricingSettingsRepositoryProvider)
          .fetch())
      .defaultRatePerKgUgx,
);

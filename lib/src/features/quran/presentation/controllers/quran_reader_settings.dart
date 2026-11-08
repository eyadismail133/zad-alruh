import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/local_settings.dart';
import '../../domain/models/quran_reciter.dart';

/// Selected recitation (persisted). Defaults to Mishary Alafasy.
final selectedReciterIdProvider =
    StateNotifierProvider<PersistedStringNotifier, String>(
  (ref) => PersistedStringNotifier('quran.reciter', QuranReciter.alafasy.id),
);

final selectedReciterProvider = Provider<QuranReciter>(
  (ref) => QuranReciter.byId(ref.watch(selectedReciterIdProvider)),
);

/// Keep the screen awake while the Mushaf reader is open (persisted, on by default).
final keepScreenOnProvider =
    StateNotifierProvider<PersistedBoolNotifier, bool>(
  (ref) => PersistedBoolNotifier('quran.keep_screen_on', true),
);

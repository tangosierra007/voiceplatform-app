import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Me screen's appearance switch: System (follow the device), Light, Dark.
enum ThemePreference {
  system(ThemeMode.system),
  light(ThemeMode.light),
  dark(ThemeMode.dark);

  const ThemePreference(this.mode);
  final ThemeMode mode;
}

/// Overridden in main() with the loaded instance, so the first frame already
/// has the stored choice (no flash of the wrong theme).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('Override sharedPreferencesProvider in main()'),
);

final themePreferenceProvider =
    NotifierProvider<ThemePreferenceNotifier, ThemePreference>(
      ThemePreferenceNotifier.new,
    );

class ThemePreferenceNotifier extends Notifier<ThemePreference> {
  static const storageKey = 'vp.theme';

  @override
  ThemePreference build() {
    final stored = ref.watch(sharedPreferencesProvider).getString(storageKey);
    return ThemePreference.values.firstWhere(
      (p) => p.name == stored,
      orElse: () => ThemePreference.system,
    );
  }

  Future<void> set(ThemePreference value) async {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    if (value == ThemePreference.system) {
      await prefs.remove(storageKey);
    } else {
      await prefs.setString(storageKey, value.name);
    }
  }
}

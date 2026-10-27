import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../net/api.dart';
import '../theme/theme_preference.dart';
import 'auth.dart';

/// Semantic version compare, `1.0.10` after `1.0.9`. Missing parts are 0.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
    for (final p in v.split('+').first.split('.'))
      int.tryParse(p.replaceAll(RegExp(r'\D.*'), '')) ?? 0,
  ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Non-null when this version is below the platform's minimum (APP7): the
/// blocking AppUpdate. Set by `GET /config` at start and by any 426.
final updateRequiredProvider =
    NotifierProvider<UpdateRequiredNotifier, AppConfig?>(
      UpdateRequiredNotifier.new,
    );

class UpdateRequiredNotifier extends Notifier<AppConfig?> {
  @override
  AppConfig? build() => null;
  void set(AppConfig? c) => state = c;
}

/// The latest `GET /config`, for the recommended-version banner.
final appConfigProvider = NotifierProvider<AppConfigNotifier, AppConfig?>(
  AppConfigNotifier.new,
);

class AppConfigNotifier extends Notifier<AppConfig?> {
  @override
  AppConfig? build() => null;

  /// Asks `GET /config` and applies the minimum version. Quiet when offline.
  Future<void> check() async {
    final api = ref.read(appApiProvider);
    final c = ref.read(apiConfigProvider);
    try {
      final config = await api.signin.getConfig(
        platform: Platform.fromJson(c.platform),
      );
      state = config;
      if (compareVersions(c.appVersion, config.minimumVersion) < 0) {
        ref.read(updateRequiredProvider.notifier).set(config);
      }
    } catch (_) {
      // Offline: the next authenticated call's 426 still gates.
    }
  }
}

/// Between minimum and recommended: a dismissible banner, once a day.
final updateBannerProvider = NotifierProvider<UpdateBannerNotifier, bool>(
  UpdateBannerNotifier.new,
);

class UpdateBannerNotifier extends Notifier<bool> {
  static const storageKey = 'vp.updateBannerDay';

  String _today() {
    final d = ref.read(clockProvider)();
    return '${d.year}-${d.month}-${d.day}';
  }

  @override
  bool build() {
    final config = ref.watch(appConfigProvider);
    if (config == null) return false;
    final version = ref.watch(apiConfigProvider).appVersion;
    if (compareVersions(version, config.recommendedVersion) >= 0) return false;
    final shown = ref.watch(sharedPreferencesProvider).getString(storageKey);
    return shown != _today();
  }

  /// "Not now" or "Update": not again today.
  Future<void> dismiss() async {
    state = false;
    await ref.read(sharedPreferencesProvider).setString(storageKey, _today());
  }
}

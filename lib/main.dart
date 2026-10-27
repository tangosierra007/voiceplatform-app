import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'net/api.dart';
import 'theme/theme_preference.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();
  // TODO(4.2): once vp_linphone (app PR #5) is a dependency, call
  // addVpLinphoneLicenses() here so its native components' licence texts
  // appear under Open source licences.
  final prefs = await SharedPreferences.getInstance();
  final info = await PackageInfo.fromPlatform();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        apiConfigProvider.overrideWithValue(
          ApiConfig(
            baseUrl: ApiConfig.defaultBaseUrl,
            platform: ApiConfig.platformName(defaultTargetPlatform),
            appVersion: info.version,
          ),
        ),
      ],
      child: const VoicePlatformApp(),
    ),
  );
}

/// The bundled fonts' OFL texts, so Open source licences lists them.
void registerFontLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final (family, path) in const [
      ('Unbounded', 'assets/fonts/unbounded/OFL.txt'),
      ('Manrope', 'assets/fonts/manrope/OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString(path));
    }
  });
}

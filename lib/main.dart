import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vp_linphone/vp_linphone.dart';

import 'app.dart';
import 'net/api.dart';
import 'theme/theme_preference.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();
  // The SIP engine's native components (liblinphone and the rest).
  addVpLinphoneLicenses();
  final prefs = await SharedPreferences.getInstance();
  final info = await PackageInfo.fromPlatform();
  final model = await _deviceModel();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        apiConfigProvider.overrideWithValue(
          ApiConfig(
            baseUrl: ApiConfig.defaultBaseUrl,
            platform: ApiConfig.platformName(defaultTargetPlatform),
            appVersion: info.version,
            deviceModel: model,
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

/// The phone's model for DeviceInfo at sign-in, for example `Pixel 8`.
Future<String> _deviceModel() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final a = await DeviceInfoPlugin().androidInfo;
      return a.model.length > 64 ? a.model.substring(0, 64) : a.model;
    }
  } catch (_) {
    // Fall through.
  }
  return 'Android';
}

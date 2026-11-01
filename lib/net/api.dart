import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/export.dart';
import '../auth/auth.dart';
import '../shell/shell_status.dart';

export '../api/app_api.dart';
export '../api/export.dart';

/// Where the API is and who is calling it.
@immutable
class ApiConfig {
  const ApiConfig({
    required this.baseUrl,
    required this.platform,
    required this.appVersion,
    this.deviceModel = 'Android',
  });

  /// For example `http://10.0.2.2:3000/app/v1` (the mock server from the
  /// Android emulator). Set with `--dart-define=VP_API_BASE=...`.
  final String baseUrl;

  /// `android`, `ios`, `windows` or `macos` (contract `Platform`).
  final String platform;

  /// The app's version name from pubspec, for example `1.0.0`.
  final String appVersion;

  /// The phone's model, for example `Pixel 8` (DeviceInfo at sign-in).
  final String deviceModel;

  /// The `X-VP-App` header every request carries (APP7).
  String get appHeader => '$platform/$appVersion';

  static const defaultBaseUrl = String.fromEnvironment(
    'VP_API_BASE',
    defaultValue: 'http://10.0.2.2:3000/app/v1',
  );

  static String platformName(TargetPlatform p) => switch (p) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.windows => 'windows',
    TargetPlatform.macOS => 'macos',
    _ => 'android',
  };
}

/// Adds `X-VP-App` to every request and the bearer access token when there is
/// one. Never logs headers (APP4, APP9).
class AppHeadersInterceptor extends Interceptor {
  AppHeadersInterceptor({required this.appHeader, required this.accessToken});

  final String appHeader;
  final String? Function() accessToken;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-VP-App'] = appHeader;
    final token = accessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

Dio buildDio(ApiConfig config, {required String? Function() accessToken}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  dio.interceptors.add(
    AppHeadersInterceptor(
      appHeader: config.appHeader,
      accessToken: accessToken,
    ),
  );
  return dio;
}

/// Overridden in main() with the platform and the version from package info.
final apiConfigProvider = Provider<ApiConfig>(
  (ref) => ApiConfig(
    baseUrl: ApiConfig.defaultBaseUrl,
    platform: ApiConfig.platformName(defaultTargetPlatform),
    appVersion: '0.0.0',
  ),
);

/// The access token, in memory only (15 minutes; refreshed with the device
/// key). Sign-in and refresh set it.
final accessTokenProvider = NotifierProvider<AccessTokenNotifier, String?>(
  AccessTokenNotifier.new,
);

class AccessTokenNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? token) => state = token;
}

/// X-VP-App and the bearer on every request; a 401 refreshes once and
/// retries; a 426 switches to AppUpdate (see SessionInterceptor).
final dioProvider = Provider<Dio>(buildSessionDio);
final appApiProvider = Provider<AppApi>(
  (ref) => AppApi(ref.watch(dioProvider)),
);

/// `GET /me` could not be asked: signed in from the stored session, but the
/// refresh for an access token failed (offline, or the API unreachable).
class MeUnavailable implements Exception {
  const MeUnavailable();

  @override
  String toString() => 'MeUnavailable';
}

/// The signed-in user; drives the tab badges and whether Messages shows.
/// Null when not signed in. Signed in without an access token yet (a cold
/// start), it waits for the refresh and fails with [MeUnavailable] when that
/// fails, so the shell can tell "failed" from "not signed in". Each answer is
/// recorded as the last known tab set (`lastKnownShellProvider`).
final meProvider = FutureProvider<Me?>((ref) async {
  final signedIn = ref.watch(authProvider.select((s) => s is SignedIn));
  final token = ref.watch(accessTokenProvider);
  final api = ref.watch(appApiProvider);
  if (token == null) {
    if (!signedIn) return null;
    if (!await ref.read(authProvider.notifier).refresh()) {
      throw const MeUnavailable();
    }
    // The new token rebuilds this provider; this run's answer is dropped.
    if (!ref.mounted) return null;
  }
  final me = await api.me.getMe();
  if (ref.mounted) ref.read(lastKnownShellProvider.notifier).record(me);
  return me;
});

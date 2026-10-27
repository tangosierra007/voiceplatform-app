import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/export.dart';

export '../api/app_api.dart';
export '../api/export.dart';

/// Where the API is and who is calling it.
@immutable
class ApiConfig {
  const ApiConfig({
    required this.baseUrl,
    required this.platform,
    required this.appVersion,
  });

  /// For example `http://10.0.2.2:3000/app/v1` (the mock server from the
  /// Android emulator). Set with `--dart-define=VP_API_BASE=...`.
  final String baseUrl;

  /// `android`, `ios`, `windows` or `macos` (contract `Platform`).
  final String platform;

  /// The app's version name from pubspec, for example `1.0.0`.
  final String appVersion;

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

/// The access token in memory. Sign-in (4.2) sets it; for the mock server in
/// debug builds `--dart-define=VP_DEV_TOKEN=<anything>` starts signed in.
final accessTokenProvider = NotifierProvider<AccessTokenNotifier, String?>(
  AccessTokenNotifier.new,
);

class AccessTokenNotifier extends Notifier<String?> {
  static const _devToken = String.fromEnvironment('VP_DEV_TOKEN');

  @override
  String? build() => kDebugMode && _devToken.isNotEmpty ? _devToken : null;

  void set(String? token) => state = token;
}

final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(apiConfigProvider);
  return buildDio(config, accessToken: () => ref.read(accessTokenProvider));
});

final appApiProvider = Provider<AppApi>(
  (ref) => AppApi(ref.watch(dioProvider)),
);

/// The signed-in user; drives the tab badges and whether Messages shows.
final meProvider = FutureProvider<Me?>((ref) async {
  if (ref.watch(accessTokenProvider) == null) return null;
  return ref.watch(appApiProvider).me.getMe();
});

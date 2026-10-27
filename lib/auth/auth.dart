import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../net/api.dart';
import '../platform/device_keys.dart';
import 'session_store.dart';
import 'version.dart';

/// Where sign-in stands. The router follows it.
sealed class AuthState {
  const AuthState();
}

/// Reading the stored session at start.
final class AuthStarting extends AuthState {
  const AuthStarting();
}

/// No session. [notice] is shown on AppSignIn (for example a link opened on
/// a phone that didn't ask for it, or a device signed out remotely).
final class NotSignedIn extends AuthState {
  const NotSignedIn({this.notice});
  final String? notice;
}

final class SignedIn extends AuthState {
  const SignedIn(this.deviceId);
  final String deviceId;
}

/// 403 `licence_basic` at sign-in or refresh: AppBasic.
final class LicenceRefused extends AuthState {
  const LicenceRefused(this.refusal);
  final LicenceRefusal refusal;
}

/// An email sign-in in progress. The request secret lives here, in memory
/// only: it is never stored, logged or sent anywhere but the API (APP1).
@immutable
class PendingSignIn {
  const PendingSignIn({
    required this.email,
    required this.requestId,
    required this.secret,
    required this.resendAt,
    required this.expiresAt,
  });
  final String email;
  final String requestId;
  final String secret;
  final DateTime resendAt;
  final DateTime expiresAt;

  @override
  String toString() => 'PendingSignIn($requestId)';
}

/// A sign-in step failed; [message] is what the screen shows.
class SignInFailure implements Exception {
  const SignInFailure(this.message, {this.code});
  final String message;
  final String? code;

  static const offline =
      "Can't reach VoicePlatform. Check your connection and try again.";

  /// Spec 22, Sign-in item 3.
  static const notThisPhone =
      'This link only signs in the phone that asked for it.';

  @override
  String toString() => 'SignInFailure($code)';
}

/// The app's clock; tests replace it.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The 32 random bytes of a request secret, base64url.
final requestSecretProvider = Provider<String Function()>(
  (ref) => () {
    final r = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => r.nextInt(256)))
        .replaceAll('=', '');
  },
);

final pendingSignInProvider =
    NotifierProvider<PendingSignInNotifier, PendingSignIn?>(
      PendingSignInNotifier.new,
    );

class PendingSignInNotifier extends Notifier<PendingSignIn?> {
  @override
  PendingSignIn? build() => null;
  void set(PendingSignIn? p) => state = p;
}

final authProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  Completer<bool>? _refreshing;

  @override
  AuthState build() {
    scheduleMicrotask(_restore);
    return const AuthStarting();
  }

  SessionStore get _store => ref.read(sessionStoreProvider);
  DeviceKeys get _keys => ref.read(deviceKeysProvider);
  AppApi get _api => ref.read(appApiProvider);
  DateTime _now() => ref.read(clockProvider)();

  DeviceInfo get _device {
    final c = ref.read(apiConfigProvider);
    return DeviceInfo(
      platform: Platform.fromJson(c.platform),
      model: c.deviceModel,
      appVersion: c.appVersion,
    );
  }

  Future<void> _restore() async {
    final stored = await _store.read();
    if (stored == null) {
      state = const NotSignedIn();
      return;
    }
    // Signed in at once (offline still opens the app); the access token
    // follows from the refresh.
    state = SignedIn(stored.deviceId);
    unawaited(refresh());
  }

  // --------------------------------------------------------------- email

  /// AppSignIn: "Email me a sign-in link".
  Future<void> requestEmail(String email) async {
    final secret = ref.read(requestSecretProvider)();
    final accepted = await _call(
      () => _api.signin.postAuthEmailRequests(
        body: EmailRequestInput(
          email: email.trim(),
          requestSecret: secret,
          device: _device,
        ),
      ),
    );
    final now = _now();
    ref
        .read(pendingSignInProvider.notifier)
        .set(
          PendingSignIn(
            email: email.trim(),
            requestId: accepted.requestId,
            secret: secret,
            resendAt: now.add(Duration(seconds: accepted.resendAfterSeconds)),
            expiresAt: now.add(Duration(seconds: accepted.expiresInSeconds)),
          ),
        );
  }

  /// AppCode: "Send again" once the timer runs out.
  Future<void> resend() async {
    final p = _pending();
    final accepted = await _call(
      () => _api.signin.postAuthEmailRequestsRequestIdResend(
        requestId: p.requestId,
        body: AuthEmailRequestsRequestIdResendRequestBody(
          requestSecret: p.secret,
        ),
      ),
    );
    final now = _now();
    ref
        .read(pendingSignInProvider.notifier)
        .set(
          PendingSignIn(
            email: p.email,
            requestId: p.requestId,
            secret: p.secret,
            resendAt: now.add(Duration(seconds: accepted.resendAfterSeconds)),
            expiresAt: now.add(Duration(seconds: accepted.expiresInSeconds)),
          ),
        );
  }

  Future<void> completeWithCode(String code) => _complete(code: code);

  /// The App Link from the email. Completes only with this phone's secret.
  Future<void> completeWithLink(String requestId, String linkToken) async {
    final p = ref.read(pendingSignInProvider);
    if (p == null || p.requestId != requestId) {
      state = const NotSignedIn(notice: SignInFailure.notThisPhone);
      throw const SignInFailure(
        SignInFailure.notThisPhone,
        code: 'not_this_phone',
      );
    }
    await _complete(linkToken: linkToken);
  }

  Future<void> _complete({String? code, String? linkToken}) async {
    final p = _pending();
    final key = await _keys.publicKey();
    final session = await _call(
      () => _api.signin.postAuthEmailRequestsRequestIdComplete(
        requestId: p.requestId,
        body: CompleteInput(
          requestSecret: p.secret,
          code: code,
          linkToken: linkToken,
          devicePublicKey: key,
          device: _device,
        ),
      ),
    );
    await _signedIn(session);
  }

  /// "Scan the QR code instead", or a `vpapp://signin/<token>` link.
  Future<void> completeWithQr(String qrToken) async {
    final key = await _keys.publicKey();
    final session = await _call(
      () => _api.signin.postAuthQrComplete(
        body: QrCompleteInput(
          qrToken: qrToken,
          devicePublicKey: key,
          device: _device,
        ),
      ),
    );
    await _signedIn(session);
  }

  Future<void> _signedIn(Session s) async {
    await _store.write(
      StoredSession(deviceId: s.deviceId, refreshToken: s.refreshToken),
    );
    ref.read(accessTokenProvider.notifier).set(s.accessToken);
    ref.read(pendingSignInProvider.notifier).set(null);
    state = SignedIn(s.deviceId);
  }

  PendingSignIn _pending() {
    final p = ref.read(pendingSignInProvider);
    if (p == null) {
      throw const SignInFailure(
        'This sign-in has expired. Start again.',
        code: 'no_request',
      );
    }
    return p;
  }

  // --------------------------------------------------------------- Basic

  /// AppBasic: "Ask my admin to upgrade". True when the request was sent.
  Future<void> askAdminToUpgrade() async {
    final s = state;
    final token = s is LicenceRefused ? s.refusal.refusalToken : null;
    if (token == null) {
      throw const SignInFailure('Start again to ask your admin.');
    }
    await _call(
      () => _api.signin.postAuthLicenceRequests(
        body: AuthLicenceRequestsRequestBody(refusalToken: token),
      ),
    );
  }

  /// A message for AppSignIn (a link that failed), when not signed in.
  void showNotice(String message) {
    if (state is SignedIn) return;
    state = NotSignedIn(notice: message);
  }

  /// AppBasic: "Use a different email". Clears the request.
  void useDifferentEmail() {
    ref.read(pendingSignInProvider.notifier).set(null);
    state = const NotSignedIn();
  }

  // ------------------------------------------------------------- refresh

  /// New access token with the device key's signature. Single flight.
  /// False when it could not refresh (offline, or signed out).
  Future<bool> refresh() async {
    if (_refreshing != null) return _refreshing!.future;
    final done = _refreshing = Completer<bool>();
    try {
      done.complete(await _refresh());
    } catch (_) {
      done.complete(false);
    } finally {
      _refreshing = null;
    }
    return done.future;
  }

  Future<bool> _refresh() async {
    final stored = await _store.read();
    if (stored == null) return false;
    final ts = _now().toUtc().toIso8601String();
    final signature = await _keys.sign(
      '${stored.deviceId}.${stored.refreshToken}.$ts',
    );
    try {
      final t = await _api.signin.postAuthRefresh(
        body: RefreshInput(
          deviceId: stored.deviceId,
          refreshToken: stored.refreshToken,
          timestamp: DateTime.parse(ts),
          signature: signature,
        ),
      );
      await _store.write(
        StoredSession(deviceId: stored.deviceId, refreshToken: t.refreshToken),
      );
      ref.read(accessTokenProvider.notifier).set(t.accessToken);
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      if (status == 401) {
        // device_revoked or refresh_invalid. AppSignedOut is 4.4; until then
        // everything local is cleared and sign-in shows.
        await signOutLocally();
      } else if (status == 403 && data is Map<String, Object?>) {
        await signOutLocally();
        state = LicenceRefused(LicenceRefusal.fromJson(data));
      }
      return false;
    }
  }

  /// Clears the stored session, the access token and the device key.
  Future<void> signOutLocally({String? notice}) async {
    await _store.clear();
    try {
      await _keys.delete();
    } catch (_) {
      // A missing key is fine.
    }
    ref.read(accessTokenProvider.notifier).set(null);
    ref.read(pendingSignInProvider.notifier).set(null);
    state = NotSignedIn(notice: notice);
  }

  // -------------------------------------------------------------- errors

  /// Runs an API call and turns failures into [SignInFailure] (or AppBasic).
  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on DioException catch (e) {
      final res = e.response;
      final data = res?.data;
      if (res == null) {
        throw const SignInFailure(SignInFailure.offline, code: 'offline');
      }
      if (res.statusCode == 426) {
        // The version gate has already switched to AppUpdate.
        throw const SignInFailure('', code: 'update_required');
      }
      if (res.statusCode == 403 &&
          data is Map<String, Object?> &&
          data['error'] == 'licence_basic') {
        state = LicenceRefused(LicenceRefusal.fromJson(data));
        throw const SignInFailure('', code: 'licence_basic');
      }
      if (data is Map<String, Object?> && data['message'] is String) {
        throw SignInFailure(
          data['message']! as String,
          code: data['error'] as String?,
        );
      }
      throw const SignInFailure(SignInFailure.offline, code: 'unexpected');
    }
  }
}

/// Wires the session into every API request: on a 401 from an authenticated
/// route, refresh once and retry; on 426, switch to AppUpdate.
class SessionInterceptor extends Interceptor {
  SessionInterceptor(this._dio, this._refresh, this._updateRequired);

  final Dio _dio;
  final Future<bool> Function() _refresh;
  final void Function(Map<String, Object?> config) _updateRequired;

  static const _retried = 'vp.retried';

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final res = err.response;
    final path = err.requestOptions.path;
    if (res?.statusCode == 426 && res?.data is Map<String, Object?>) {
      _updateRequired(res!.data as Map<String, Object?>);
      return handler.next(err);
    }
    if (res?.statusCode == 401 &&
        !path.startsWith('/auth/') &&
        err.requestOptions.extra[_retried] != true &&
        await _refresh()) {
      final o = err.requestOptions..extra[_retried] = true;
      o.headers.remove('Authorization');
      try {
        return handler.resolve(await _dio.fetch<Object?>(o));
      } on DioException catch (e) {
        return handler.next(e);
      }
    }
    handler.next(err);
  }
}

/// Builds the app's Dio with the session hooks.
Dio buildSessionDio(Ref ref) {
  final config = ref.watch(apiConfigProvider);
  final dio = buildDio(
    config,
    accessToken: () => ref.read(accessTokenProvider),
  );
  dio.interceptors.add(
    SessionInterceptor(
      dio,
      () => ref.read(authProvider.notifier).refresh(),
      (json) => ref
          .read(updateRequiredProvider.notifier)
          .set(AppConfig.fromJson(json)),
    ),
  );
  return dio;
}

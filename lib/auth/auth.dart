import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../calls/directory.dart';
import '../diagnostics/scrubber.dart';
import '../engine/full_screen_access.dart' show fullScreenPromptProvider;
import '../features/messages/messages_data.dart';
import '../features/recents/recents_data.dart' show pickedRecentProvider;
import '../net/api.dart';
import '../platform/device_keys.dart';
import '../screens/contacts/colleague_detail.dart'
    show
        pickedColleagueProvider,
        pickedPhoneContactProvider,
        pickedTeamMemberProvider;
import '../screens/contacts/contacts_screen.dart'
    show contactsListPlacesProvider, contactsOpenTeamsProvider;
import '../screens/keypad/keypad_matches.dart' show pickedMatchProvider;
import '../screens/keypad/keypad_screen.dart' show dialledProvider;
import '../shell/shell_status.dart';
import '../theme/theme_preference.dart';
import 'app_lock.dart';
import 'local_wipe.dart';
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

/// The platform signed this phone out (refresh answered `device_revoked`,
/// perhaps after a `signed_out` push): AppSignedOut. Everything local is
/// already cleared; [info] says who, when and whom to ask.
final class SignedOutRemotely extends AuthState {
  const SignedOutRemotely(this.info);
  final SignedOut info;
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

  /// The session ended without a revocation (`refresh_invalid`, or a 401
  /// with no usable body): AppSignIn's note, blaming no one.
  static const signInAgain = 'Please sign in again.';

  /// [signInAgain], plus the API's own message when it says more than "Sign
  /// in again" (today: "Check this phone's date and time").
  static String signInAgainNotice(SignedOut? info) {
    var m = info?.message.trim() ?? '';
    if (m.endsWith('.')) m = m.substring(0, m.length - 1);
    if (m.isEmpty || m.toLowerCase() == 'sign in again') return signInAgain;
    return '$signInAgain $m.';
  }

  /// Spec 22, Sign-in item 3.
  static const notThisPhone =
      'This link only signs in the phone that asked for it.';

  @override
  String toString() => 'SignInFailure($code)';
}

/// Everything else kept on the phone that must go at sign-out.
final localDataWipersProvider = Provider<List<Future<void> Function()>>(
  (ref) => [
    // Settings and remembered choices (theme, biometric unlock, contacts
    // asked, update banner, full-screen sheet, the last known tab set): back
    // to a new install.
    () async {
      await ref.read(sharedPreferencesProvider).clear();
      ref.invalidate(themePreferenceProvider);
      ref.invalidate(lastKnownShellProvider);
      ref.invalidate(biometricUnlockProvider);
      ref.invalidate(fullScreenPromptProvider);
    },
    // The address-book values held for the scrubber, and the contacts read:
    // signed in again, they are read and registered afresh.
    () async {
      DiagnosticsScrubber.instance.forgetAddressBookValues();
      ref.invalidate(phoneContactsProvider);
    },
    // Half-typed replies and the open conversation (memory only).
    () async {
      ref.invalidate(threadDraftProvider);
      ref.invalidate(pickedThreadProvider);
    },
    // The half-typed number and the match picked for it (memory only), so
    // the next account never sees the last one's caller.
    () async {
      ref.invalidate(dialledProvider);
      ref.invalidate(pickedMatchProvider);
    },
    // What was picked (a call; a colleague, team member, phone contact or
    // shared phonebook entry) and where the lists were, in Recents and
    // Contacts (memory only): the next account opens on its own lists.
    () async {
      ref.invalidate(pickedRecentProvider);
      ref.invalidate(pickedColleagueProvider);
      ref.invalidate(pickedTeamMemberProvider);
      ref.invalidate(pickedPhoneContactProvider);
      ref.invalidate(contactsListPlacesProvider);
      ref.invalidate(contactsOpenTeamsProvider);
    },
    // Crash-report scope and the on-disk outbox.
    clearDiagnosticsOnDevice,
  ],
);

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
      // A link opened the app cold and already answered (for example "This
      // link only signs in the phone that asked for it"): keep its notice.
      if (state is AuthStarting) state = const NotSignedIn();
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
    // The tab set from the session's own `me`, before `GET /me` answers
    // and before the router shows the shell: Messages already right, no tab
    // flashing in. After the token, as `record` needs a session.
    ref.read(lastKnownShellProvider.notifier).record(s.me);
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
        // Everything local is cleared either way. Only `device_revoked` is a
        // real revocation: AppSignedOut, saying who and when as far as the
        // body says. `refresh_invalid` (a session the server doesn't know,
        // reused or expired), an unparsable body or any other 401 blames no
        // one: AppSignIn with a neutral note.
        SignedOut? info;
        if (data is Map<String, Object?>) {
          try {
            info = SignedOut.fromJson(data);
          } catch (_) {}
        }
        if (info != null && info.error == SignedOutError.deviceRevoked) {
          await signOutLocally();
          state = SignedOutRemotely(info);
        } else {
          await signOutLocally(notice: SignInFailure.signInAgainNotice(info));
        }
      } else if (status == 403 && data is Map<String, Object?>) {
        await signOutLocally();
        state = LicenceRefused(LicenceRefusal.fromJson(data));
      }
      return false;
    }
  }

  /// A `signed_out` push. It carries nothing (APP5), so ask the server: the
  /// refresh answers `device_revoked` with who and when, and a stale push
  /// changes nothing.
  Future<void> onSignedOutPush() async {
    if (state is! SignedIn) return;
    await refresh();
  }

  /// Me, Sign out: tells the platform (best effort), then clears the phone.
  Future<void> signOut() async {
    try {
      await _api.device.postDevicesMeSignOut();
    } catch (_) {
      // Offline: the phone is still cleared; the admin can revoke it.
    }
    await signOutLocally();
  }

  /// AppSignedOut: Sign in again.
  void acknowledgeSignedOut() {
    if (state is SignedOutRemotely) state = const NotSignedIn();
  }

  /// Clears every local store: the session, the access token, the device
  /// key, and each store in [localDataWipersProvider] (settings, the
  /// address-book values held for the scrubber, playback).
  Future<void> signOutLocally({String? notice}) async {
    for (final wipe in ref.read(localDataWipersProvider)) {
      try {
        await wipe();
      } catch (_) {}
    }
    await _store.clear();
    try {
      await _keys.delete();
    } catch (_) {
      // A missing key is fine.
    }
    ref.read(accessTokenProvider.notifier).set(null);
    ref.read(pendingSignInProvider.notifier).set(null);
    // Again, now the token has gone: a `GET /me` answer that landed while
    // the wipers above were awaiting (token still held) may have written
    // the tab set back. From here `record` is a no-op.
    try {
      await ref
          .read(sharedPreferencesProvider)
          .remove(LastKnownShellNotifier.storageKey);
    } catch (_) {}
    ref.invalidate(lastKnownShellProvider);
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

import 'package:call_engine/call_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vp_linphone/vp_linphone.dart';

import 'engine_provider.dart';

/// How long the app registers with the SIP password it keeps before it asks
/// the API for a new one (Q356-1, TJ 22 Nov; decision 170's 7-day binding).
const keptAccountMaxAge = Duration(days: 7);

/// The SIP account the engine keeps on the phone (Android Keystore,
/// `CredentialStore.kt`), as the app may use it: its issue time, a register
/// with it, and a wipe. The password never reaches Dart (APP4).
abstract interface class KeptSipAccount {
  /// When the kept password was issued; null when none is kept.
  Future<DateTime?> issuedAt();

  /// Registers the engine with the kept account, with [push] when given.
  /// False when none is kept.
  Future<bool> register({PushParams? push});

  /// Deletes it from the phone.
  Future<void> wipe();
}

/// A new password is needed: none is kept, it is 7 days old or more, or its
/// time is ahead of the phone's clock (the clock went back).
bool keptAccountTooOld(DateTime? issuedAt, DateTime now) {
  if (issuedAt == null) return true;
  final age = now.difference(issuedAt);
  return age.isNegative || age >= keptAccountMaxAge;
}

/// A register refused for its credentials (401, 403): the kept password was
/// rotated elsewhere or the device was removed.
bool refusedCredentials(RegistrationEvent e) =>
    e.state == RegistrationState.failed &&
    (e.failure == RegistrationFailure.badCredentials ||
        e.failure == RegistrationFailure.forbidden ||
        e.sipCode == 401 ||
        e.sipCode == 403);

class _LinphoneKept implements KeptSipAccount {
  const _LinphoneKept(this.engine);
  final VpLinphoneEngine engine;

  @override
  Future<DateTime?> issuedAt() => engine.keptAccountIssuedAt();

  @override
  Future<bool> register({PushParams? push}) => engine.registerKept(push: push);

  @override
  Future<void> wipe() => engine.forgetKeptAccount();
}

/// The kept account with the real engine. None with the fake: every start
/// asks the API, as before Q356-1. Tests override it.
final keptSipAccountProvider = Provider<KeptSipAccount?>((ref) {
  final engine = ref.watch(callEngineProvider);
  return engine is VpLinphoneEngine ? _LinphoneKept(engine) : null;
});

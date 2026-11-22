import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A sign-out made with no network (spec 22, "Sign out with no network"):
/// the refresh token the phone held, signed with the device key over
/// `sign-out.<deviceId>.<refreshToken>.<timestamp>` before the key was
/// deleted. The only thing kept after such a sign-out; sent once, first, on
/// the next connection (`POST /auth/sign-out`), so the platform ends the
/// binding instead of leaving it up to 7 days. Never logged; [toString]
/// shows no token or signature.
@immutable
class PendingSignOut {
  const PendingSignOut({
    required this.deviceId,
    required this.refreshToken,
    required this.timestamp,
    required this.signature,
  });

  final String deviceId;
  final String refreshToken;

  /// When the user signed out: UTC ISO 8601, exactly as signed.
  final String timestamp;
  final String signature;

  DateTime get signedAt => DateTime.parse(timestamp);

  /// Kept on the phone 30 days at most: the refresh token's lifetime, after
  /// which the session it could end is gone anyway (the platform refuses an
  /// older one too).
  static const maxAge = Duration(days: 30);

  /// The bytes the device key signs.
  static String message(String deviceId, String refreshToken, String ts) =>
      'sign-out.$deviceId.$refreshToken.$ts';

  @override
  String toString() => 'PendingSignOut($deviceId)';
}

abstract interface class PendingSignOutStore {
  Future<PendingSignOut?> read();
  Future<void> write(PendingSignOut p);
  Future<void> clear();
}

/// flutter_secure_storage, under its own keys: sign-out clears the session's
/// keys (SessionStore) but never these.
class SecurePendingSignOutStore implements PendingSignOutStore {
  SecurePendingSignOutStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  static const _device = 'vp.signOut.deviceId';
  static const _refresh = 'vp.signOut.refreshToken';
  static const _ts = 'vp.signOut.timestamp';
  static const _sig = 'vp.signOut.signature';

  @override
  Future<PendingSignOut?> read() async {
    final d = await _s.read(key: _device);
    final r = await _s.read(key: _refresh);
    final t = await _s.read(key: _ts);
    final g = await _s.read(key: _sig);
    if (d == null || r == null || t == null || g == null) return null;
    if (DateTime.tryParse(t) == null) return null;
    return PendingSignOut(
      deviceId: d,
      refreshToken: r,
      timestamp: t,
      signature: g,
    );
  }

  @override
  Future<void> write(PendingSignOut p) async {
    await _s.write(key: _device, value: p.deviceId);
    await _s.write(key: _refresh, value: p.refreshToken);
    await _s.write(key: _ts, value: p.timestamp);
    await _s.write(key: _sig, value: p.signature);
  }

  @override
  Future<void> clear() async {
    for (final k in [_device, _refresh, _ts, _sig]) {
      await _s.delete(key: k);
    }
  }
}

/// For tests and the mock-server runs.
class MemoryPendingSignOutStore implements PendingSignOutStore {
  MemoryPendingSignOutStore([this.pending]);
  PendingSignOut? pending;

  @override
  Future<PendingSignOut?> read() async => pending;

  @override
  Future<void> write(PendingSignOut p) async => pending = p;

  @override
  Future<void> clear() async => pending = null;
}

final pendingSignOutStoreProvider = Provider<PendingSignOutStore>(
  (ref) => SecurePendingSignOutStore(),
);

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What survives a restart: the device id and its refresh token. The access
/// token lives in memory only. Never logged; [toString] shows no token.
@immutable
class StoredSession {
  const StoredSession({required this.deviceId, required this.refreshToken});
  final String deviceId;
  final String refreshToken;

  @override
  String toString() => 'StoredSession($deviceId)';
}

abstract interface class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

/// flutter_secure_storage: values encrypted with a key held in Android
/// Keystore; excluded from backups by the plugin.
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  static const _device = 'vp.deviceId';
  static const _refresh = 'vp.refreshToken';

  @override
  Future<StoredSession?> read() async {
    final d = await _s.read(key: _device);
    final r = await _s.read(key: _refresh);
    if (d == null || r == null) return null;
    return StoredSession(deviceId: d, refreshToken: r);
  }

  @override
  Future<void> write(StoredSession session) async {
    await _s.write(key: _device, value: session.deviceId);
    await _s.write(key: _refresh, value: session.refreshToken);
  }

  @override
  Future<void> clear() async {
    await _s.delete(key: _device);
    await _s.delete(key: _refresh);
  }
}

/// For tests and the mock-server runs.
class MemorySessionStore implements SessionStore {
  MemorySessionStore([this.session]);
  StoredSession? session;

  @override
  Future<StoredSession?> read() async => session;

  @override
  Future<void> write(StoredSession s) async => session = s;

  @override
  Future<void> clear() async => session = null;
}

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(),
);

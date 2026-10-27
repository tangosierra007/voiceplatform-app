import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_keys.g.dart';

/// The phone's device key (spec 22, Sign-in item 6): a P-256 key that never
/// leaves Android Keystore. Its public half goes to the API when sign-in
/// completes; every refresh is signed with it.
abstract interface class DeviceKeys {
  /// Creates the key if needed; SPKI DER, base64url without padding.
  Future<String> publicKey();

  /// ECDSA P-256 SHA-256 over UTF-8 [message]; DER, base64url.
  Future<String> sign(String message);

  /// Forgets the key (signed out or revoked).
  Future<void> delete();
}

/// Android Keystore through the Pigeon channel (`keys/DeviceKeyStore.kt`).
class KeystoreDeviceKeys implements DeviceKeys {
  KeystoreDeviceKeys([DeviceKeysApi? api]) : _api = api ?? DeviceKeysApi();
  final DeviceKeysApi _api;

  @override
  Future<String> publicKey() async => (await _api.ensureKey()).publicKeySpki;

  @override
  Future<String> sign(String message) => _api.sign(message);

  @override
  Future<void> delete() => _api.deleteKey();
}

final deviceKeysProvider = Provider<DeviceKeys>((ref) => KeystoreDeviceKeys());

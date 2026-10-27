// The typed channel to the device key in Android Keystore (spec 22, Sign-in
// item 6). Regenerate with:
//
//   dart run pigeon --input tool/pigeons/device_keys.dart
//
// (Not .g.dart: build_runner would take that for its own output.)
//
// The key never leaves the Keystore: Dart sees only the public key and
// signatures.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/device_keys.pigeon.dart',
    dartPackageName: 'voiceplatform_app',
    kotlinOut: 'android/app/src/main/kotlin/au/com/voiceplatform/app/keys/DeviceKeysApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'au.com.voiceplatform.app.keys'),
    copyrightHeader: 'tool/pigeons/header.txt',
  ),
)
class DeviceKeyInfo {
  DeviceKeyInfo({required this.publicKeySpki, required this.strongBox});

  /// SubjectPublicKeyInfo DER of the P-256 key, base64url without padding.
  final String publicKeySpki;

  /// True when the key lives in StrongBox.
  final bool strongBox;
}

@HostApi()
abstract class DeviceKeysApi {
  /// Creates the P-256 signing key if there is none (StrongBox when the phone
  /// has one) and returns its public half.
  DeviceKeyInfo ensureKey();

  /// ECDSA with SHA-256 over the UTF-8 [message]; the DER signature,
  /// base64url without padding.
  String sign(String message);

  /// Deletes the key (sign-out, revoked device).
  void deleteKey();
}

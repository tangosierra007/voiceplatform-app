import 'dart:async';

import 'package:voiceplatform_app/auth/app_lock.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/auth/version.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/platform/device_keys.dart';
import 'package:voiceplatform_app/platform/phone.dart';

/// A device key that records what it signed. Not a real key.
class FakeDeviceKeys implements DeviceKeys {
  final signed = <String>[];
  int deletes = 0;

  @override
  Future<String> publicKey() async =>
      'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE-fake-spki';

  @override
  Future<String> sign(String message) async {
    signed.add(message);
    return 'MEUCIQ-fake-signature';
  }

  @override
  Future<void> delete() async => deletes++;
}

class FakePhone implements PhoneLauncher {
  FakePhone({this.hasDialler = true});
  bool hasDialler;
  final dialled = <String>[];
  final opened = <String>[];

  @override
  Future<bool> canDial() async => hasDialler;

  @override
  Future<void> openDialler(String number) async => dialled.add(number);

  @override
  Future<void> openUrl(String url) async => opened.add(url);
}

class FakeBiometrics implements Biometrics {
  FakeBiometrics({this.available = true, this.pass = true});
  bool available;
  bool pass;
  int asked = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return pass;
  }
}

/// An AuthController that starts in [initial] and records the calls the
/// screens make, answering with [script] (throw a SignInFailure to fail).
class ScriptedAuth extends AuthController {
  ScriptedAuth(this.initial, {this.script});
  final AuthState initial;
  final FutureOr<void> Function(String call, List<Object?> args)? script;
  final calls = <String>[];

  @override
  AuthState build() => initial;

  Future<void> _run(String call, [List<Object?> args = const []]) async {
    calls.add(call);
    await script?.call(call, args);
  }

  @override
  Future<void> requestEmail(String email) async {
    await _run('requestEmail', [email]);
    ref
        .read(pendingSignInProvider.notifier)
        .set(
          PendingSignIn(
            email: email,
            requestId: 'r1',
            secret: 's',
            resendAt: ref
                .read(clockProvider)()
                .add(const Duration(seconds: 60)),
            expiresAt: ref
                .read(clockProvider)()
                .add(const Duration(minutes: 10)),
          ),
        );
  }

  @override
  Future<void> resend() => _run('resend');

  @override
  Future<void> completeWithCode(String code) =>
      _run('completeWithCode', [code]);

  @override
  Future<void> completeWithQr(String token) => _run('completeWithQr', [token]);

  @override
  Future<void> askAdminToUpgrade() => _run('askAdminToUpgrade');

  @override
  Future<bool> refresh() async {
    calls.add('refresh');
    return false;
  }

  void setState(AuthState s) => state = s;
}

/// No `GET /config` at start.
class NoConfigCheck extends AppConfigNotifier {
  NoConfigCheck([this.config]);
  final AppConfig? config;

  @override
  AppConfig? build() => config;

  @override
  Future<void> check() async {}
}

/// The Warehouse refusal AppBasic shows.
const warehouseRefusal = LicenceRefusal(
  error: LicenceRefusalError.licenceBasic,
  message: 'This app needs an Advanced licence',
  extensionValue: '204',
  extensionName: 'Warehouse',
  refusalToken: 'refusal-1',
);

class PresetUpdateRequired extends UpdateRequiredNotifier {
  PresetUpdateRequired(this.config);
  final AppConfig config;

  @override
  AppConfig? build() => config;
}

class PresetPending extends PendingSignInNotifier {
  PresetPending(this.pending);
  final PendingSignIn pending;

  @override
  PendingSignIn? build() => pending;
}

/// The mock's AppConfig for this app at [version]: minimum above it.
AppConfig configWithMinimum(String minimum, {String? recommended}) => AppConfig(
  platform: Platform.android,
  minimumVersion: minimum,
  recommendedVersion: recommended ?? minimum,
  storeUrl:
      'https://play.google.com/store/apps/details?id=au.com.voiceplatform.app',
);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../nav/routes.dart';
import '../theme/app_theme.dart';
import '../theme/theme_preference.dart';
import '../widgets/vp_controls.dart';
import 'auth.dart';

/// The device's biometric or screen-lock check; tests replace it.
abstract interface class Biometrics {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}

class LocalAuthBiometrics implements Biometrics {
  LocalAuthBiometrics([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() => _auth.isDeviceSupported();

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }
}

final biometricsProvider = Provider<Biometrics>((ref) => LocalAuthBiometrics());

/// The Me switch "Unlock with fingerprint or face" (spec 22, Sign-in item 8):
/// off by default. It gates opening the app only; incoming calls still ring
/// and can be answered (the call screens are never covered).
final biometricUnlockProvider = NotifierProvider<BiometricUnlockNotifier, bool>(
  BiometricUnlockNotifier.new,
);

class BiometricUnlockNotifier extends Notifier<bool> {
  static const storageKey = 'vp.biometricUnlock';

  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(storageKey) ?? false;

  /// Turning it on asks for the check once, so a user can't lock themselves out.
  Future<bool> set(bool on) async {
    if (on) {
      final b = ref.read(biometricsProvider);
      if (!await b.isAvailable() ||
          !await b.authenticate('Turn on unlock for VoicePlatform')) {
        return false;
      }
    }
    await ref.read(sharedPreferencesProvider).setBool(storageKey, on);
    state = on;
    return true;
  }
}

/// Covers the app with an unlock screen when it opens or comes back from the
/// background, if the switch is on and someone is signed in.
class AppLock extends ConsumerStatefulWidget {
  const AppLock({super.key, required this.child, required this.location});

  final Widget child;

  /// The current route, so the call screens are never covered.
  final String Function() location;

  @override
  ConsumerState<AppLock> createState() => _AppLockState();
}

class _AppLockState extends ConsumerState<AppLock> {
  late final AppLifecycleListener _listener;
  late bool _locked = ref.read(biometricUnlockProvider);

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onHide: () {
        if (ref.read(biometricUnlockProvider)) setState(() => _locked = true);
      },
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final ok = await ref
        .read(biometricsProvider)
        .authenticate('Unlock VoicePlatform');
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(biometricUnlockProvider);
    final signedIn = ref.watch(authProvider) is SignedIn;
    final show = on && _locked && signedIn && !isCallRoute(widget.location());
    return Stack(
      children: [
        widget.child,
        if (show) Positioned.fill(child: _LockScreen(onUnlock: _unlock)),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.vp.canvas,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: VpLogo()),
              const SizedBox(height: 32),
              VpButton(label: 'Unlock', onPressed: onUnlock),
            ],
          ),
        ),
      ),
    );
  }
}

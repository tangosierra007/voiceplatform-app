import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the app asks of the phone itself: its dialler and the store.
abstract interface class PhoneLauncher {
  /// True when something on the phone handles ACTION_DIAL for a tel: number.
  Future<bool> canDial();

  /// Opens the phone's dialler with [number] filled in (ACTION_DIAL: the user
  /// presses call there; the app holds no CALL_PHONE permission).
  Future<void> openDialler(String number);

  /// Opens the Play listing (or any https URL).
  Future<void> openUrl(String url);
}

class AndroidPhoneLauncher implements PhoneLauncher {
  const AndroidPhoneLauncher();

  static AndroidIntent _dial(String number) =>
      AndroidIntent(action: 'android.intent.action.DIAL', data: 'tel:$number');

  @override
  Future<bool> canDial() async =>
      (await _dial('000').canResolveActivity()) ?? false;

  @override
  Future<void> openDialler(String number) => _dial(number).launch();

  @override
  Future<void> openUrl(String url) =>
      AndroidIntent(action: 'android.intent.action.VIEW', data: url).launch();
}

final phoneLauncherProvider = Provider<PhoneLauncher>(
  (ref) => const AndroidPhoneLauncher(),
);

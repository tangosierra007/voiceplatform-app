import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vp_linphone/vp_linphone.dart'
    show VpBatteryStatus, VpLinphoneEngine, VpPushMessage;

import 'engine_provider.dart';

export 'package:vp_linphone/vp_linphone.dart'
    show VpBatteryStatus, VpPushMessage, VpPushType;

/// What the Android engine (WS3) tells the app beyond calls: data pushes for
/// the app and the battery facts for Me. Nothing with the fake engine.
abstract interface class PhoneExtras {
  /// `voicemail`, `message`, `signed_out`, `config` while the app runs.
  Stream<VpPushMessage> get pushes;

  /// Those that arrived while it was not running, once.
  Future<List<VpPushMessage>> takePendingPushes();

  /// Null when not known (not Android, or the engine is not running).
  Future<VpBatteryStatus?> battery();

  Future<void> openBatterySettings();
}

class _LinphoneExtras implements PhoneExtras {
  const _LinphoneExtras(this.engine);
  final VpLinphoneEngine engine;

  @override
  Stream<VpPushMessage> get pushes => engine.pushMessages;

  @override
  Future<List<VpPushMessage>> takePendingPushes() async {
    try {
      return await engine.takePendingPushes();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<VpBatteryStatus?> battery() async {
    try {
      return await engine.batteryStatus();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> openBatterySettings() =>
      engine.openBatteryOptimizationSettings();
}

class _NoExtras implements PhoneExtras {
  const _NoExtras();

  @override
  Stream<VpPushMessage> get pushes => const Stream.empty();

  @override
  Future<List<VpPushMessage>> takePendingPushes() async => const [];

  @override
  Future<VpBatteryStatus?> battery() async => null;

  @override
  Future<void> openBatterySettings() async {}
}

final phoneExtrasProvider = Provider<PhoneExtras>((ref) {
  final engine = ref.watch(callEngineProvider);
  return engine is VpLinphoneEngine
      ? _LinphoneExtras(engine)
      : const _NoExtras();
});

/// Late push wakes in the last 7 days at which the Me battery card shows.
/// Proposed (no decision yet): 2, so one slow wake does not nag.
const lateWakesForBatteryCard = 2;

/// The Me battery card: shown when Android delayed call pushes this week and
/// the app is not exempt from battery optimisation.
final batteryCardProvider = FutureProvider<VpBatteryStatus?>((ref) async {
  final b = await ref.watch(phoneExtrasProvider).battery();
  if (b == null ||
      b.ignoringOptimizations ||
      b.lateWakesLastWeek < lateWakesForBatteryCard) {
    return null;
  }
  return b;
});

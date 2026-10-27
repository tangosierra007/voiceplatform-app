import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:permission_handler/permission_handler.dart';

import '../emergency/emergency.dart';
import '../engine/engine_provider.dart';
import '../net/api.dart';
import '../screens/calls/microphone_sheet.dart';
import 'me_state.dart';

/// RECORD_AUDIO, asked only when a call starts (spec 22, Microphone).
abstract interface class MicPermission {
  Future<bool> isGranted();

  /// Asks the system once; true when granted.
  Future<bool> request();

  /// The app's page in Android Settings.
  Future<void> openSettings();
}

class DeviceMicPermission implements MicPermission {
  const DeviceMicPermission();

  @override
  Future<bool> isGranted() => Permission.microphone.isGranted;

  @override
  Future<bool> request() async =>
      (await Permission.microphone.request()).isGranted;

  @override
  Future<void> openSettings() => openAppSettings();
}

final micPermissionProvider = Provider<MicPermission>(
  (ref) => const DeviceMicPermission(),
);

/// What the call screens know beyond the engine's snapshot: the caller ID
/// each outgoing call used, and an attended transfer in progress.
@immutable
class CallBook {
  const CallBook({this.callerIds = const {}, this.transfer});

  final Map<String, CallerId?> callerIds;

  /// (call on hold, consult call) while "Talk to `<name>` first" is under way.
  final (String held, String consult)? transfer;

  CallBook copyWith({
    Map<String, CallerId?>? callerIds,
    (String, String)? transfer,
    bool clearTransfer = false,
  }) => CallBook(
    callerIds: callerIds ?? this.callerIds,
    transfer: clearTransfer ? null : transfer ?? this.transfer,
  );
}

final callBookProvider = NotifierProvider<CallBookNotifier, CallBook>(
  CallBookNotifier.new,
);

class CallBookNotifier extends Notifier<CallBook> {
  @override
  CallBook build() {
    final sub = ref.watch(callEngineProvider).calls.listen((c) {
      if (c.state != CallState.ended) return;
      final t = state.transfer;
      if (t != null && (t.$1 == c.id || t.$2 == c.id)) {
        state = state.copyWith(clearTransfer: true);
      }
    });
    ref.onDispose(sub.cancel);
    return const CallBook();
  }

  void usedCallerId(String callId, CallerId? id) =>
      state = state.copyWith(callerIds: {...state.callerIds, callId: id});

  void startTransfer(String held, String consult) =>
      state = state.copyWith(transfer: (held, consult));

  void endTransfer() => state = state.copyWith(clearTransfer: true);
}

/// Places a call from any screen (keypad, Recents, contacts, add call).
///
/// 1. Emergency numbers go to AppEmergency and the phone's dialler, before
///    anything else (APP6).
/// 2. The microphone is asked for now, and only now. Refused: AppMicrophone.
/// 3. A call already connected is put on hold first (Add call).
/// 4. The engine places it with the picked caller ID (null: the default).
Future<String?> startCall(
  BuildContext context,
  WidgetRef ref,
  String number, {
  CallerId? callerId,
}) => startCallWith(context, ref.read, number, callerId: callerId);

/// Reads providers.
typedef ProviderRead = T Function<T>(ProviderListenable<T> provider);

/// [startCall] for code that holds a container rather than a WidgetRef.
Future<String?> startCallWith(
  BuildContext context,
  ProviderRead read,
  String number, {
  CallerId? callerId,
}) async {
  if (isEmergencyNumber(number)) {
    await showEmergencySheet(context, number);
    return null;
  }
  final mic = read(micPermissionProvider);
  if (!await mic.isGranted() && !await mic.request()) {
    if (context.mounted) {
      await showMicrophoneSheet(context, number: number, callerId: callerId);
    }
    return null;
  }
  final engine = read(callEngineProvider);
  for (final c in engine.activeCalls) {
    if (c.state == CallState.connected) await engine.hold(c.id);
  }
  final id = callerId ?? read(selectedCallerIdProvider);
  try {
    final callId = await engine.call(
      number,
      callerId: id == null || id.isDefault ? null : id.value,
    );
    read(callBookProvider.notifier).usedCallerId(callId, id);
    return callId;
  } on EmergencyNumberUseDialler {
    if (context.mounted) await showEmergencySheet(context, number);
  } on MicrophoneDenied {
    if (context.mounted) {
      await showMicrophoneSheet(context, number: number, callerId: callerId);
    }
  } on NotRegistered {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text("Not connected yet. Try again in a moment."),
        ),
      );
    }
  }
  return null;
}

/// "Call from my desk phone instead" (A1): the platform rings the desk phone,
/// then the number (`POST /calls/via-desk-phone`; WS1 1.3b builds it, the
/// mock answers today). Returns the desk phone's name, for example
/// `Desk phone 202`.
typedef DeskPhoneCall = Future<String> Function(
  String number,
  CallerId? callerId,
);

final deskPhoneCallProvider = Provider<DeskPhoneCall>((ref) {
  return (number, callerId) async {
    final r = await ref
        .read(appApiProvider)
        .calls
        .postCallsViaDeskPhone(
          body: ViaDeskPhoneInput(
            number: number,
            callerId: callerId == null || callerId.isDefault
                ? null
                : callerId.value,
          ),
        );
    return r.deskPhone;
  };
});

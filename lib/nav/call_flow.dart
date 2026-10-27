import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vp_linphone/vp_linphone.dart' show VpUiRequest, VpUiRequestKind;

import '../calls/call_actions.dart';
import '../engine/engine_provider.dart';
import 'routes.dart';

/// Moves between the tabs and the call screens as the engine's calls change:
/// ringing here opens Incoming, connecting or dialling opens In call, and the
/// last call ending goes back to where the user was.
class CallFlow extends ConsumerStatefulWidget {
  const CallFlow({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CallFlow> createState() => _CallFlowState();
}

class _CallFlowState extends ConsumerState<CallFlow> {
  StreamSubscription<CallSnapshot>? _sub;
  StreamSubscription<VpUiRequest>? _ui;
  String? _returnTo;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(callEngineProvider).calls.listen(_onCall);
    // The incoming-call notification and full-screen intent (WS3 3.2): a
    // cold start brings one request; a running app gets them as a stream.
    final ui = ref.read(engineUiProvider);
    _ui = ui.requests.listen(_onUiRequest);
    ui.take().then((r) {
      if (r != null && mounted) _onUiRequest(r);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ui?.cancel();
    super.dispose();
  }

  void _onUiRequest(VpUiRequest r) {
    final router = ref.read(routerProvider);
    final here = router.routerDelegate.currentConfiguration.uri.path;
    _returnTo ??= isCallRoute(here) ? null : here;
    router.go(
      r.kind == VpUiRequestKind.showIncoming
          ? Routes.incoming(r.callId)
          : Routes.inCall(r.callId),
    );
  }

  final Map<String, CallState> _last = {};

  /// Calls BLUETOOTH_CONNECT has been asked for: once per call.
  final Set<String> _bluetoothAsked = {};

  void _onCall(CallSnapshot c) {
    final router = ref.read(routerProvider);
    final here = router.routerDelegate.currentConfiguration.uri.path;
    final prev = _last[c.id];
    _last[c.id] = c.state;
    _returnTo ??= isCallRoute(here) ? null : here;
    final showing =
        here.startsWith(Routes.inCall(c.id)) || here == Routes.incoming(c.id);
    switch (c.state) {
      case CallState.incoming:
        if (prev == null) router.go(Routes.incoming(c.id));
      case CallState.dialling:
        if (!showing) router.go(Routes.inCall(c.id));
      case CallState.connected:
        // BLUETOOTH_CONNECT once the call is up, never before answering
        // (WS6): the system dialog must not stand between the user and the
        // Answer button. Any path that ends connected passes here, including
        // answering after a trip to Settings for the microphone.
        if (_bluetoothAsked.add(c.id)) {
          unawaited(ref.read(micPermissionProvider).requestBluetooth());
        }
        // Only on the change to connected: a merge or a mute must not move.
        if (prev != CallState.connected &&
            prev != CallState.heldByMe &&
            !here.startsWith(Routes.inCall(c.id))) {
          router.go(Routes.inCall(c.id));
        }
      case CallState.ended:
        _last.remove(c.id);
        _bluetoothAsked.remove(c.id);
        if (!showing && isCallRoute(here)) return;
        final engine = ref.read(callEngineProvider);
        final next = engine.activeCalls.where((o) => o.id != c.id).firstOrNull;
        if (next != null) {
          router.go(
            next.state == CallState.incoming
                ? Routes.incoming(next.id)
                : Routes.inCall(next.id),
          );
        } else if (isCallRoute(here)) {
          router.go(_returnTo ?? Routes.keypad);
          _returnTo = null;
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

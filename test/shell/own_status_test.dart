// The rail's own status: the presence dot and what a screen reader says,
// for each state, on a call included.
import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/calls/me_state.dart';
import 'package:voiceplatform_app/engine/engine_provider.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/theme/app_theme.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';

CallSnapshot _call(CallState state) => CallSnapshot(
  id: 'c1',
  direction: CallDirection.outgoing,
  state: state,
  remoteNumber: '+61491570737',
);

Future<void> _pump(
  WidgetTester tester, {
  StatusStatus status = StatusStatus.available,
  List<CallSnapshot> calls = const [],
  bool offline = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        callEngineProvider.overrideWithValue(
          FakeCallEngine(outgoing: OutgoingScript.manual),
        ),
        activeCallsProvider.overrideWith((ref) => Stream.value(calls)),
        myStatusProvider.overrideWith(() => PresetStatus(status)),
        meProvider.overrideWith(
          (ref) async => Me.fromJson(fx.me(status: status.json!)),
        ),
        if (offline) offlineProvider.overrideWith(PresetOffline.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Center(child: OwnStatus())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color _dot(WidgetTester tester) {
  final dots = tester.widgetList<Container>(
    find.descendant(
      of: find.byType(OwnStatus),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 12 &&
            w.decoration is BoxDecoration,
      ),
    ),
  );
  return (dots.single.decoration! as BoxDecoration).color!;
}

void main() {
  final c = vpLightColors;

  for (final (name, status, calls, offline, label, colour) in [
    (
      'free',
      StatusStatus.available,
      <CallSnapshot>[],
      false,
      'Your status: Available. Change',
      c.statusOk,
    ),
    (
      'on a call',
      StatusStatus.available,
      [_call(CallState.connected)],
      false,
      'Your status: On a call. Change',
      c.brand,
    ),
    (
      'on hold counts as on a call',
      StatusStatus.available,
      [_call(CallState.heldByMe)],
      false,
      'Your status: On a call. Change',
      c.brand,
    ),
    (
      'ringing in is not on a call yet',
      StatusStatus.available,
      [_call(CallState.incoming)],
      false,
      'Your status: Available. Change',
      c.statusOk,
    ),
    (
      'do not disturb wins over a call',
      StatusStatus.dnd,
      [_call(CallState.connected)],
      false,
      'Your status: Do not disturb. Change',
      c.statusBad,
    ),
    (
      'away',
      StatusStatus.away,
      <CallSnapshot>[],
      false,
      'Your status: Away. Change',
      c.borderStrong,
    ),
    (
      'offline',
      StatusStatus.available,
      <CallSnapshot>[],
      true,
      'Your status: Offline',
      c.borderStrong,
    ),
  ]) {
    testWidgets('own status: $name', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, status: status, calls: calls, offline: offline);
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(_dot(tester), colour);
      handle.dispose();
    });
  }
}

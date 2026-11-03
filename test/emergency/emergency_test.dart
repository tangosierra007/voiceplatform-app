import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/emergency/emergency.dart';
import 'package:voiceplatform_app/engine/engine_provider.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/platform/phone.dart';
import 'package:voiceplatform_app/theme/app_theme.dart';

import 'package:voiceplatform_app/calls/call_actions.dart';

import '../support/call_fakes.dart';
import '../support/fakes.dart';
import '../support/phone.dart';

/// Records every number the engine is asked to call.
class _SpyEngine extends FakeCallEngine {
  _SpyEngine() : super(outgoing: OutgoingScript.manual);
  final asked = <String>[];

  @override
  Future<String> call(String number, {String? callerId}) {
    asked.add(number);
    return Future.value('call-1');
  }
}

class _DialButton extends ConsumerWidget {
  const _DialButton(this.number);
  final String number;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => dialNumber(context, ref, number),
        child: Text('dial $number'),
      ),
    ),
  );
}

Future<(FakePhone, _SpyEngine)> _pump(
  WidgetTester tester,
  String number, {
  bool hasDialler = true,
  ThemeData? theme,
}) async {
  usePhone(tester);
  final phone = FakePhone(hasDialler: hasDialler);
  final engine = _SpyEngine();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        phoneLauncherProvider.overrideWithValue(phone),
        callEngineProvider.overrideWithValue(engine),
        micPermissionProvider.overrideWithValue(FakeMic()),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: _DialButton(number),
      ),
    ),
  );
  return (phone, engine);
}

void main() {
  setUpAll(loadAppFonts);

  test('the dial string: the three digits, however they were written', () {
    for (final (typed, want) in [
      ('000', '000'),
      ('0000', '000'),
      ('0112', '112'),
      ('(1) 0-6', '106'),
      ('1 1 2', '112'),
      ('+61 000', '000'),
      ('+61000', '000'),
      ('61 000', '000'),
      ('+61 0 000', '000'),
      ('+61 (0) 112', '112'),
      ('0061 112', '112'),
      ('0011 61 106', '106'),
      ('0011 61 0 106', '106'),
      ('+61 00', '000'),
      ('0011 61 00', '000'),
      ('61000', '000'),
      ('610112', '112'),
      ('1831 000', '000'),
      ('1832 +61 112', '112'),
      ('#31#106', '106'),
      ('*31# 0061 000', '000'),
      ('1831 1831 000', '000'),
      ('#31#*31#112', '112'),
      ('1832 1831 +61 00', '000'),
    ]) {
      expect(emergencyDialString(typed), want, reason: typed);
    }
  });

  // WS6 on #47: the sheet only ever offers 000, 112 or 106.
  test('the dial string is never anything but 000, 112 or 106', () {
    for (final (typed, want) in [
      ('\u00851831 000', '000'),
      ('﻿1831 000', '000'),
      ('1831​112', '112'),
      (' +61 106', '106'),
      // Not an emergency number by the rule: still 000, never its digits.
      ('1831 0001', '000'),
      ('0491 570 737', '000'),
      ('', '000'),
    ]) {
      expect(emergencyDialString(typed), want, reason: typed.runes.toString());
    }
  });

  for (final n in [
    '000',
    '112',
    '106',
    '0000',
    '0112',
    '0106',
    '1 1 2',
    '(000)',
    '000.',
    '+61 000',
    '61 112',
    '0061 106',
    '0011 61 000',
    '+61 (0) 112',
    '+61 00',
    '61106',
    '1831 000',
    '#31#000',
    '*31# +61 112',
    '1831 1831 000',
    '#31#1832 +61 00',
  ]) {
    testWidgets('$n opens AppEmergency and never reaches the engine', (
      tester,
    ) async {
      final (phone, engine) = await _pump(tester, n);
      await tester.tap(find.text('dial $n'));
      await tester.pumpAndSettle();
      expect(
        find.text("Emergency calls use your phone's own network"),
        findsOneWidget,
      );
      expect(engine.asked, isEmpty);
      final dial = emergencyDialString(n);
      await tester.tap(find.text('Call $dial now'));
      await tester.pumpAndSettle();
      expect(phone.dialled, [dial]);
      expect(engine.asked, isEmpty);
      expect(
        find.text("Emergency calls use your phone's own network"),
        findsNothing,
      );
    });
  }

  testWidgets('Cancel closes it and calls nothing', (tester) async {
    final (phone, engine) = await _pump(tester, '000');
    await tester.tap(find.text('dial 000'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      find.text("Emergency calls use your phone's own network"),
      findsNothing,
    );
    expect(phone.dialled, isEmpty);
    expect(engine.asked, isEmpty);
  });

  testWidgets('no dialler on this device: says it cannot, offers no call', (
    tester,
  ) async {
    final (phone, engine) = await _pump(tester, '000', hasDialler: false);
    await tester.tap(find.text('dial 000'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining("This device can't make emergency calls"),
      findsOneWidget,
    );
    expect(find.text('Call 000 now'), findsNothing);
    expect(engine.asked, isEmpty);
  });

  for (final n in [
    '0491 570 737',
    '0006',
    '1120',
    '+61 0001',
    '0011 000',
    '61 00',
    '1833 000',
    '18310001',
    '1831 1833 000',
  ]) {
    testWidgets('$n is not an emergency number: it goes to the engine', (
      tester,
    ) async {
      final (_, engine) = await _pump(tester, n);
      await tester.tap(find.text('dial $n'));
      await tester.pumpAndSettle();
      expect(engine.asked, [n]);
      expect(
        find.text("Emergency calls use your phone's own network"),
        findsNothing,
      );
    });
  }

  testWidgets('the sheet: labelled controls, 200 % text fits', (tester) async {
    final h = tester.ensureSemantics();
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester, '000');
    await tester.tap(find.text('dial 000'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Call 000 now'), findsOneWidget);
    expect(find.bySemanticsLabel('Cancel'), findsOneWidget);
    h.dispose();
  });
}

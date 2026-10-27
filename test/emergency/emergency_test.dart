import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/emergency/emergency.dart';
import 'package:voiceplatform_app/engine/engine_provider.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/platform/phone.dart';
import 'package:voiceplatform_app/theme/app_theme.dart';

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

  test('the dial string drops a trunk 0 and punctuation', () {
    expect(emergencyDialString('000'), '000');
    expect(emergencyDialString('0000'), '000');
    expect(emergencyDialString('0112'), '112');
    expect(emergencyDialString('(1) 0-6'), '106');
    expect(emergencyDialString('1 1 2'), '112');
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

  testWidgets('any other number goes to the engine', (tester) async {
    final (_, engine) = await _pump(tester, '0491 570 737');
    await tester.tap(find.text('dial 0491 570 737'));
    await tester.pumpAndSettle();
    expect(engine.asked, ['0491 570 737']);
    expect(
      find.text("Emergency calls use your phone's own network"),
      findsNothing,
    );
  });

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

// The full-screen sheet after sign-in and the Me card (task 2): denied,
// allowed, and allowed after a trip to Settings.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/engine/full_screen_access.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

const _sheetTitle = 'Let calls show on your locked screen';
const _sheetBody =
    'Without this, a call to a locked phone shows only as a notification, '
    'and you can miss it.';
const _cardTitle = "Calls can't show on your locked screen";

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

/// Away to Settings and back: the app goes inactive, then resumes.
Future<void> _backFromSettings(WidgetTester t) async {
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await t.pump();
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await _settle(t);
}

Future<void> _openMe(WidgetTester t) async {
  await t.tap(
    find.descendant(of: find.byType(VpTabBar), matching: find.text('Me')),
  );
  await _settle(t);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('denied: the sheet after sign-in, closed by Settings', (
    tester,
  ) async {
    usePhone(tester);
    final extras = FakeExtras()..fullScreenAllowed = false;
    final mic = FakeMic();
    await tester.pumpWidget(
      await appUnderTest(
        extras: extras,
        mic: mic,
        api: FakeApi(),
        accessToken: 'tok',
      ),
    );
    await _settle(tester);
    await _settle(tester);
    expect(mic.notificationAsks, 1);
    expect(find.text(_sheetTitle), findsOneWidget);
    expect(find.text(_sheetBody), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);

    await tester.tap(find.text('Open settings'));
    expect(extras.fullScreenSettingsOpened, 1);
    // Switched on in Settings, then back: the sheet goes by itself.
    extras.fullScreenAllowed = true;
    await _backFromSettings(tester);
    expect(find.text(_sheetTitle), findsNothing);
    await _openMe(tester);
    expect(find.text(_cardTitle), findsNothing);
  });

  testWidgets('denied: "Not now" leaves the Me card until allowed', (
    tester,
  ) async {
    usePhone(tester);
    final extras = FakeExtras()..fullScreenAllowed = false;
    await tester.pumpWidget(
      await appUnderTest(extras: extras, api: FakeApi(), accessToken: 'tok'),
    );
    await _settle(tester);
    await _settle(tester);
    await tester.tap(find.text('Not now'));
    await _settle(tester);
    expect(find.text(_sheetTitle), findsNothing);

    await _openMe(tester);
    expect(find.text(_cardTitle), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    expect(extras.fullScreenSettingsOpened, 1);
    extras.fullScreenAllowed = true;
    await _backFromSettings(tester);
    expect(find.text(_cardTitle), findsNothing);

    // Taken away again in the background: the card is back.
    extras.fullScreenAllowed = false;
    await _backFromSettings(tester);
    expect(find.text(_cardTitle), findsOneWidget);
    // The sheet doesn't come back on its own.
    expect(find.text(_sheetTitle), findsNothing);
  });

  testWidgets('denied, already asked: the card but no sheet', (tester) async {
    usePhone(tester);
    final extras = FakeExtras()..fullScreenAllowed = false;
    await tester.pumpWidget(
      await appUnderTest(
        extras: extras,
        api: FakeApi(),
        accessToken: 'tok',
        prefs: {FullScreenPromptNotifier.shownKey: true},
      ),
    );
    await _settle(tester);
    await _settle(tester);
    expect(find.text(_sheetTitle), findsNothing);
    await _openMe(tester);
    expect(find.text(_cardTitle), findsOneWidget);
  });

  testWidgets('allowed: no sheet and no card', (tester) async {
    usePhone(tester);
    final extras = FakeExtras();
    await tester.pumpWidget(
      await appUnderTest(extras: extras, api: FakeApi(), accessToken: 'tok'),
    );
    await _settle(tester);
    await _settle(tester);
    expect(extras.fullScreenChecks, greaterThan(0));
    expect(find.text(_sheetTitle), findsNothing);
    await _openMe(tester);
    expect(find.text(_cardTitle), findsNothing);
  });

  testWidgets('allowed again before the sheet shows: no sheet', (tester) async {
    usePhone(tester);
    ProviderContainer? c;
    // Denied when asked after sign-in, allowed by the time the tabs would
    // show the sheet (for example back from Settings in between).
    final extras = FakeExtras()
      ..fullScreenAnswer = () => c?.read(fullScreenPromptProvider) ?? false;
    await tester.pumpWidget(
      await appUnderTest(extras: extras, api: FakeApi(), accessToken: 'tok'),
    );
    c = ProviderScope.containerOf(tester.element(find.byType(Navigator).first));
    await _settle(tester);
    await _settle(tester);
    expect(extras.fullScreenChecks, greaterThanOrEqualTo(2));
    expect(find.text(_sheetTitle), findsNothing);
    expect(c.read(fullScreenPromptProvider), isFalse);
    // Not marked as asked: a later denial can still ask.
    final prefs = c.read(sharedPreferencesProvider);
    expect(prefs.getBool(FullScreenPromptNotifier.shownKey), isNull);
  });
}

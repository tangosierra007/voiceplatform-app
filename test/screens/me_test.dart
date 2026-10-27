// AppMe, its pages, and AppSignedOut.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/auth/local_wipe.dart';
import 'package:voiceplatform_app/calls/directory.dart';
import 'package:voiceplatform_app/features/recents/media_player.dart';
import 'package:voiceplatform_app/features/recents/voicemail_actions.dart';
import 'package:voiceplatform_app/auth/session_store.dart';
import 'package:voiceplatform_app/engine/phone_extras.dart';
import 'package:voiceplatform_app/features/me/me_data.dart';
import 'package:voiceplatform_app/engine/push_handler.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/net/live_events.dart';
import 'package:voiceplatform_app/nav/routes.dart';
import 'package:voiceplatform_app/platform/device_keys.dart';
import 'package:voiceplatform_app/screens/signin/sign_in_screen.dart';
import 'package:voiceplatform_app/screens/signin/signed_out_screen.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';
import '../support/phone.dart';

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _back(WidgetTester t) async {
  ProviderScope.containerOf(t.element(find.byType(Navigator).first))
      .read(routerProvider)
      .pop();
  await _settle(t);
}

/// The page's own list, not a sideways chip row.
final _vertical = find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;

Finder _tab(String label) =>
    find.descendant(of: find.byType(VpTabBar), matching: find.text(label));

final _now = DateTime.utc(2026, 10, 27, 4, 40);

SignedOut _revoked() => SignedOut.fromJson({
  'error': 'device_revoked',
  'message': "You've been signed out",
  'revokedBy': 'Priya Shah, your admin',
  'revokedAt': DateTime.utc(2026, 10, 27, 4, 12).toIso8601String(),
  'extension': '202',
  'support': {'name': 'Demo Telco', 'phone': '+61355504000'},
});

void main() {
  setUpAll(loadAppFonts);

  Future<void> openMe(WidgetTester tester) async {
    await tester.tap(_tab('Me'));
    await _settle(tester);
  }

  testWidgets('Me as the artboard', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, appVersion: '1.0.3'),
    );
    await _settle(tester);
    await openMe(tester);
    for (final t in [
      'Ava Nguyen',
      '202 · Demo Co · Advanced',
      'Available',
      'Do not disturb',
      'Away',
      'Your desk phone shows the same status.',
      'CALLS',
      "When I don't answer",
      'Desk phone and app 15 s, then voicemail',
      'Office hours',
      'Following the schedule, open now',
      'Change',
      'Recordings',
      'Your recorded calls, last 90 days',
      'THIS PHONE',
      'Signed-in devices',
      'This Pixel 8, Windows PC',
      'Send call logs to support',
      'For the last call, no passwords included',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await tester.scrollUntilVisible(
      find.text('Version 1.0.3 · '),
      200,
      scrollable: _vertical,
    );
    expect(find.bySemanticsLabel('Open source licences'), findsOneWidget);
    expect(find.bySemanticsLabel('Sign out'), findsOneWidget);
  });

  testWidgets('Do not disturb asks until when and sends it', (tester) async {
    usePhone(tester);
    final sent = PresetStatus(StatusStatus.available);
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, statusController: sent),
    );
    await _settle(tester);
    await openMe(tester);
    await tester.tap(find.bySemanticsLabel('Do not disturb'));
    await _settle(tester);
    await tester.tap(find.text('For 1 hour'));
    await _settle(tester);
    expect(sent.sent, [StatusInputStatus.dnd]);
    expect(sent.sentUntil.single, _now.toLocal().add(const Duration(hours: 1)));
    expect(find.textContaining('Do not disturb until'), findsOneWidget);
  });

  testWidgets('Office hours Change only when granted', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest(clock: () => _now));
    await _settle(tester);
    await openMe(tester);
    expect(find.bySemanticsLabel('Change'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await _settle(tester);
    expect(find.text('Follow the schedule'), findsOneWidget);
    expect(find.text('Open until changed back'), findsOneWidget);
    expect(find.text('Closed until changed back'), findsOneWidget);
  });

  test('office hours are not even fetched without the permission', () async {
    final api = FakeApi({
      'GET /me/office-hours': (_) => [fx.officeHours('schedule')],
    });
    Future<ProviderContainer> make(bool allowed) async {
      final me = {
        ...fx.me(status: 'available'),
        'permissions': {
          'recordings': true,
          'officeHours': allowed,
          'messages': true,
          'sharedVoicemail': true,
        },
      };
      final c = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(
            Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9/app/v1'))
              ..httpClientAdapter = api,
          ),
          accessTokenProvider.overrideWith(_Token.new),
          meProvider.overrideWith((ref) async => Me.fromJson(me)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    final no = await make(false);
    expect(await no.read(officeHoursProvider.future), isNull);
    expect(api.requests, isEmpty);
    final yes = await make(true);
    expect(
      (await yes.read(officeHoursProvider.future))?.name,
      'Business hours',
    );
    expect(api.requests.single.path, '/me/office-hours');
  });

  testWidgets('pages: call settings, recordings, devices', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest(clock: () => _now));
    await _settle(tester);
    await openMe(tester);
    await tester.tap(find.text("When I don't answer"));
    await _settle(tester);
    expect(find.text('Ring my desk phone and app for'), findsOneWidget);
    expect(find.text('15 s'), findsOneWidget);
    await _back(tester);
    await tester.tap(find.text('Recordings'));
    await _settle(tester);
    expect(find.text('Jordan Price'), findsOneWidget);
    expect(find.bySemanticsLabel('Play Jordan Price'), findsOneWidget);
    await _back(tester);
    await tester.tap(find.text('Signed-in devices'));
    await _settle(tester);
    expect(find.text('Pixel 8 (this phone)'), findsOneWidget);
    expect(find.text('Windows PC'), findsOneWidget);
    // Rings for the phone and the PC; the desk phone is set by the admin.
    expect(find.byType(Switch), findsNWidgets(2));
    expect(find.text('Desk phone GRP2616'), findsOneWidget);
    // Only the PC can be signed out from here.
    expect(find.bySemanticsLabel('Sign out'), findsOneWidget);
  });

  testWidgets('battery card when Android delayed call pushes', (tester) async {
    usePhone(tester);
    final extras = FakeExtras(
      batteryStatus: const VpBatteryStatus(
        ignoringOptimizations: false,
        lateWakesLastWeek: 3,
        manufacturer: 'samsung',
      ),
    );
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, extras: extras),
    );
    await _settle(tester);
    await openMe(tester);
    expect(find.text('Calls may ring late on this phone'), findsOneWidget);
    await tester.tap(find.text('Open battery settings'));
    expect(extras.batterySettingsOpened, 1);
  });

  testWidgets('no battery card when exempt or rarely late', (tester) async {
    usePhone(tester);
    final extras = FakeExtras(
      batteryStatus: const VpBatteryStatus(
        ignoringOptimizations: false,
        lateWakesLastWeek: 1,
        manufacturer: 'samsung',
      ),
    );
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, extras: extras),
    );
    await _settle(tester);
    await openMe(tester);
    expect(find.text('Calls may ring late on this phone'), findsNothing);
  });

  testWidgets('dark mode switch and call logs', (tester) async {
    usePhone(tester);
    String? sent;
    await tester.pumpWidget(
      await appUnderTest(
        clock: () => _now,
        sendCallLogs: () async => sent = 'VP-7Q2K',
      ),
    );
    await _settle(tester);
    await openMe(tester);
    await tester.tap(find.text('Send call logs to support'));
    await _settle(tester);
    expect(sent, 'VP-7Q2K');
    expect(find.text('Sent. Quote VP-7Q2K to support.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Dark'),
      200,
      scrollable: _vertical,
    );
    await tester.tap(find.text('Dark'));
    await _settle(tester);
    expect(
      Theme.of(tester.element(find.text('Dark'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('call logs go through CallDiagnostics to the API', (
    tester,
  ) async {
    usePhone(tester);
    final api = FakeApi({
      'POST /diagnostics/call-logs': (_) => (201, {'reference': 'LOG-7F3K9Q'}),
    });
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, api: api, accessToken: 'tok'),
    );
    await _settle(tester);
    await openMe(tester);
    await tester.tap(find.text('Send call logs to support'));
    await _settle(tester);
    expect(find.text('Sent. Quote LOG-7F3K9Q to support.'), findsOneWidget);
    final r = api.requests.singleWhere(
      (r) => r.path == '/diagnostics/call-logs',
    );
    expect(r.headers['content-type'], 'application/gzip');
    expect(r.headers['Authorization'], 'Bearer tok');
  });

  testWidgets('clearing a number sends null, never an empty string', (
    tester,
  ) async {
    usePhone(tester);
    final api = FakeApi({'PATCH /me/call-settings': (r) => fx.callSettings});
    await tester.pumpWidget(await appUnderTest(clock: () => _now, api: api));
    await _settle(tester);
    await openMe(tester);
    await tester.tap(find.text("When I don't answer"));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, '0491 570 156');
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, '');
    await _settle(tester);
    await tester.ensureVisible(find.bySemanticsLabel('Save'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Save'));
    await _settle(tester);
    final body = api.requests
        .singleWhere((r) => r.path == '/me/call-settings')
        .body
        .replaceAll(' ', '');
    expect(body, contains('"followMeTo":null'));
    expect(body, contains('"forwardAlwaysTo":null'));
    expect(body, isNot(contains('""')));
  });

  testWidgets('Sign out asks first', (tester) async {
    usePhone(tester);
    final auth = ScriptedAuth(const SignedIn('d1'));
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, authController: auth),
    );
    await _settle(tester);
    await openMe(tester);
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Sign out'),
      200,
      scrollable: _vertical,
    );
    await tester.tap(find.bySemanticsLabel('Sign out'));
    await _settle(tester);
    expect(find.text('Sign out of this phone?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await _settle(tester);
    expect(auth.calls, contains('signOut'));
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  group('AppSignedOut', () {
    testWidgets('who, when, whom to ask; Sign in again', (tester) async {
      usePhone(tester);
      final auth = ScriptedAuth(SignedOutRemotely(_revoked()));
      await tester.pumpWidget(
        await appUnderTest(clock: () => _now, authController: auth),
      );
      await _settle(tester);
      expect(find.byType(SignedOutScreen), findsOneWidget);
      expect(find.byType(VpTabBar), findsNothing);
      expect(find.text("You've been signed out"), findsOneWidget);
      expect(
        find.textContaining('Priya Shah, your admin, signed this phone out at'),
        findsOneWidget,
      );
      expect(find.text('Calls to 202 still ring your desk phone'), findsOne);
      expect(
        find.text(
          'Not expecting this? Ask Priya, or call Demo Telco on 03 5550 4000.',
        ),
        findsOneWidget,
      );
      // Nowhere else opens while it shows.
      final router = ProviderScope.containerOf(
        tester.element(find.byType(Navigator).first),
      ).read(routerProvider);
      router.go(Routes.keypad);
      await _settle(tester);
      expect(find.byType(SignedOutScreen), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Sign in again'));
      await _settle(tester);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(router, isA<GoRouter>());
    });

    test('the line reads as the artboard', () {
      final now = DateTime(2026, 10, 27, 16);
      final info = SignedOut(
        error: SignedOutError.deviceRevoked,
        message: 'x',
        revokedBy: 'Priya Shah, your admin',
        revokedAt: DateTime(2026, 10, 27, 15, 12),
      );
      expect(
        signedOutLine(info, now),
        'Priya Shah, your admin, signed this phone out at 3:12 pm today. '
        'This usually happens when a phone is replaced or lost.',
      );
    });

    test('a signed_out push asks the server', () async {
      final extras = FakeExtras();
      final auth = ScriptedAuth(const SignedIn('d1'));
      final c = ProviderContainer(
        overrides: [
          phoneExtrasProvider.overrideWithValue(extras),
          authProvider.overrideWith(() => auth),
          liveEventsProvider.overrideWithValue(quietLiveEvents()),
          meProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(c.dispose);
      c.read(pushHandlerProvider);
      extras.push(VpPushType.signedOut);
      await Future<void>.delayed(Duration.zero);
      expect(auth.calls, ['onSignedOutPush']);
    });

    test('signing out clears every local store', () async {
      SharedPreferences.setMockInitialValues({
        ThemePreferenceNotifier.storageKey: 'dark',
        'contacts.permission_asked': true,
      });
      final sp = await SharedPreferences.getInstance();
      final store = MemorySessionStore()
        ..session = const StoredSession(deviceId: 'd', refreshToken: 'r');
      final keys = FakeDeviceKeys();
      final contacts = FixedPhoneContacts(const [
        PhoneContact('Kim Bell', ['03 5550 1142']),
      ]);
      final registered = <List<String>>[];
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          sessionStoreProvider.overrideWithValue(store),
          deviceKeysProvider.overrideWithValue(keys),
          phoneContactsSourceProvider.overrideWithValue(contacts),
          addressBookScrubberProvider.overrideWithValue(
            (v) => registered.add([...v]),
          ),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(phoneContactsProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(phoneContactsProvider.future);
      c.read(accessTokenProvider.notifier).set('tok');
      await c.read(authProvider.notifier).signOutLocally();
      // The contacts are read again, and their values registered with the
      // scrubber again, for whoever signs in next.
      await c.read(phoneContactsProvider.future);
      expect(contacts.reads, 2);
      expect(registered, hasLength(2));
      expect(registered.last, contains('Kim Bell'));
      expect(store.session, isNull);
      expect(keys.deletes, 1);
      expect(c.read(accessTokenProvider), isNull);
      expect(sp.getKeys(), isEmpty);
      expect(c.read(themePreferenceProvider), ThemePreference.system);
    });

    test('the crash-report outbox on disk goes too', () async {
      final dir = Directory.systemTemp.createTempSync('cache');
      addTearDown(() => dir.deleteSync(recursive: true));
      final outbox = Directory('${dir.path}/sentry/outbox')
        ..createSync(recursive: true);
      File('${outbox.path}/envelope').writeAsStringSync('x');
      File('${dir.path}/other').writeAsStringSync('kept');
      // Sentry isn't initialised here: clearing the scope must not throw.
      await clearDiagnosticsOnDevice(cacheDir: dir);
      expect(Directory('${dir.path}/sentry').existsSync(), isFalse);
      expect(File('${dir.path}/other').existsSync(), isTrue);
    });

    test('another screen taking the player resets the voicemail card', () {
      final c = ProviderContainer(
        overrides: [mediaPlayerProvider.overrideWithValue(FakeMediaPlayer())],
      );
      addTearDown(c.dispose);
      final vm = c.read(voicemailPlayerProvider.notifier);
      c.listen(voicemailPlayerProvider, (_, _) {});
      vm.debugLoad('v1');
      c.read(mediaOwnerProvider.notifier).set('voicemail:v1');
      expect(c.read(voicemailPlayerProvider).loadedId, 'v1');
      c.read(mediaOwnerProvider.notifier).set('recording:r1');
      expect(c.read(voicemailPlayerProvider).loadedId, isNull);
    });
  });
}

class _Token extends AccessTokenNotifier {
  @override
  String? build() => 'tok';
}

// Q364-1 (TJ, 22 Nov): a licence refusal still signs the phone out and the
// engine's unregister wipes the call logs (chosen on the side of privacy),
// but one short diagnostic is kept for support: the time, the refusal code
// and the app version, nothing else, for 7 days. "Send call logs to support"
// shows it and sends it.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpOverrides, gzip;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/auth/session_store.dart';
import 'package:voiceplatform_app/calls/call_actions.dart';
import 'package:voiceplatform_app/diagnostics/refusal_diagnostic.dart';
import 'package:voiceplatform_app/engine/engine_provider.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/platform/device_keys.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../../tool/mock_server/fixtures.dart';
import '../../tool/mock_server/server.dart';
import '../support/app_harness.dart';
import '../support/phone.dart';

class _SpyEngine extends FakeCallEngine {
  int unregisters = 0;

  @override
  Future<void> unregister() {
    unregisters++;
    return super.unregister();
  }
}

/// The longest run of digits in [s].
int _longestDigitRun(String s) =>
    RegExp(r'\d+')
        .allMatches(s)
        .fold(0, (m, x) => x.group(0)!.length > m ? x.group(0)!.length : m);

void main() {
  group('a refusal on refresh', () {
    late MockServer server;

    setUpAll(() async {
      HttpOverrides.global = null;
      server = await MockServer.start(port: 0);
    });
    tearDownAll(() => server.close());

    test('a refusal wipes the logs but keeps one diagnostic with time, code '
        'and version only', () async {
      SharedPreferences.setMockInitialValues({'vp.someSetting': true});
      final sp = await SharedPreferences.getInstance();
      final engine = _SpyEngine();
      final store = MemorySessionStore()
        ..session = StoredSession(
          deviceId: uid(0x6, 1),
          refreshToken: SignInFixtures.basicRefreshToken,
        );
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          sessionStoreProvider.overrideWithValue(store),
          deviceKeysProvider.overrideWithValue(FakeDeviceKeys()),
          callEngineProvider.overrideWithValue(engine),
          pushTokensProvider.overrideWithValue(null),
          micPermissionProvider.overrideWithValue(FakeMic()),
          appResumesProvider.overrideWithValue(const Stream.empty()),
          apiConfigProvider.overrideWithValue(
            ApiConfig(
              baseUrl: server.baseUri.toString(),
              platform: 'android',
              appVersion: '1.0.6',
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.read(engineSessionProvider);
      c.read(authProvider);
      for (var i = 0; i < 40 && c.read(authProvider) is! LicenceRefused; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await pumpEventQueue();

      expect(c.read(authProvider), isA<LicenceRefused>());
      expect(store.session, isNull, reason: 'signed out');
      expect(
        engine.unregisters,
        greaterThanOrEqualTo(1),
        reason: 'the unregister wipes the call logs natively, as before',
      );
      expect(sp.getBool('vp.someSetting'), isNull, reason: 'the wipe ran');

      final kept = await c.read(refusalDiagnosticsProvider).read();
      expect(kept, hasLength(1));
      expect(kept.single.code, 'licence_basic');
      expect(kept.single.appVersion, '1.0.6');
      expect(
        DateTime.now().toUtc().difference(kept.single.at).abs(),
        lessThan(const Duration(minutes: 1)),
      );

      // Exactly three fields on disk: no extension, name, token or message.
      final raw = sp.getString(RefusalDiagnosticStore.key)!;
      final onDisk = jsonDecode(raw) as List<Object?>;
      expect((onDisk.single! as Map).keys.toSet(), {
        'at',
        'code',
        'appVersion',
      });
      expect(raw, isNot(contains('204')), reason: 'the refused extension');
      expect(raw, isNot(contains('Warehouse')), reason: "the extension's name");
      expect(raw, isNot(contains('Advanced')), reason: 'the message');
    });
  });

  group('the store', () {
    late SharedPreferences sp;
    late DateTime now;
    late RefusalDiagnosticStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      sp = await SharedPreferences.getInstance();
      now = DateTime.utc(2026, 11, 23, 1, 15);
      store = RefusalDiagnosticStore(sp, () => now, '1.0.6');
    });

    test('the diagnostic is gone after 7 days', () async {
      await store.record('licence_basic');
      now = now.add(const Duration(days: 6, hours: 23));
      expect(await store.read(), hasLength(1), reason: 'under 7 days: kept');

      now = now.add(const Duration(hours: 1));
      await store.purge();
      expect(
        sp.getString(RefusalDiagnosticStore.key),
        isNull,
        reason: '7 days: deleted from the phone',
      );
      expect(await store.read(), isEmpty);
    });

    test('purged on app start and on each wake', () async {
      final resumes = StreamController<void>.broadcast();
      addTearDown(resumes.close);
      await store.record('licence_basic');
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          clockProvider.overrideWithValue(() => now),
          appResumesProvider.overrideWithValue(resumes.stream),
          apiConfigProvider.overrideWithValue(
            ApiConfig(
              baseUrl: 'http://localhost:1',
              platform: 'android',
              appVersion: '1.0.6',
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.read(refusalDiagnosticPurgeProvider);
      await pumpEventQueue();
      expect(
        sp.getString(RefusalDiagnosticStore.key),
        isNotNull,
        reason: 'start, under 7 days',
      );

      now = now.add(refusalDiagnosticMaxAge);
      resumes.add(null);
      await pumpEventQueue();
      expect(
        sp.getString(RefusalDiagnosticStore.key),
        isNull,
        reason: 'the wake after 7 days',
      );
    });

    test('a time ahead of the clock does not stretch the 7 days', () async {
      await store.record('licence_basic');
      now = now.subtract(const Duration(days: 1));
      expect(await store.read(), isEmpty);
    });

    test('a refusal loop keeps at most 5, the newest', () async {
      for (var i = 0; i < 12; i++) {
        await store.record('licence_basic');
        now = now.add(const Duration(minutes: 1));
      }
      final kept = await store.read();
      expect(kept, hasLength(refusalDiagnosticMaxRecords));
      expect(kept.last.at, now.subtract(const Duration(minutes: 1)));
    });

    test('it holds no phone number', () async {
      await store.record('licence_basic');
      // A code or version that isn't the API's shape is not kept as text.
      await store.record('call 0491570006 now');
      final s = RefusalDiagnosticStore(sp, () => now, '0491 570 006');
      await s.record('licence_basic');
      final raw = sp.getString(RefusalDiagnosticStore.key)!;
      final kept = await store.read();
      expect(kept.map((d) => d.code), [
        'licence_basic',
        'unknown',
        'licence_basic',
      ]);
      expect(kept.last.appVersion, 'unknown');
      // No digits run longer than the version string: the year (4) is the
      // longest, from the ISO time.
      expect(_longestDigitRun(raw), lessThanOrEqualTo('1.0.6'.length - 1));
      for (final d in kept) {
        expect(_longestDigitRun(d.logLine), lessThanOrEqualTo(4));
        expect(_longestDigitRun(d.shown), lessThanOrEqualTo(4));
      }
    });

    test('unreadable storage reads as none', () async {
      await sp.setString(RefusalDiagnosticStore.key, 'not json');
      expect(await store.read(), isEmpty);
    });
  });

  test('the upload carries the diagnostic lines first, then the call log', () {
    final log = Uint8List.fromList(gzip.encode(utf8.encode('call log line\n')));
    final d = RefusalDiagnostic(
      at: DateTime.utc(2026, 11, 23, 1, 15),
      code: 'licence_basic',
      appVersion: '1.0.6',
    );
    final text = utf8.decode(gzip.decode(withRefusalLines(log, [d])));
    expect(
      text,
      'licence refusal at 2026-11-23T01:15:00.000Z: code licence_basic, app 1.0.6\ncall log line\n',
    );
    // With no call logged, the diagnostic alone.
    final alone = utf8.decode(gzip.decode(withRefusalLines(Uint8List(0), [d])));
    expect(alone, '${d.logLine}\n');
  });

  testWidgets(
    'Send call logs shows the diagnostic first, sends it, then deletes it',
    (tester) async {
      usePhone(tester);
      final now = DateTime.utc(2026, 11, 23, 1, 15);
      final api = FakeApi({
        'POST /diagnostics/call-logs': (_) =>
            (201, {'reference': 'LOG-7F3K9Q'}),
      });
      final record = RefusalDiagnostic(
        at: now.subtract(const Duration(days: 1)),
        code: 'licence_basic',
        appVersion: '1.0.6',
      );
      await tester.pumpWidget(
        await appUnderTest(
          clock: () => now,
          api: api,
          accessToken: 'tok',
          prefs: {
            RefusalDiagnosticStore.key: jsonEncode([record.toJson()]),
          },
        ),
      );
      Future<void> settle() async {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      await settle();
      await tester.tap(
        find.descendant(of: find.byType(VpTabBar), matching: find.text('Me')),
      );
      await settle();

      // Cancel first: nothing leaves the phone.
      await tester.tap(find.text('Send call logs to support'));
      await settle();
      expect(find.text('Send call logs to support?'), findsOneWidget);
      expect(find.textContaining(record.shown), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle();
      expect(
        api.requests.where((r) => r.path == '/diagnostics/call-logs'),
        isEmpty,
      );

      await tester.tap(find.text('Send call logs to support'));
      await settle();
      await tester.tap(find.text('Send'));
      await settle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle();
      expect(find.text('Sent. Quote LOG-7F3K9Q to support.'), findsOneWidget);
      final r = api.requests.singleWhere(
        (r) => r.path == '/diagnostics/call-logs',
      );
      expect(r.headers['content-type'], 'application/gzip');
      final sp = await SharedPreferences.getInstance();
      expect(
        sp.getString(RefusalDiagnosticStore.key),
        isNull,
        reason: 'deleted once sent',
      );
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}

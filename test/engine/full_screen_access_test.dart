// Full-screen access (task 2): the resume re-check, the sheet once after
// sign-in, and again after a denied call at most once a day.
import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/engine/engine_provider.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/engine/full_screen_access.dart';
import 'package:voiceplatform_app/engine/phone_extras.dart';
import 'package:voiceplatform_app/calls/call_actions.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../support/call_fakes.dart';
import '../support/fake_api.dart';
import '../support/fakes.dart';

void main() {
  late FakeExtras extras;
  late FakeCallEngine engine;
  late StreamController<void> resumes;
  late SharedPreferences prefs;
  late DateTime now;

  Future<ProviderContainer> container({
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        phoneExtrasProvider.overrideWithValue(extras),
        callEngineProvider.overrideWithValue(engine),
        appResumesProvider.overrideWithValue(resumes.stream),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    extras = FakeExtras();
    engine = FakeCallEngine();
    resumes = StreamController<void>.broadcast();
    now = DateTime(2026, 11, 10, 9);
  });
  tearDown(() async {
    await resumes.close();
    await engine.dispose();
  });

  group('fullScreenAccessProvider', () {
    test('checks at once, then again on each resume', () async {
      extras.fullScreenAllowed = false;
      final c = await container();
      c.listen(fullScreenAccessProvider, (_, _) {});
      // Allowed until the engine answers, so nothing nags early.
      expect(c.read(fullScreenAccessProvider), isTrue);
      await pumpEventQueue();
      expect(c.read(fullScreenAccessProvider), isFalse);
      expect(extras.fullScreenChecks, 1);

      // Back from Settings with it on.
      extras.fullScreenAllowed = true;
      resumes.add(null);
      await pumpEventQueue();
      expect(c.read(fullScreenAccessProvider), isTrue);
      expect(extras.fullScreenChecks, 2);

      // Taken away while the app was in the background.
      extras.fullScreenAllowed = false;
      resumes.add(null);
      await pumpEventQueue();
      expect(c.read(fullScreenAccessProvider), isFalse);
    });

    test('the fake engine and other platforms count as allowed', () async {
      final c = ProviderContainer(
        overrides: [
          callEngineProvider.overrideWithValue(engine),
          appResumesProvider.overrideWithValue(resumes.stream),
        ],
      );
      addTearDown(c.dispose);
      expect(await c.read(phoneExtrasProvider).canUseFullScreen(), isTrue);
      c.listen(fullScreenAccessProvider, (_, _) {});
      await pumpEventQueue();
      expect(c.read(fullScreenAccessProvider), isTrue);
    });
  });

  group('after sign-in', () {
    test('asks once when denied, not on the next start', () async {
      extras.fullScreenAllowed = false;
      final c = await container();
      c.listen(fullScreenPromptProvider, (_, _) {});
      await c.read(fullScreenPromptProvider.notifier).afterSignIn();
      expect(c.read(fullScreenPromptProvider), isTrue);
      await c.read(fullScreenPromptProvider.notifier).shown();
      expect(c.read(fullScreenPromptProvider), isFalse);
      expect(prefs.getBool(FullScreenPromptNotifier.shownKey), isTrue);

      // The next start (a new process) keeps quiet.
      final again = await container(
        stored: {FullScreenPromptNotifier.shownKey: true},
      );
      again.listen(fullScreenPromptProvider, (_, _) {});
      await again.read(fullScreenPromptProvider.notifier).afterSignIn();
      expect(again.read(fullScreenPromptProvider), isFalse);
    });

    test('never asks when allowed', () async {
      final c = await container();
      c.listen(fullScreenPromptProvider, (_, _) {});
      await c.read(fullScreenPromptProvider.notifier).afterSignIn();
      expect(c.read(fullScreenPromptProvider), isFalse);
    });
  });

  group('after a denied call', () {
    Future<String> deniedCall() async {
      await engine.start();
      final id = engine.simulateIncoming(remoteNumber: '0491570156');
      extras.deniedCalls.add(id);
      await pumpEventQueue();
      return id;
    }

    test('asks once the call ends, then not again that day', () async {
      extras.fullScreenAllowed = false;
      final c = await container(
        stored: {FullScreenPromptNotifier.shownKey: true},
      );
      c.listen(fullScreenPromptProvider, (_, _) {});
      await pumpEventQueue();

      final id = await deniedCall();
      // Not while it rings.
      expect(c.read(fullScreenPromptProvider), isFalse);
      engine.remoteHangup(id);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isTrue);
      await c.read(fullScreenPromptProvider.notifier).shown();

      // A second denied call the same day: no sheet.
      now = DateTime(2026, 11, 10, 17);
      engine.remoteHangup(await deniedCall());
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isFalse);

      // The next day: once more.
      now = DateTime(2026, 11, 11, 8);
      engine.remoteHangup(await deniedCall());
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isTrue);
    });

    test('a call that rang on the full screen asks nothing', () async {
      final c = await container();
      c.listen(fullScreenPromptProvider, (_, _) {});
      await engine.start();
      final id = engine.simulateIncoming(remoteNumber: '0491570156');
      await pumpEventQueue();
      // Taken away during the call: this call still rang on the full screen.
      extras.fullScreenAllowed = false;
      engine.remoteHangup(id);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isFalse);
    });

    test('no report from the engine: an incoming call seen while denied '
        'counts', () async {
      // The app was swiped away: the engine's report went nowhere.
      extras.fullScreenAllowed = false;
      final c = await container(
        stored: {FullScreenPromptNotifier.shownKey: true},
      );
      c.listen(fullScreenPromptProvider, (_, _) {});
      await engine.start();
      final id = engine.simulateIncoming(remoteNumber: '0491570156');
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isFalse);
      engine.remoteHangup(id);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isTrue);
    });

    test('Flutter starting at Answer, mid-call: asks once it ends', () async {
      extras.fullScreenAllowed = false;
      await engine.start();
      final id = engine.simulateIncoming(remoteNumber: '0491570156');
      await engine.answer(id);
      // The provider only starts now, with the call already up.
      final c = await container(
        stored: {FullScreenPromptNotifier.shownKey: true},
      );
      c.listen(fullScreenPromptProvider, (_, _) {});
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isFalse);
      engine.remoteHangup(id);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isTrue);
    });

    test('waits until no call is left', () async {
      extras.fullScreenAllowed = false;
      final c = await container();
      c.listen(fullScreenPromptProvider, (_, _) {});
      await engine.start();
      final first = engine.simulateIncoming(remoteNumber: '0491570156');
      final second = engine.simulateIncoming(remoteNumber: '0255501234');
      await pumpEventQueue();
      engine.remoteHangup(first);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isFalse);
      engine.remoteHangup(second);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isTrue);
    });

    test('an outgoing call ending last still shows the waiting sheet', () async {
      // An engine that registers at once and leaves outgoing calls to the test.
      await engine.dispose();
      engine = FakeCallEngine(
        outgoing: OutgoingScript.manual,
        registerAfter: Duration.zero,
      );
      extras.fullScreenAllowed = false;
      final c = await container();
      c.listen(fullScreenPromptProvider, (_, _) {});
      final incoming = await deniedCall();
      await engine.register(
        const SipAccount(
          authUsername: 'mock-202-pixel8',
          password: 'test-password',
          domain: 'sip.demo-co.example',
          outboundProxy: 'sip:sip.voiceplatform.example:5061;transport=tls',
          displayName: 'Ava Nguyen',
          expiresSeconds: 600,
          instanceId: 'urn:uuid:60000000-0000-4000-8000-000000000001',
        ),
      );
      await pumpEventQueue();
      final outgoing = await engine.call('0255501234');
      await pumpEventQueue();
      engine.remoteHangup(incoming);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isFalse);
      engine.remoteHangup(outgoing);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isTrue);
    });

    test('allowed by the time it ends: no sheet', () async {
      extras.fullScreenAllowed = false;
      final c = await container();
      c.listen(fullScreenPromptProvider, (_, _) {});
      final id = await deniedCall();
      extras.fullScreenAllowed = true;
      engine.remoteHangup(id);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isFalse);
    });

    test('the sign-in sheet does not use up the day', () async {
      // Device tests 4 and 5: signed in at 09:00, the sheet shows.
      extras.fullScreenAllowed = false;
      final c = await container();
      c.listen(fullScreenPromptProvider, (_, _) {});
      await c.read(fullScreenPromptProvider.notifier).afterSignIn();
      expect(c.read(fullScreenPromptProvider), isTrue);
      await c.read(fullScreenPromptProvider.notifier).shown();
      expect(prefs.getString(FullScreenPromptNotifier.kindKey), 'signIn');

      // 10:00, a denied call: the sheet again.
      now = DateTime(2026, 11, 10, 10);
      engine.remoteHangup(await deniedCall());
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isTrue);
      await c.read(fullScreenPromptProvider.notifier).shown();
      expect(prefs.getString(FullScreenPromptNotifier.kindKey), 'afterCall');

      // 11:00, another: not again today.
      now = DateTime(2026, 11, 10, 11);
      engine.remoteHangup(await deniedCall());
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isFalse);

      // The next day: once more.
      now = DateTime(2026, 11, 11, 9);
      engine.remoteHangup(await deniedCall());
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isTrue);
    });
  });

  test(
    'each new sign-in checks again, notifications asked only once',
    () async {
      extras.fullScreenAllowed = false;
      final mic = FakeMic();
      final auth = _Auth(const SignedIn('d1'));
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          phoneExtrasProvider.overrideWithValue(extras),
          callEngineProvider.overrideWithValue(engine),
          appResumesProvider.overrideWithValue(resumes.stream),
          clockProvider.overrideWithValue(() => now),
          micPermissionProvider.overrideWithValue(mic),
          authProvider.overrideWith(() => auth),
          dioProvider.overrideWithValue(Dio()..httpClientAdapter = FakeApi()),
        ],
      );
      addTearDown(c.dispose);
      c.listen(fullScreenPromptProvider, (_, _) {});
      c.read(engineSessionProvider);
      c.read(accessTokenProvider.notifier).set('tok');
      await pumpEventQueue(times: 50);
      expect(c.read(fullScreenPromptProvider), isTrue);
      await c.read(fullScreenPromptProvider.notifier).shown();

      // Sign-out clears the stored flags; the same process signs in again.
      auth.set(const NotSignedIn());
      await prefs.clear();
      await pumpEventQueue(times: 50);
      auth.set(const SignedIn('d2'));
      await pumpEventQueue(times: 50);
      expect(c.read(fullScreenPromptProvider), isTrue);
      expect(mic.notificationAsks, 1);
    },
  );

  group('history on opening the app', () {
    late Future<DateTime?> Function() history;
    late int historyReads;

    Future<ProviderContainer> opened({
      required Map<String, Object> stored,
    }) async {
      SharedPreferences.setMockInitialValues(stored);
      prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          phoneExtrasProvider.overrideWithValue(extras),
          callEngineProvider.overrideWithValue(engine),
          appResumesProvider.overrideWithValue(resumes.stream),
          clockProvider.overrideWithValue(() => now),
          authProvider.overrideWith(() => ScriptedAuth(const SignedIn('d1'))),
          latestIncomingCallProvider.overrideWithValue(() {
            historyReads++;
            return history();
          }),
        ],
      );
      addTearDown(c.dispose);
      c.listen(fullScreenPromptProvider, (_, _) {});
      // The app starts: the access token arrives.
      c.read(accessTokenProvider.notifier).set('tok');
      await pumpEventQueue();
      return c;
    }

    // Shown yesterday at 10:00, once since sign-in.
    final yesterday10 = DateTime(2026, 11, 9, 10);
    Map<String, Object> shownAt(Object when) => {
      FullScreenPromptNotifier.shownKey: true,
      FullScreenPromptNotifier.dayKey: when is DateTime
          ? when.toIso8601String()
          : when,
    };

    setUp(() {
      extras.fullScreenAllowed = false;
      historyReads = 0;
      history = () async => null;
    });

    test('an incoming call before the sheet last showed: no sheet', () async {
      history = () async => DateTime(2026, 11, 9, 9, 30);
      final c = await opened(stored: shownAt(yesterday10));
      expect(historyReads, greaterThan(0));
      expect(c.read(fullScreenPromptProvider), isFalse);
    });

    test('an incoming call after it showed: the sheet', () async {
      history = () async => DateTime(2026, 11, 9, 21, 5).toUtc();
      final c = await opened(stored: shownAt(yesterday10));
      expect(c.read(fullScreenPromptProvider), isTrue);
    });

    test('checked again on each resume', () async {
      final c = await opened(stored: shownAt(yesterday10));
      expect(c.read(fullScreenPromptProvider), isFalse);
      // A call the app never saw, answered from the lock screen.
      history = () async => DateTime(2026, 11, 10, 8, 40);
      now = now.add(const Duration(minutes: 3));
      resumes.add(null);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isTrue);
    });

    test('access allowed: never a sheet', () async {
      extras.fullScreenAllowed = true;
      history = () async => DateTime(2026, 11, 10, 8, 40);
      final c = await opened(stored: shownAt(yesterday10));
      resumes.add(null);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isFalse);
      expect(historyReads, 0);
    });

    test('already shown after a call today: no sheet', () async {
      history = () async => DateTime(2026, 11, 10, 8, 40);
      final c = await opened(
        stored: {
          ...shownAt(DateTime(2026, 11, 10, 8)),
          FullScreenPromptNotifier.kindKey: 'afterCall',
        },
      );
      expect(c.read(fullScreenPromptProvider), isFalse);
      expect(historyReads, 0);
    });

    test('history fails: no sheet', () async {
      history = () async => throw Exception('offline');
      final c = await opened(stored: shownAt(yesterday10));
      expect(historyReads, greaterThan(0));
      expect(c.read(fullScreenPromptProvider), isFalse);
    });

    test('no sign-in baseline and never shown: no history read', () async {
      history = () async => DateTime(2026, 11, 10, 8, 40);
      final c = await opened(stored: {});
      expect(c.read(fullScreenPromptProvider), isFalse);
      expect(historyReads, 0);
    });

    test('a day-only value from an earlier build counts to the end of that '
        'day', () async {
      history = () async => DateTime(2026, 11, 9, 20);
      final c = await opened(stored: shownAt('2026-11-9'));
      expect(c.read(fullScreenPromptProvider), isFalse);
      history = () async => DateTime(2026, 11, 10, 7);
      now = now.add(const Duration(minutes: 3));
      resumes.add(null);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isTrue);
    });

    test('shown stores the exact moment', () async {
      final c = await opened(stored: {});
      await c.read(fullScreenPromptProvider.notifier).shown();
      expect(
        prefs.getString(FullScreenPromptNotifier.dayKey),
        now.toIso8601String(),
      );
    });

    test('history read at most once in 2 minutes', () async {
      final c = await opened(stored: shownAt(yesterday10));
      expect(historyReads, 1);
      // 30 s later: not read again.
      now = now.add(const Duration(seconds: 30));
      resumes.add(null);
      await pumpEventQueue();
      expect(historyReads, 1);
      // 3 minutes after the first read: read again, and a new call asks.
      history = () async => DateTime(2026, 11, 10, 9, 2);
      now = DateTime(2026, 11, 10, 9, 3);
      resumes.add(null);
      await pumpEventQueue();
      expect(historyReads, 2);
      expect(c.read(fullScreenPromptProvider), isTrue);
    });

    test('one history read at a time', () async {
      final held = Completer<DateTime?>();
      history = () => held.future;
      final c = await opened(stored: shownAt(yesterday10));
      expect(historyReads, 1);
      now = now.add(const Duration(minutes: 5));
      resumes.add(null);
      await pumpEventQueue();
      expect(historyReads, 1);
      held.complete(null);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isFalse);
    });

    test('allowed at sign-in, turned off later: a call after sign-in asks '
        'on the next open', () async {
      // Signed in at 09:00 with access allowed: no sheet, nothing shown.
      extras.fullScreenAllowed = true;
      final c = await opened(stored: {});
      await c.read(fullScreenPromptProvider.notifier).afterSignIn();
      expect(c.read(fullScreenPromptProvider), isFalse);
      expect(
        prefs.getString(FullScreenPromptNotifier.sinceKey),
        now.toIso8601String(),
      );
      // Turned off later; a call at 12:10 the app never saw.
      extras.fullScreenAllowed = false;
      history = () async => DateTime(2026, 11, 10, 12, 10);
      now = DateTime(2026, 11, 10, 12, 30);
      resumes.add(null);
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isTrue);
    });

    test('a call before sign-in never asks', () async {
      history = () async => DateTime(2026, 11, 10, 8, 30);
      final c = await opened(
        stored: {
          FullScreenPromptNotifier.sinceKey: DateTime(
            2026,
            11,
            10,
            8,
            45,
          ).toIso8601String(),
        },
      );
      expect(historyReads, 1);
      expect(c.read(fullScreenPromptProvider), isFalse);
    });

    test('a call after the sign-in sheet the same day: the sheet', () async {
      // The sign-in sheet at 08:00 today, a call at 08:40 the app never saw.
      history = () async => DateTime(2026, 11, 10, 8, 40);
      final c = await opened(
        stored: {
          ...shownAt(DateTime(2026, 11, 10, 8)),
          FullScreenPromptNotifier.kindKey: 'signIn',
        },
      );
      expect(c.read(fullScreenPromptProvider), isTrue);
    });
  });
}

class _Auth extends ScriptedAuth {
  _Auth(super.initial);
  void set(AuthState s) => state = s;
}

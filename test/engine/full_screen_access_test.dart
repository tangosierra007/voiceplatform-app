// Full-screen access (task 2): the resume re-check, the sheet once after
// sign-in, and again after a denied call at most once a day.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/engine/engine_provider.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/engine/full_screen_access.dart';
import 'package:voiceplatform_app/engine/phone_extras.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../support/call_fakes.dart';

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
      extras.fullScreenAllowed = false;
      final c = await container();
      c.listen(fullScreenPromptProvider, (_, _) {});
      await engine.start();
      engine.remoteHangup(engine.simulateIncoming(remoteNumber: '0491570156'));
      await pumpEventQueue();
      expect(c.read(fullScreenPromptProvider), isFalse);
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
  });
}

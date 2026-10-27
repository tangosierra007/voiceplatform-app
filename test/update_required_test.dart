// APP7 (spec 22, Minimum version): below the platform's minimum the app can't
// register or call. /config at start and any 426 open the blocking AppUpdate;
// between minimum and recommended a banner shows once a day.
import 'dart:io' show HttpOverrides;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/auth/session_store.dart';
import 'package:voiceplatform_app/auth/version.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/platform/device_keys.dart';
import 'package:voiceplatform_app/screens/signin/update_screen.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../tool/mock_server/server.dart';
import 'support/app_harness.dart';
import 'support/phone.dart';

void main() {
  late MockServer server;
  var now = DateTime.now();
  DateTime clock() => now;

  setUpAll(() async {
    await loadAppFonts();
    HttpOverrides.global = null;
    server = await MockServer.start(
      port: 0,
      now: clock,
      minimumVersion: '1.0.0',
      recommendedVersion: '1.0.2',
    );
  });
  tearDownAll(() => server.close());

  late ProviderContainer c;

  Future<ProviderContainer> make({String version = '1.0.0'}) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        sessionStoreProvider.overrideWithValue(MemorySessionStore()),
        deviceKeysProvider.overrideWithValue(FakeDeviceKeys()),
        clockProvider.overrideWithValue(clock),
        apiConfigProvider.overrideWithValue(
          ApiConfig(
            baseUrl: server.baseUri.toString(),
            platform: 'android',
            appVersion: version,
            deviceModel: 'Pixel 8',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(authProvider);
    await pumpEventQueue();
    return container;
  }

  setUp(() async {
    now = DateTime.now();
    c = await make();
  });

  group('version gate (APP7)', () {
    test('below the minimum: /config sets AppUpdate', () async {
      final old = await make(version: '0.9.0');
      await old.read(appConfigProvider.notifier).check();
      expect(old.read(updateRequiredProvider)?.minimumVersion, '1.0.0');
    });

    test('any 426 sets AppUpdate', () async {
      final old = await make(version: '0.9.0');
      await expectLater(old.read(appApiProvider).me.getMe(), throwsA(anything));
      expect(old.read(updateRequiredProvider), isNotNull);
    });

    test('between minimum and recommended: the banner, once a day', () async {
      await c.read(appConfigProvider.notifier).check();
      expect(c.read(updateRequiredProvider), isNull);
      expect(c.read(updateBannerProvider), isTrue);
      await c.read(updateBannerProvider.notifier).dismiss();
      c.invalidate(updateBannerProvider);
      expect(c.read(updateBannerProvider), isFalse);
      now = now.add(const Duration(days: 1));
      c.invalidate(updateBannerProvider);
      expect(c.read(updateBannerProvider), isTrue);
    });

    test('at or above recommended: no banner', () async {
      final current = await make(version: '1.0.2');
      await current.read(appConfigProvider.notifier).check();
      expect(current.read(updateBannerProvider), isFalse);
    });
  });

  group('AppUpdate', () {
    testWidgets(
      'blocks everything; no back; Update now opens the Play listing',
      (tester) async {
        usePhone(tester);
        final phone = FakePhone();
        await tester.pumpWidget(
          await appUnderTest(
            updateRequired: configWithMinimum('1.0.2'),
            appVersion: '1.0.1',
            phone: phone,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(UpdateScreen), findsOneWidget);
        expect(find.byType(VpTabBar), findsNothing);
        expect(find.text('Update to keep calling'), findsOneWidget);
        expect(
          find.textContaining('This version (1.0.1) can no longer'),
          findsOneWidget,
        );
        expect(
          find.text("For emergencies, use your phone's dialler."),
          findsOneWidget,
        );

        final popped = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(popped, isTrue, reason: 'the back press is taken and ignored');
        expect(find.byType(UpdateScreen), findsOneWidget);

        await tester.tap(find.text('Update now'));
        await tester.pump();
        expect(phone.opened.single, contains('id=au.com.voiceplatform.app'));
      },
    );

    testWidgets('the recommended-version banner on the tabs, until Not now', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(
          config: configWithMinimum('1.0.0', recommended: '1.0.3'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A new version of the app is ready.'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('A new version of the app is ready.'), findsNothing);
    });

    testWidgets('a banner dismissed today stays away', (tester) async {
      usePhone(tester);
      final today = DateTime.now();
      await tester.pumpWidget(
        await appUnderTest(
          config: configWithMinimum('1.0.0', recommended: '1.0.3'),
          prefs: {
            UpdateBannerNotifier.storageKey:
                '${today.year}-${today.month}-${today.day}',
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A new version of the app is ready.'), findsNothing);
    });
  });
}

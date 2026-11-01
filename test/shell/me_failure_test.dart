// `GET /me` loading or failing never drops the Messages tab: the shell keeps
// the last known tab set and badges, and Me shows its error state.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/calls/me_state.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/net/live_events.dart';
import 'package:voiceplatform_app/screens/me/me_screen.dart';
import 'package:voiceplatform_app/shell/me_failed_banner.dart';
import 'package:voiceplatform_app/shell/shell_status.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';
import '../support/phone.dart';

const _key = LastKnownShellNotifier.storageKey;
const _meError = "Your details didn't load. Pull down to try again.";

Me _me({bool messages = true, int recents = 2, int unread = 1}) {
  final j = fx.me(status: 'available');
  return Me.fromJson({
    ...j,
    'permissions': <String, Object?>{
      ...j['permissions']! as Map<String, Object?>,
      'messages': messages,
    },
    'badges': {'recents': recents, 'messages': unread},
  });
}

List<String> _tabLabels(WidgetTester tester) => [
  for (final t in AppTab.values)
    if (find
        .descendant(of: find.byType(VpTabBar), matching: find.text(t.label))
        .evaluate()
        .isNotEmpty)
      t.label,
];

const _five = ['Keypad', 'Recents', 'Contacts', 'Messages', 'Me'];
const _four = ['Keypad', 'Recents', 'Contacts', 'Me'];

Finder _tab(String label) =>
    find.descendant(of: find.byType(VpTabBar), matching: find.text(label));

void main() {
  setUpAll(loadAppFonts);

  group('shell status', () {
    Future<ProviderContainer> make(
      Future<Me?> Function() me, {
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          liveEventsProvider.overrideWithValue(quietLiveEvents()),
          // Signed in: `record` keeps nothing without a session.
          accessTokenProvider.overrideWith(() => _Token('access')),
          meProvider.overrideWith((ref) async {
            final m = await me();
            if (m != null) ref.read(lastKnownShellProvider.notifier).record(m);
            return m;
          }),
        ],
        // Riverpod's own retries are not under test here.
        retry: (_, _) => null,
      );
      addTearDown(c.dispose);
      c.listen(shellStatusProvider, (_, _) {});
      return c;
    }

    test('loading with nothing known: Messages hidden, no error', () async {
      final c = await make(() => Completer<Me?>().future);
      final s = c.read(shellStatusProvider);
      expect(s.tabsKnown, isFalse);
      expect(s.tabs, isNot(contains(AppTab.messages)));
      expect(s.meFailed, isFalse);
    });

    test('loading with a last known set: Messages already there', () async {
      final c = await make(() => Completer<Me?>().future, prefs: {_key: true});
      final s = c.read(shellStatusProvider);
      expect(s.tabsKnown, isTrue);
      expect(s.tabs, contains(AppTab.messages));
      expect(s.meFailed, isFalse);
    });

    test(
      'error with a last known set keeps Messages, flags the failure',
      () async {
        final c = await make(
          () async => throw const MeUnavailable(),
          prefs: {_key: true},
        );
        await expectLater(
          c.read(meProvider.future),
          throwsA(isA<MeUnavailable>()),
        );
        final s = c.read(shellStatusProvider);
        expect(s.tabs, contains(AppTab.messages));
        expect(s.meFailed, isTrue);
        expect(
          s.recentsBadge,
          0,
          reason: 'counts are not kept across restarts',
        );
      },
    );

    test('error with nothing known: four tabs, flags the failure', () async {
      final c = await make(() async => throw const MeUnavailable());
      await expectLater(
        c.read(meProvider.future),
        throwsA(isA<MeUnavailable>()),
      );
      final s = c.read(shellStatusProvider);
      expect(s.tabsKnown, isFalse);
      expect(s.tabs, isNot(contains(AppTab.messages)));
      expect(s.meFailed, isTrue);
    });

    test(
      'a failed refetch keeps the tabs and badges of the last answer',
      () async {
        var fail = false;
        final c = await make(() async {
          if (fail) throw const MeUnavailable();
          return _me(recents: 3, unread: 4);
        });
        await c.read(meProvider.future);
        fail = true;
        c.invalidate(meProvider);
        await expectLater(c.read(meProvider.future), throwsA(anything));
        final s = c.read(shellStatusProvider);
        expect(s.tabs, contains(AppTab.messages));
        expect((s.recentsBadge, s.messagesBadge), (3, 4));
        expect(s.meFailed, isFalse, reason: 'an answer is still held');
      },
    );

    test('messages: false hides the tab and is remembered', () async {
      final c = await make(
        () async => _me(messages: false),
        prefs: {_key: true},
      );
      await c.read(meProvider.future);
      expect(c.read(shellStatusProvider).tabs, _fourTabs);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool(_key), isFalse);
    });

    test(
      'the tab set survives a restart; nothing personal is stored',
      () async {
        final c = await make(() async => _me());
        await c.read(meProvider.future);
        final sp = await SharedPreferences.getInstance();
        expect(sp.getKeys(), {_key});
        expect(sp.getBool(_key), isTrue);

        // A second run of the app, offline.
        final again = await make(
          () async => throw const MeUnavailable(),
          prefs: {_key: true},
        );
        await expectLater(again.read(meProvider.future), throwsA(anything));
        expect(again.read(shellStatusProvider).tabs, contains(AppTab.messages));
      },
    );

    test('the Messages route needs an SMS line, known or last known', () {
      expect(const ShellStatus(hasSmsLine: true).allowsMessages, isTrue);
      expect(const ShellStatus().allowsMessages, isFalse);
      // Nothing known, still loading.
      expect(const ShellStatus(tabsKnown: false).allowsMessages, isFalse);
    });

    test('nothing known and /me failed: Messages refused', () async {
      final c = await make(() async => throw const MeUnavailable());
      await expectLater(c.read(meProvider.future), throwsA(anything));
      final s = c.read(shellStatusProvider);
      expect((s.tabsKnown, s.meFailed), (false, true));
      expect(s.allowsMessages, isFalse);
    });

    test('record keeps nothing without an access token', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(c.dispose);
      c.read(lastKnownShellProvider.notifier).record(_me());
      expect(c.read(lastKnownShellProvider).hasSmsLine, isNull);
      expect(sp.getKeys(), isEmpty);
    });
  });

  group('meProvider', () {
    ProviderContainer make(AuthState auth, {String? token}) {
      final c = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => ScriptedAuth(auth)),
          if (token != null)
            accessTokenProvider.overrideWith(() => _Token(token)),
          dioProvider.overrideWithValue(
            Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9/app/v1'))
              ..httpClientAdapter = FakeApi(),
          ),
        ],
        retry: (_, _) => null,
      );
      addTearDown(c.dispose);
      return c;
    }

    test('not signed in: null, not an error', () async {
      final c = make(const NotSignedIn());
      expect(await c.read(meProvider.future), isNull);
    });

    test('signed in, the refresh fails: MeUnavailable, not null', () async {
      final auth = ScriptedAuth(const SignedIn('d1'));
      final c = ProviderContainer(
        overrides: [authProvider.overrideWith(() => auth)],
        retry: (_, _) => null,
      );
      addTearDown(c.dispose);
      await expectLater(
        c.read(meProvider.future),
        throwsA(isA<MeUnavailable>()),
      );
      expect(auth.calls, ['refresh']);
    });

    test('signed in with a token, /me fails: the error, not null', () async {
      final c = make(const SignedIn('d1'), token: 'access');
      await expectLater(
        c.read(meProvider.future),
        throwsA(isA<DioException>()),
      );
    });

    test('signed in with a token, /me answers: recorded and stored', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final api = FakeApi({
        'GET /me': (_) => _me(messages: true, recents: 3, unread: 4).toJson(),
      });
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          authProvider.overrideWith(() => ScriptedAuth(const SignedIn('d1'))),
          accessTokenProvider.overrideWith(() => _Token('access')),
          dioProvider.overrideWithValue(
            Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9/app/v1'))
              ..httpClientAdapter = api,
          ),
        ],
        retry: (_, _) => null,
      );
      addTearDown(c.dispose);
      final me = await c.read(meProvider.future);
      expect(me!.name, 'Ava Nguyen');
      expect(api.requests.map((r) => '$r'), ['GET /me']);
      final known = c.read(lastKnownShellProvider);
      expect(known.hasSmsLine, isTrue);
      expect((known.badges!.recents, known.badges!.messages), (3, 4));
      expect(sp.getBool(LastKnownShellNotifier.storageKey), isTrue);
    });
  });

  group('the app', () {
    testWidgets('cold start offline with a last known set: five tabs, the '
        'offline banner, Me in its error state', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(
          status: null,
          offline: true,
          prefs: {_key: true},
          me: () async => throw const MeUnavailable(),
        ),
      );
      await tester.pumpAndSettle();
      expect(_tabLabels(tester), _five);
      expect(
        find.textContaining('No internet on this phone', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(_tab('Me'));
      await tester.pumpAndSettle();
      expect(find.byType(MeScreen), findsOneWidget);
      expect(find.text(_meError), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Sign out'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(MeScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Sign out'), findsOneWidget, reason: 'still reachable');
      expect(_tabLabels(tester), _five);
    });

    testWidgets('error with nothing known: four tabs and the error state', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(
          status: null,
          me: () async => throw const MeUnavailable(),
        ),
      );
      await tester.pumpAndSettle();
      expect(_tabLabels(tester), _four);
      await tester.tap(_tab('Me'));
      await tester.pumpAndSettle();
      expect(find.text(_meError), findsOneWidget);
    });

    testWidgets('fresh install, /me unreachable (the A53 case): the banner on '
        'every tab says tabs may be missing; Try again recovers', (
      tester,
    ) async {
      usePhone(tester);
      final handle = tester.ensureSemantics();
      var asked = 0;
      await tester.pumpWidget(
        await appUnderTest(
          status: null,
          me: () async {
            asked++;
            if (asked == 1) throw const MeUnavailable();
            return _me();
          },
        ),
      );
      await tester.pumpAndSettle();
      final banner = find.text(
        '${MeFailedBanner.title}\n${MeFailedBanner.unknownTabs}',
        findRichText: true,
      );
      for (final t in ['Keypad', 'Recents', 'Contacts', 'Me']) {
        await tester.tap(_tab(t));
        await tester.pumpAndSettle();
        expect(banner, findsOneWidget, reason: t);
      }
      expect(
        tester.getSemantics(find.bySemanticsLabel('Try again')),
        matchesSemantics(
          label: 'Try again',
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(asked, 2);
      expect(find.byType(MeFailedBanner), findsNothing);
      expect(_tabLabels(tester), _five);
    });

    testWidgets('offline: Keypad keeps AppOffline\'s banner alone; the other '
        'tabs show the /me banner', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(
          status: null,
          offline: true,
          prefs: {_key: true},
          me: () async => throw const MeUnavailable(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MeFailedBanner), findsNothing);
      await tester.tap(_tab('Recents'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '${MeFailedBanner.title}\n${MeFailedBanner.knownTabs}',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    for (final size in const [
      Size(390, 844),
      Size(360, 800),
      Size(412, 915),
      Size(368, 904),
    ]) {
      testWidgets('the banner at 200% text stays inside its box, '
          '${size.width.toInt()} x ${size.height.toInt()}', (tester) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          await appUnderTest(
            status: null,
            me: () async => throw const MeUnavailable(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MeFailedBanner), findsOneWidget);
        expect(tester.takeException(), isNull);
        final box = tester.getRect(find.byType(MeFailedBanner));
        expect(box.right, lessThanOrEqualTo(size.width));
      });
    }

    testWidgets('still loading with a last known set: Messages never flashes '
        'out, then the answer leaves it in place', (tester) async {
      usePhone(tester);
      final answer = Completer<Me?>();
      await tester.pumpWidget(
        await appUnderTest(
          status: null,
          prefs: {_key: true},
          me: () => answer.future,
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(_tabLabels(tester), _five);
      }
      expect(find.text(_meError), findsNothing);
      answer.complete(_me());
      await tester.pumpAndSettle();
      expect(_tabLabels(tester), _five);
      expect(_tab('2'), findsOneWidget, reason: 'the Recents badge');
    });

    testWidgets('messages: false from /me drops the tab', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(
          status: null,
          prefs: {_key: true},
          me: () async => _me(messages: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(_tabLabels(tester), _four);
    });

    testWidgets('back in the foreground after a failed /me asks again', (
      tester,
    ) async {
      usePhone(tester);
      var asked = 0;
      await tester.pumpWidget(
        await appUnderTest(
          status: null,
          me: () async {
            asked++;
            if (asked == 1) throw const MeUnavailable();
            return _me();
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MeFailedBanner), findsOneWidget);
      background(tester);
      await tester.pump();
      expect(asked, 1, reason: 'not while in the background');
      foreground(tester);
      await tester.pumpAndSettle();
      expect(asked, 2);
      expect(find.byType(MeFailedBanner), findsNothing);
      expect(_tabLabels(tester), _five);

      // Resumed again with /me fine: no extra request.
      background(tester);
      foreground(tester);
      await tester.pumpAndSettle();
      expect(asked, 2);
    });

    testWidgets('back online after a failed /me asks again', (tester) async {
      usePhone(tester);
      var asked = 0;
      await tester.pumpWidget(
        await appUnderTest(
          status: null,
          offline: true,
          prefs: {_key: true},
          me: () async {
            asked++;
            if (asked == 1) throw const MeUnavailable();
            return _me();
          },
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(VpTabBar)),
      );
      // Riverpod may retry on its own; count from here.
      final before = asked;
      container.read(offlineProvider.notifier).set(false);
      await tester.pumpAndSettle();
      expect(asked, greaterThan(before));
      expect(container.read(shellStatusProvider).meFailed, isFalse);
      expect(_tabLabels(tester), _five);
    });

    testWidgets('Me: pull down asks /me again', (tester) async {
      usePhone(tester);
      var asked = 0;
      await tester.pumpWidget(
        await appUnderTest(
          status: null,
          prefs: {_key: true},
          me: () async {
            asked++;
            if (asked == 1) throw const MeUnavailable();
            return _me();
          },
          theme: ThemePreference.light,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_tab('Me'));
      await tester.pumpAndSettle();
      expect(find.text(_meError), findsOneWidget);
      await tester.fling(find.text(_meError), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(asked, 2);
      expect(find.text(_meError), findsNothing);
      expect(find.text('Ava Nguyen'), findsOneWidget);
    });
  });
}

/// Every step, as Android goes to the background and back.
void background(WidgetTester tester) {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void foreground(WidgetTester tester) {
  for (final s in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

const _fourTabs = [AppTab.keypad, AppTab.recents, AppTab.contacts, AppTab.me];

class _Token extends AccessTokenNotifier {
  _Token(this.token);
  final String token;

  @override
  String? build() => token;
}

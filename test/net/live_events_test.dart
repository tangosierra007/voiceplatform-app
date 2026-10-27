import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/net/events.dart';
import 'package:voiceplatform_app/net/live_events.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

/// A scripted server: each connect() hands out a new controller the test drives.
class FakeServer {
  final streams = <StreamController<ServerEvent>>[];
  final polls = <String?>[];
  int refreshes = 0;
  bool presenceChanged = true;

  StreamController<ServerEvent> get last => streams.last;
  int get connects => streams.length;
  int get open => streams.where((s) => s.hasListener).length;

  LiveEvents build() => LiveEvents(
    connect: () {
      final c = StreamController<ServerEvent>();
      streams.add(c);
      return c.stream;
    },
    poll: (etag) async {
      polls.add(etag);
      return presenceChanged
          ? (
              items: [
                {'extension': '206', 'presence': 'available'},
              ],
              etag: '"e${polls.length}"',
            )
          : (items: null, etag: etag);
    },
    refreshToken: () async => refreshes++,
  );
}

const _snapshot = ServerEvent('presence.snapshot', {'items': []});

void main() {
  test('foreground opens the stream, background closes it', () {
    fakeAsync((async) {
      final s = FakeServer();
      final live = s.build();
      final got = <String>[];
      live.events.listen((e) => got.add(e.type));
      live.resume();
      expect(s.connects, 1);
      expect(s.open, 1);
      s.last.add(_snapshot);
      s.last.add(
        const ServerEvent('presence', {
          'extension': '206',
          'presence': 'on_call',
        }),
      );
      async.flushMicrotasks();
      expect(got, ['presence.snapshot', 'presence']);

      live.pause();
      async.flushMicrotasks();
      expect(s.open, 0);
      expect(live.isStreamOpen, isFalse);
      async.elapse(const Duration(minutes: 10));
      expect(s.connects, 1, reason: 'nothing reconnects in the background');

      live.resume();
      expect(s.connects, 2);
      live.dispose();
    });
  });

  test('reauth refreshes the token and reopens at once, not as a failure', () {
    fakeAsync((async) {
      final s = FakeServer();
      final live = s.build()..resume();
      s.last.add(_snapshot);
      s.last.add(const ServerEvent('reauth', {}));
      async.flushMicrotasks();
      expect(s.refreshes, 1);
      expect(s.connects, 2);
      expect(s.streams.first.hasListener, isFalse);
      expect(live.consecutiveFailures, 0);
      live.dispose();
    });
  });

  test(
    'reconnects with backoff 1 s, 2 s, then falls back after three failures',
    () {
      fakeAsync((async) {
        final s = FakeServer();
        final live = s.build()..resume();
        s.last.addError(Exception('refused'));
        async.flushMicrotasks();
        expect(live.consecutiveFailures, 1);
        async.elapse(const Duration(milliseconds: 999));
        expect(s.connects, 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(s.connects, 2);

        s.last.close(); // closed by the server counts as a failure too
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1999));
        expect(s.connects, 2);
        async.elapse(const Duration(milliseconds: 1));
        expect(s.connects, 3);

        s.last.addError(Exception('refused'));
        async.flushMicrotasks();
        expect(live.inFallback, isTrue);
        live.dispose();
      });
    },
  );

  test('a stream that delivers resets the failure count', () {
    fakeAsync((async) {
      final s = FakeServer();
      final live = s.build()..resume();
      s.last.addError(Exception('x'));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      s.last.addError(Exception('x'));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      s.last.add(_snapshot);
      async.flushMicrotasks();
      expect(live.consecutiveFailures, 0);
      s.last.addError(Exception('x'));
      async.flushMicrotasks();
      expect(live.inFallback, isFalse);
      expect(live.consecutiveFailures, 1);
      live.dispose();
    });
  });

  group('fallback', () {
    LiveEvents failThrice(FakeServer s, FakeAsync async) {
      final live = s.build()..resume();
      for (var i = 0; i < 3; i++) {
        s.last.addError(Exception('down'));
        async.flushMicrotasks();
        if (i < 2) async.elapse(LiveEvents.backoff(i + 1));
      }
      expect(live.inFallback, isTrue);
      return live;
    }

    test('polls /presence every 30 s with the ETag only while Contacts or Transfer is open', () {
      fakeAsync((async) {
        final s = FakeServer();
        final got = <ServerEvent>[];
        final live = failThrice(s, async);
        live.events.listen(got.add);
        async.elapse(const Duration(seconds: 60));
        expect(s.polls, isEmpty, reason: 'not on Contacts or Transfer');

        live.presenceVisible = true;
        async.flushMicrotasks();
        expect(s.polls, [null]);
        expect(got.single.type, 'presence.snapshot');
        expect(got.single.data['items'], isNotEmpty);

        s.presenceChanged = false;
        async.elapse(const Duration(seconds: 30));
        expect(s.polls, [null, '"e1"']);
        expect(got, hasLength(1), reason: '304 sends nothing');
        async.elapse(const Duration(seconds: 30));
        expect(s.polls, hasLength(3));

        live.presenceVisible = false;
        async.elapse(const Duration(seconds: 90));
        expect(s.polls, hasLength(3));
        live.dispose();
      });
    });

    test(
      'retries the stream every 2 minutes; the first event ends the fallback',
      () {
        fakeAsync((async) {
          final s = FakeServer();
          final live = failThrice(s, async);
          live.presenceVisible = true;
          async.flushMicrotasks();
          expect(s.connects, 3);
          async.elapse(const Duration(seconds: 119));
          expect(s.connects, 3);
          async.elapse(const Duration(seconds: 1));
          expect(s.connects, 4);

          s.last.addError(Exception('still down'));
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 2));
          expect(s.connects, 5);
          expect(live.isPolling, isTrue);

          s.last.add(_snapshot);
          async.flushMicrotasks();
          expect(live.inFallback, isFalse);
          expect(live.isPolling, isFalse);
          final polls = s.polls.length;
          async.elapse(const Duration(minutes: 5));
          expect(s.polls.length, polls);
          expect(s.connects, 5);
          live.dispose();
        });
      },
    );

    test('background stops polling and retries', () {
      fakeAsync((async) {
        final s = FakeServer();
        final live = failThrice(s, async);
        live.presenceVisible = true;
        async.flushMicrotasks();
        live.pause();
        final polls = s.polls.length;
        async.elapse(const Duration(minutes: 10));
        expect(s.polls.length, polls);
        expect(s.connects, 3);
        live.dispose();
      });
    });
  });

  group('app lifecycle', () {
    setUpAll(loadAppFonts);

    testWidgets('paused closes the stream, resumed reopens it', (tester) async {
      usePhone(tester);
      final s = FakeServer();
      final live = s.build();
      await tester.pumpWidget(await appUnderTest(live: live));
      await tester.pumpAndSettle();
      expect(live.isRunning, isTrue);
      expect(s.connects, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(live.isRunning, isFalse);
      expect(s.open, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(live.isRunning, isTrue);
      expect(s.connects, 2);
      live.pause();
    });

    testWidgets('Contacts turns presence polling on, other tabs off', (
      tester,
    ) async {
      usePhone(tester);
      final live = quietLiveEvents();
      await tester.pumpWidget(await appUnderTest(live: live));
      await tester.pumpAndSettle();
      expect(live.presenceVisible, isFalse);
      await tester.tap(
        find.descendant(
          of: find.byType(VpTabBar),
          matching: find.text('Contacts'),
        ),
      );
      await tester.pumpAndSettle();
      expect(live.presenceVisible, isTrue);
      await tester.tap(
        find.descendant(of: find.byType(VpTabBar), matching: find.text('Me')),
      );
      await tester.pumpAndSettle();
      expect(live.presenceVisible, isFalse);
      live.pause();
    });
  });
}

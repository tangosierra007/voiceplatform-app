// The generated client against the mock server: every GET parses into the
// contract's models (so the fixtures keep to the contract), the interceptor
// sends X-VP-App and the bearer, and /events streams presence.
import 'dart:async';
import 'dart:io' show HttpOverrides;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/features/me/me_data.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/net/events.dart';
import 'package:voiceplatform_app/net/live_events.dart';

import '../../tool/mock_server/fixtures.dart';
import '../../tool/mock_server/server.dart';

void main() {
  late MockServer server;
  late AppApi api;
  late Dio dio;
  String? token = 'mock-access-token';

  setUpAll(() async {
    // flutter_test stubs HttpClient for widget tests; this test talks to a real
    // local socket.
    HttpOverrides.global = null;
    server = await MockServer.start(
      port: 0,
      presenceEvery: const Duration(milliseconds: 100),
    );
  });

  tearDownAll(() => server.close());

  setUp(() {
    token = 'mock-access-token';
    dio = buildDio(
      ApiConfig(
        baseUrl: server.baseUri.toString(),
        platform: 'android',
        appVersion: '1.0.0',
      ),
      accessToken: () => token,
    );
    api = AppApi(dio);
  });

  group('headers', () {
    test('X-VP-App and Authorization go on every request', () async {
      final seen = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            seen.add(o);
            h.next(o);
          },
        ),
      );
      await api.me.getMe();
      expect(seen.single.headers['X-VP-App'], 'android/1.0.0');
      expect(seen.single.headers['Authorization'], 'Bearer mock-access-token');
    });

    test('no token: no Authorization, and the mock answers 401', () async {
      token = null;
      await expectLater(
        api.me.getMe(),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            401,
          ),
        ),
      );
      final config = await api.signin.getConfig(platform: Platform.android);
      expect(config.minimumVersion, '1.0.0');
    });

    test('without X-VP-App the mock refuses', () async {
      final raw = Dio(BaseOptions(baseUrl: server.baseUri.toString()));
      await expectLater(
        raw.get<Object?>('/config', queryParameters: {'platform': 'android'}),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            400,
          ),
        ),
      );
    });

    test(
      'below the minimum version: 426 update_required with the config',
      () async {
        final old = AppApi(
          buildDio(
            ApiConfig(
              baseUrl: server.baseUri.toString(),
              platform: 'android',
              appVersion: '0.9.0',
            ),
            accessToken: () => 'x',
          ),
        );
        try {
          await old.me.getMe();
          fail('expected 426');
        } on DioException catch (e) {
          expect(e.response?.statusCode, 426);
          final cfg = AppConfig.fromJson(
            e.response!.data as Map<String, Object?>,
          );
          expect(cfg.minimumVersion, '1.0.0');
        }
      },
    );
  });

  group('fixtures parse into the contract models', () {
    test('me', () async {
      final me = await api.me.getMe();
      expect(me.name, 'Ava Nguyen');
      expect(me.extensionValue, '202');
      expect(me.tenantName, 'Demo Co');
      expect(me.badges!.recents, 2);
      expect(me.badges!.messages, 1);
      expect(me.permissions.messages, isTrue);
      expect(me.support.name, 'Demo Telco');
    });

    test('calls, settings, office hours, devices', () async {
      final ids = await api.calls.getMeCallerIds();
      expect(ids.first.label, 'Main 03 5550 1200');
      expect(ids.first.isDefault, isTrue);
      expect(ids.last.value, 'withheld');
      final cs = await api.me.getMeCallSettings();
      expect(cs.ringSeconds, 15);
      final oh = await api.me.getMeOfficeHours();
      expect(oh.single.summary, 'Following the schedule, open now');
      final devs = await api.device.getMeDevices();
      expect(devs.map((d) => d.label), [
        'Pixel 8',
        'Windows PC',
        'Desk phone GRP2616',
      ]);
      final sip = await api.device.postDevicesMeSipCredentials();
      expect(sip.domain, 'sip.demo-co.example');
      expect(sip.instanceId, 'urn:uuid:${uid(0x6, 1)}');
    });

    test('directory', () async {
      final c = await api.directory.getDirectoryColleagues();
      expect(c.total, 22);
      // Counted from presence: Mia and Priya available, Tom on mobile.
      expect(c.freeNow, 3);
      expect(
        c.items.firstWhere((x) => x.extensionValue == '201').name,
        'Reception',
      );
      expect(c.items.map((x) => x.name).first, 'Ava Nguyen');
      expect(
        c.items
            .firstWhere((x) => x.extensionValue == '301')
            .presence
            .presence
            .json,
        'mobile_only',
      );
      final teams = await api.directory.getDirectoryTeams();
      expect(teams.first.name, 'Sales');
      final shared = await api.directory.getDirectorySharedContacts(
        q: 'harbour',
      );
      expect(shared.single.name, 'Jordan Price');
      final p = await api.directory.getPresence();
      expect(p, hasLength(colleagues.length));
    });

    test('history adds up: Missed 2, Voicemail 2', () async {
      final all = await api.history.getHistory();
      expect(all.items, hasLength(7));
      expect(all.counts.missed, 2);
      expect(all.counts.voicemail, 2);
      expect(all.items.first.name, 'Westgate Supplies');
      expect(all.items[2].answeredBy, 'Mia on her desk phone');
      final missed = await api.history.getHistory(filter: HistoryFilter.missed);
      expect(missed.items, hasLength(2));
      final page = await api.history.getHistory(limit: 3);
      expect(page.items, hasLength(3));
      expect(page.nextBefore, '3');
    });

    test('voicemail: Sales 1 and Rentals 1 new', () async {
      final boxes = await api.voicemail.getVoicemailBoxes();
      expect(
        {for (final b in boxes) b.name: b.newCount},
        {'Mine': 0, 'Sales': 1, 'Rentals': 1},
      );
      final msgs = await api.voicemail.getVoicemailMessages();
      expect(msgs.items, hasLength(4));
      expect(msgs.items.where((m) => !m.heard), hasLength(2));
      final url = await api.voicemail.postVoicemailMessagesIdMediaUrl(
        id: msgs.items.first.id,
      );
      expect(url.url, startsWith('/app/v1/media/'));
      expect((await api.voicemail.getVoicemailGreetings()), hasLength(3));
      expect((await api.recordings.getRecordings()).items, hasLength(2));
    });

    test('messages: two lines, unread 1, the Olivia Chen thread', () async {
      final lines = await api.messages.getMessagesLines();
      expect(lines.map((l) => l.label), ['Sales mobile', 'Service mobile']);
      final threads = await api.messages.getMessagesThreads();
      expect(threads.unreadTotal, 1);
      expect(threads.items.first.name, 'Olivia Chen');
      final sales = await api.messages.getMessagesThreads(lineId: salesLineId);
      expect(sales.items, hasLength(2));
      final msgs = await api.messages.getMessagesThreadsIdMessages(
        id: threads.items.first.id,
      );
      expect(msgs.items.first.senderName, 'Ava');
      expect(msgs.items.last.text, 'Perfect, can you email it to me as well?');
    });

    test('sign-in by code; Basic refused; revoked refresh', () async {
      token = null;
      final req = await api.signin.postAuthEmailRequests(
        body: const EmailRequestInput(
          email: SignInFixtures.advancedEmail,
          requestSecret: 'secret-1',
          device: DeviceInfo(
            platform: Platform.android,
            model: 'Pixel 8',
            appVersion: '1.0.0',
          ),
        ),
      );
      expect(req.expiresInSeconds, 600);
      final session = await api.signin.postAuthEmailRequestsRequestIdComplete(
        requestId: req.requestId,
        body: const CompleteInput(
          requestSecret: 'secret-1',
          code: SignInFixtures.code,
          devicePublicKey: 'spki',
          device: DeviceInfo(
            platform: Platform.android,
            model: 'Pixel 8',
            appVersion: '1.0.0',
          ),
        ),
      );
      expect(session.me.name, 'Ava Nguyen');

      final basic = await api.signin.postAuthEmailRequests(
        body: const EmailRequestInput(
          email: SignInFixtures.basicEmail,
          requestSecret: 'secret-2',
          device: DeviceInfo(
            platform: Platform.android,
            model: 'Pixel 8',
            appVersion: '1.0.0',
          ),
        ),
      );
      try {
        await api.signin.postAuthEmailRequestsRequestIdComplete(
          requestId: basic.requestId,
          body: const CompleteInput(
            requestSecret: 'secret-2',
            code: SignInFixtures.code,
            devicePublicKey: 'spki',
            device: DeviceInfo(
              platform: Platform.android,
              model: 'Pixel 8',
              appVersion: '1.0.0',
            ),
          ),
        );
        fail('expected 403');
      } on DioException catch (e) {
        final r = LicenceRefusal.fromJson(
          e.response!.data as Map<String, Object?>,
        );
        expect(r.extensionValue, '204');
        expect(r.extensionName, 'Warehouse');
      }

      try {
        await api.signin.postAuthRefresh(
          body: RefreshInput(
            deviceId: uid(0x6, 1),
            refreshToken: SignInFixtures.revokedRefreshToken,
            timestamp: DateTime.utc(2026, 10, 27),
            signature: 'sig',
          ),
        );
        fail('expected 401');
      } on DioException catch (e) {
        final s = SignedOut.fromJson(e.response!.data as Map<String, Object?>);
        expect(s.revokedBy, 'Priya Shah, your admin');
      }
    });
  });

  test('/events: snapshot, badges, then presence changes', () async {
    final events = <ServerEvent>[];
    final cancel = CancelToken();
    final done = Completer<void>();
    final sub = openEvents(dio, cancelToken: cancel).listen((e) {
      events.add(e);
      if (events.where((x) => x.type == 'presence').length >= 2 &&
          !done.isCompleted) {
        done.complete();
      }
    }, onError: (_) {});
    await done.future.timeout(const Duration(seconds: 5));
    cancel.cancel();
    await sub.cancel();

    expect(events[0].type, 'presence.snapshot');
    final items = (events[0].data['items'] as List)
        .cast<Map<String, Object?>>();
    expect(
      items.map((i) => PresenceEntry.fromJson(i).extensionValue),
      contains('206'),
    );
    expect(events[1].type, 'badges');
    expect(events[1].data, {'recents': 2, 'messages': 1});
    final p = PresenceEntry.fromJson(
      events.firstWhere((e) => e.type == 'presence').data,
    );
    expect(p.extensionValue, presenceScript.first['extension']);
    expect(p.presence.json, presenceScript.first['presence']);
  });

  test('status change shows on presence', () async {
    await api.me.putMeStatus(
      body: const StatusInput(status: StatusInputStatus.dnd),
    );
    final p = await api.directory.getPresence();
    expect(p.firstWhere((x) => x.extensionValue == '202').presence.json, 'dnd');
    await api.me.putMeStatus(
      body: const StatusInput(status: StatusInputStatus.available),
    );
  });

  test(
    'pollPresence keeps the ETag; unchanged answers 304 with no items',
    () async {
      final first = await pollPresence(dio, null);
      expect(first.items, hasLength(colleagues.length));
      expect(first.etag, isNotNull);
      final again = await pollPresence(dio, first.etag);
      expect(again.items, isNull);
      expect(again.etag, first.etag);
    },
  );

  test('connectEvents through LiveEvents against the mock', () async {
    final live = LiveEvents(
      connect: () => connectEvents(dio),
      poll: (etag) => pollPresence(dio, etag),
    );
    final first = live.events.first;
    live.resume();
    final e = await first.timeout(const Duration(seconds: 5));
    expect(e.type, 'presence.snapshot');
    expect(live.consecutiveFailures, 0);
    await live.dispose();
  });

  group('optional fields (zod: missing is fine, null is refused)', () {
    test('the generated client leaves absent fields out', () {
      final body = const CompleteInput(
        requestSecret: 's',
        code: '123456',
        devicePublicKey: 'k',
        device: DeviceInfo(
          platform: Platform.android,
          model: 'Pixel 8',
          appVersion: '1.0.0',
        ),
      ).toJson();
      expect(body.containsKey('linkToken'), isFalse);
      expect((body['device']! as Map).containsKey('osVersion'), isFalse);
      expect(body.values, isNot(contains(isNull)));
    });

    test('the mock refuses a null optional field with 400', () async {
      final raw = Dio(BaseOptions(baseUrl: server.baseUri.toString()));
      try {
        await raw.post<Object?>(
          '/auth/email-requests',
          options: Options(headers: {'X-VP-App': 'android/1.0.0'}),
          data: {
            'email': SignInFixtures.advancedEmail,
            'requestSecret': 's',
            'device': {
              'platform': 'android',
              'model': 'Pixel 8',
              'appVersion': '1.0.0',
              'osVersion': null,
            },
          },
        );
        fail('expected 400');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 400);
        expect('${e.response?.data}', contains('device.osVersion'));
      }
    });

    test(
      'a full sign-in through the generated client passes the mock',
      () async {
        token = null;
        final req = await api.signin.postAuthEmailRequests(
          body: const EmailRequestInput(
            email: SignInFixtures.advancedEmail,
            requestSecret: 'secret-n',
            device: DeviceInfo(
              platform: Platform.android,
              model: 'Pixel 8',
              appVersion: '1.0.0',
            ),
          ),
        );
        final s = await api.signin.postAuthEmailRequestsRequestIdComplete(
          requestId: req.requestId,
          body: const CompleteInput(
            requestSecret: 'secret-n',
            code: SignInFixtures.code,
            devicePublicKey: 'spki',
            device: DeviceInfo(
              platform: Platform.android,
              model: 'Pixel 8',
              appVersion: '1.0.0',
            ),
          ),
        );
        expect(s.me.name, 'Ava Nguyen');
      },
    );
  });

  group('call settings', () {
    test('null clears a number; an empty string is refused', () async {
      final c = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(c.dispose);
      final save = c.read(callSettingsSaveProvider);
      var s = await save(
        ringSeconds: 20,
        followMeTo: '0491 570 156',
        followMeSeconds: 20,
        followMeConfirm: true,
        forwardAlwaysTo: null,
      );
      expect(s.followMeTo, '0491570156');
      expect(s.ringSeconds, 20);
      // Cleared in the form: sent as null, and the mock drops it.
      s = await save(
        ringSeconds: 20,
        followMeTo: '',
        followMeSeconds: 20,
        followMeConfirm: true,
        forwardAlwaysTo: '  ',
      );
      expect(s.followMeTo, isNull);
      expect(s.forwardAlwaysTo, isNull);
      await expectLater(
        dio.patch<Object?>('/me/call-settings', data: {'followMeTo': ''}),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            400,
          ),
        ),
      );
    });

    test('call logs answer a reference', () async {
      final r = await dio.post<Map<String, Object?>>(
        '/diagnostics/call-logs',
        data: Stream.fromIterable([
          [31, 139, 8, 0],
        ]),
        options: Options(
          contentType: 'application/gzip',
          headers: {Headers.contentLengthHeader: 4},
        ),
      );
      expect(r.statusCode, 201);
      expect(r.data!['reference'], 'LOG-7F3K9Q');
    });
  });
}

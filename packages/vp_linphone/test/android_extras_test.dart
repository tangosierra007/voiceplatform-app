import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vp_linphone/src/messages.g.dart';
import 'package:vp_linphone/vp_linphone.dart';

class _Host extends VpLinphoneHostApi {
  int syncs = 0;
  List<PushMsg> pending = [];
  UiRequestMsg? ui;
  final List<String> calls = [];

  @override
  Future<void> syncState() async => syncs++;
  @override
  Future<List<PushMsg>> takePendingPushes() async => pending;
  @override
  Future<UiRequestMsg?> takeUiRequest() async => ui;
  @override
  Future<BatteryMsg> batteryStatus() async =>
      BatteryMsg(ignoringOptimizations: false, lateWakesLastWeek: 2, manufacturer: 'samsung');
  @override
  Future<bool> canUseFullScreenIntent() async => false;
  @override
  Future<void> openBatteryOptimizationSettings() async => calls.add('battery');
  @override
  Future<void> openFullScreenIntentSettings() async => calls.add('fsi');
  @override
  Future<void> updatePush(String provider, String prid, String param) async => calls.add('updatePush $prid');
}

class _Tokens implements PushTokenSource {
  final refresh = StreamController<String>();
  @override
  Future<String?> currentToken() async => 'token-1';
  @override
  Stream<String> get tokenRefresh => refresh.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Host host;
  late VpLinphoneEngine engine;

  setUp(() {
    host = _Host();
    engine = VpLinphoneEngine(hostApi: host);
  });

  test('a new engine asks the platform side to catch up (push wake before Flutter)', () async {
    await pumpEventQueue();
    expect(host.syncs, 1);
  });

  test('app pushes reach the stream; call pushes never do', () async {
    final got = <VpPushMessage>[];
    final sub = engine.pushMessages.listen(got.add);
    engine.events.onPush(PushMsg(type: PushTypeMsg.voicemail, pushId: 'p1', sentAt: '2026-10-28T00:00:00Z'));
    engine.events.onPush(PushMsg(type: PushTypeMsg.signedOut, pushId: 'p2'));
    engine.events.onPush(PushMsg(type: PushTypeMsg.incomingCall, pushId: 'p3'));
    await pumpEventQueue();
    expect(got.map((p) => p.type), [VpPushType.voicemail, VpPushType.signedOut]);
    expect(got.first.sentAt, DateTime.utc(2026, 10, 28));
    await sub.cancel();
  });

  test('pending pushes from while the app was not running', () async {
    host.pending = [PushMsg(type: PushTypeMsg.message, pushId: 'a'), PushMsg(type: PushTypeMsg.config, pushId: 'b')];
    final p = await engine.takePendingPushes();
    expect(p.map((m) => '${m.type.name}:${m.pushId}'), ['message:a', 'config:b']);
  });

  test('UI requests: the stream and the launch request', () async {
    final got = <VpUiRequest>[];
    final sub = engine.uiRequests.listen(got.add);
    engine.events.onUiRequest(UiRequestMsg(kind: UiRequestKindMsg.showIncoming, callId: 'call-1'));
    engine.events.onUiRequest(UiRequestMsg(kind: UiRequestKindMsg.showCall, callId: 'call-1'));
    await pumpEventQueue();
    expect(got, const [
      VpUiRequest(VpUiRequestKind.showIncoming, 'call-1'),
      VpUiRequest(VpUiRequestKind.showCall, 'call-1'),
    ]);
    expect(await engine.takeUiRequest(), isNull);
    host.ui = UiRequestMsg(kind: UiRequestKindMsg.showIncoming, callId: 'call-2');
    expect(await engine.takeUiRequest(), const VpUiRequest(VpUiRequestKind.showIncoming, 'call-2'));
    await sub.cancel();
  });

  test('full-screen intent refused: stream, check and settings', () async {
    final got = <String>[];
    final sub = engine.fullScreenIntentDenied.listen(got.add);
    engine.events.onFullScreenIntentDenied('call-1');
    await pumpEventQueue();
    expect(got, ['call-1']);
    expect(await engine.canUseFullScreenIntent(), isFalse);
    await engine.openFullScreenIntentSettings();
    expect(host.calls, ['fsi']);
    await sub.cancel();
  });

  test('battery status for the Me card, and the settings link', () async {
    final b = await engine.batteryStatus();
    expect(b.ignoringOptimizations, isFalse);
    expect(b.lateWakesLastWeek, 2);
    expect(b.manufacturer, 'samsung');
    await engine.openBatteryOptimizationSettings();
    expect(host.calls, ['battery']);
  });

  group('push tokens', () {
    test('start gives the token and the RFC 8599 params', () async {
      final tokens = VpPushTokens(engine: engine, source: _Tokens());
      expect(await tokens.start(), 'token-1');
      final p = VpPushTokens.paramsFor('token-1');
      expect([p.provider, p.prid, p.param], ['fcm', 'token-1', 'voiceplatform-app']);
    });

    test('a refresh updates the engine without dropping calls and tells the app', () async {
      final source = _Tokens();
      final tokens = VpPushTokens(engine: engine, source: source);
      await tokens.start();
      final got = <String>[];
      final sub = tokens.tokens.listen(got.add);
      source.refresh
        ..add('token-1') // same as now: nothing
        ..add('token-2');
      await pumpEventQueue();
      expect(host.calls, ['updatePush token-2']);
      expect(got, ['token-2']);
      expect(tokens.current, 'token-2');
      await sub.cancel();
      await tokens.dispose();
    });

    test('not registered yet: the token is still passed on for the API', () async {
      final source = _Tokens();
      final failing = _FailingEngine();
      final tokens = VpPushTokens(engine: failing, source: source);
      await tokens.start();
      final got = <String>[];
      final sub = tokens.tokens.listen(got.add);
      source.refresh.add('token-3');
      await pumpEventQueue();
      expect(got, ['token-3']);
      await sub.cancel();
    });
  });
}

class _FailingEngine implements CallEngine {
  @override
  Future<void> updatePush(PushParams push) async => throw const NotRegistered();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

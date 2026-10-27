import 'package:call_engine/call_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vp_linphone/vp_linphone.dart';

/// The engine against a fake platform channel: real Pigeon messages on the
/// wire, answered by a mock handler the way the Kotlin side answers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMessageCodec();
  const prefix = 'dev.flutter.pigeon.vp_linphone.VpLinphoneHostApi.';

  final received = <String, List<Object?>>{};

  void handle(String method, Object? Function(List<Object?> args) reply) {
    messenger.setMockMessageHandler('$prefix$method', (ByteData? data) async {
      final args = (codec.decodeMessage(data) as List<Object?>?) ?? const [];
      received[method] = args;
      return codec.encodeMessage(reply(args));
    });
  }

  tearDown(() {
    received.clear();
    for (final m in ['call', 'register', 'answer', 'start']) {
      messenger.setMockMessageHandler('$prefix$m', null);
    }
  });

  test('call goes over the channel and returns the engine call id', () async {
    handle('call', (_) => ['call-7']);
    final engine = VpLinphoneEngine();
    expect(await engine.call('204', callerId: 'withheld'), 'call-7');
    expect(received['call'], ['204', 'withheld']);
  });

  test('register sends the fields in order, expiry as an int', () async {
    handle('register', (_) => [null]);
    final engine = VpLinphoneEngine();
    await engine.register(
      const SipAccount(
        authUsername: 'app-abcde12345',
        password: 'testpasswordtestpassword',
        domain: 'democo.sip.voiceplatform.com.au',
        outboundProxy: 'sip:sip.voiceplatform.com.au:5061;transport=tls',
        displayName: 'Ava Nguyen',
        expiresSeconds: 600,
        instanceId: 'urn:uuid:0e2f3c4a-5b6c-4d7e-8f90-a1b2c3d4e5f6',
        push: PushParams(provider: 'fcm', prid: 'token-1', param: 'voiceplatform-app'),
      ),
    );
    expect(received['register']!.length, 10);
    expect(received['register']![5], 600);
    expect(received['register']![6], 'urn:uuid:0e2f3c4a-5b6c-4d7e-8f90-a1b2c3d4e5f6');
    expect(received['register']![7], 'fcm');
  });

  test('a Pigeon error envelope becomes the typed contract error', () async {
    handle('answer', (_) => ['microphone_denied', 'Microphone permission not granted', null]);
    final engine = VpLinphoneEngine();
    await expectLater(engine.answer('call-1'), throwsA(isA<MicrophoneDenied>()));
  });

  test('no platform side at all is an InvalidState, not a crash', () async {
    final engine = VpLinphoneEngine();
    await expectLater(engine.start(), throwsA(isA<InvalidState>()));
  });
}

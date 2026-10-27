import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:call_engine/call_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vp_linphone/src/messages.g.dart';
import 'package:vp_linphone/vp_linphone.dart';

import '../../../test/diagnostics/shared_scrub_cases.dart' as app;
import 'shared_scrub_cases.dart';

class _Host extends VpLinphoneHostApi {
  Uint8List log = Uint8List(0);
  @override
  Future<void> syncState() async {}
  @override
  Future<Uint8List> exportLastCallLog() async => log;
}

String _gunzip(Uint8List bytes) => utf8.decode(gzip.decode(bytes));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shared scrub table (the app scrubber passes the same cases)', () {
    test('this copy has the same cases as the app'
        's test/diagnostics/shared_scrub_cases.dart', () {
      expect(sharedScrubCases, app.sharedScrubCases);
    });

    for (final (input, expected) in sharedScrubCases) {
      test(input.length > 50 ? '${input.substring(0, 50)}...' : input, () {
        expect(LogScrubber().scrub(input), expected);
      });
    }
  });

  group('export format', () {
    late _Host host;
    late VpLinphoneEngine engine;

    setUp(() {
      host = _Host();
      engine = VpLinphoneEngine(hostApi: host);
    });

    test('no call logged: empty, and sendCallLogs says so', () async {
      expect(await engine.exportLastCallLog(), isEmpty);
      final d = CallDiagnostics(engine: engine, upload: (_) async => fail('nothing to send'));
      await expectLater(d.sendCallLogs(), throwsA(isA<NoCallLog>()));
    });

    test('gzip of the log, scrubbed again in Dart', () async {
      host.log = Uint8List.fromList(
        utf8.encode('2026 Oct 27 03:15:00.123Z ENGINE dial 0491570737\nAuthorization: Digest response="x"\n'),
      );
      final out = await engine.exportLastCallLog();
      expect(out.sublist(0, 2), [0x1f, 0x8b]); // gzip magic
      expect(_gunzip(out), '2026 Oct 27 03:15:00.123Z ENGINE dial [n]\nAuthorization: [scrubbed]\n');
    });

    test('a log that does not fit in 2 MB loses its oldest lines, with a marker', () {
      final rnd = Random(1);
      String noise() => String.fromCharCodes(List.generate(70, (_) => 97 + rnd.nextInt(26)));
      final lines = List.generate(60000, (i) => 'line $i ${noise()}'); // about 4.6 MB, poorly compressible
      final text = '${lines.join('\n')}\n';
      final out = packCallLog(text);
      expect(out.length, lessThanOrEqualTo(callLogMaxBytes));
      final back = _gunzip(out);
      expect(back.startsWith('$callLogTruncatedMarker\n'), isTrue);
      expect(back, contains('line 59999 '));
      expect(back, isNot(contains('line 0 ')));
      // Cut at a line boundary: the line after the marker is whole.
      expect(back.split('\n')[1], startsWith('line '));
    });

    test('a log that fits is untouched', () {
      final out = packCallLog('short log\n');
      expect(_gunzip(out), 'short log\n');
    });

    test('a smaller limit also holds', () {
      final text = List.generate(2000, (i) => 'line $i ${'x' * 40}${i * 7919}').join('\n');
      final out = packCallLog(text, maxBytes: 4000);
      expect(out.length, lessThanOrEqualTo(4000));
      expect(_gunzip(out), startsWith(callLogTruncatedMarker));
    });
  });

  group('CallDiagnostics', () {
    test('sendCallLogs uploads the gzipped log and returns the reference', () async {
      final host = _Host()..log = Uint8List.fromList(utf8.encode('call log line\n'));
      final engine = VpLinphoneEngine(hostApi: host);
      Uint8List? sent;
      final d = CallDiagnostics(
        engine: engine,
        upload: (bytes) async {
          sent = bytes;
          return 'LOG-7F3K9Q';
        },
      );
      expect(await d.sendCallLogs(), 'LOG-7F3K9Q');
      expect(_gunzip(sent!), 'call log line\n');
      expect(sent!.length, lessThanOrEqualTo(callLogMaxBytes));
    });

    test('upload errors come back as they are', () async {
      final host = _Host()..log = Uint8List.fromList(utf8.encode('x\n'));
      final d = CallDiagnostics(
        engine: VpLinphoneEngine(hostApi: host),
        upload: (_) async => throw const HttpException('413 log_too_large'),
      );
      await expectLater(d.sendCallLogs(), throwsA(isA<HttpException>()));
    });
  });

  test('call quality samples reach the optional stream', () async {
    final engine = VpLinphoneEngine(hostApi: _Host());
    final got = <VpCallQuality>[];
    final sub = engine.callQuality.listen(got.add);
    engine.events.onCallQuality(
      QualityMsg(
        callId: 'call-1',
        quality: 4.2,
        jitterMs: 12.5,
        localLossPercent: 0.5,
        remoteLossPercent: 1.0,
        roundTripMs: 48,
      ),
    );
    await pumpEventQueue();
    expect(got.single.callId, 'call-1');
    expect(got.single.quality, 4.2);
    expect(got.single.roundTripMs, 48);
    engine.events.onCallQuality(
      QualityMsg(callId: 'call-1', jitterMs: 0, localLossPercent: 0, remoteLossPercent: 0, roundTripMs: 0),
    );
    await pumpEventQueue();
    expect(got.last.quality, isNull); // no estimate yet: null, not 0
    await sub.cancel();
  });

  test('CallEngine contract still holds', () {
    expect(VpLinphoneEngine(hostApi: _Host()), isA<CallEngine>());
  });
}

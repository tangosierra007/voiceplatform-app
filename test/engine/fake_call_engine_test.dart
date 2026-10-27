import 'dart:convert';

import 'package:call_engine/call_engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';

const _account = SipAccount(
  authUsername: 'mock-202-pixel8',
  password: 'test-password',
  domain: 'sip.demo-co.example',
  outboundProxy: 'sip:sip.voiceplatform.example:5061;transport=tls',
  displayName: 'Ava Nguyen',
  expiresSeconds: 600,
  instanceId: 'urn:uuid:60000000-0000-4000-8000-000000000001',
  push: PushParams(
    provider: 'fcm',
    prid: 'token-1',
    param: 'voiceplatform-app',
  ),
);

const _westgate = IncomingInfo(
  calledNumber: '+61355501201',
  calledLabel: 'Sales group',
  alsoRinging: ["Mia's desk phone"],
  repeatCount: 3,
  lastAnsweredBy: 'Tom Walsh',
);

/// A started, registered engine whose far end does nothing by itself.
Future<FakeCallEngine> _ready({
  OutgoingScript outgoing = OutgoingScript.manual,
}) async {
  final e = FakeCallEngine(outgoing: outgoing, registerAfter: Duration.zero);
  addTearDown(e.dispose);
  await e.start();
  await e.register(_account);
  return e;
}

void main() {
  group('registration', () {
    test('progress then ok, and the password never comes back', () async {
      final e = FakeCallEngine(registerAfter: Duration.zero);
      addTearDown(e.dispose);
      final events = <RegistrationState>[];
      e.registration.listen((r) => events.add(r.state));
      await e.start();
      await e.register(_account);
      await pumpEventQueue();
      expect(events, [RegistrationState.progress, RegistrationState.ok]);
      expect(e.registeredAs, 'mock-202-pixel8@sip.demo-co.example');
      expect(e.pushParams!.provider, 'fcm');
      final log = utf8.decode(await e.exportLastCallLog());
      expect(log, isNot(contains(_account.password)));
      expect(_account.toString(), isNot(contains(_account.password)));
    });

    test('a scripted failure, then unregister clears', () async {
      final e = FakeCallEngine(registerAfter: Duration.zero);
      addTearDown(e.dispose);
      final events = <RegistrationEvent>[];
      e.registration.listen(events.add);
      await e.start();
      e.failNextRegistration(RegistrationFailure.badCredentials, sipCode: 403);
      await e.register(_account);
      await pumpEventQueue();
      expect(events.last.state, RegistrationState.failed);
      expect(events.last.failure, RegistrationFailure.badCredentials);
      expect(events.last.sipCode, 403);
      await e.unregister();
      await pumpEventQueue();
      expect(events.last.state, RegistrationState.cleared);
      expect(e.registeredAs, isNull);
    });

    test('registration takes registerAfter', () {
      fakeAsync((async) {
        final e = FakeCallEngine(
          registerAfter: const Duration(milliseconds: 200),
        );
        e.start();
        e.register(_account);
        async.flushMicrotasks();
        expect(e.registrationState, RegistrationState.progress);
        async.elapse(const Duration(milliseconds: 200));
        expect(e.registrationState, RegistrationState.ok);
        e.dispose();
      });
    });

    test('calling before registering is refused', () async {
      final e = FakeCallEngine();
      addTearDown(e.dispose);
      await e.start();
      expect(() => e.call('+61491570737'), throwsA(isA<NotRegistered>()));
    });
  });

  group('incoming', () {
    test('rings with IncomingInfo, answer connects with tags', () async {
      final e = await _ready();
      final seen = <CallSnapshot>[];
      e.calls.listen(seen.add);
      final id = e.simulateIncoming(
        remoteNumber: '+61355501987',
        remoteName: 'Westgate Supplies',
        info: _westgate,
      );
      await pumpEventQueue();
      expect(seen.single.state, CallState.incoming);
      expect(seen.single.direction, CallDirection.incoming);
      expect(seen.single.incoming!.calledLabel, 'Sales group');
      expect(seen.single.incoming!.repeatCount, 3);
      expect(e.activeCalls.single.id, id);

      await e.answer(id);
      await pumpEventQueue();
      expect(seen.last.state, CallState.connected);
      expect(seen.last.connectedAt, isNotNull);
      expect(seen.last.encrypted, isTrue);
      expect(seen.last.hdAudio, isTrue);
      expect(seen.last.incoming!.lastAnsweredBy, 'Tom Walsh');
    });

    test(
      'decline, to voicemail and answered elsewhere end with their reasons',
      () async {
        final e = await _ready();
        final ended = <EndReason>[];
        e.calls
            .where((c) => c.state == CallState.ended)
            .listen((c) => ended.add(c.endReason!));
        await e.decline(e.simulateIncoming(remoteNumber: '+61491571804'));
        await e.toVoicemail(e.simulateIncoming(remoteNumber: '+61491572665'));
        e.simulateAnsweredElsewhere(
          e.simulateIncoming(remoteNumber: '+61491570006'),
        );
        e.remoteHangup(e.simulateIncoming(remoteNumber: 'anonymous'));
        await pumpEventQueue();
        expect(ended, [
          EndReason.declined,
          EndReason.toVoicemail,
          EndReason.answeredElsewhere,
          EndReason.remote,
        ]);
        expect(e.activeCalls, isEmpty);
      },
    );

    test('answer needs the microphone', () async {
      final e = await _ready();
      e.microphoneGranted = false;
      final id = e.simulateIncoming(remoteNumber: '+61491570737');
      expect(() => e.answer(id), throwsA(isA<MicrophoneDenied>()));
    });
  });

  group('outgoing', () {
    test('scripted: dialling, ringing, connected', () {
      fakeAsync((async) {
        final e = FakeCallEngine(
          registerAfter: Duration.zero,
          outgoing: const OutgoingScript(
            ringAfter: Duration(milliseconds: 400),
            answerAfter: Duration(seconds: 2),
          ),
        );
        final states = <CallState>[];
        e.calls.listen((c) => states.add(c.state));
        e.start();
        e.register(_account);
        async.flushMicrotasks();
        e.call('+61491570737', callerId: '+61355501200');
        async.flushMicrotasks();
        expect(states, [CallState.dialling]);
        async.elapse(const Duration(milliseconds: 400));
        expect(states.last, CallState.ringing);
        async.elapse(const Duration(seconds: 2));
        expect(states.last, CallState.connected);
        e.dispose();
      });
    });

    test('busy and no answer', () {
      for (final (outcome, reason) in [
        (OutgoingOutcome.busy, EndReason.busy),
        (OutgoingOutcome.noAnswer, EndReason.noAnswer),
        (OutgoingOutcome.failed, EndReason.failed),
      ]) {
        fakeAsync((async) {
          final e = FakeCallEngine(
            registerAfter: Duration.zero,
            outgoing: OutgoingScript(
              ringAfter: Duration.zero,
              answerAfter: Duration.zero,
              outcome: outcome,
            ),
          );
          CallSnapshot? last;
          e.calls.listen((c) => last = c);
          e.start();
          e.register(_account);
          async.flushMicrotasks();
          e.call('+61355501987');
          async.elapse(const Duration(milliseconds: 1));
          expect(last!.state, CallState.ended);
          expect(last!.endReason, reason);
          e.dispose();
        });
      }
    });

    group(
      'emergency numbers go to the phone dialler, ahead of every check',
      () {
        const emergency = [
          '000',
          '112',
          '106',
          '0000',
          '0112',
          '0106',
          '000.',
          '(000)',
          '1 1 2',
          '1-0-6',
          '+000',
          ' 0 0 0 0 ',
        ];
        Future<void> refused(FakeCallEngine e) async {
          for (final n in emergency) {
            await expectLater(
              e.call(n),
              throwsA(isA<EmergencyNumberUseDialler>()),
              reason: n,
            );
          }
          expect(e.activeCalls, isEmpty);
        }

        test('registered', () async => refused(await _ready()));

        test('not started', () async {
          final e = FakeCallEngine();
          addTearDown(e.dispose);
          await refused(e);
        });

        test('started but not registered', () async {
          final e = FakeCallEngine();
          addTearDown(e.dispose);
          await e.start();
          await refused(e);
        });

        test('microphone refused', () async {
          final e = await _ready();
          e.microphoneGranted = false;
          await refused(e);
        });

        test('near misses are ordinary numbers', () async {
          final e = await _ready();
          for (final n in [
            '1000',
            '00000',
            '0001',
            '1120',
            '131',
            '+61355501200',
          ]) {
            await e.call(n);
          }
          expect(e.activeCalls, hasLength(6));
        });
      },
    );

    test('the log masks numbers', () async {
      final e = await _ready();
      await e.call('+61491570737');
      final log = utf8.decode(await e.exportLastCallLog());
      expect(log, isNot(contains('491570737')));
      expect(log, contains('737'));
    });
  });

  group('in call', () {
    Future<(FakeCallEngine, String)> connected() async {
      final e = await _ready();
      final id = await e.call('+61491570737');
      e.remoteAnswer(id);
      return (e, id);
    }

    test('hold and resume, remote hold', () async {
      final (e, id) = await connected();
      await e.hold(id);
      expect(e.activeCalls.single.state, CallState.heldByMe);
      expect(() => e.hold(id), throwsA(isA<InvalidState>()));
      await e.resume(id);
      expect(e.activeCalls.single.state, CallState.connected);
      e.remoteHold(id);
      expect(e.activeCalls.single.state, CallState.heldByRemote);
      e.remoteResume(id);
      expect(e.activeCalls.single.state, CallState.connected);
    });

    test('mute applies to every call', () async {
      final (e, id) = await connected();
      await e.setMuted(true);
      expect(e.activeCalls.single.muted, isTrue);
      expect(e.muted, isTrue);
      await e.setMuted(false);
      expect(e.activeCalls.single.muted, isFalse);
    });

    test('DTMF', () async {
      final (e, id) = await connected();
      await e.sendDtmf(id, '12#');
      await e.sendDtmf(id, '*');
      expect(e.dtmfSent[id], '12#*');
      expect(() => e.sendDtmf(id, 'x'), throwsA(isA<InvalidState>()));
    });

    test(
      'blind transfer to an emergency number is refused, never sent on',
      () async {
        final (e, id) = await connected();
        for (final n in ['000', '112', '0106']) {
          await expectLater(
            e.transferBlind(id, n),
            throwsA(isA<EmergencyNumberUseDialler>()),
          );
        }
        expect(e.activeCalls.single.state, CallState.connected);
        expect(e.transferredTo, isEmpty);
      },
    );

    test('blind transfer ends the call', () async {
      final (e, id) = await connected();
      await e.transferBlind(id, '206');
      expect(e.transferredTo[id], '206');
      expect(e.activeCalls, isEmpty);
    });

    test('attended transfer needs the first call on hold and the consult connected', () async {
      final (e, id) = await connected();
      final consult = await e.call('206');
      e.remoteAnswer(consult);
      expect(
        () => e.transferAttended(id, consult),
        throwsA(isA<InvalidState>()),
      );
      await e.hold(id);
      await e.transferAttended(id, consult);
      expect(e.transferredTo[id], '206');
      expect(e.activeCalls, isEmpty);
    });

    test('merge two calls', () async {
      final (e, id) = await connected();
      await e.hold(id);
      final second = await e.call('+61491572549');
      e.remoteAnswer(second);
      await e.merge(id, second);
      expect(e.merged, {id, second});
      expect(
        e.activeCalls.every((c) => c.state == CallState.connected),
        isTrue,
      );
    });

    test('unknown call ids', () async {
      final e = await _ready();
      expect(() => e.hangup('nope'), throwsA(isA<NoSuchCall>()));
    });

    test('network lost ends calls and fails registration', () async {
      final (e, id) = await connected();
      CallSnapshot? last;
      e.calls.listen((c) => last = c);
      e.simulateNetworkLost();
      await pumpEventQueue();
      expect(last!.endReason, EndReason.networkLost);
      expect(e.registrationState, RegistrationState.failed);
    });
  });

  group('audio', () {
    test('routes, available devices', () async {
      final e = await _ready();
      final states = <AudioState>[];
      e.audio.listen(states.add);
      await e.setAudioRoute(AudioRoute.speaker);
      expect(
        () => e.setAudioRoute(AudioRoute.bluetooth),
        throwsA(isA<InvalidState>()),
      );
      e.simulateAudioDevices({
        AudioRoute.speaker,
        AudioRoute.bluetooth,
      }, route: AudioRoute.bluetooth);
      await pumpEventQueue();
      expect(states.first.route, AudioRoute.speaker);
      expect(states.last.route, AudioRoute.bluetooth);
      expect(
        states.last.available,
        containsAll([AudioRoute.earpiece, AudioRoute.bluetooth]),
      );
      e.simulateAudioDevices({AudioRoute.speaker});
      expect(e.audioState.route, AudioRoute.earpiece);
    });
  });

  group('input level', () {
    test(
      'about 20 Hz while connected, 0 when muted, stops when the call ends',
      () {
        fakeAsync((async) {
          final e = FakeCallEngine(
            registerAfter: Duration.zero,
            outgoing: OutgoingScript.manual,
          );
          final levels = <double>[];
          e.inputLevel.listen(levels.add);
          e.start();
          e.register(_account);
          async.flushMicrotasks();
          late String id;
          e.call('+61491570737').then((v) => id = v);
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 1));
          expect(levels, isEmpty, reason: 'no level before connecting');
          e.remoteAnswer(id);
          async.elapse(const Duration(seconds: 1));
          expect(levels.length, inInclusiveRange(19, 21));
          expect(levels.every((l) => l >= 0 && l <= 1), isTrue);
          expect(levels.toSet().length, greaterThan(5));
          e.setMuted(true);
          async.flushMicrotasks();
          levels.clear();
          async.elapse(const Duration(milliseconds: 500));
          expect(levels.every((l) => l == 0), isTrue);
          e.hangup(id);
          async.flushMicrotasks();
          levels.clear();
          async.elapse(const Duration(seconds: 1));
          expect(levels, isEmpty);
          e.dispose();
        });
      },
    );

    test('a scripted level pattern', () {
      fakeAsync((async) {
        final e = FakeCallEngine(
          registerAfter: Duration.zero,
          outgoing: OutgoingScript.manual,
        )..levelPattern = (tick) => tick.isEven ? 0.9 : 0.1;
        final levels = <double>[];
        e.inputLevel.listen(levels.add);
        e.start();
        e.register(_account);
        async.flushMicrotasks();
        final id = e.simulateIncoming(remoteNumber: '+61355501987');
        e.answer(id);
        async.elapse(const Duration(milliseconds: 200));
        expect(levels.take(4), [0.9, 0.1, 0.9, 0.1]);
        e.dispose();
      });
    });
  });

  test('stop ends every call', () async {
    final e = await _ready();
    e.simulateIncoming(remoteNumber: '+61355501987');
    await e.call('+61491570737');
    await e.stop();
    expect(e.activeCalls, isEmpty);
    expect(e.isStarted, isFalse);
  });
}

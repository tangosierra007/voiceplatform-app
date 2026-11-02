// WS6 on #37: a voicemail change made on this phone is added to the counts
// until the server's own figures include it, and never after, so a newer
// badge arriving during the re-read, or two changes in flight, never count
// a change twice.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/shell/shell_status.dart';

import '../../tool/mock_server/fixtures.dart' as fx;

/// Badges pushed by the test, as the stream's `badges` events.
class _Badges extends LiveBadgesNotifier {
  @override
  Badges? build() => null;
  void push(int recents) => state = Badges(recents: recents, messages: 0);
}

void main() {
  late ProviderContainer c;
  var meRecents = 2;

  setUp(() {
    meRecents = 2;
    c = ProviderContainer(
      overrides: [
        liveBadgesProvider.overrideWith(_Badges.new),
        meProvider.overrideWith(
          (ref) async => Me.fromJson({
            ...fx.me(status: 'available'),
            'badges': {'recents': meRecents, 'messages': 0},
          }),
        ),
      ],
    );
    addTearDown(c.dispose);
    // The shell reads /me; the pending counts listen to it from the start.
    c.listen(meProvider, (_, _) {});
  });

  VoicemailPendingNotifier pending() =>
      c.read(voicemailPendingProvider.notifier);
  Map<String, PendingVoicemail> now() => c.read(voicemailPendingProvider);

  test('before the server has a change, every count adds it, even when a '
      'badge arrives meanwhile', () async {
    await c.read(meProvider.future);
    pending().add('m1', 'sales', -1);
    (c.read(liveBadgesProvider.notifier) as _Badges).push(2);
    for (final count in VoicemailCount.values) {
      expect(now().total(count), -1, reason: count.name);
    }
    expect(now().forBox('sales'), -1);
  });

  test('a newer live badge after the server took it: the badge stops adding '
      'it; the chip and the boxes still do until they are read', () async {
    await c.read(meProvider.future);
    pending()
      ..add('m1', 'sales', -1)
      ..ack('m1');
    expect(now().total(VoicemailCount.badge), -1);
    (c.read(liveBadgesProvider.notifier) as _Badges).push(1);
    expect(now().total(VoicemailCount.badge), 0);
    expect(now().total(VoicemailCount.history), -1);
    expect(now().forBox('sales'), -1);
  });

  test('/me read again after the server took it: the badge stops adding '
      'it', () async {
    await c.read(meProvider.future);
    pending()
      ..add('m1', 'sales', -1)
      ..ack('m1');
    meRecents = 1;
    c.invalidate(meProvider);
    await c.read(meProvider.future);
    expect(now().total(VoicemailCount.badge), 0);
  });

  test('two changes in flight: a re-read for one includes the other the '
      'server already took, and neither is counted twice', () async {
    await c.read(meProvider.future);
    // B is taken first; A after; C is still on its way.
    pending()
      ..add('a', 'sales', -1)
      ..add('b', 'rentals', -1)
      ..add('c', 'mine', 1)
      ..ack('b')
      ..ack('a');
    // A's re-read starts now and so includes A and B, not C.
    final upTo = pending().mark;
    pending()
      ..settle(VoicemailCount.history, upTo: upTo)
      ..settle(VoicemailCount.boxes, upTo: upTo)
      ..remove('a');
    expect(now().total(VoicemailCount.history), 1, reason: 'only C');
    expect(now().forBox('rentals'), 0);
    expect(now().forBox('mine'), 1);
    // B's own re-read then ends: B goes; C still counts.
    pending().remove('b');
    expect(now().total(VoicemailCount.history), 1);
  });

  test('a change the server took after a read started is still added to '
      'that read', () async {
    await c.read(meProvider.future);
    pending().add('a', 'sales', -1);
    final upTo = pending().mark; // the read starts before the server takes A
    pending().ack('a');
    pending().settle(VoicemailCount.history, upTo: upTo);
    expect(now().total(VoicemailCount.history), -1);
  });

  test('the tab badge never goes below none', () async {
    await c.read(meProvider.future);
    expect(withPending(0, -1), 0);
    expect(withPending(2, -1), 1);
  });
}

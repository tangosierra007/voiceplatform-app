import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/calls/directory.dart';
import 'package:voiceplatform_app/calls/numbers.dart';
import 'package:voiceplatform_app/net/api.dart';

import '../support/call_fakes.dart';

void main() {
  group('numbers', () {
    test('Australian formats', () {
      expect(formatAuNumber('+61355501987'), '03 5550 1987');
      expect(formatAuNumber('+61491570737'), '0491 570 737');
      expect(formatAuNumber('0491570737'), '0491 570 737');
      expect(formatAuNumber('1300975707'), '1300 975 707');
      expect(formatAuNumber('131234'), '13 1234');
      expect(formatAuNumber('206'), '206');
      expect(formatAuNumber('anonymous'), 'Private');
      // While typing, as far as it goes.
      expect(formatAuNumber('0491'), '0491');
      expect(formatAuNumber('049157'), '0491 57');
      expect(formatAuNumber('035550'), '03 5550');
    });

    test('ordinals, times, timer, initials', () {
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 103].map(ordinal), [
        '1st',
        '2nd',
        '3rd',
        '4th',
        '11th',
        '12th',
        '13th',
        '21st',
        '22nd',
        '103rd',
      ]);
      final now = DateTime(2026, 10, 27, 15, 0); // a Tuesday
      expect(whenShort(DateTime(2026, 10, 27, 14, 2), now), '2:02 pm');
      expect(whenShort(DateTime(2026, 10, 27, 0, 5), now), '12:05 am');
      expect(whenShort(DateTime(2026, 10, 26, 10, 14), now), 'Mon 10:14 am');
      expect(whenShort(DateTime(2026, 10, 13, 9, 0), now), '13 Oct');
      expect(callTimer(const Duration(seconds: 84)), '01:24');
      expect(callTimer(const Duration(hours: 1, seconds: 3)), '1:00:03');
      expect(initialsOf('Westgate Supplies'), 'WS');
      expect(initialsOf("Liam O'Brien"), 'LO');
      expect(initialsOf('Reception'), 'R');
    });
  });

  group('contact match, on the device only', () {
    final m = ContactMatcher(
      colleagues: fixtureColleagues(),
      shared: fixtureShared(),
      phone: const [
        PhoneContact('Mum', ['0491 579 212']),
      ],
    );

    test('shared contacts by number, with the company', () {
      expect(m.match('0491570737')!.line, 'Jordan Price, Harbour Cafe');
      expect(m.match('+61491570737')!.line, 'Jordan Price, Harbour Cafe');
      expect(m.match('03 5550 1987')!.name, 'Westgate Supplies');
    });

    test('colleagues by extension and shared mobile', () {
      expect(m.match('206')!.line, 'Mia Rossi, ext 206');
      expect(m.match('0491570156')!.name, 'Priya Shah');
    });

    test('phone contacts', () {
      expect(m.match('0491579212')!.name, 'Mum');
    });

    test('a unique prefix of 6 digits or more; nothing shorter', () {
      expect(m.match('049157073')!.name, 'Jordan Price');
      expect(m.match('04915'), isNull);
      expect(m.match('0491 57'), isNull, reason: 'several start this way');
      expect(m.match('0399999999'), isNull);
      expect(m.match(''), isNull);
    });
  });

  test('presence text and look (spec 22; "Available on mobile")', () {
    expect(presenceText(Presence.mobileOnly), 'Available on mobile');
    expect(presenceText(Presence.onCall), 'On a call');
    expect(presenceLook(Presence.mobileOnly), PresenceLook.free);
    expect(presenceLook(Presence.offline), PresenceLook.away);
    expect(presenceLook(Presence.dnd), PresenceLook.dnd);
  });
}

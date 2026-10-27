import 'package:flutter_test/flutter_test.dart';
import 'package:vp_linphone/vp_linphone.dart';

// Fixtures use ACMA fictional numbers only.
void main() {
  group('X-VP-Called', () {
    test('number and quoted label', () {
      final c = IncomingHeaders.parseCalled('+61355501201;label="Sales group"');
      expect(c.number, '+61355501201');
      expect(c.label, 'Sales group');
    });

    test('token label, spaces around', () {
      final c = IncomingHeaders.parseCalled(' +61491570737 ; label=Sales ');
      expect(c.number, '+61491570737');
      expect(c.label, 'Sales');
    });

    test('label only', () {
      final c = IncomingHeaders.parseCalled(';label="Sales group"');
      expect(c.number, isNull);
      expect(c.label, 'Sales group');
    });

    test('a number that is not E.164 is dropped, the label kept', () {
      final c = IncomingHeaders.parseCalled('0355501201;label="Support"');
      expect(c.number, isNull);
      expect(c.label, 'Support');
    });

    test('escapes and semicolons inside quotes', () {
      final c = IncomingHeaders.parseCalled(r'+61355501201;label="Sales \"A\"; Mel"');
      expect(c.label, 'Sales "A"; Mel');
    });

    test('empty or missing', () {
      expect(IncomingHeaders.parseCalled(null).number, isNull);
      expect(IncomingHeaders.parseCalled('  ').label, isNull);
    });
  });

  group('X-VP-Also-Ringing', () {
    test('quoted list', () {
      expect(IncomingHeaders.parseAlsoRinging('"Mia\'s desk phone", "Front desk DECT"'), [
        "Mia's desk phone",
        'Front desk DECT',
      ]);
    });

    test('commas inside quotes and token items', () {
      expect(IncomingHeaders.parseAlsoRinging('"Desk, upstairs", Groundwire'), ['Desk, upstairs', 'Groundwire']);
    });

    test('empty items, duplicates and the cap of five', () {
      expect(IncomingHeaders.parseAlsoRinging('a,,"a",b,c,d,e,f,g'), ['a', 'b', 'c', 'd', 'e']);
    });

    test('long and control-character text', () {
      final long = 'x' * 100;
      final out = IncomingHeaders.parseAlsoRinging('"$long", "bad\u0007bell"');
      expect(out.first.length, IncomingHeaders.maxText);
      expect(out.last, 'badbell');
    });

    test('missing', () {
      expect(IncomingHeaders.parseAlsoRinging(null), isEmpty);
    });
  });

  group('X-VP-Repeat', () {
    test('count', () {
      expect(IncomingHeaders.parseRepeat('3'), 3);
      expect(IncomingHeaders.parseRepeat(' 1 '), 1);
    });

    test('rejects zero, negatives, words and huge values', () {
      for (final v in ['0', '-2', 'three', '3.5', '100000', '', null]) {
        expect(IncomingHeaders.parseRepeat(v), isNull, reason: '$v');
      }
    });
  });

  group('X-VP-Last-Answered', () {
    test('name and UTC time', () {
      final l = IncomingHeaders.parseLastAnswered('"Mia Chen";at=2026-10-27T03:15:00Z');
      expect(l.name, 'Mia Chen');
      expect(l.at, DateTime.utc(2026, 10, 27, 3, 15));
    });

    test('offset time is converted to UTC', () {
      final l = IncomingHeaders.parseLastAnswered('Mia;at=2026-10-27T14:15:00+11:00');
      expect(l.name, 'Mia');
      expect(l.at, DateTime.utc(2026, 10, 27, 3, 15));
    });

    test('a time with no zone is dropped (it would be read as local time)', () {
      final l = IncomingHeaders.parseLastAnswered('"Mia";at=2026-10-27T03:15:00');
      expect(l.name, 'Mia');
      expect(l.at, isNull);
    });

    test('garbage time, no time', () {
      expect(IncomingHeaders.parseLastAnswered('"Mia";at=yesterday').at, isNull);
      expect(IncomingHeaders.parseLastAnswered('"Mia"').at, isNull);
    });
  });

  test('parse builds IncomingInfo from all four', () {
    final info = IncomingHeaders.parse(
      called: '+61355501201;label="Sales group"',
      alsoRinging: '"Mia\'s desk phone"',
      repeat: '3',
      lastAnswered: '"Mia Chen";at=2026-10-27T03:15:00Z',
    );
    expect(info.calledNumber, '+61355501201');
    expect(info.calledLabel, 'Sales group');
    expect(info.alsoRinging, ["Mia's desk phone"]);
    expect(info.repeatCount, 3);
    expect(info.lastAnsweredBy, 'Mia Chen');
    expect(info.lastAnsweredAt, DateTime.utc(2026, 10, 27, 3, 15));
  });

  test('no headers gives an empty IncomingInfo', () {
    final info = IncomingHeaders.parse();
    expect(info.calledNumber, isNull);
    expect(info.alsoRinging, isEmpty);
    expect(info.repeatCount, isNull);
  });
}

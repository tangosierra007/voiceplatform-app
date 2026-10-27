import 'package:call_engine/call_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'matches 000, 112 and 106, alone or with a leading 0, ignoring punctuation',
    () {
      for (final n in [
        '000',
        '112',
        '106',
        '0000',
        '0112',
        '0106',
        '0 0 0',
        '(000)',
        '112#',
        '+112',
      ]) {
        expect(isEmergencyNumber(n), isTrue, reason: n);
      }
    },
  );

  test('leaves other numbers alone', () {
    for (final n in [
      '',
      '00',
      '0001',
      '1120',
      '13 11 14',
      '0491 570 737',
      '03 5550 1201',
      '*97',
      '1060',
    ]) {
      expect(isEmergencyNumber(n), isFalse, reason: n);
    }
  });
}

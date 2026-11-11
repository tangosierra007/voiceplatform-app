// FU60: when the app fetches Me again for a timed Do not disturb.
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/net/api.dart';

final _now = DateTime.utc(2026, 11, 11, 9, 0);

Status _s(String status, [DateTime? until]) => Status.fromJson({
  'status': status,
  if (until != null) 'dndUntil': until.toIso8601String(),
});

void main() {
  test('a timed Do not disturb is fetched again just after its end', () {
    expect(
      dndEndRefreshIn(_s('dnd', _now.add(const Duration(hours: 1))), _now),
      const Duration(hours: 1) + dndEndSettle,
    );
  });

  test('an end just gone (a frozen app back, or the platform late) asks '
      'again soon', () {
    expect(
      dndEndRefreshIn(
        _s('dnd', _now.subtract(const Duration(seconds: 30))),
        _now,
      ),
      dndEndRetry,
    );
  });

  test('an end long gone is not asked about again and again', () {
    expect(
      dndEndRefreshIn(
        _s('dnd', _now.subtract(const Duration(minutes: 3))),
        _now,
      ),
      isNull,
    );
  });

  test('no end, or not on Do not disturb: nothing to fetch', () {
    expect(dndEndRefreshIn(_s('dnd'), _now), isNull);
    expect(
      dndEndRefreshIn(
        _s('available', _now.add(const Duration(hours: 1))),
        _now,
      ),
      isNull,
    );
    expect(dndEndRefreshIn(_s('away'), _now), isNull);
  });
}

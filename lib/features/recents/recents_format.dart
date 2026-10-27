import '../../calls/directory.dart';
import '../../calls/numbers.dart';
import '../../net/api.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// AppRecents' time column: `11:04 am` today, `Yesterday`, `Fri` this week,
/// `14 Oct` before that.
String recentsWhen(DateTime at, DateTime now) {
  final a = at.toLocal(), n = now.toLocal();
  final diff = DateTime(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime(a.year, a.month, a.day)).inDays;
  if (diff <= 0) return clockTime(a);
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return _days[a.weekday - 1];
  return '${a.day} ${_months[a.month - 1]}';
}

/// `4:12`, `1:02:03` past the hour.
String minutesSeconds(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

bool isPrivateNumber(String n) => n.isEmpty || n == 'anonymous';

/// The row title: the platform's name, else the phone's own contact (matched
/// on the device only, APP12), else the number as people read it.
String historyTitle(HistoryEntry h, ContactMatcher matcher) {
  if (isPrivateNumber(h.number)) return 'Private';
  final name = h.name;
  if (name != null && name.isNotEmpty) return name;
  return matcher.match(h.number)?.name ?? formatAuNumber(h.number);
}

/// The line under it: `Missed · left voicemail`, `Incoming · 4:12`,
/// `Answered by Mia on her desk phone`.
String historySubtitle(HistoryEntry h) {
  final dir = h.direction == HistoryEntryDirection.outgoing
      ? 'Outgoing'
      : 'Incoming';
  final d = h.durationSeconds;
  return switch (h.outcome) {
    HistoryEntryOutcome.missed =>
      h.direction == HistoryEntryDirection.outgoing
          ? 'Outgoing · No answer'
          : 'Missed',
    HistoryEntryOutcome.voicemail => 'Missed · left voicemail',
    HistoryEntryOutcome.answeredElsewhere =>
      h.answeredBy == null || h.answeredBy!.isEmpty
          ? 'Answered elsewhere'
          : 'Answered by ${h.answeredBy}',
    HistoryEntryOutcome.busy => '$dir · Busy',
    HistoryEntryOutcome.failed => "$dir · Didn't connect",
    _ => d == null ? dir : '$dir · ${minutesSeconds(d)}',
  };
}

/// Missed and voicemail rows are drawn in the alert colour.
bool historyIsMissed(HistoryEntry h) =>
    h.direction == HistoryEntryDirection.incoming &&
    (h.outcome == HistoryEntryOutcome.missed ||
        h.outcome == HistoryEntryOutcome.voicemail);

/// The voicemail title: name, the phone's contact, or the number.
String voicemailTitle(VoicemailMessage m, ContactMatcher matcher) {
  if (isPrivateNumber(m.number)) return 'Private';
  final name = m.name;
  if (name != null && name.isNotEmpty) return name;
  return matcher.match(m.number)?.name ?? formatAuNumber(m.number);
}

/// `0491 571 804 · Mine box`; just `Rentals box` when the title is already
/// the number.
String voicemailSubtitle(VoicemailMessage m, String title) {
  final number = formatAuNumber(m.number);
  final box = '${m.boxName} box';
  return title == number || isPrivateNumber(m.number) ? box : '$number · $box';
}

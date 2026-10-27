// Fixtures for the mock server: the design canvas sample data only (Demo Co,
// Ava Nguyen on ext 202, her colleagues, the Sales and Service mobile lines,
// the outside callers), ACMA fictional numbers, `.example` addresses. The
// figures agree with the artboards so the screens built on them add up:
// Recents badge 2, Missed 2, Voicemail 2 (Sales 1, Rentals 1), Messages 1,
// "22 colleagues, 4 free now".
//
// Times are fixed on Tuesday 27 October 2026 in Melbourne (AEDT, UTC+11), so
// "11:04 am", "Yesterday" and "Fri" read as on the artboards.

/// A stable UUID per kind and number, for example `uid(0xa, 202)`.
String uid(int kind, int n) =>
    '${kind.toRadixString(16)}0000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

/// Melbourne local time on the sample days, as RFC 3339 UTC.
String melb(int day, int hour, int minute) => DateTime.utc(
  2026,
  10,
  day,
  hour,
  minute,
).subtract(const Duration(hours: 11)).toIso8601String();

final avaId = uid(0xa, 202);

const support = {'name': 'Demo Telco', 'phone': '+61355504000'};

Map<String, Object?> me({required String status}) => {
  'userId': avaId,
  'name': 'Ava Nguyen',
  'initials': 'AN',
  'email': 'ava.nguyen@demo-co.example',
  'extension': '202',
  'extensionName': 'Ava Nguyen',
  'tenantName': 'Demo Co',
  'licence': 'advanced',
  'status': {'status': status},
  'permissions': {
    'recordings': true,
    'officeHours': true,
    'messages': true,
    'sharedVoicemail': true,
  },
  'badges': {'recents': 2, 'messages': 1},
  'support': support,
};

const callerIds = [
  {'value': '+61355501200', 'label': 'Main 03 5550 1200', 'isDefault': true},
  {
    'value': '+61355501202',
    'label': 'My direct line 03 5550 1202',
    'isDefault': false,
  },
  {'value': '+61355501201', 'label': 'Sales 03 5550 1201', 'isDefault': false},
  {
    'value': '+61491571266',
    'label': 'Sales mobile 0491 571 266',
    'isDefault': false,
  },
  {'value': 'withheld', 'label': 'Withheld', 'isDefault': false},
];

const callSettings = {
  'ringDevices': ['desk_phone', 'apps'],
  'ringSeconds': 15,
  'thenTo': 'voicemail',
};

final officeHoursId = uid(0x7, 1);

Map<String, Object?> officeHours(String mode) => {
  'id': officeHoursId,
  'name': 'Business hours',
  'mode': mode,
  'openNow': mode != 'closed',
  'summary': switch (mode) {
    'open' => 'Open until changed back',
    'closed' => 'Closed until changed back',
    _ => 'Following the schedule, open now',
  },
};

final devices = [
  {
    'id': uid(0x6, 1),
    'kind': 'android',
    'label': 'Pixel 8',
    'isThisDevice': true,
    'rings': true,
    'canSignOut': false,
    'signedInAt': melb(20, 9, 12),
    'lastSeenAt': melb(27, 9, 41),
  },
  {
    'id': uid(0x6, 2),
    'kind': 'windows',
    'label': 'Windows PC',
    'isThisDevice': false,
    'rings': true,
    'canSignOut': true,
    'signedInAt': melb(13, 8, 55),
    'lastSeenAt': melb(26, 17, 30),
  },
  {
    'id': uid(0x6, 3),
    'kind': 'desk_phone',
    'label': 'Desk phone GRP2616',
    'isThisDevice': false,
    'rings': true,
    'canSignOut': false,
  },
];

/// Colleagues as AppContacts lists them, with team as AppTransfer shows it.
/// Presence `since` is seconds before now, so "On a call · 1:37" reads right.
const colleagues = [
  {
    'n': 202,
    'name': 'Ava Nguyen',
    'initials': 'AN',
    'team': 'Sales',
    'presence': 'on_call',
    'ago': 97,
  },
  {
    'n': 201,
    'name': 'Jess Rowe',
    'initials': 'JR',
    'role': 'Reception',
    'presence': 'on_call',
    'ago': 252,
  },
  {
    'n': 205,
    'name': "Liam O'Brien",
    'initials': 'LO',
    'team': 'Sales',
    'presence': 'dnd',
  },
  {
    'n': 206,
    'name': 'Mia Rossi',
    'initials': 'MR',
    'team': 'Sales',
    'presence': 'available',
  },
  {
    'n': 302,
    'name': 'Priya Shah',
    'initials': 'PS',
    'team': 'Accounts',
    'presence': 'available',
    'mobile': '+61491570156',
  },
  {'n': 312, 'name': 'Sam Lee', 'initials': 'SL', 'presence': 'offline'},
  {
    'n': 301,
    'name': 'Tom Walsh',
    'initials': 'TW',
    'team': 'Management',
    'presence': 'mobile_only',
  },
];

/// Totals the Contacts header shows; the list above is its first screen.
const colleaguesTotal = 22;
const colleaguesFreeNow = 4;

final teams = [
  {
    'id': uid(0x5, 1),
    'name': 'Sales',
    'number': '+61355501201',
    'memberCount': 3,
    'freeCount': 1,
    'ringOrder': 'all_at_once',
    'members': [uid(0xa, 202), uid(0xa, 205), uid(0xa, 206)],
  },
  {
    'id': uid(0x5, 2),
    'name': 'Accounts',
    'number': '302',
    'memberCount': 1,
    'freeCount': 1,
    'ringOrder': 'in_order',
    'members': [uid(0xa, 302)],
  },
  {
    'id': uid(0x5, 3),
    'name': 'Management',
    'number': '301',
    'memberCount': 1,
    'freeCount': 1,
    'ringOrder': 'in_order',
    'members': [uid(0xa, 301)],
  },
];

final sharedContacts = [
  {
    'id': uid(0x4, 1),
    'name': 'Westgate Supplies',
    'company': 'Westgate Supplies',
    'numbers': [
      {'label': 'Main', 'number': '+61355501987'},
    ],
  },
  {
    'id': uid(0x4, 2),
    'name': 'Jordan Price',
    'company': 'Harbour Cafe',
    'numbers': [
      {'label': 'Mobile', 'number': '+61491570737'},
    ],
  },
  {
    'id': uid(0x4, 3),
    'name': 'Olivia Chen',
    'company': 'Chen Physio',
    'numbers': [
      {'label': 'Mobile', 'number': '+61491572549'},
    ],
  },
];

final voicemailBoxes = [
  {
    'id': uid(0xb, 1),
    'name': 'Mine',
    'kind': 'own',
    'newCount': 0,
    'totalCount': 2,
  },
  {
    'id': uid(0xb, 2),
    'name': 'Sales',
    'kind': 'shared',
    'newCount': 1,
    'totalCount': 1,
  },
  {
    'id': uid(0xb, 3),
    'name': 'Rentals',
    'kind': 'shared',
    'newCount': 1,
    'totalCount': 1,
  },
];

List<double> _wave(int seed) => [
  for (var i = 0; i < 48; i++)
    (((i * 37 + seed * 11) % 23) / 23 * 0.8 + 0.15).clamp(0.0, 1.0),
];

final voicemails = [
  {
    'id': uid(0xc, 1),
    'boxId': uid(0xb, 2),
    'boxName': 'Sales',
    'at': melb(27, 11, 4),
    'number': '+61355501987',
    'name': 'Westgate Supplies',
    'durationSeconds': 75,
    'heard': false,
    'waveform': _wave(1),
    'transcript': null,
  },
  {
    'id': uid(0xc, 2),
    'boxId': uid(0xb, 1),
    'boxName': 'Mine',
    'at': melb(26, 16, 2),
    'number': '+61491571804',
    'name': 'Chris Doyle',
    'durationSeconds': 28,
    'heard': true,
    'waveform': _wave(2),
    'transcript': null,
  },
  {
    'id': uid(0xc, 3),
    'boxId': uid(0xb, 1),
    'boxName': 'Mine',
    'at': melb(22, 12, 30),
    'number': '+61491572665',
    'name': 'Dana Ho',
    'durationSeconds': 51,
    'heard': true,
    'waveform': _wave(3),
    'transcript': null,
  },
  {
    'id': uid(0xc, 4),
    'boxId': uid(0xb, 3),
    'boxName': 'Rentals',
    'at': melb(21, 14, 0),
    'number': '+61491574632',
    'durationSeconds': 22,
    'heard': false,
    'waveform': _wave(4),
    'transcript': null,
  },
];

const greetings = [
  {
    'kind': 'unavailable',
    'isCustom': true,
    'durationSeconds': 9,
    'updatedAt': '2026-09-01T00:15:00.000Z',
  },
  {'kind': 'busy', 'isCustom': false},
  {
    'kind': 'name',
    'isCustom': true,
    'durationSeconds': 2,
    'updatedAt': '2026-09-01T00:16:00.000Z',
  },
];

/// AppRecents, newest first. The artboard's "03 9555 0142" is not an ACMA
/// fictional number, so the fixture uses 03 7010 0142 in its place.
final history = [
  {
    'id': 'h1',
    'at': melb(27, 11, 4),
    'direction': 'incoming',
    'outcome': 'voicemail',
    'number': '+61355501987',
    'name': 'Westgate Supplies',
    'line': 'Sales',
    'mine': false,
    'voicemailId': uid(0xc, 1),
  },
  {
    'id': 'h2',
    'at': melb(27, 10, 42),
    'direction': 'incoming',
    'outcome': 'answered',
    'number': '+61491570737',
    'name': 'Jordan Price',
    'durationSeconds': 252,
    'line': 'Sales',
    'mine': false,
  },
  {
    'id': 'h3',
    'at': melb(27, 10, 31),
    'direction': 'incoming',
    'outcome': 'answered_elsewhere',
    'number': '+61491570110',
    'answeredBy': 'Mia on her desk phone',
    'line': 'Sales',
    'mine': false,
  },
  {
    'id': 'h4',
    'at': melb(27, 9, 58),
    'direction': 'outgoing',
    'outcome': 'answered',
    'number': '302',
    'name': 'Priya Shah',
    'durationSeconds': 97,
    'mine': true,
  },
  {
    'id': 'h5',
    'at': melb(26, 15, 20),
    'direction': 'incoming',
    'outcome': 'answered',
    'number': '+61491571804',
    'name': 'Chris Doyle',
    'durationSeconds': 51,
    'mine': true,
  },
  {
    'id': 'h6',
    'at': melb(26, 11, 15),
    'direction': 'outgoing',
    'outcome': 'answered',
    'number': '+61370100142',
    'durationSeconds': 380,
    'mine': true,
  },
  {
    'id': 'h7',
    'at': melb(23, 16, 40),
    'direction': 'incoming',
    'outcome': 'missed',
    'number': 'anonymous',
    'mine': true,
  },
];

final recordings = [
  {
    'id': uid(0x3, 1),
    'at': melb(27, 10, 42),
    'direction': 'incoming',
    'number': '+61491570737',
    'name': 'Jordan Price',
    'durationSeconds': 252,
  },
  {
    'id': uid(0x3, 2),
    'at': melb(26, 15, 20),
    'direction': 'incoming',
    'number': '+61491571804',
    'name': 'Chris Doyle',
    'durationSeconds': 51,
  },
];

final salesLineId = uid(0xf, 1);
final serviceLineId = uid(0xf, 2);

final smsLines = [
  {
    'id': salesLineId,
    'label': 'Sales mobile',
    'number': '+61491571266',
    'canSend': true,
  },
  {
    'id': serviceLineId,
    'label': 'Service mobile',
    'number': '+61491572983',
    'canSend': true,
  },
];

final threads = [
  {
    'id': uid(0xd, 1),
    'lineId': salesLineId,
    'lineLabel': 'Sales mobile',
    'number': '+61491572549',
    'name': 'Olivia Chen',
    'lastAt': melb(27, 14, 31),
    'lastText': 'Perfect, can you email it to me as well?',
    'unread': 1,
    'channel': 'sms',
  },
  {
    'id': uid(0xd, 2),
    'lineId': salesLineId,
    'lineLabel': 'Sales mobile',
    'number': '+61491570737',
    'name': 'Jordan Price',
    'lastAt': melb(27, 13, 5),
    'lastText': 'Running 10 minutes late for the 3 pm, sorry',
    'unread': 0,
    'channel': 'sms',
  },
  {
    'id': uid(0xd, 3),
    'lineId': serviceLineId,
    'lineLabel': 'Service mobile',
    'number': '+61355501987',
    'name': 'Westgate Supplies',
    'lastAt': melb(27, 11, 48),
    'lastText': 'You: Delivery booked for Thursday morning',
    'unread': 0,
    'channel': 'sms',
  },
  {
    'id': uid(0xd, 4),
    'lineId': serviceLineId,
    'lineLabel': 'Service mobile',
    'number': '+61491572665',
    'name': 'Dana Ho',
    'lastAt': melb(26, 16, 10),
    'lastText': 'Sent a picture message (not shown yet)',
    'unread': 0,
    'channel': 'sms',
  },
];

/// AppThread: Olivia Chen on Sales mobile.
final threadMessages = <String, List<Map<String, Object?>>>{
  uid(0xd, 1): [
    {
      'id': uid(0xe, 1),
      'threadId': uid(0xd, 1),
      'direction': 'out',
      'at': melb(27, 14, 16),
      'kind': 'text',
      'text': 'Hi Olivia, happy to help. Same model as your current ones (Yealink T54W)?',
      'senderName': 'Ava',
      'status': 'delivered',
    },
    {
      'id': uid(0xe, 2),
      'threadId': uid(0xd, 1),
      'direction': 'in',
      'at': melb(27, 14, 18),
      'kind': 'text',
      'text': 'Yes please, and do you install?',
      'status': 'received',
    },
    {
      'id': uid(0xe, 3),
      'threadId': uid(0xd, 1),
      'direction': 'out',
      'at': melb(27, 14, 24),
      'kind': 'text',
      'text': r'We do. 3 x T54W set up and installed is $780 including GST. I can book Thursday.',
      'senderName': 'Ava',
      'status': 'delivered',
    },
    {
      'id': uid(0xe, 4),
      'threadId': uid(0xd, 1),
      'direction': 'in',
      'at': melb(27, 14, 31),
      'kind': 'text',
      'text': 'Perfect, can you email it to me as well?',
      'status': 'received',
    },
  ],
  uid(0xd, 2): [
    {
      'id': uid(0xe, 5),
      'threadId': uid(0xd, 2),
      'direction': 'in',
      'at': melb(27, 13, 5),
      'kind': 'text',
      'text': 'Running 10 minutes late for the 3 pm, sorry',
      'status': 'received',
    },
  ],
  uid(0xd, 3): [
    {
      'id': uid(0xe, 6),
      'threadId': uid(0xd, 3),
      'direction': 'out',
      'at': melb(27, 11, 48),
      'kind': 'text',
      'text': 'Delivery booked for Thursday morning',
      'senderName': 'Ava',
      'status': 'delivered',
    },
  ],
  uid(0xd, 4): [
    {
      'id': uid(0xe, 7),
      'threadId': uid(0xd, 4),
      'direction': 'in',
      'at': melb(26, 16, 10),
      'kind': 'picture',
      'status': 'received',
    },
  ],
};

/// Sign-in fixtures. Mock-only values: never a real account or code.
abstract final class SignInFixtures {
  static const advancedEmail = 'ava.nguyen@demo-co.example';

  /// Extension 204 Warehouse is on Basic (AppBasic).
  static const basicEmail = 'warehouse@demo-co.example';
  static const code = '123456';
  static const linkToken = 'mock-link-token';
  static const qrToken = 'mock-qr-token';

  /// A refresh with this token answers 401 device_revoked (AppSignedOut).
  static const revokedRefreshToken = 'mock-revoked';
}

/// The live presence script the event stream plays, one step per interval.
/// It returns to where it started, so a long-running stream stays consistent.
const presenceScript = [
  {'extension': '206', 'presence': 'on_call'},
  {'extension': '205', 'presence': 'available'},
  {'extension': '202', 'presence': 'available'},
  {'extension': '206', 'presence': 'available'},
  {'extension': '205', 'presence': 'dnd'},
  {'extension': '202', 'presence': 'on_call'},
];

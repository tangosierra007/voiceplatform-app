// A contact's detail (TJ, 3 Nov): a phone contact beside the list like a
// colleague, with each number under its label and each one a call through
// the one call path; on the phone, a colleague's and a phone contact's own
// page; folding with one picked lands on it; Back returns to the list where
// it was. Teams have no detail.
import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' show PhoneLabel;
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/calls/directory.dart';
import 'package:voiceplatform_app/emergency/emergency.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/screens/contacts/colleague_detail.dart';
import 'package:voiceplatform_app/screens/contacts/contacts_screen.dart';
import 'package:voiceplatform_app/shell/list_detail.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 4, 40);
const _unfolded = Size(884, 1030);
const _phone = Size(390, 844);

// Short windows, so the sample's few colleagues scroll.
const _shortUnfolded = Size(884, 480);
const _shortPhone = Size(390, 560);

const _account = SipAccount(
  authUsername: 'mock-202-pixel8',
  password: 'test-password',
  domain: 'sip.demo-co.example',
  outboundProxy: 'sip:sip.voiceplatform.example:5061;transport=tls',
  displayName: 'Ava Nguyen',
  expiresSeconds: 600,
  instanceId: 'urn:uuid:60000000-0000-4000-8000-000000000001',
);

/// ACMA's fictional numbers only.
const _book = [
  PhoneContact(
    'Dr Rowan Achebe',
    ['0491 573 770', '+61 3 5550 1777', '03 5550 1778'],
    labels: ['mobile', 'work', "Rowan's clinic"],
    id: '7',
  ),
  PhoneContact('Kim Bell', ['03 5550 1142'], labels: ['home'], id: '3'),
];

class _Spy extends FakeCallEngine {
  _Spy() : super(outgoing: OutgoingScript.manual, registerAfter: Duration.zero);
  final called = <String>[];

  @override
  Future<String> call(String number, {String? callerId}) {
    called.add(number);
    return super.call(number, callerId: callerId);
  }
}

void _window(WidgetTester tester, Size size, {double text = 1}) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.view.viewPadding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 2;
  await _settle(tester);
}

Future<_Spy> _open(
  WidgetTester tester, {
  List<PhoneContact> book = _book,
  FixedPhoneContacts? source,
}) async {
  final e = _Spy();
  await e.start();
  await e.register(_account);
  await tester.pumpWidget(
    await appUnderTest(
      engine: e,
      clock: () => _now,
      api: FakeApi({}),
      phoneContacts: book,
      phoneSource: source,
    ),
  );
  await _settle(tester);
  final rail = find.descendant(
    of: find.byType(VpNavRail),
    matching: find.text('Contacts'),
  );
  await tester.tap(
    rail.evaluate().isNotEmpty
        ? rail
        : find.descendant(
            of: find.byType(VpTabBar),
            matching: find.text('Contacts'),
          ),
  );
  await _settle(tester);
  return e;
}

Future<void> _end(WidgetTester t, FakeCallEngine e) async {
  await t.pumpWidget(const SizedBox());
  await e.dispose();
}

/// Who the detail shows (colleague, phone contact or shared phonebook
/// entry), or null for none.
String? _shown(WidgetTester tester) {
  final col = find.byType(ColleagueDetail);
  if (col.evaluate().isNotEmpty) {
    return tester.widget<ColleagueDetail>(col).colleague.name;
  }
  final phone = find.byType(PhoneContactDetail);
  if (phone.evaluate().isNotEmpty) {
    return tester.widget<PhoneContactDetail>(phone).contact.name;
  }
  final shared = find.byType(SharedContactDetail);
  if (shared.evaluate().isNotEmpty) {
    return tester.widget<SharedContactDetail>(shared).contact.name;
  }
  return null;
}

Finder _button(String label) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.properties.button == true &&
      w.properties.label == label,
);

/// A label and value pair in the detail, as read out ("Mobile: …").
Finder _kv(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

/// Within the phone contact's or shared phonebook entry's detail.
Finder _inDetail(Finder f) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is PhoneContactDetail || w is SharedContactDetail,
  ),
  matching: f,
);

/// Taps [f] to call, then hangs the call up so the detail is back.
Future<void> _callAndHangUp(WidgetTester tester, _Spy e, Finder f) async {
  await tester.tap(f);
  await _settle(tester);
  for (final c in [...e.activeCalls]) {
    await tester.runAsync(() => e.hangup(c.id));
  }
  await _settle(tester);
  await tester.pump(const Duration(seconds: 2));
  await _settle(tester);
}

/// The tab's list (not the rail, the filter chips or the detail).
final _list = find.descendant(
  of: find.byKey(ContactsScreen.listKey),
  matching: find.byType(Scrollable),
);

ScrollPosition _listPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(_list.first).position;

Future<void> _phoneTab(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Phone contacts'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Phone contacts'));
  await _settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  test("labels: the phone's words, and the person's own as written", () {
    expect(labelTitle('mobile'), 'Mobile');
    expect(labelTitle('work fax'), 'Work fax');
    expect(labelTitle('iPhone'), 'iPhone');
    expect(labelTitle('ISDN'), 'ISDN');
    expect(labelTitle("Rowan's clinic"), "Rowan's clinic");
    expect(phoneLabelText(PhoneLabel.workMobile, null), 'work mobile');
    expect(phoneLabelText(PhoneLabel.custom, r'_$!<Clinic>!$_'), 'Clinic');
    expect(phoneLabelText(PhoneLabel.custom, ' '), 'phone');
    expect(const PhoneContact('A', ['1', '2']).labelAt(1), 'phone');
    expect(standardPhoneLabels, isNot(contains("Rowan's clinic")));
    expect(isStandardPhoneLabel('Work'), isTrue, reason: 'typed, not picked');
    expect(isStandardPhoneLabel(' IPHONE '), isTrue);
    expect(isStandardPhoneLabel("Rowan's clinic"), isFalse);
    expect(labelWord('Main'), 'main');
    expect(labelWord('Apple Watch'), 'Apple Watch');
    expect(labelWord('ISDN'), 'ISDN');
  });

  testWidgets('884 dp: a phone contact picked shows beside the list, each '
      'number under its label, each one a call', (tester) async {
    _window(tester, _unfolded);
    final e = await _open(tester);
    await _phoneTab(tester);
    expect(_shown(tester), isNull, reason: 'nothing picked on this tab');
    await tester.tap(find.text('Dr Rowan Achebe'));
    await _settle(tester);
    expect(find.byType(ListDetailLayout), findsOneWidget);
    expect(_shown(tester), 'Dr Rowan Achebe');
    expect(_inDetail(find.text('On this phone')), findsOneWidget);
    expect(_inDetail(find.text('Numbers')), findsOneWidget);
    expect(_inDetail(_kv('Mobile: 0491 573 770')), findsOneWidget);
    expect(_inDetail(_kv('Work: 03 5550 1777')), findsOneWidget);
    expect(_inDetail(_kv("Rowan's clinic: 03 5550 1778")), findsOneWidget);
    expect(find.text('Send to voicemail'), findsNothing);

    await _callAndHangUp(tester, e, _inDetail(find.text('Call mobile')));
    await _callAndHangUp(
      tester,
      e,
      _inDetail(_button('Call Work, 03 5550 1777')),
    );
    await _callAndHangUp(tester, e, _inDetail(find.text('03 5550 1778')));
    expect(e.called, ['0491 573 770', '+61 3 5550 1777', '03 5550 1778']);

    expect(tester.takeException(), isNull);
    expect(tester.takeException(), isNull);
    await _end(tester, e);
  });

  testWidgets("a phone contact's emergency number goes the one way: "
      'AppEmergency, never the engine', (tester) async {
    _window(tester, _unfolded);
    final e = await _open(
      tester,
      book: const [
        PhoneContact('Test only', ['000'], labels: ['other'], id: '1'),
      ],
    );
    await _phoneTab(tester);
    await tester.tap(find.text('Test only'));
    await _settle(tester);
    await tester.tap(_inDetail(_button('Call Other, 000')));
    await _settle(tester);
    expect(find.byType(EmergencySheet), findsOneWidget);
    expect(e.called, isEmpty);
    await _end(tester, e);
  });

  testWidgets("phone: a colleague's own page, full screen; Back returns to "
      'the list where it was', (tester) async {
    _window(tester, _shortPhone);
    final e = await _open(tester);
    expect(_shown(tester), isNull);
    await tester.scrollUntilVisible(
      find.text('Priya Shah'),
      100,
      scrollable: _list.first,
    );
    await tester.pumpAndSettle();
    final at = _listPosition(tester).pixels;
    expect(at, greaterThan(0), reason: 'scrolled to her');
    await tester.tap(find.text('Priya Shah'));
    await _settle(tester);
    expect(_shown(tester), 'Priya Shah');
    expect(find.byType(ListDetailLayout), findsNothing);
    expect(find.byType(VpTabBar), findsOneWidget);
    expect(find.text('Call 302'), findsOneWidget);
    expect(find.text('Calls with Priya'), findsOneWidget);
    expect(_kv('Mobile: 0491 570 156'), findsOneWidget);
    await _callAndHangUp(tester, e, find.text('Call mobile'));
    expect(e.called, ['+61491570156']);

    await tester.tap(_button('Back to Contacts'));
    await _settle(tester);
    expect(_shown(tester), isNull);
    expect(_listPosition(tester).pixels, at);

    // Android's back does the same.
    await tester.tap(find.text('Priya Shah'));
    await _settle(tester);
    expect(_shown(tester), 'Priya Shah');
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_shown(tester), isNull);
    expect(find.text('Priya Shah'), findsOneWidget);
    await _end(tester, e);
  });

  testWidgets("phone: a phone contact's own page, each number a call; Back "
      'to Phone contacts', (tester) async {
    _window(tester, _phone);
    final e = await _open(tester);
    await _phoneTab(tester);
    await tester.tap(find.text('Dr Rowan Achebe'));
    await _settle(tester);
    expect(_shown(tester), 'Dr Rowan Achebe');
    expect(_inDetail(_kv('Mobile: 0491 573 770')), findsOneWidget);
    expect(_inDetail(_kv('Work: 03 5550 1777')), findsOneWidget);
    await _callAndHangUp(
      tester,
      e,
      _inDetail(_button('Call Work, 03 5550 1777')),
    );
    expect(e.called, ['+61 3 5550 1777']);
    await tester.tap(_button('Back to Contacts'));
    await _settle(tester);
    expect(_shown(tester), isNull);
    expect(find.text('Kim Bell'), findsOneWidget, reason: 'Phone contacts');
    await _end(tester, e);
  });

  testWidgets('a team picked on Teams has no detail; its member opens their '
      'page; Back finds the team still open', (tester) async {
    _window(tester, _phone);
    final e = await _open(tester);
    await tester.tap(find.text('Teams'));
    await _settle(tester);
    await tester.tap(find.text('Accounts'));
    await _settle(tester);
    expect(_shown(tester), isNull, reason: 'the team opens in place');
    await tester.tap(find.text('Priya Shah'));
    await _settle(tester);
    expect(_shown(tester), 'Priya Shah');
    await tester.tap(_button('Back to Contacts'));
    await _settle(tester);
    expect(_shown(tester), isNull);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            (w.properties.label ?? '').startsWith('Accounts,') &&
            w.properties.label!.endsWith('hide members'),
      ),
      findsOneWidget,
      reason: 'still open',
    );
    expect(find.text('Priya Shah'), findsOneWidget, reason: 'a member, shown');
    await _end(tester, e);
  });

  for (final (what, tab, name) in [
    ('a colleague', 'Colleagues', 'Mia Rossi'),
    ('a phone contact', 'Phone contacts', 'Dr Rowan Achebe'),
  ]) {
    testWidgets('fold with $what picked: their page; Back: the list; unfold: '
        'nothing picked again', (tester) async {
      _window(tester, _unfolded);
      final e = await _open(tester);
      if (tab != 'Colleagues') await _phoneTab(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(ListDetailLayout),
          matching: find.text(name),
        ),
      );
      await _settle(tester);
      expect(_shown(tester), name);

      await _resize(tester, _phone);
      expect(find.byType(ListDetailLayout), findsNothing);
      expect(_shown(tester), name, reason: 'full screen');
      expect(_button('Back to Contacts'), findsOneWidget);

      await _resize(tester, _unfolded);
      expect(_shown(tester), name, reason: 'beside the list again');
      await _resize(tester, _phone);
      await tester.tap(_button('Back to Contacts'));
      await _settle(tester);
      expect(_shown(tester), isNull);
      expect(find.text(tab), findsOneWidget);

      await _resize(tester, _unfolded);
      expect(
        _shown(tester),
        tab == 'Colleagues' ? 'Reception' : null,
        reason: 'nothing picked',
      );
      expect(tester.takeException(), isNull);
      await _end(tester, e);
    });
  }

  testWidgets('fold and unfold with nothing picked: the list where it was', (
    tester,
  ) async {
    _window(tester, _shortUnfolded);
    final e = await _open(tester);
    expect(_listPosition(tester).maxScrollExtent, greaterThan(60));
    _listPosition(tester).jumpTo(60);
    await tester.pump();
    await _resize(tester, _shortPhone);
    expect(_shown(tester), isNull);
    expect(_listPosition(tester).pixels, 60);
    _listPosition(tester).jumpTo(40);
    await tester.pump();
    await _resize(tester, _shortUnfolded);
    expect(_listPosition(tester).pixels, 40);
    await _end(tester, e);
  });

  for (final w in [360.0, 680.0]) {
    testWidgets('${w.toInt()} dp at 200% text: the phone contact and the '
        'colleague fit', (tester) async {
      _window(tester, Size(w, w < 600 ? 800 : 1030), text: 2);
      final e = await _open(tester);
      await _phoneTab(tester);
      await tester.scrollUntilVisible(
        find.text('Dr Rowan Achebe'),
        200,
        scrollable: _list.first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dr Rowan Achebe'));
      await _settle(tester);
      expect(_shown(tester), 'Dr Rowan Achebe');
      expect(_inDetail(_kv('Work: 03 5550 1777')), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (w < 600) {
        await tester.tap(_button('Back to Contacts'));
        await _settle(tester);
      }
      await tester.ensureVisible(find.text('Colleagues'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Colleagues'));
      await _settle(tester);
      final priya = find.text('Priya Shah');
      await tester.scrollUntilVisible(priya, 200, scrollable: _list.first);
      await tester.pumpAndSettle();
      await tester.tap(priya.first);
      await _settle(tester);
      expect(_shown(tester), 'Priya Shah');
      expect(tester.takeException(), isNull);
      await _end(tester, e);
    });
  }

  testWidgets('back in the foreground, the address book is read again: an '
      "open page shows the edits, and closes when they're deleted", (
    tester,
  ) async {
    _window(tester, _phone);
    final book = [..._book];
    final source = FixedPhoneContacts(book);
    final e = await _open(tester, source: source);
    await _phoneTab(tester);
    await tester.tap(find.text('Kim Bell'));
    await _settle(tester);
    expect(_inDetail(_kv('Home: 03 5550 1142')), findsOneWidget);

    Future<void> resume() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      await _settle(tester);
    }

    // Edited in the phone's Contacts app while away (same id).
    book[1] = const PhoneContact(
      'Kim Bell',
      ['03 5550 1142', '0491 570 156'],
      labels: ['home', 'mobile'],
      id: '3',
    );
    await resume();
    expect(_shown(tester), 'Kim Bell');
    expect(_inDetail(_kv('Mobile: 0491 570 156')), findsOneWidget);

    // Deleted while away: the page closes, back to Phone contacts.
    book.removeAt(1);
    await resume();
    expect(_shown(tester), isNull);
    expect(find.text('Kim Bell'), findsNothing);
    expect(find.text('Dr Rowan Achebe'), findsOneWidget);
    await _end(tester, e);
  });

  testWidgets('a number with no label: "Call", and "Phone" in the card', (
    tester,
  ) async {
    _window(tester, _unfolded);
    final e = await _open(
      tester,
      book: const [
        PhoneContact('Sam Lowe', ['03 5550 1990'], id: '9'),
      ],
    );
    await _phoneTab(tester);
    await tester.tap(find.text('Sam Lowe'));
    await _settle(tester);
    expect(_inDetail(find.text('Call')), findsOneWidget);
    expect(_inDetail(find.text('Call phone')), findsNothing);
    expect(_inDetail(find.text('Number')), findsOneWidget);
    expect(_inDetail(_kv('Phone: 03 5550 1990')), findsOneWidget);
    await _end(tester, e);
  });

  testWidgets('884 dp: the pane follows the tab, each with its own pick, '
      'kept when switching back (TJ, 3 Nov)', (tester) async {
    _window(tester, _unfolded);
    final e = await _open(tester);
    Finder row(String name) => find.descendant(
      of: find.byType(ListDetailLayout),
      matching: find.text(name),
    );
    Future<void> tab(String name) async {
      await tester.tap(find.text(name).first);
      await _settle(tester);
    }

    expect(_shown(tester), 'Reception', reason: 'Colleagues: the first');
    await tester.tap(row('Mia Rossi'));
    await _settle(tester);
    expect(_shown(tester), 'Mia Rossi');

    await tab('Teams');
    expect(_shown(tester), isNull, reason: 'nothing picked on Teams');
    expect(
      find.text('Open a team and pick someone to see them here.'),
      findsOneWidget,
    );
    await tester.tap(row('Accounts'));
    await _settle(tester);
    await tester.tap(row('Priya Shah'));
    await _settle(tester);
    expect(_shown(tester), 'Priya Shah');

    await tab('Phone contacts');
    expect(_shown(tester), isNull, reason: 'no colleague stays');
    expect(
      find.text('Pick a contact to see their numbers here.'),
      findsOneWidget,
    );
    await tester.tap(row('Dr Rowan Achebe'));
    await _settle(tester);
    expect(_shown(tester), 'Dr Rowan Achebe');

    await tab('Colleagues');
    expect(_shown(tester), 'Mia Rossi', reason: 'no phone contact stays');
    await tab('Teams');
    expect(_shown(tester), 'Priya Shah');
    await tab('Phone contacts');
    expect(_shown(tester), 'Dr Rowan Achebe');
    expect(tester.takeException(), isNull);
    await _end(tester, e);
  });

  group('a shared phonebook entry', () {
    // One entry with two numbers: a row each in the list.
    final shared = [
      SharedContact.fromJson({
        'id': 'shared-1',
        'name': 'Jordan Price',
        'company': 'Harbour Cafe',
        'numbers': [
          {'label': 'Mobile', 'number': '+61491570737'},
          {'label': 'Work', 'number': '+61355501993'},
        ],
      }),
    ];

    Future<_Spy> open(WidgetTester tester) async {
      final e = _Spy();
      await e.start();
      await e.register(_account);
      await tester.pumpWidget(
        await appUnderTest(
          engine: e,
          clock: () => _now,
          api: FakeApi({}),
          phoneContacts: _book,
          sharedContacts: shared,
        ),
      );
      await _settle(tester);
      final rail = find.descendant(
        of: find.byType(VpNavRail),
        matching: find.text('Contacts'),
      );
      await tester.tap(
        rail.evaluate().isNotEmpty
            ? rail
            : find.descendant(
                of: find.byType(VpTabBar),
                matching: find.text('Contacts'),
              ),
      );
      await _settle(tester);
      await _phoneTab(tester);
      return e;
    }

    testWidgets('884 dp: either row picks it; beside the list with the '
        'company and each number under its label, each one a call', (
      tester,
    ) async {
      _window(tester, _unfolded);
      final e = await open(tester);
      expect(find.text('Jordan Price'), findsNWidgets(2), reason: 'two rows');
      await tester.tap(find.text('Jordan Price').last);
      await _settle(tester);
      expect(_shown(tester), 'Jordan Price');
      expect(
        _inDetail(find.text('Harbour Cafe · Shared phonebook')),
        findsOneWidget,
      );
      expect(_inDetail(_kv('Mobile: 0491 570 737')), findsOneWidget);
      expect(_inDetail(_kv('Work: 03 5550 1993')), findsOneWidget);
      await _callAndHangUp(tester, e, _inDetail(find.text('Call mobile')));
      await _callAndHangUp(
        tester,
        e,
        _inDetail(_button('Call Work, 03 5550 1993')),
      );
      expect(e.called, ['+61491570737', '+61355501993']);

      // The first row picks the same entry.
      await tester.tap(find.text('Jordan Price').first);
      await _settle(tester);
      expect(_shown(tester), 'Jordan Price');
      expect(tester.takeException(), isNull);
      await _end(tester, e);
    });

    testWidgets("phone: the entry's own page; Back to Phone contacts", (
      tester,
    ) async {
      _window(tester, _phone);
      final e = await open(tester);
      await tester.tap(find.text('Jordan Price').first);
      await _settle(tester);
      expect(_shown(tester), 'Jordan Price');
      expect(find.byType(ListDetailLayout), findsNothing);
      expect(_inDetail(_kv('Work: 03 5550 1993')), findsOneWidget);
      await _callAndHangUp(
        tester,
        e,
        _inDetail(_button('Call Mobile, 0491 570 737')),
      );
      expect(e.called, ['+61491570737']);
      await tester.tap(_button('Back to Contacts'));
      await _settle(tester);
      expect(_shown(tester), isNull);
      expect(find.text('Kim Bell'), findsOneWidget);
      await _end(tester, e);
    });
  });
}

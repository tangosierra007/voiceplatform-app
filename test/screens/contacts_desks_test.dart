// Desks in Colleagues (spec 31, G14; decision 257): the contract's `desks`
// and `desksFree`, parsed and shown under the colleagues. The platform
// leaves out a desk an admin switched out of the apps (66-c), so the app
// shows exactly what the reply lists.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/screens/contacts/contacts_screen.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 0, 10);

Map<String, Object?> _desk(String ext, String name, String presence) => {
  'extensionId': '70000000-0000-4000-8000-000000000$ext',
  'extension': ext,
  'name': name,
  'initials': name[0],
  'presence': {'extension': ext, 'presence': presence},
};

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(VpTabBar), matching: find.text(label));

Finder _button(String label) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.properties.button == true &&
      w.properties.label == label,
);

void main() {
  group('Colleagues reply parsing', () {
    test('reads desks and desksFree, ignoring a field it does not know', () {
      final dir = Colleagues.fromJson({
        'total': 1,
        'freeNow': 0,
        'items': const [],
        'desks': [
          {
            ..._desk('210', 'Front desk', 'available'),
            'team': 'Sales',
            'somethingNew': {'nested': true},
          },
        ],
        'desksFree': 1,
        'alsoNew': 'ignored',
      });
      final desk = dir.desks!.single;
      expect(desk.extensionValue, '210');
      expect(desk.name, 'Front desk');
      expect(desk.initials, 'F');
      expect(desk.team, 'Sales');
      expect(desk.presence.presence, Presence.available);
      expect(dir.desksFree, 1);
    });

    test('a reply without desks is still valid', () {
      final dir = Colleagues.fromJson({
        'total': 0,
        'freeNow': 0,
        'items': const [],
      });
      expect(dir.desks, isNull);
      expect(dir.desksFree, isNull);
    });
  });

  setUpAll(loadAppFonts);

  testWidgets('desks show under the colleagues with their own free count', (
    tester,
  ) async {
    usePhone(tester);
    final people = fixtureDirectory(now: _now);
    // The platform switched a third desk out of the apps: it is not in the
    // reply, so the app never shows it.
    final directory = Colleagues(
      total: people.total,
      freeNow: people.freeNow,
      items: people.items,
      desks: [
        Desk.fromJson(_desk('210', 'Front desk', 'available')),
        Desk.fromJson(_desk('211', 'Warehouse phone', 'offline')),
      ],
      desksFree: 1,
    );
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, directory: directory),
    );
    await _settle(tester);
    await tester.tap(_tab('Contacts'));
    await _settle(tester);
    // The colleagues' band still counts people only.
    expect(find.text('22 COLLEAGUES · 3 FREE NOW'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Warehouse phone'),
      200,
      scrollable: find.descendant(
        of: find.byKey(ContactsScreen.listKey),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('2 DESKS · 1 FREE NOW'), findsOneWidget);
    expect(find.text('Front desk'), findsOneWidget);
    expect(find.text('210 · Available'), findsOneWidget);
    expect(find.text('211 · Offline'), findsOneWidget);
    expect(_button('Call Front desk'), findsOneWidget);
    expect(find.text('Loading dock'), findsNothing);
  });

  testWidgets('no desks in the reply: no desks band', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest(clock: () => _now));
    await _settle(tester);
    await tester.tap(_tab('Contacts'));
    await _settle(tester);
    expect(find.textContaining('DESK'), findsNothing);
  });
}

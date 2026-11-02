// A contact's detail (TJ, 3 Nov; no artboard: drawn as FoldContacts'
// colleague detail): on a 360 x 800 phone, the own pages of Priya Shah, Dr
// Rowan Achebe (a phone contact: mobile, work and his own label) and
// Jordan Price (a shared phonebook entry: Harbour Cafe, mobile and work);
// at 680 x 1030, the narrowest split, Dr Rowan Achebe and Jordan Price
// beside the Phone contacts list. Each at 100% and 200% text, light and
// dark (dark from the tokens), at 3:40 pm on Tuesday 27 October in Melbourne.
//
//   flutter test --update-goldens test/goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/calls/directory.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/screens/contacts/contacts_screen.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 4, 40);

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

/// A shared phonebook entry with two numbers (a row each in the list).
final _shared = [
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

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pumpAndSettle();
}

final _list = find.descendant(
  of: find.byKey(ContactsScreen.listKey),
  matching: find.byType(Scrollable),
);

void main() {
  setUpAll(loadAppFonts);

  for (final (view, size, who) in [
    ('colleague_360', const Size(360, 800), 'Priya Shah'),
    ('phone_contact_360', const Size(360, 800), 'Dr Rowan Achebe'),
    ('phone_contact_wide_680', const Size(680, 1030), 'Dr Rowan Achebe'),
    ('shared_contact_360', const Size(360, 800), 'Jordan Price'),
    ('shared_contact_wide_680', const Size(680, 1030), 'Jordan Price'),
  ]) {
    final phoneTab = who != 'Priya Shah';
    for (final (name, pref, text) in [
      ('light', ThemePreference.light, 1.0),
      ('dark', ThemePreference.dark, 1.0),
      ('200pct_light', ThemePreference.light, 2.0),
      ('200pct_dark', ThemePreference.dark, 2.0),
    ]) {
      testWidgets('contact detail, ${view}_$name', (tester) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        tester.view.padding = const FakeViewPadding(top: artboardStatusBar * 2);
        tester.view.viewPadding = const FakeViewPadding(
          top: artboardStatusBar * 2,
        );
        tester.platformDispatcher.textScaleFactorTestValue = text;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          await appUnderTest(
            theme: pref,
            clock: () => _now,
            api: FakeApi({}),
            phoneContacts: _book,
            sharedContacts: _shared,
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
        if (phoneTab) {
          await tester.ensureVisible(find.text('Phone contacts'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Phone contacts'));
          await _settle(tester);
        }
        if (find.text(who).evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            find.text(who),
            200,
            scrollable: _list.first,
          );
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text(who).first);
        await _settle(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('contact_detail_${view}_$name.png'),
        );
      });
    }
  }
}

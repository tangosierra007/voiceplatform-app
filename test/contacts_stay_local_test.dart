// APP12: the phone's address book stays on the phone. READ_CONTACTS is asked
// only on the first opening of the Phone contacts tab; refusing leaves the
// rest working; names overlay calls on the device; nothing read from the
// address book goes into any request; every value is registered with the
// diagnostics scrubber.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/calls/directory.dart';
import 'package:voiceplatform_app/diagnostics/scrubber.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import 'support/app_harness.dart';
import 'support/phone.dart';

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(VpTabBar), matching: find.text(label));

const _book = [
  PhoneContact('Kim Bell', ['03 5550 1142']),
  PhoneContact('Dr Rowan Achebe', ['0491 579 999', '+61 3 5550 1777']),
];

void main() {
  setUpAll(loadAppFonts);

  testWidgets('asked once, on first opening Phone contacts only', (
    tester,
  ) async {
    usePhone(tester);
    final source = FixedPhoneContacts(
      _book,
      granted: false,
      grantOnRequest: true,
    );
    await tester.pumpWidget(await appUnderTest(phoneSource: source));
    await _settle(tester);
    // Nothing asks at start, on Recents, or on the other Contacts tabs.
    await tester.tap(_tab('Recents'));
    await _settle(tester);
    await tester.tap(_tab('Contacts'));
    await _settle(tester);
    await tester.tap(find.text('Teams'));
    await _settle(tester);
    expect(source.requests, 0);

    await tester.tap(find.text('Phone contacts'));
    await _settle(tester);
    expect(source.requests, 1);
    expect(find.text('Kim Bell'), findsOneWidget);
    expect(find.text('Dr Rowan Achebe'), findsOneWidget);

    // Back and forth: not asked again.
    await tester.tap(find.text('Colleagues'));
    await _settle(tester);
    await tester.tap(find.text('Phone contacts'));
    await _settle(tester);
    expect(source.requests, 1);
  });

  testWidgets('refusing leaves Colleagues, Teams and the phonebook working', (
    tester,
  ) async {
    usePhone(tester);
    final source = FixedPhoneContacts(
      _book,
      granted: false,
      grantOnRequest: false,
    );
    await tester.pumpWidget(await appUnderTest(phoneSource: source));
    await _settle(tester);
    await tester.tap(_tab('Contacts'));
    await _settle(tester);
    await tester.tap(find.text('Phone contacts'));
    await _settle(tester);
    expect(source.requests, 1);
    expect(find.text('Kim Bell'), findsNothing);
    expect(find.textContaining("Your phone's contacts aren't shown"), findsOne);
    // The shared phonebook still shows, marked as in the apps.
    expect(find.text('Westgate Supplies'), findsOneWidget);
    expect(find.text('In the apps'), findsWidgets);
    await tester.tap(find.text('Colleagues'));
    await _settle(tester);
    expect(find.text('Mia Rossi'), findsOneWidget);
    // Never asked a second time, even on the next opening.
    await tester.tap(find.text('Phone contacts'));
    await _settle(tester);
    expect(source.requests, 1);
  });

  testWidgets('nothing from the address book leaves the device', (
    tester,
  ) async {
    usePhone(tester);
    final api = FakeApi({
      'POST /history/seen': (_) => null,
      'GET /directory/shared-contacts': (_) => <Object>[],
    });
    final registered = <String>[];
    final source = FixedPhoneContacts(_book);
    await tester.pumpWidget(
      await appUnderTest(
        phoneSource: source,
        api: api,
        accessToken: 'tok',
        addressBook: registered.addAll,
      ),
    );
    await _settle(tester);
    // Overlay on Recents, the Phone contacts tab, a search.
    await tester.tap(_tab('Recents'));
    await _settle(tester);
    expect(find.text('Kim Bell'), findsOneWidget);
    await tester.tap(_tab('Contacts'));
    await _settle(tester);
    await tester.tap(find.text('Phone contacts'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'Rowan');
    await _settle(tester);
    expect(find.text('Dr Rowan Achebe'), findsOneWidget);

    final values = [
      'Kim Bell',
      'Kim',
      'Bell',
      'Rowan',
      'Achebe',
      '0491579999',
      '0491 579 999',
      '55501777',
    ];
    for (final r in api.requests) {
      final text = '${r.uri} ${r.headers} ${r.body}';
      for (final v in values) {
        expect(text.contains(v), isFalse, reason: '$v in $r');
      }
    }
    // Registered with the scrubber, so logs and crash reports drop them.
    expect(registered, containsAll(['Kim Bell', '03 5550 1142']));
    expect(registered, contains('Dr Rowan Achebe'));
    final scrubber = DiagnosticsScrubber()
      ..rememberAddressBookValues(registered);
    expect(scrubber.scrub('Called Kim Bell back'), isNot(contains('Kim Bell')));
  });
}

// The wide layout's shell: the switch at 600 dp of the window's width, the
// navigation rail (same tabs, badges and labels as the tab bar, own status
// at the bottom), and state kept when the window changes width (fold and
// unfold, rotation).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/api/export.dart';
import 'package:voiceplatform_app/net/api.dart' show MeUnavailable;
import 'package:voiceplatform_app/screens/contacts/contacts_screen.dart';
import 'package:voiceplatform_app/screens/me/me_pages.dart';
import 'package:voiceplatform_app/screens/recents/recents_screen.dart';
import 'package:voiceplatform_app/shell/layout.dart';
import 'package:voiceplatform_app/shell/me_failed_banner.dart';
import 'package:voiceplatform_app/shell/shell_status.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

/// The window at [size] dp, 2x, with the artboards' 47 px status bar.
void useWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.view.viewPadding = const FakeViewPadding(top: artboardStatusBar * 2);
  addTearDown(tester.view.reset);
}

/// Unfolds or folds: the same app, a new window size.
Future<void> resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 2;
  await tester.pumpAndSettle();
}

const unfolded = Size(884, 1030);
const phone = Size(390, 844);

Finder _rail(String label) =>
    find.descendant(of: find.byType(VpNavRail), matching: find.text(label));

List<String> _railLabels(WidgetTester tester) => [
  for (final t in AppTab.values)
    if (_rail(t.label).evaluate().isNotEmpty) t.label,
];

void main() {
  setUpAll(loadAppFonts);

  group('the switch', () {
    for (final (size, wide) in [
      (const Size(599, 900), false),
      (const Size(600, 900), true),
      (unfolded, true),
      (const Size(915, 412), true), // a 20:9 phone in landscape
      (const Size(360, 800), false),
      (const Size(412, 915), false),
      (const Size(368, 904), false), // a folding phone's cover screen
      (phone, false),
    ]) {
      testWidgets('${size.width.toInt()} x ${size.height.toInt()}: '
          '${wide ? 'rail' : 'tab bar'}', (tester) async {
        useWindow(tester, size);
        await tester.pumpWidget(await appUnderTest());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(VpNavRail), wide ? findsOneWidget : findsNothing);
        expect(find.byType(VpTabBar), wide ? findsNothing : findsOneWidget);
      });
    }

    test('the breakpoint is 600 dp', () {
      expect(wideLayoutMinWidth, 600);
    });

    test('no orientation or aspect-ratio lock in the manifest or code', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      for (final lock in [
        'screenOrientation',
        'maxAspectRatio',
        'minAspectRatio',
        'resizeableActivity="false"',
      ]) {
        expect(manifest, isNot(contains(lock)), reason: lock);
      }
      final code = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync());
      for (final c in code) {
        expect(c, isNot(contains('setPreferredOrientations')));
      }
    });
  });

  group('the rail', () {
    testWidgets('five items in order with the badges, Keypad active', (
      tester,
    ) async {
      useWindow(tester, unfolded);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(await appUnderTest());
      await tester.pumpAndSettle();
      expect(_railLabels(tester), [
        'Keypad',
        'Recents',
        'Contacts',
        'Messages',
        'Me',
      ]);
      expect(_rail('2'), findsOneWidget);
      expect(_rail('1'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Keypad').last),
        matchesSemantics(
          label: 'Keypad',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Recents, 2 new')),
        matchesSemantics(
          label: 'Recents, 2 new',
          isButton: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      expect(find.bySemanticsLabel('Messages, 1 unread'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('tapping an item opens its tab', (tester) async {
      useWindow(tester, unfolded);
      await tester.pumpWidget(await appUnderTest());
      await tester.pumpAndSettle();
      await tester.tap(_rail('Recents'));
      await tester.pumpAndSettle();
      expect(find.byType(RecentsScreen), findsOneWidget);
      await tester.tap(_rail('Contacts'));
      await tester.pumpAndSettle();
      expect(find.byType(ContactsScreen), findsOneWidget);
    });

    testWidgets('the same tab-set rule: no SMS line, no Messages', (
      tester,
    ) async {
      useWindow(tester, unfolded);
      await tester.pumpWidget(
        await appUnderTest(status: const ShellStatus(recentsBadge: 2)),
      );
      await tester.pumpAndSettle();
      expect(_railLabels(tester), ['Keypad', 'Recents', 'Contacts', 'Me']);
    });

    testWidgets('the same rule when /me fails with nothing known: four '
        'items and the banner beside the rail', (tester) async {
      useWindow(tester, unfolded);
      await tester.pumpWidget(
        await appUnderTest(
          status: null,
          me: () async => throw const MeUnavailable(),
        ),
      );
      await tester.pumpAndSettle();
      expect(_railLabels(tester), ['Keypad', 'Recents', 'Contacts', 'Me']);
      final banner = tester.getRect(find.byType(MeFailedBanner));
      final rail = tester.getRect(find.byType(VpNavRail));
      expect(banner.left, greaterThanOrEqualTo(rail.right));
    });

    testWidgets('own status: initials, Available, opens the status sheet', (
      tester,
    ) async {
      useWindow(tester, unfolded);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(await appUnderTest());
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(OwnStatus), matching: find.text('AN')),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byType(OwnStatus)),
        matchesSemantics(
          label: 'Your status: Available. Change',
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
      await tester.tap(find.byType(OwnStatus));
      await tester.pumpAndSettle();
      expect(find.text('Do not disturb'), findsOneWidget);
      expect(find.text('Away'), findsOneWidget);
    });

    testWidgets('own status: Do not disturb, and Offline', (tester) async {
      useWindow(tester, unfolded);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(await appUnderTest(myStatus: StatusStatus.dnd));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Your status: Do not disturb. Change'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('own status: Offline, nothing to change', (tester) async {
      useWindow(tester, unfolded);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(await appUnderTest(offline: true));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Your status: Offline'), findsOneWidget);
      handle.dispose();
    });

    for (final size in [unfolded, const Size(600, 900), const Size(915, 412)]) {
      testWidgets('text at 200% stays inside the rail, '
          '${size.width.toInt()} x ${size.height.toInt()}', (tester) async {
        useWindow(tester, size);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(await appUnderTest());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final rail = tester.getRect(find.byType(VpNavRail));
        expect(rail.width, VpNavRail.width);
        for (final label in ['Keypad', 'Recents', 'Contacts', 'Messages']) {
          final box = tester.renderObject<RenderBox>(_rail(label));
          final left = box.localToGlobal(Offset.zero).dx;
          final right = box.localToGlobal(box.size.bottomRight(Offset.zero)).dx;
          expect(left, greaterThanOrEqualTo(rail.left), reason: label);
          expect(right, lessThanOrEqualTo(rail.right - 1), reason: label);
        }
      });
    }
  });

  group('state across the switch', () {
    testWidgets('unfold and fold on a pushed page: still there', (
      tester,
    ) async {
      useWindow(tester, phone);
      await tester.pumpWidget(await appUnderTest());
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(VpTabBar), matching: find.text('Me')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text("When I don't answer"));
      await tester.pumpAndSettle();
      expect(find.byType(CallSettingsScreen), findsOneWidget);
      await resize(tester, unfolded);
      expect(find.byType(VpNavRail), findsOneWidget);
      expect(find.byType(CallSettingsScreen), findsOneWidget);
      await resize(tester, phone);
      expect(find.byType(VpTabBar), findsOneWidget);
      expect(find.byType(CallSettingsScreen), findsOneWidget);
    });

    testWidgets('half-typed search and the open tab survive unfold and fold', (
      tester,
    ) async {
      useWindow(tester, phone);
      await tester.pumpWidget(await appUnderTest());
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(VpTabBar),
          matching: find.text('Contacts'),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byType(ContactsScreen),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, 'Mi');
      await tester.pumpAndSettle();
      await resize(tester, unfolded);
      expect(find.byType(ContactsScreen), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, 'Mi');
      await resize(tester, const Size(368, 904));
      expect(find.byType(ContactsScreen), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, 'Mi');
    });

    testWidgets('a scrolled list keeps its place', (tester) async {
      useWindow(tester, const Size(390, 560));
      await tester.pumpWidget(await appUnderTest());
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(VpTabBar),
          matching: find.text('Recents'),
        ),
      );
      await tester.pumpAndSettle();
      final list = find
          .descendant(
            of: find.byType(RecentsScreen),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      await tester.drag(list, const Offset(0, -200));
      await tester.pumpAndSettle();
      final before = tester.state<ScrollableState>(list).position.pixels;
      expect(before, greaterThan(0));
      // Wider, same height (the fixture list would fit an 884 x 1030 screen
      // whole, leaving nothing to keep).
      await resize(tester, const Size(700, 560));
      expect(find.byType(VpNavRail), findsOneWidget);
      // Kept, not reset to the top; clamped only where the taller viewport
      // (no tab bar under it) leaves less to scroll.
      final after = tester.state<ScrollableState>(list).position;
      expect(after.pixels, greaterThan(0));
      expect(after.pixels, before.clamp(0, after.maxScrollExtent));
    });

    testWidgets('a half-typed number on the keypad survives', (tester) async {
      useWindow(tester, phone);
      await tester.pumpWidget(await appUnderTest());
      await tester.pumpAndSettle();
      for (final d in ['0', '3', '5']) {
        await tester.tap(find.text(d).first);
        await tester.pump();
      }
      await resize(tester, unfolded);
      await resize(tester, phone);
      expect(find.text('035'), findsOneWidget);
    });
  });
}

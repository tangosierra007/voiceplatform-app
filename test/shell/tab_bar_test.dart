import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/shell/shell_status.dart';
import 'package:voiceplatform_app/screens/keypad/keypad_screen.dart';
import 'package:voiceplatform_app/screens/me/me_screen.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

Finder _tab(String label) =>
    find.descendant(of: find.byType(VpTabBar), matching: find.text(label));

void main() {
  setUpAll(loadAppFonts);

  testWidgets('five tabs in order, Keypad active, badges 2 and 1', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest());
    await tester.pumpAndSettle();
    final labels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(VpTabBar),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .toList();
    expect(labels, [
      'Keypad',
      'Recents',
      '2',
      'Contacts',
      'Messages',
      '1',
      'Me',
    ]);
  });

  testWidgets('screen reader labels, selected state', (tester) async {
    usePhone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(await appUnderTest());
    await tester.pumpAndSettle();
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
    expect(find.bySemanticsLabel('Contacts'), findsWidgets);
    expect(find.bySemanticsLabel('Me'), findsWidgets);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('tapping a tab switches screens and the active tab', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest());
    await tester.pumpAndSettle();
    for (final label in ['Recents', 'Contacts', 'Messages', 'Me', 'Keypad']) {
      await tester.tap(_tab(label));
      await tester.pumpAndSettle();
      // Each heading names the tab; Keypad has none and Me shows who.
      if (label == 'Keypad') {
        expect(find.byType(KeypadScreen), findsOneWidget);
      } else if (label == 'Me') {
        expect(find.byType(MeScreen), findsOneWidget);
      } else {
        expect(
          find.descendant(
            of: find.byType(Scaffold).first,
            matching: find.text(label),
          ),
          findsNWidgets(2),
        );
      }
      final active = tester
          .widgetList<Semantics>(
            find.descendant(
              of: find.byType(VpTabBar),
              matching: find.byType(Semantics),
            ),
          )
          .where((s) => s.properties.selected == true)
          .map((s) => s.properties.label)
          .toList();
      expect(active.single, startsWith(label));
    }
  });

  testWidgets('Messages is hidden without an SMS line', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      await appUnderTest(status: const ShellStatus(recentsBadge: 2)),
    );
    await tester.pumpAndSettle();
    expect(_tab('Messages'), findsNothing);
    expect(_tab('Me'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(VpTabBar), matching: find.text('1')),
      findsNothing,
    );
  });

  testWidgets('no badge at zero, 99+ above 99', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      await appUnderTest(
        status: const ShellStatus(
          recentsBadge: 0,
          messagesBadge: 120,
          hasSmsLine: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(VpTabBar), matching: find.text('0')),
      findsNothing,
    );
    expect(find.text('99+'), findsOneWidget);
    expect(find.bySemanticsLabel('Messages, 120 unread'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('text at ${(scale * 100).round()}% stays inside the tab bar', (
      tester,
    ) async {
      usePhone(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(await appUnderTest());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final bar = tester.getRect(find.byType(VpTabBar));
      final slots = tester.widgetList<Expanded>(
        find.descendant(
          of: find.byType(VpTabBar),
          matching: find.byType(Expanded),
        ),
      );
      expect(slots, hasLength(5));
      for (final label in ['Keypad', 'Recents', 'Contacts', 'Messages', 'Me']) {
        final text = _tab(label);
        final r = tester.getRect(text);
        // Painted size after FittedBox scaling.
        final box = tester.renderObject<RenderBox>(text);
        final topLeft = box.localToGlobal(Offset.zero);
        final bottomRight = box.localToGlobal(
          box.size.bottomRight(Offset.zero),
        );
        expect(topLeft.dx, greaterThanOrEqualTo(bar.left), reason: label);
        expect(bottomRight.dx, lessThanOrEqualTo(bar.right), reason: label);
        expect(bottomRight.dy, lessThanOrEqualTo(bar.bottom), reason: label);
        expect(r.width, greaterThan(0));
        // Each label stays inside its own fifth of the bar.
        final slotWidth = (bar.width - 12) / 5;
        expect(
          bottomRight.dx - topLeft.dx,
          lessThanOrEqualTo(slotWidth + 0.01),
          reason: label,
        );
      }
    });
  }
}

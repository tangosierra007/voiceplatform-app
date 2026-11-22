// FU56 (A3, 11 Nov): at 200 % text the bottom tab labels ran together and
// the caller ID chip cut the number off.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/screens/keypad/keypad_screen.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

void _window(WidgetTester tester, Size size, double scale) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.view.viewPadding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pumpAndSettle();
}

/// Each tab label as drawn (after any scaling down), left to right.
List<Rect> _labelRects(WidgetTester tester) => [
  for (final t in AppTab.values)
    if (find
        .descendant(of: find.byType(VpTabBar), matching: find.text(t.label))
        .evaluate()
        .isNotEmpty)
      tester.getRect(
        find
            .ancestor(
              of: find.descendant(
                of: find.byType(VpTabBar),
                matching: find.text(t.label),
              ),
              matching: find.byType(FittedBox),
            )
            .first,
      ),
];

void main() {
  setUpAll(loadAppFonts);

  for (final width in [360.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('tab labels at $width dp and ${scale}x text stay apart', (
        tester,
      ) async {
        _window(tester, Size(width, 844), scale);
        await tester.pumpWidget(await appUnderTest());
        await _settle(tester);
        final rects = _labelRects(tester);
        expect(rects, hasLength(5));
        for (var i = 1; i < rects.length; i++) {
          expect(
            rects[i].left - rects[i - 1].right,
            greaterThanOrEqualTo(2 * tabLabelGutter - 0.01),
            reason: 'labels ${i - 1} and $i',
          );
        }
        expect(rects.first.left, greaterThanOrEqualTo(0));
        expect(rects.last.right, lessThanOrEqualTo(width));
      });
    }
  }

  for (final (width, scale) in [(390.0, 1.0), (390.0, 2.0), (360.0, 2.0)]) {
    testWidgets(
      'the caller ID chip never cuts its text at $width dp, ${scale}x',
      (tester) async {
        // 1030 dp tall at 200 %: at 844 the Keypad is short there (task
        // 401) and the caller ID is behind More, read in full.
        _window(tester, Size(width, scale == 1.0 ? 844 : 1030), scale);
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(await appUnderTest());
        await _settle(tester);
        final text = find.descendant(
          of: find.byType(CallerIdChip),
          matching: find.byType(Text),
        );
        expect(text, findsOneWidget);
        final shown = tester.widget<Text>(text).data!;
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: text, matching: find.byType(RichText)),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: shown);
        if (scale == 1.0) {
          expect(shown, startsWith('Calls show '));
        } else {
          // Too narrow for the whole line: just what calls show.
          expect(shown, isNot(startsWith('Calls show')));
        }
        // A screen reader still hears the whole line.
        expect(
          find.bySemanticsLabel(RegExp(r'^Calls show .+\. Change caller ID$')),
          findsOneWidget,
        );
        handle.dispose();
      },
    );
  }
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The artboards' phone: 390 x 844 logical pixels.
const phoneSize = Size(390, 844);

/// The artboards draw a 47 px status bar; the app gets it as top padding.
const artboardStatusBar = 47.0;

/// Loads the bundled Unbounded and Manrope so tests measure and draw with the
/// real fonts (flutter_test otherwise uses its box font).
Future<void> loadAppFonts() async {
  Future<ByteData> read(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());
  await (FontLoader(
    'Unbounded',
  )..addFont(read('assets/fonts/unbounded/Unbounded-Variable.ttf'))).load();
  await (FontLoader(
    'Manrope',
  )..addFont(read('assets/fonts/manrope/Manrope-Variable.ttf'))).load();
}

/// Sizes the test view as the artboard phone at [dpr].
void usePhone(WidgetTester tester, {double dpr = 2}) {
  tester.view.physicalSize = phoneSize * dpr;
  tester.view.devicePixelRatio = dpr;
  tester.view.padding = FakeViewPadding(top: artboardStatusBar * dpr);
  tester.view.viewPadding = FakeViewPadding(top: artboardStatusBar * dpr);
  addTearDown(tester.view.reset);
}

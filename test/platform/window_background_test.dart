import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/theme/tokens.g.dart';

/// The Android window behind Flutter (launch and normal theme) is
/// AppIncoming's ink, so a call opened over the lock screen from a cold start
/// never shows black or white before the first frame.
void main() {
  const res = 'android/app/src/main/res';

  test('the window colour is the ink token', () {
    final colors = File('$res/values/window_background.xml').readAsStringSync();
    final hex = RegExp(r'<color name="vp_window_ink">#([0-9A-Fa-f]{6})</color>')
        .firstMatch(colors)!
        .group(1)!;
    expect(int.parse('FF$hex', radix: 16), VpPalette.ink900.toARGB32());
  });

  test('launch and normal themes use it, day and night', () {
    for (final f in ['values/styles.xml', 'values-night/styles.xml']) {
      final xml = File('$res/$f').readAsStringSync();
      for (final theme in ['LaunchTheme', 'NormalTheme']) {
        final style = RegExp(
          '<style name="$theme"[^>]*>(.*?)</style>',
          dotAll: true,
        ).firstMatch(xml)!.group(1)!;
        expect(
          style,
          contains(
            '<item name="android:windowBackground">@color/vp_window_ink</item>',
          ),
          reason: '$f $theme',
        );
      }
    }
  });
}

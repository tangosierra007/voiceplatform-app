import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/gen_theme.dart' as gen;

void main() {
  test('lib/theme/tokens.g.dart matches design/tokens.json (run dart run tool/gen_theme.dart)', () {
    final expected = gen.generateTokens(
      File(gen.tokensPath).readAsStringSync(),
    );
    final actual = File(gen.outputPath)
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(
      actual,
      expected,
      reason: 'Generated theme is stale: run `dart run tool/gen_theme.dart`',
    );
  });

  test('design/tokens.json is the design system copy, light and dark', () {
    final src = File(gen.tokensPath).readAsStringSync();
    expect(src, contains('"id": "light"'));
    expect(src, contains('"id": "dark"'));
    expect(src, contains('"value": "#ea7500"'));
  });
}

import 'dart:io';

import 'package:test/test.dart';

// The package must stay byte-identical to the lead-owned contract.
void main() {
  test('lib/call_engine.dart matches contracts/call_engine.dart', () {
    final pkg = File('lib/call_engine.dart').readAsStringSync();
    final contract = File('../../contracts/call_engine.dart').readAsStringSync();
    expect(pkg, contract);
  });
}
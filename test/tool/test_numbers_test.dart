// Keeps arbitrary13Number (test/support/test_numbers.dart) to TJ's rule: one
// constant, matched by the call_engine package's copy, allowed by the phone
// number check in those two files only, and never outside tests.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/phone_numbers/allow_list.dart';
import '../../tool/phone_numbers/phone_numbers.dart';
import '../support/test_numbers.dart';

const _app = 'test/support/test_numbers.dart';
const _package = 'packages/call_engine/test/support/test_numbers.dart';

// Where the number must never be: app code, the mock server, bundled assets,
// store material, and the golden tests (screenshots).
const _forbidden = [
  'lib/',
  'tool/mock_server/',
  'assets/',
  'docs/store/',
  'test/goldens/',
  'android/',
  'integration_test/',
];

bool _isForbidden(String path) =>
    _forbidden.any(path.startsWith) ||
    RegExp(r'^packages/[^/]+/lib/').hasMatch(path); // packages' own code

final _digits = arbitrary13Number.replaceAll(' ', '');

List<String> _tracked() {
  final r = Process.runSync('git', ['ls-files', '-z']);
  return (r.stdout as String).split('\x00').where((p) => p.isNotEmpty).toList();
}

void main() {
  test('is a 13 number and not an ACMA fictional number', () {
    final hits = findAuPhoneNumbers(arbitrary13Number);
    expect(hits.single.kind, AuNumberKind.localRateShort);
    expect(hits.single.isFictional, isFalse);
  });

  test("the call_engine package's copy matches", () {
    final copy = File(_package).readAsStringSync();
    final m = RegExp(r"const arbitrary13Number = '([^']*)';").firstMatch(copy);
    expect(m?.group(1), arbitrary13Number);
  });

  test('the phone number check allows it in exactly the two files', () {
    final key = allowKey(_digits);
    final entries = File('tool/phone_numbers/allow_list.txt')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .where((l) => l.split(RegExp(r'\s+'))[1] == key)
        .map((l) => l.split(RegExp(r'\s+'))[0])
        .toList();
    expect(entries, unorderedEquals([_app, _package]));
    final list = AllowList.parse(
      File('tool/phone_numbers/allow_list.txt').readAsStringSync(),
    );
    expect(list.allows('test/calls/x_test.dart', _digits), isFalse);
  });

  test('never in code, mock server, assets, store, goldens (_forbidden)', () {
    final bad = <String>[];
    for (final path in _tracked()) {
      if (!_isForbidden(path)) continue;
      final f = File(path);
      if (!f.existsSync()) continue;
      final bytes = f.readAsBytesSync();
      if (bytes.take(8192).contains(0)) continue; // binary
      final lines = String.fromCharCodes(bytes).split('\n');
      for (var n = 0; n < lines.length; n++) {
        final l = lines[n];
        if (l.contains('arbitrary13Number') ||
            findAuPhoneNumbers(l).any((h) => h.national == _digits)) {
          bad.add('$path:${n + 1}');
        }
      }
    }
    expect(bad, isEmpty);
  });
}

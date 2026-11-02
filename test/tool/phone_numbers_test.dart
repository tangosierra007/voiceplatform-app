// Tests for tool/check_phone_numbers.dart and tool/phone_numbers/.
//
// Real-looking numbers are built at run time from parts (_n), so this file
// never holds one and the check passes over its own source. The ACMA
// fictional numbers are written out in full: they are allowed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/phone_numbers/allow_list.dart';
import '../../tool/phone_numbers/phone_numbers.dart';

/// Joins [parts] into one string at run time.
String _n(List<String> parts) => parts.join();

// Made-up numbers outside ACMA's lists, built from parts. Each is a valid
// shape for its kind; none is known to belong to anyone.
final _mobile = _n(['04', '12', ' 345 ', '678']);
final _mobileTight = _n(['04', '12', '345', '678']);
final _geo = _n(['(02)', ' 9', '876 ', '5432']);
final _local = _n(['13', '00 ', '123 ', '456']);
final _free = _n(['18', '00 ', '123 ', '456']);
final _short13 = _n(['13 ', '24 ', '68']);

List<String> _found(String line) =>
    findRealAuPhoneNumbers(line).map((h) => h.national).toList();

void main() {
  group('finds real numbers', () {
    test('mobiles with any separator', () {
      for (final sep in ['', ' ', '.', '-']) {
        final s = _n(['04', '12', sep, '345', sep, '678']);
        expect(_found('call $s now'), [_mobileTight], reason: 'sep "$sep"');
      }
      expect(_found(_n(['0412', ' 345', '678'])), [_mobileTight]);
    });

    test('E.164 and bare 61 forms map to the national number', () {
      for (final s in [
        _n(['+61', ' 412 ', '345 ', '678']),
        _n(['+61', '412', '345', '678']),
        _n(['+61', '-412-', '345-', '678']),
        _n(['+61', ' (0)', '412 ', '345 ', '678']),
        _n(['61', '412', '345', '678']),
      ]) {
        expect(_found('"$s"'), [_mobileTight], reason: s);
      }
      expect(_found(_n(['+61', ' 2 ', '9876 ', '5432'])), [
        _n(['02', '9876', '5432']),
      ]);
    });

    test('geographic numbers in 02 03 07 08, with or without brackets', () {
      expect(_found(_geo), [
        _n(['02', '9876', '5432']),
      ]);
      for (final a in ['03', '07', '08']) {
        expect(_found(_n([a, ' 9876', ' 5432'])), [
          _n([a, '9876', '5432']),
        ]);
        expect(_found(_n([a, '.9876', '.5432'])), hasLength(1));
      }
    });

    test('1300, 1800 and 13 numbers', () {
      expect(_found(_local), [
        _n(['1300', '123456']),
      ]);
      expect(_found(_free), [
        _n(['1800', '123456']),
      ]);
      expect(_found(_short13), [
        _n(['13', '2468']),
      ]);
      expect(_found(_n(['13', ' 2468'])), [
        _n(['13', '2468']),
      ]);
    });

    test('several numbers on one line, and the kind of each', () {
      final hits = findRealAuPhoneNumbers('$_mobile or $_geo or $_free');
      expect(hits.map((h) => h.kind), [
        AuNumberKind.mobile,
        AuNumberKind.geographic,
        AuNumberKind.freephone,
      ]);
    });

    test('just outside the ACMA lists', () {
      expect(_found(_n(['0491 ', '570 ', '007'])), hasLength(1));
      expect(
        _found(_n(['0491 ', '579 ', '999'])),
        hasLength(1),
        reason: 'ACMA lists single mobiles, not a 570 006 to 579 999 range',
      );
      expect(_found(_n(['02 ', '5551 ', '0000'])), hasLength(1));
      expect(
        _found(_n(['04 ', '5550 ', '1234'])),
        hasLength(1),
        reason: '5550 blocks are geographic only',
      );
      expect(_found(_n(['1800 ', '975 ', '712'])), hasLength(1));
      expect(_found(_n(['1300 ', '160 ', '401'])), hasLength(1));
      expect(
        _found(_n(['1900 ', '654 ', '321'])),
        isEmpty,
        reason: '190x numbers are not scanned',
      );
    });
  });

  group('allows ACMA fictional numbers', () {
    test('geographic 5550 and 7010 blocks in every area code', () {
      for (final s in [
        '02 5550 1234',
        '(03) 7010 0000',
        '07 5550 9999',
        '08 7010 4321',
        '+61 2 5550 1234',
        '61370109999',
      ]) {
        expect(_found(s), isEmpty, reason: s);
        expect(findAuPhoneNumbers(s), hasLength(1), reason: s);
      }
    });

    test('the listed mobiles', () {
      for (final s in [
        '0491 570 006',
        '0491 570 110',
        '0491571266',
        '+61 491 579 455',
        '0491-578-888',
      ]) {
        expect(_found(s), isEmpty, reason: s);
      }
    });

    test('the listed freephone and local rate numbers', () {
      for (final s in [
        '1800 160 401',
        '1800 975 707',
        '1800 975 711',
        '1300 975 707',
        '1300 975 711',
      ]) {
        expect(_found(s), isEmpty, reason: s);
      }
    });

    test('isAcmaFictional matches national digits', () {
      expect(isAcmaFictional('0255501234'), isTrue);
      expect(isAcmaFictional('0491570006'), isTrue);
      expect(isAcmaFictional(_mobileTight), isFalse);
    });
  });

  group('ignores what is not a phone number', () {
    test('emergency and short codes', () {
      for (final s in ['000', '112', '106', 'dial 000 now', '*121#']) {
        expect(findAuPhoneNumbers(s), isEmpty, reason: s);
      }
    });

    test('digits inside words, versions, IDs and dates', () {
      for (final s in [
        _n(['abc', '04', '12345678']),
        _n(['04', '12345678', 'ff']),
        _n(['1.2.', '04', '12345678']),
        _n(['04', '12345678', '.3']),
        _n(['id_', '04', '12345678']),
        _n(['99', '04', '12345678']),
        _n(['04', '12345678', '99']),
        '13-05-26',
        '2026-11-02',
        '130526',
        'sha256:9f8e7d6c5b4a',
      ]) {
        expect(findAuPhoneNumbers(s), isEmpty, reason: s);
      }
    });
  });

  group('masking', () {
    test('keeps the prefix, the last three digits and the spacing', () {
      expect(maskNumber(_mobile), '04xx xxx 678');
      expect(maskNumber(_mobileTight), '04xxxxx678');
      expect(
        maskNumber(_n(['+61', ' 412 ', '345 ', '678'])),
        '+61 4xx xxx 678',
      );
      expect(maskNumber(_geo), '(02) xxxx x432');
      expect(maskNumber(_free), '1800 xxx 456');
      expect(maskNumber(_short13), '13 xx 68');
    });

    test('a hit masks itself', () {
      final h = findRealAuPhoneNumbers('x $_mobile y').single;
      expect(h.masked, '04xx xxx 678');
      expect(h.text, _mobile);
    });
  });

  group('allow-list', () {
    test('allows a key for its path only', () {
      final key = allowKey(_mobileTight);
      final list = AllowList.parse('# comment\n\nlib/a.dart $key # an ID\n');
      expect(list.allows('lib/a.dart', _mobileTight), isTrue);
      expect(list.allows('lib/b.dart', _mobileTight), isFalse);
      expect(list.allows('lib/a.dart', _n(['04', '12345679'])), isFalse);
    });

    test('every entry needs a reason and a 16 hex key', () {
      final key = allowKey(_mobileTight);
      expect(() => AllowList.parse('lib/a.dart $key\n'), throwsFormatException);
      expect(
        () => AllowList.parse('lib/a.dart abc # why\n'),
        throwsFormatException,
      );
    });

    test('the repo allow-list parses', () {
      final f = File('tool/phone_numbers/allow_list.txt');
      expect(() => AllowList.parse(f.readAsStringSync()), returnsNormally);
    });
  });

  group('check_phone_numbers CLI', () {
    final tool = File('tool/check_phone_numbers.dart').absolute.path;
    late Directory repo;

    Future<ProcessResult> git(List<String> args) => Process.run('git', [
      '-c', 'user.name=test', //
      '-c', 'user.email=test@users.noreply.github.com',
      '-c', 'commit.gpgsign=false',
      ...args,
    ], workingDirectory: repo.path);

    Future<ProcessResult> check(List<String> args) => Process.run(
      'dart',
      [tool, ...args],
      workingDirectory: repo.path,
      runInShell: Platform.isWindows,
    );

    setUp(() async {
      repo = await Directory.systemTemp.createTemp('phone_numbers_');
      await git(['init', '-q']);
    });

    tearDown(() => repo.delete(recursive: true));

    test('passes a tree with only ACMA numbers', () async {
      File('${repo.path}/a.md')
          .writeAsStringSync('Call 0491 570 006 or 02 5550 1234.\n');
      await git(['add', '.']);
      final r = await check([]);
      expect(r.exitCode, 0, reason: '${r.stdout}');
    });

    test(
      'fails with file, line and the masked number, never in full',
      () async {
        File('${repo.path}/a.md')
            .writeAsStringSync('fine\nCall $_mobile today.\n');
        File('${repo.path}/b.png').writeAsStringSync('$_mobile\n');
        await git(['add', '.']);
        final r = await check([]);
        expect(r.exitCode, 1);
        expect(
          r.stdout,
          contains(
            'a.md:2: real Australian mobile number '
            '04xx xxx 678',
          ),
        );
        expect(r.stdout, isNot(contains('b.png')));
        expect(r.stdout, isNot(contains(_mobile)));
        expect(r.stdout, isNot(contains(_mobileTight)));
      },
    );

    test('checks commit messages and added lines in a range', () async {
      File('${repo.path}/a.md').writeAsStringSync('ok\n');
      await git(['add', '.']);
      await git(['commit', '-q', '-m', 'base']);
      File('${repo.path}/a.md').writeAsStringSync('ok\n$_geo\n');
      await git(['add', '.']);
      await git(['commit', '-q', '-m', 'Ring $_free\n\nthen $_mobile']);
      File('${repo.path}/a.md').writeAsStringSync('ok\n');
      await git(['commit', '-q', '-am', 'remove it']);

      final tree = await check([]);
      expect(tree.exitCode, 0, reason: 'the tree is clean again');

      final r = await check(['--commits', 'HEAD~2..HEAD']);
      expect(r.exitCode, 1);
      final out = r.stdout as String;
      expect(out, contains('message:1: real Australian 1800 number'));
      expect(out, contains('message:3: real Australian mobile number'));
      expect(
        out,
        contains(
          ' a.md:2: real Australian geographic number '
          '(02) xxxx x432',
        ),
      );
      expect(out, isNot(contains(_geo)));
    });

    test('checks a text file such as a pull request description', () async {
      final body = File('${repo.path}/body.txt')
        ..writeAsStringSync('Tested on $_mobile.\n');
      final r = await check(['--text', 'PR description=${body.path}']);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('PR description:1:'));
    });

    test('an allow-list entry silences its hit', () async {
      File('${repo.path}/a.md').writeAsStringSync('$_mobile\n');
      File('${repo.path}/allow.txt').writeAsStringSync(
        'a.md ${allowKey(_mobileTight)} # a made-up build ID\n',
      );
      await git(['add', 'a.md']);
      final r = await check(['--allow', 'allow.txt']);
      expect(r.exitCode, 0, reason: '${r.stdout}');
    });
  });
}

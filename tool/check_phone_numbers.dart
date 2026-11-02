// Fails when a real Australian phone number (anything outside ACMA's
// fictional numbers) is in the repo: tracked files, commit messages, lines
// added by commits, or a given text such as a pull request description.
//
//   dart tool/check_phone_numbers.dart                 # tracked files
//   dart tool/check_phone_numbers.dart --commits origin/main..HEAD
//   dart tool/check_phone_numbers.dart --text "PR description=body.txt"
//   dart tool/check_phone_numbers.dart --print-allow-keys   # local only
//
// Options combine; with none, it scans the tracked files. Every hit is
// printed masked (04xx xxx 123), never in full. Exit code 1 when a hit is
// found, 2 on a usage or git error.
//
// The rules and the allow-list are in tool/phone_numbers/. Only dart:
// libraries are used, so `dart tool/check_phone_numbers.dart` runs without
// `pub get`.

import 'dart:convert';
import 'dart:io';

import 'phone_numbers/allow_list.dart';
import 'phone_numbers/phone_numbers.dart';

const _defaultAllowList = 'tool/phone_numbers/allow_list.txt';

// Never scanned as text: images, fonts, archives, audio and other binaries.
// Files with a NUL byte in their first 8 KB are skipped too.
final _binaryExt = RegExp(
  r'\.(png|jpe?g|gif|webp|ico|bmp|ttf|otf|woff2?|zip|gz|jar|aar|apk|aab|so|'
  r'a|wav|mp3|ogg|opus|m4a|flac|pdf|keystore|jks|class|dex|bin)$',
  caseSensitive: false,
);

class _Finding {
  _Finding(this.where, this.line, this.hit, {this.path});
  final String where; // "lib/a.dart" or "commit abc1234 lib/a.dart"
  final String? path; // for the allow-list and annotations
  final int line;
  final PhoneHit hit;
}

Future<void> main(List<String> args) async {
  var tree = false;
  final ranges = <String>[];
  final texts = <String, String>{};
  var allowPath = _defaultAllowList;
  var printKeys = false;

  for (var i = 0; i < args.length; i++) {
    String next() {
      if (i + 1 >= args.length) _usage('${args[i]} needs a value');
      return args[++i];
    }

    switch (args[i]) {
      case '--tree':
        tree = true;
      case '--commits':
        ranges.add(next());
      case '--text':
        final v = next();
        final eq = v.indexOf('=');
        if (eq < 1) _usage('--text takes <label>=<file>');
        texts[v.substring(0, eq)] = v.substring(eq + 1);
      case '--allow':
        allowPath = next();
      case '--print-allow-keys':
        printKeys = true;
      case '-h' || '--help':
        _usage(null);
      default:
        _usage('unknown option ${args[i]}');
    }
  }
  if (!tree && ranges.isEmpty && texts.isEmpty) tree = true;

  final allow = AllowList.parse(
    File(allowPath).existsSync() ? File(allowPath).readAsStringSync() : '',
  );
  final findings = <_Finding>[];

  if (tree) findings.addAll(await _scanTree());
  for (final r in ranges) {
    findings.addAll(await _scanCommits(r));
  }
  texts.forEach((label, file) {
    final lines = File(file).readAsStringSync().split('\n');
    for (var n = 0; n < lines.length; n++) {
      for (final h in findRealAuPhoneNumbers(lines[n])) {
        findings.add(_Finding(label, n + 1, h));
      }
    }
  });

  final kept = findings
      .where((f) => !allow.allows(f.path ?? f.where, f.hit.national))
      .toList();
  final gha = Platform.environment['GITHUB_ACTIONS'] == 'true';
  for (final f in kept) {
    final msg =
        'real Australian ${f.hit.kind.label} number '
        '${f.hit.masked} (not an ACMA fictional number)';
    stdout.writeln('${f.where}:${f.line}: $msg');
    if (printKeys) {
      stdout.writeln(
        '    allow-list key: ${f.path ?? f.where} '
        '${allowKey(f.hit.national)}',
      );
    }
    if (gha) {
      final file = f.where == f.path ? 'file=${f.path},line=${f.line},' : '';
      stdout.writeln(
        '::error ${file}title=Real phone number::'
        '${f.where}:${f.line}: $msg',
      );
    }
  }
  if (kept.isEmpty) {
    stdout.writeln('No real Australian phone numbers found.');
    exit(0);
  }
  stdout.writeln(
    '\n${kept.length} real Australian phone number(s) found. '
    'Use ACMA fictional numbers (see README.md, Test data).',
  );
  exit(1);
}

Future<List<_Finding>> _scanTree() async {
  final ls = await _git(['ls-files', '-z']);
  final out = <_Finding>[];
  for (final path in ls.split('\x00').where((p) => p.isNotEmpty)) {
    if (_binaryExt.hasMatch(path)) continue;
    final f = File(path);
    if (!f.existsSync()) continue; // deleted in the work tree
    final bytes = f.readAsBytesSync();
    final head = bytes.length < 8192 ? bytes : bytes.sublist(0, 8192);
    if (head.contains(0)) continue;
    final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
    for (var n = 0; n < lines.length; n++) {
      for (final h in findRealAuPhoneNumbers(lines[n])) {
        out.add(_Finding(path, n + 1, h, path: path));
      }
    }
  }
  return out;
}

/// Commit messages and added lines of every commit in [range].
Future<List<_Finding>> _scanCommits(String range) async {
  final out = <_Finding>[];

  final log = await _git(['log', '--no-color', '--format=%x1e%h%x1f%B', range]);
  for (final rec in log.split('\x1e').where((r) => r.contains('\x1f'))) {
    final sep = rec.indexOf('\x1f');
    final hash = rec.substring(0, sep);
    final lines = rec.substring(sep + 1).split('\n');
    for (var n = 0; n < lines.length; n++) {
      for (final h in findRealAuPhoneNumbers(lines[n])) {
        out.add(
          _Finding('commit $hash message', n + 1, h, path: 'commit:$hash'),
        );
      }
    }
  }

  final patch = await _git([
    'log', '-p', '-U0', '--no-color', '--no-ext-diff', '--no-renames',
    '--format=%x1e%h', range, //
  ]);
  String? hash;
  String? path;
  var line = 0;
  final hunk = RegExp(r'^@@ -\S+ \+(\d+)');
  for (final l in patch.split('\n')) {
    if (l.startsWith('\x1e')) {
      hash = l.substring(1).trim();
      path = null;
    } else if (l.startsWith('+++ ')) {
      path = l == '+++ /dev/null' ? null : l.substring(6);
    } else if (l.startsWith('@@')) {
      line = int.parse(hunk.firstMatch(l)?.group(1) ?? '0');
    } else if (l.startsWith('+') && path != null) {
      if (!_binaryExt.hasMatch(path)) {
        for (final h in findRealAuPhoneNumbers(l.substring(1))) {
          out.add(_Finding('commit $hash $path', line, h, path: path));
        }
      }
      line++;
    }
  }
  return out;
}

Future<String> _git(List<String> args) async {
  final r = await Process.run(
    'git',
    args,
    stdoutEncoding: const Utf8Codec(allowMalformed: true),
  );
  if (r.exitCode != 0) {
    stderr.writeln('git ${args.first} failed: ${r.stderr}');
    exit(2);
  }
  return r.stdout as String;
}

Never _usage(String? error) {
  if (error != null) stderr.writeln('check_phone_numbers: $error');
  stderr.writeln(
    'usage: dart tool/check_phone_numbers.dart [--tree] '
    '[--commits <range>]... [--text <label>=<file>]... [--allow <file>] '
    '[--print-allow-keys]',
  );
  exit(error == null ? 0 : 2);
}

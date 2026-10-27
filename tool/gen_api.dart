// Regenerates the API client in lib/api/ from contracts/app-api.openapi.yaml.
//
//   dart run tool/gen_api.dart
//
// 1. Reads the contract and names its inline enum parameters (see
//    [normaliseContract]); writes the result to .dart_tool/vp_api/ as JSON.
// 2. swagger_parser (options in tool/api/swagger_parser.yaml) writes the
//    Retrofit clients and json_serializable models.
// 3. build_runner writes their .g.dart parts.
//
// Never edit lib/api/ by hand; change the contract (through mobile-lead) and
// run this again. Hand-written code that uses the client lives in lib/net/.
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const contractPath = 'contracts/app-api.openapi.yaml';
const normalisedPath = '.dart_tool/vp_api/app-api.openapi.json';
const configPath = 'tool/api/swagger_parser.yaml';

Future<void> main() async {
  final contract = loadYaml(File(contractPath).readAsStringSync());
  final normalised = normaliseContract(
    _plain(contract) as Map<String, Object?>,
  );
  File(normalisedPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(normalised));

  final api = Directory('lib/api');
  if (api.existsSync()) api.deleteSync(recursive: true);
  await _run(['run', 'swagger_parser', '-f', configPath]);
  await _run(['run', 'build_runner', 'build', '--delete-conflicting-outputs']);
  _silenceGeneratorWarnings(api);
}

/// swagger_parser names an inline enum parameter after the parameter alone,
/// so `GET /voicemail/messages?status=` became a `Status` enum that replaced
/// the contract's `Status` schema. Each inline enum parameter is given a
/// component schema named after its path and parameter instead (for example
/// `VoicemailMessagesStatus`). Only names change; the wire format is the same.
Map<String, Object?> normaliseContract(Map<String, Object?> doc) {
  final components = (doc['components'] as Map<String, Object?>?) ?? {};
  final schemas = (components['schemas'] as Map<String, Object?>?) ?? {};
  final byValues = <String, String>{};
  final paths = doc['paths'] as Map<String, Object?>;
  for (final MapEntry(key: path, value: item) in paths.entries) {
    for (final op in (item as Map<String, Object?>).values) {
      if (op is! Map<String, Object?>) continue;
      for (final p in (op['parameters'] as List<Object?>?) ?? const []) {
        if (p is! Map<String, Object?>) continue;
        final schema = p['schema'];
        if (schema is! Map<String, Object?> || schema['enum'] == null) continue;
        final key = '${p['name']}:${jsonEncode(schema['enum'])}';
        final name = byValues[key] ??= _pascal([
          for (final seg in path.split('/'))
            if (seg.isNotEmpty && !seg.startsWith('{')) seg,
          p['name'] as String,
        ]);
        final defaultValue = schema['default'];
        schemas.putIfAbsent(name, () => {...schema}..remove('default'));
        p['schema'] = {
          r'$ref': '#/components/schemas/$name',
          'default': ?defaultValue,
        };
      }
    }
  }
  components['schemas'] = schemas;
  doc['components'] = components;
  return doc;
}

String _pascal(List<String> words) => words
    .expand((w) => w.split(RegExp(r'[-_]')))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join();

Object? _plain(Object? y) => switch (y) {
  YamlMap m => {for (final e in m.entries) '${e.key}': _plain(e.value)},
  YamlList l => [for (final v in l) _plain(v)],
  _ => y,
};

/// swagger_parser's enums carry casts the analyzer flags; its own
/// `ignore_for_file` line covers lints only, so the warning is added to it.
void _silenceGeneratorWarnings(Directory api) {
  const marker = '// ignore_for_file: type=lint';
  for (final f in api.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final src = f.readAsStringSync();
    if (src.contains(marker) && !src.contains('unnecessary_cast')) {
      f.writeAsStringSync(
        src.replaceFirst(marker, '$marker, unnecessary_cast'),
      );
    }
  }
}

Future<void> _run(List<String> args) async {
  final p = await Process.start(
    Platform.resolvedExecutable,
    args,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await p.exitCode;
  if (code != 0) {
    stderr.writeln('dart ${args.join(' ')} failed with $code');
    exit(code);
  }
}

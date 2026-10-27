import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vp_linphone/vp_linphone.dart';

/// Serves the licenses/ folder the way the APK's asset bundle does.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    const prefix = 'packages/vp_linphone/';
    if (!key.startsWith(prefix)) throw FlutterError('not an asset of this package: $key');
    final bytes = File(key.substring(prefix.length)).readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final onDisk = [
    for (final f in Directory('licenses').listSync(recursive: true).whereType<File>())
      f.path.replaceAll(r'\', '/').substring('licenses/'.length),
  ]..sort();
  final listed = [for (final l in bundledLicences) ...l.files]..sort();

  test('every licence file is listed, and every listed file exists and is not empty', () {
    expect(listed, onDisk);
    for (final f in onDisk) {
      expect(File('licenses/$f').lengthSync(), greaterThan(100), reason: f);
    }
  });

  test('every licences/ folder is a declared asset', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final dir in onDisk.map((f) => f.split('/').first).toSet()) {
      expect(pubspec, contains('    - licenses/$dir/'), reason: dir);
    }
  });

  test('NOTICE names every component and every licence file', () {
    final notice = File('../../NOTICE').readAsStringSync();
    for (final l in bundledLicences) {
      for (final f in l.files) {
        expect(notice, contains('packages/vp_linphone/licenses/$f'), reason: f);
      }
    }
    for (final l in bundledLicences.where((l) => l.files.isEmpty)) {
      expect(notice, contains(l.name.split(' (').first), reason: l.name);
    }
  });

  test('addVpLinphoneLicenses puts one entry per component in the LicenseRegistry', () async {
    LicenseRegistry.reset();
    addVpLinphoneLicenses(bundle: _DiskBundle());
    final entries = await LicenseRegistry.licenses.toList();
    expect(entries.length, bundledLicences.length);
    final opus = entries.firstWhere((e) => e.packages.first.startsWith('opus'));
    expect(opus.paragraphs.map((p) => p.text).join(' '), contains('Redistribution and use in source and binary forms'));
    final gsm = entries.firstWhere((e) => e.packages.first.startsWith('GSM'));
    expect(gsm.paragraphs.map((p) => p.text).join(' '), contains('could not be obtained'));
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vp_linphone/vp_linphone.dart' show packCallLog;

import '../auth/auth.dart' show clockProvider;
import '../engine/engine_provider.dart' show appResumesProvider;
import '../net/api.dart';
import '../theme/theme_preference.dart';

/// How long a licence refusal's diagnostic stays on the phone (Q364-1, TJ
/// 22 Nov).
const refusalDiagnosticMaxAge = Duration(days: 7);

/// At most this many are kept, the newest: a refusal loop can't grow it.
const refusalDiagnosticMaxRecords = 5;

/// One licence refusal, as kept for support (Q364-1): the time, the refusal
/// code and the app version, and nothing else. No number, name, extension,
/// SIP address, token or call log.
final class RefusalDiagnostic {
  const RefusalDiagnostic({
    required this.at,
    required this.code,
    required this.appVersion,
  });

  final DateTime at;
  final String code;
  final String appVersion;

  Map<String, String> toJson() => {
    // ISO 8601 with separators: no long digit run that could read as a
    // phone number to a scrubber.
    'at': at.toUtc().toIso8601String(),
    'code': code,
    'appVersion': appVersion,
  };

  static RefusalDiagnostic? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['at']}');
    final code = json['code'];
    final version = json['appVersion'];
    if (at == null || code is! String || version is! String) return null;
    return RefusalDiagnostic(
      at: at.toUtc(),
      code: safeRefusalCode(code),
      appVersion: safeAppVersion(version),
    );
  }

  /// The line support sees at the top of the uploaded log.
  String get logLine =>
      'licence refusal at ${at.toUtc().toIso8601String()}: code $code, '
      'app $appVersion';

  /// What the person sees before it is sent, in the phone's time.
  String get shown {
    final l = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Licence refused ${l.day} ${months[l.month - 1]} ${l.year} at '
        '${two(l.hour)}:${two(l.minute)}, code $code, app $appVersion';
  }
}

/// A refusal code as the API sends it (`licence_basic`); anything else is
/// kept as `unknown`, so no free text reaches the phone's storage.
String safeRefusalCode(String code) =>
    RegExp(r'^[a-z_]{1,40}$').hasMatch(code) ? code : 'unknown';

/// An app version such as `1.0.6`; anything else is kept as `unknown`.
String safeAppVersion(String v) =>
    RegExp(r'^[0-9A-Za-z.+-]{1,20}$').hasMatch(v) ? v : 'unknown';

/// Keeps the licence refusal diagnostics (Q364-1). They outlive the
/// refusal's own sign-out (written after its wipe); a later sign-out wipes
/// them with the other settings, and they go after 7 days, or once sent.
class RefusalDiagnosticStore {
  RefusalDiagnosticStore(this._prefs, this._now, this._appVersion);

  static const key = 'vp.licenceRefusalDiagnostics';

  final SharedPreferences _prefs;
  final DateTime Function() _now;
  final String _appVersion;

  /// A refusal: one record with the time, [code] and the app version.
  Future<void> record(String code) async {
    final kept = _fresh(_load())
      ..add(
        RefusalDiagnostic(
          at: _now().toUtc(),
          code: safeRefusalCode(code),
          appVersion: safeAppVersion(_appVersion),
        ),
      );
    final newest = kept.length > refusalDiagnosticMaxRecords
        ? kept.sublist(kept.length - refusalDiagnosticMaxRecords)
        : kept;
    await _save(newest);
  }

  /// The records under 7 days old, oldest first; older ones are deleted.
  Future<List<RefusalDiagnostic>> read() async {
    await purge();
    return _load();
  }

  /// Deletes every record 7 days old or more (on each app start and wake).
  Future<void> purge() async {
    final all = _load();
    final kept = _fresh(all);
    if (kept.length == all.length && _prefs.getString(key) == _encode(kept)) {
      return;
    }
    await _save(kept);
  }

  /// Deletes them all (after they were sent).
  Future<void> clear() => _prefs.remove(key);

  List<RefusalDiagnostic> _fresh(List<RefusalDiagnostic> all) {
    final now = _now().toUtc();
    return [
      for (final d in all)
        if (now.difference(d.at) < refusalDiagnosticMaxAge &&
            // A time ahead of the clock (the clock went back) can't stretch
            // the 7 days.
            !d.at.isAfter(now.add(const Duration(minutes: 5))))
          d,
    ];
  }

  List<RefusalDiagnostic> _load() {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [for (final j in list) ?RefusalDiagnostic.fromJson(j)];
    } catch (_) {
      return [];
    }
  }

  String _encode(List<RefusalDiagnostic> l) =>
      jsonEncode([for (final d in l) d.toJson()]);

  Future<void> _save(List<RefusalDiagnostic> l) async {
    if (l.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, _encode(l));
    }
  }
}

final refusalDiagnosticsProvider = Provider<RefusalDiagnosticStore>(
  (ref) => RefusalDiagnosticStore(
    ref.read(sharedPreferencesProvider),
    ref.read(clockProvider),
    ref.read(apiConfigProvider).appVersion,
  ),
);

/// Purges diagnostics 7 days old on app start and on every return to the
/// foreground (Q364-1). Watched by the app root.
final refusalDiagnosticPurgeProvider = Provider<void>((ref) {
  final store = ref.read(refusalDiagnosticsProvider);
  Future<void> purge() async {
    try {
      await store.purge();
    } catch (_) {}
  }

  unawaited(purge());
  final sub = ref.read(appResumesProvider).listen((_) => unawaited(purge()));
  ref.onDispose(sub.cancel);
});

/// [gzippedLog] (the engine's last call log, already scrubbed; empty when
/// there is none) with one line per refusal diagnostic first, packed again
/// to the upload's 2 MB.
Uint8List withRefusalLines(
  Uint8List gzippedLog,
  List<RefusalDiagnostic> refusals,
) {
  final text = gzippedLog.isEmpty ? '' : utf8.decode(gzip.decode(gzippedLog));
  final lines = [for (final r in refusals) r.logLine].join('\n');
  return packCallLog(text.isEmpty ? '$lines\n' : '$lines\n$text');
}

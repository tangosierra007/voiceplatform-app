// Runs the mock app API on http://localhost:3000/app/v1 (the contract's mock
// server URL). From the Android emulator it is http://10.0.2.2:3000/app/v1:
//
//   dart run tool/mock_server/main.dart
//   flutter run
//
// then sign in as ava@democo.example with code 123456 (SignInFixtures).
//
// Options: --port <n>, --host <address> (default 127.0.0.1; 0.0.0.0 for a
// phone on the LAN), --presence-every <seconds>, --minimum-version <x.y.z>,
// --recommended-version <x.y.z>. Sign-in values: SignInFixtures in fixtures.dart.
import 'dart:io';

import 'server.dart';

Future<void> main(List<String> args) async {
  String? opt(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final server = await MockServer.start(
    port: int.tryParse(opt('port') ?? '') ?? 3000,
    address:
        InternetAddress.tryParse(opt('host') ?? '') ??
        InternetAddress.loopbackIPv4,
    presenceEvery: Duration(
      seconds: int.tryParse(opt('presence-every') ?? '') ?? 5,
    ),
    minimumVersion: opt('minimum-version') ?? '1.0.0',
    recommendedVersion: opt('recommended-version'),
  );
  stdout.writeln('Mock app API on ${server.baseUri}');
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close();
    exit(0);
  });
}

// FU54: the greeting sheet keeps its recorder alive while it records.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/features/recents/greetings.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/screens/recents/greeting_screen.dart';
import 'package:voiceplatform_app/theme/app_theme.dart';

/// Like the device recorder: it can't start once disposed, and start takes
/// a moment (the temporary directory lookup).
class _FakeRecorder implements GreetingRecorder {
  bool disposed = false;
  bool started = false;
  bool stopped = false;

  @override
  Future<void> start() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (disposed) throw StateError('Record has been disposed');
    started = true;
  }

  @override
  Future<File?> stop() async {
    if (disposed) throw StateError('Record has been disposed');
    stopped = true;
    return null;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  testWidgets('the greeting sheet starts recording and keeps its recorder', (
    tester,
  ) async {
    final recorders = <_FakeRecorder>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          greetingRecorderProvider.overrideWith((ref) {
            final r = _FakeRecorder();
            recorders.add(r);
            ref.onDispose(r.dispose);
            return r;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: RecordGreetingSheet(kind: GreetingKind.unavailable),
          ),
        ),
      ),
    );
    // Frames go by while start() is still waiting, as on a phone.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(recorders, hasLength(1));
    expect(recorders.single.disposed, isFalse);
    expect(recorders.single.started, isTrue);
    expect(find.text("Recording didn't start."), findsNothing);

    // Closing the sheet releases the recorder.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(recorders.single.disposed, isTrue);
  });
}

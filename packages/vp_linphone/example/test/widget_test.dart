import 'dart:async';
import 'dart:typed_data';

import 'package:call_engine/call_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vp_linphone_example/main.dart';

class _QuietEngine implements CallEngine {
  @override
  Stream<RegistrationEvent> get registration => const Stream.empty();
  @override
  Stream<CallSnapshot> get calls => const Stream.empty();
  @override
  Stream<AudioState> get audio => const Stream.empty();
  @override
  Stream<double> get inputLevel => const Stream.empty();
  @override
  List<CallSnapshot> get activeCalls => const [];
  @override
  Future<void> start() async {}
  @override
  Future<Uint8List> exportLastCallLog() async => Uint8List(3);
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  testWidgets('bench app starts the engine and exports the log', (tester) async {
    await tester.pumpWidget(BenchApp(engine: _QuietEngine()));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('start ok'), findsOneWidget);
    await tester.tap(find.text('Export log'));
    await tester.pumpAndSettle();
    expect(find.text('export ok 3 bytes'), findsOneWidget);
  });
}

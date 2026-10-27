import 'package:call_engine/call_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_call_engine.dart';

/// The app's one CallEngine. FakeCallEngine until WS3's vp_linphone lands;
/// tests override it with a scripted FakeCallEngine.
final callEngineProvider = Provider<CallEngine>((ref) {
  final engine = FakeCallEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// The latest snapshot of one call, ended included.
final callSnapshotProvider = StreamProvider.autoDispose
    .family<CallSnapshot, String>((ref, id) async* {
      final engine = ref.watch(callEngineProvider);
      for (final c in engine.activeCalls) {
        if (c.id == id) yield c;
      }
      yield* engine.calls.where((c) => c.id == id);
    });

import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'events.dart';

/// One poll of `GET /presence`: the entries, or null when unchanged (304).
typedef PresencePoll = ({List<Map<String, Object?>>? items, String? etag});

/// Keeps the presence and badge events coming while the app is in the
/// foreground (spec 22, Contacts and presence; decision 138):
///
/// - [resume] opens `GET /events`; [pause] closes it and stops every timer.
///   Nothing runs in the background.
/// - A `reauth` event: [refreshToken] runs, then the stream reopens at once.
/// - The stream failing or closing: reopen after 1, 2, then 4 s.
/// - Three failures in a row: fall back. Poll `GET /presence` (with its ETag)
///   every 30 s while Contacts or Transfer is open ([presenceVisible]), and
///   try the stream again every 2 minutes. The first event on a reopened
///   stream ends the fallback.
///
/// Polled presence comes out of [events] as a `presence.snapshot`, so screens
/// handle one kind of event whichever way it arrived. Only timers are used,
/// so fake_async drives it in tests.
class LiveEvents {
  LiveEvents({
    required this.connect,
    required this.poll,
    Future<void> Function()? refreshToken,
  }) : refreshToken = refreshToken ?? _noRefresh;

  static Future<void> _noRefresh() async {}

  /// Opens the event stream. Cancelling the subscription closes it.
  final Stream<ServerEvent> Function() connect;

  /// `GET /presence` with `If-None-Match: <etag>`.
  final Future<PresencePoll> Function(String? etag) poll;

  /// Gets a new access token before the stream reopens after `reauth`.
  final Future<void> Function() refreshToken;

  static const failuresBeforeFallback = 3;
  static const pollEvery = Duration(seconds: 30);
  static const streamRetryInFallback = Duration(minutes: 2);

  /// Reconnect delay after the nth failure in a row (n = 1, 2).
  static Duration backoff(int failures) =>
      Duration(seconds: 1 << math.min(math.max(failures - 1, 0), 5));

  final _out = StreamController<ServerEvent>.broadcast();
  StreamSubscription<ServerEvent>? _sub;
  Timer? _reconnect;
  Timer? _poll;
  bool _running = false;
  bool _presenceVisible = false;
  bool _gotEvent = false;
  int _failures = 0;
  String? _etag;
  int _generation = 0;

  /// Presence snapshots and changes, badges; from the stream or polling.
  Stream<ServerEvent> get events => _out.stream;

  bool get isRunning => _running;
  bool get isStreamOpen => _sub != null;
  bool get inFallback => _failures >= failuresBeforeFallback;
  bool get isPolling => _poll != null;
  int get consecutiveFailures => _failures;

  /// Contacts or Transfer is on screen: polling runs only then.
  bool get presenceVisible => _presenceVisible;
  set presenceVisible(bool v) {
    if (_presenceVisible == v) return;
    _presenceVisible = v;
    _updatePolling();
  }

  /// The app came to the foreground.
  void resume() {
    if (_running) return;
    _running = true;
    _open();
    _updatePolling();
  }

  /// The app went to the background: close the stream, stop every timer.
  void pause() {
    _running = false;
    _generation++;
    _closeStream();
    _reconnect?.cancel();
    _reconnect = null;
    _stopPolling();
  }

  Future<void> dispose() async {
    pause();
    await _out.close();
  }

  void _open() {
    if (!_running) return;
    _closeStream();
    _reconnect?.cancel();
    _reconnect = null;
    _gotEvent = false;
    final gen = ++_generation;
    _sub = connect().listen(
      (e) => _onEvent(gen, e),
      onError: (Object _) => _onFailure(gen),
      onDone: () => _onFailure(gen),
      cancelOnError: true,
    );
  }

  void _onEvent(int gen, ServerEvent e) {
    if (gen != _generation) return;
    if (!_gotEvent) {
      _gotEvent = true;
      _failures = 0;
      _stopPolling();
    }
    if (e.type == 'reauth') {
      _generation++;
      _closeStream();
      refreshToken().whenComplete(() {
        if (_running) _open();
      });
      return;
    }
    _out.add(e);
  }

  void _onFailure(int gen) {
    if (gen != _generation || !_running) return;
    _sub = null;
    _failures++;
    final delay = inFallback ? streamRetryInFallback : backoff(_failures);
    _reconnect = Timer(delay, _open);
    _updatePolling();
  }

  void _closeStream() {
    _sub?.cancel();
    _sub = null;
  }

  void _updatePolling() {
    final want = _running && _presenceVisible && inFallback;
    if (want && _poll == null) {
      _pollOnce();
      _poll = Timer.periodic(pollEvery, (_) => _pollOnce());
    } else if (!want) {
      _stopPolling();
    }
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _pollOnce() async {
    final gen = _generation;
    try {
      final r = await poll(_etag);
      if (gen != _generation || !_running) return;
      _etag = r.etag ?? _etag;
      if (r.items != null) {
        _out.add(ServerEvent('presence.snapshot', {'items': r.items}));
      }
    } catch (_) {
      // Try again on the next tick.
    }
  }
}

/// `GET /presence` through Dio, keeping the ETag (the generated client hides
/// both the header and the 304).
Future<PresencePoll> pollPresence(Dio dio, String? etag) async {
  final res = await dio.get<List<Object?>>(
    '/presence',
    options: Options(
      headers: {'If-None-Match': ?etag},
      validateStatus: (s) => s == 200 || s == 304,
    ),
  );
  final tag = res.headers.value('etag');
  if (res.statusCode == 304) return (items: null, etag: tag ?? etag);
  return (
    items: [
      for (final i in res.data ?? const []) (i! as Map).cast<String, Object?>(),
    ],
    etag: tag,
  );
}

/// The event stream through Dio, closed (request cancelled) on cancel.
Stream<ServerEvent> connectEvents(Dio dio) {
  final cancel = CancelToken();
  late final StreamController<ServerEvent> c;
  StreamSubscription<ServerEvent>? sub;
  c = StreamController<ServerEvent>(
    onListen: () {
      sub = openEvents(
        dio,
        cancelToken: cancel,
      ).listen(c.add, onError: c.addError, onDone: c.close);
    },
    onCancel: () async {
      // Stop listening first, so the cancellation error has no one to reach.
      final s = sub;
      sub = null;
      await s?.cancel();
      cancel.cancel();
    },
  );
  return c.stream;
}

final liveEventsProvider = Provider<LiveEvents>((ref) {
  final dio = ref.watch(dioProvider);
  final live = LiveEvents(
    connect: () => connectEvents(dio),
    poll: (etag) => pollPresence(dio, etag),
    // Sign-in (4.2) supplies the refresh; until then the stream reopens with
    // the token it has.
  );
  ref.onDispose(live.dispose);
  return live;
});

/// Opens the stream while the app is in the foreground and closes it in the
/// background. Wrap the app in it once.
class LiveEventsLifecycle extends ConsumerStatefulWidget {
  const LiveEventsLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LiveEventsLifecycle> createState() =>
      _LiveEventsLifecycleState();
}

class _LiveEventsLifecycleState extends ConsumerState<LiveEventsLifecycle> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    final live = ref.read(liveEventsProvider);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) live.resume();
    _listener = AppLifecycleListener(
      onStateChange: (s) {
        if (s == AppLifecycleState.resumed) {
          live.resume();
        } else if (s == AppLifecycleState.paused ||
            s == AppLifecycleState.hidden ||
            s == AppLifecycleState.detached) {
          live.pause();
        }
      },
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

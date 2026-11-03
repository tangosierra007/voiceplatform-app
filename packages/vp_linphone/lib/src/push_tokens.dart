import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'engine.dart';

/// Where the FCM registration token comes from; faked in tests.
abstract interface class PushTokenSource {
  /// Null when push is unavailable (no Firebase config, no Play services).
  Future<String?> currentToken();
  Stream<String> get tokenRefresh;
}

/// firebase_messaging, for the token only: data messages are received
/// natively by the plugin (`PushReceiver`), so an incoming call never waits
/// for Flutter to start.
final class FirebasePushTokenSource implements PushTokenSource {
  bool _ready = false;

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      _ready = true;
    } catch (_) {
      // No google-services config for this build (the example app): no push.
      _ready = false;
    }
    return _ready;
  }

  // The FCM registration token, as the contract's pn-prid. firebase_messaging 17
  // deprecates it for register()/onRegistered (a Firebase Installation ID as
  // the send target); moving needs the push gateway (WS2) to send that way.
  @override
  // ignore: deprecated_member_use
  Future<String?> currentToken() async => await _init() ? FirebaseMessaging.instance.getToken() : null;

  @override
  Stream<String> get tokenRefresh async* {
    // ignore: deprecated_member_use
    if (await _init()) yield* FirebaseMessaging.instance.onTokenRefresh;
  }
}

/// Whether the API still needs the token: the background registration (after
/// a phone restart or an app update) may have put a rotated token in the SIP
/// contact with no app running to send it. Faked in tests.
abstract interface class PushTokenLedger {
  Future<bool> unsent();
  Future<void> markSent();
}

final class _EngineLedger implements PushTokenLedger {
  const _EngineLedger(this.engine);
  final VpLinphoneEngine engine;

  @override
  Future<bool> unsent() => engine.pushTokenUnsent();

  @override
  Future<void> markSent() => engine.markPushTokenSent();
}

/// The FCM token for RFC 8599 and the API (spec 22, decision 138).
///
/// [start] gives the current token. On every refresh the engine's contact is
/// updated without dropping calls (`CallEngine.updatePush`), and [tokens]
/// emits it so the app can `PUT /devices/me/push-token` (WS4 wires the call).
final class VpPushTokens {
  VpPushTokens({required this.engine, PushTokenSource? source, PushTokenLedger? ledger})
    : _source = source ?? FirebasePushTokenSource(),
      _ledger = ledger ?? (engine is VpLinphoneEngine ? _EngineLedger(engine) : null);

  static const provider = 'fcm';
  static const param = 'voiceplatform-app';

  final CallEngine engine;
  final PushTokenSource _source;
  final PushTokenLedger? _ledger;
  final _tokens = StreamController<String>.broadcast();
  StreamSubscription<String>? _sub;
  String? _current;

  /// Every token after [start]: the refreshed ones, for the API.
  Stream<String> get tokens => _tokens.stream;

  /// The token now, for `SipAccount.push` and the first PUT; null without push.
  String? get current => _current;

  static PushParams paramsFor(String token) => PushParams(provider: provider, prid: token, param: param);

  Future<String?> start() async {
    _current = await _source.currentToken();
    _sub ??= _source.tokenRefresh.listen(_onRefresh);
    return _current;
  }

  Future<void> _onRefresh(String token) async {
    if (token == _current) return;
    _current = token;
    try {
      await engine.updatePush(paramsFor(token));
    } on CallEngineError {
      // Not registered yet: the next register() carries the new token.
    }
    _tokens.add(token);
  }

  /// True when the token in the SIP contact hasn't reached the API yet
  /// (`PUT /devices/me/push-token`); false when unknown.
  Future<bool> tokenUnsent() async {
    try {
      return await _ledger?.unsent() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The API has the token now.
  Future<void> markTokenSent() async {
    try {
      await _ledger?.markSent();
    } catch (_) {
      // Sent again on the next start.
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _tokens.close();
  }
}

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth.dart';

/// The sign-in links the app answers (spec 22, Sign-in items 2 to 5).
sealed class SignInLink {
  const SignInLink();
}

/// `https://<portal host>/app/signin/<requestId>/<linkToken>` from the email.
final class EmailSignInLink extends SignInLink {
  const EmailSignInLink(this.requestId, this.linkToken);
  final String requestId;
  final String linkToken;
}

/// `vpapp://signin/<token>` from the portal's QR.
final class QrSignInLink extends SignInLink {
  const QrSignInLink(this.token);
  final String token;
}

SignInLink? parseSignInLink(Uri uri) {
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (uri.scheme == 'https' &&
      seg.length == 4 &&
      seg[0] == 'app' &&
      seg[1] == 'signin') {
    return EmailSignInLink(seg[2], seg[3]);
  }
  final qr = qrSignInToken(uri.toString());
  return qr == null ? null : QrSignInLink(qr);
}

/// The token in `vpapp://signin/<token>`, or null.
String? qrSignInToken(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null || uri.scheme != 'vpapp' || uri.host != 'signin') {
    return null;
  }
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  return seg.length == 1 ? seg.single : null;
}

/// Where links come from; tests feed their own.
final incomingLinksProvider = Provider<Stream<Uri>>(
  (ref) => AppLinks().uriLinkStream,
);

/// Completes sign-in from a link. A link for a request this phone did not
/// make (forwarded, or the app restarted and lost the secret) shows "This
/// link only signs in the phone that asked for it" on AppSignIn.
class SignInLinkListener extends ConsumerStatefulWidget {
  const SignInLinkListener({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SignInLinkListener> createState() => _SignInLinkListenerState();
}

class _SignInLinkListenerState extends ConsumerState<SignInLinkListener> {
  StreamSubscription<Uri>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(incomingLinksProvider).listen(_onLink, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onLink(Uri uri) async {
    final link = parseSignInLink(uri);
    if (link == null) return;
    if (ref.read(authProvider) is SignedIn) return;
    final auth = ref.read(authProvider.notifier);
    try {
      switch (link) {
        case EmailSignInLink(:final requestId, :final linkToken):
          await auth.completeWithLink(requestId, linkToken);
        case QrSignInLink(:final token):
          await auth.completeWithQr(token);
      }
    } on SignInFailure catch (e) {
      if (e.message.isNotEmpty && e.code != 'not_this_phone') {
        auth.showNotice(e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

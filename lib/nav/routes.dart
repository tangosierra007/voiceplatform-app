import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth.dart';
import '../auth/version.dart';
import '../screens/calls/in_call_screen.dart';
import '../screens/calls/incoming_screen.dart';
import '../screens/calls/transfer_screen.dart';
import '../screens/contacts/contacts_screen.dart';
import '../screens/keypad/keypad_screen.dart';
import '../screens/placeholders.dart';
import '../screens/recents/greeting_screen.dart';
import '../screens/recents/recents_screen.dart';
import '../screens/signin/basic_screen.dart';
import '../screens/signin/code_screen.dart';
import '../screens/signin/qr_screen.dart';
import '../screens/signin/sign_in_screen.dart';
import '../screens/signin/update_screen.dart';
import '../shell/app_shell.dart';
import '../shell/shell_status.dart';
import '../shell/vp_tab_bar.dart';
import '../theme/app_theme.dart';

/// Every route in the app. Tabs live in one StatefulShellRoute (each keeps its
/// own stack); the full-screen flows sit above it with no tab bar.
abstract final class Routes {
  static const keypad = '/keypad';
  static const recents = '/recents';

  /// The Greeting link from Voicemail.
  static const greeting = '/recents/greeting';
  static const contacts = '/contacts';
  static const messages = '/messages';
  static const me = '/me';

  /// Reading the stored session at start.
  static const starting = '/starting';

  /// AppSignIn.
  static const signIn = '/sign-in';

  /// AppCode.
  static const signInCode = '/sign-in/code';

  /// "Scan the QR code instead".
  static const signInQr = '/sign-in/qr';

  /// AppBasic.
  static const signInBasic = '/sign-in/basic';

  /// AppUpdate (blocking).
  static const update = '/update';

  /// AppIncoming. Also the target of the full-screen incoming intent (WS3).
  static String incoming(String callId) => '/incoming/$callId';

  /// AppInCall.
  static String inCall(String callId) => '/in-call/$callId';

  /// AppTransfer, over the call it transfers.
  static String transfer(String callId) => '/in-call/$callId/transfer';

  static String forTab(AppTab t) => switch (t) {
    AppTab.keypad => keypad,
    AppTab.recents => recents,
    AppTab.contacts => contacts,
    AppTab.messages => messages,
    AppTab.me => me,
  };
}

/// Where the app must be for the sign-in and version state, or null to stay.
/// Pure, so tests can check every case.
String? gateRedirect({
  required String location,
  required AuthState auth,
  required bool updateRequired,
  required bool hasPendingEmail,
}) {
  final inSignIn = location.startsWith(Routes.signIn);
  // Below the minimum version nothing else opens (APP7), not even sign-in.
  if (updateRequired) return location == Routes.update ? null : Routes.update;
  if (location == Routes.update) return Routes.starting;
  switch (auth) {
    case AuthStarting():
      return location == Routes.starting ? null : Routes.starting;
    case LicenceRefused():
      return location == Routes.signInBasic ? null : Routes.signInBasic;
    case NotSignedIn():
      if (location == Routes.signInCode && !hasPendingEmail) {
        return Routes.signIn;
      }
      if (location == Routes.signInBasic) return Routes.signIn;
      return inSignIn ? null : Routes.signIn;
    case SignedIn():
      return inSignIn || location == Routes.starting ? Routes.keypad : null;
  }
}

/// Re-runs the redirect when sign-in or the version gate changes.
class _GateListenable extends ChangeNotifier {
  void ping() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final gate = _GateListenable();
  ref.listen(authProvider, (_, _) => gate.ping());
  ref.listen(updateRequiredProvider, (_, _) => gate.ping());
  ref.listen(pendingSignInProvider, (_, _) => gate.ping());

  final router = GoRouter(
    initialLocation: Routes.starting,
    refreshListenable: gate,
    redirect: (context, state) => gateRedirect(
      location: state.matchedLocation,
      auth: ref.read(authProvider),
      updateRequired: ref.read(updateRequiredProvider) != null,
      hasPendingEmail: ref.read(pendingSignInProvider) != null,
    ),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          for (final t in AppTab.values)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.forTab(t),
                  pageBuilder: (context, state) => NoTransitionPage(
                    child: switch (t) {
                      AppTab.keypad => const KeypadScreen(),
                      AppTab.recents => const RecentsScreen(),
                      AppTab.contacts => const ContactsScreen(),
                      _ => TabPlaceholder(tab: t),
                    },
                  ),
                  routes: [
                    if (t == AppTab.recents)
                      GoRoute(
                        path: 'greeting',
                        builder: (context, state) => const GreetingScreen(),
                      ),
                  ],
                  redirect: t == AppTab.messages
                      ? (context, state) =>
                            ProviderScope.containerOf(context)
                                .read(shellStatusProvider)
                                .hasSmsLine
                            ? null
                            : Routes.keypad
                      : null,
                ),
              ],
            ),
        ],
      ),
      GoRoute(
        path: Routes.starting,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: _Starting()),
      ),
      GoRoute(
        path: Routes.signIn,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: SignInScreen()),
        routes: [
          GoRoute(
            path: 'code',
            builder: (context, state) => const CodeScreen(),
          ),
          GoRoute(path: 'qr', builder: (context, state) => const QrScreen()),
          GoRoute(
            path: 'basic',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: BasicScreen()),
          ),
        ],
      ),
      GoRoute(
        path: Routes.update,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: UpdateScreen()),
      ),
      GoRoute(
        path: '/incoming/:callId',
        builder: (context, state) =>
            IncomingScreen(callId: state.pathParameters['callId']!),
      ),
      GoRoute(
        path: '/in-call/:callId',
        builder: (context, state) =>
            InCallScreen(callId: state.pathParameters['callId']!),
        routes: [
          GoRoute(
            path: 'transfer',
            builder: (context, state) =>
                TransferScreen(callId: state.pathParameters['callId']!),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  ref.onDispose(gate.dispose);
  return router;
});

/// The canvas while the stored session is read (a few milliseconds).
class _Starting extends StatelessWidget {
  const _Starting();

  @override
  Widget build(BuildContext context) => ColoredBox(color: context.vp.canvas);
}

/// True for the full-screen call routes.
bool isCallRoute(String location) =>
    location.startsWith('/incoming/') || location.startsWith('/in-call/');

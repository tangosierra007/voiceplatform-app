import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/call_placeholders.dart';
import '../screens/placeholders.dart';
import '../shell/app_shell.dart';
import '../shell/shell_status.dart';
import '../shell/vp_tab_bar.dart';

/// Every route in the app. Tabs live in one StatefulShellRoute (each keeps its
/// own stack); the full-screen flows sit above it with no tab bar.
abstract final class Routes {
  static const keypad = '/keypad';
  static const recents = '/recents';
  static const contacts = '/contacts';
  static const messages = '/messages';
  static const me = '/me';

  /// AppSignIn, AppCode, AppBasic and the rest of getting in (4.2).
  static const signIn = '/sign-in';

  /// AppIncoming (4.3).
  static String incoming(String callId) => '/incoming/$callId';

  /// AppInCall (4.3).
  static String inCall(String callId) => '/in-call/$callId';

  static String forTab(AppTab t) => switch (t) {
    AppTab.keypad => keypad,
    AppTab.recents => recents,
    AppTab.contacts => contacts,
    AppTab.messages => messages,
    AppTab.me => me,
  };
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: Routes.keypad,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          for (final t in AppTab.values)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.forTab(t),
                  pageBuilder: (context, state) =>
                      NoTransitionPage(child: TabPlaceholder(tab: t)),
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
        path: Routes.signIn,
        builder: (context, state) => const SignInPlaceholder(),
      ),
      GoRoute(
        path: '/incoming/:callId',
        builder: (context, state) =>
            IncomingCallPlaceholder(callId: state.pathParameters['callId']!),
      ),
      GoRoute(
        path: '/in-call/:callId',
        builder: (context, state) =>
            InCallPlaceholder(callId: state.pathParameters['callId']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// True for the full-screen call routes.
bool isCallRoute(String location) =>
    location.startsWith('/incoming/') || location.startsWith('/in-call/');

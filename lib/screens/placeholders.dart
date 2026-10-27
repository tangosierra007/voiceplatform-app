import 'package:flutter/material.dart';

import '../shell/vp_tab_bar.dart';
import '../theme/app_theme.dart';

/// Stand-in for a tab's screen until its task builds it (4.3, 4.4).
class TabPlaceholder extends StatelessWidget {
  const TabPlaceholder({super.key, required this.tab});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          VpSpace.s5 - 4,
          VpSpace.s2,
          VpSpace.s5 - 4,
          0,
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Semantics(
            header: true,
            child: Text(
              tab.label,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
        ),
      ),
    );
  }
}

/// Stand-in for AppSignIn and the rest of getting in (4.2).
class SignInPlaceholder extends StatelessWidget {
  const SignInPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Text(
            'Sign in',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
      ),
    );
  }
}

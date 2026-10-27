import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth.dart';
import '../../nav/routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';

/// AppSignIn: work email, "Email me a sign-in link", or the portal's QR.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(
      text: ref.read(pendingSignInProvider)?.email ?? '',
    );
  }

  bool _busy = false;
  String? _error;

  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!_emailShape.hasMatch(email)) {
      setState(() => _error = 'Enter your work email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).requestEmail(email);
      if (mounted) context.push(Routes.signInCode);
    } on SignInFailure catch (e) {
      if (mounted && e.message.isNotEmpty) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final auth = ref.watch(authProvider);
    final notice = auth is NotSignedIn ? auth.notice : null;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    28,
                    40,
                    28,
                    20 + vpBottomInset(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: VpLogo(),
                      ),
                      const SizedBox(height: 18 + 30),
                      Semantics(
                        header: true,
                        child: Text(
                          'Sign in with your work email',
                          style: vpTitle(context, size: 32, line: 38),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "We'll email you a link and a code. No password needed.",
                        style: vpMuted(context),
                      ),
                      if (notice != null) ...[
                        const SizedBox(height: 18),
                        _Notice(text: notice),
                      ],
                      const SizedBox(height: 18),
                      _EmailField(
                        controller: _email,
                        error: _error,
                        onSubmit: _busy ? null : _send,
                      ),
                      const SizedBox(height: 18),
                      VpButton(
                        label: 'Email me a sign-in link',
                        busy: _busy,
                        onPressed: _send,
                      ),
                      const SizedBox(height: 18),
                      ExcludeSemantics(
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(height: 1, color: c.border),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'or',
                                style: VpType.small.copyWith(
                                  color: c.textMuted,
                                  // 13 px on the inherited 22 px line.
                                  height: 22 / 13,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(height: 1, color: c.border),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      VpButton(
                        label: 'Scan the QR code instead',
                        kind: VpButtonKind.outline,
                        icon: VpIcon.qr,
                        onPressed: _busy
                            ? null
                            : () => context.push(Routes.signInQr),
                      ),
                      const Spacer(),
                      const SizedBox(height: 18),
                      Text(
                        "The app works with an Advanced licence. Ask your admin if you're not sure which you have.",
                        textAlign: TextAlign.center,
                        style: vpMuted(context, size: 12, line: 18),
                      ),
                      // The artboard's <p> keeps its default 12 px bottom margin.
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailField extends StatelessWidget {
  const _EmailField({
    required this.controller,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? error;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    OutlineInputBorder border(Color colour, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(VpRadius.sm),
      borderSide: BorderSide(color: colour, width: width),
    );
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Work email',
            style: VpType.body.copyWith(
              fontSize: 13,
              height: 18 / 13,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              color: c.text,
            ),
          ),
          const SizedBox(height: VpSpace.s2),
          TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            textInputAction: TextInputAction.send,
            onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            style: VpType.body.copyWith(
              fontSize: 17,
              height: 1.3,
              color: c.text,
            ),
            cursorColor: c.text,
            decoration: InputDecoration(
              labelText: null,
              semanticCounterText: null,
              hintText: null,
              filled: true,
              fillColor: c.surface,
              isDense: true,
              constraints: const BoxConstraints(minHeight: 52),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              enabledBorder: border(
                error == null ? c.borderStrong : c.statusBad,
                error == null ? 1 : 2,
              ),
              focusedBorder: border(c.focus, 2),
              errorText: error,
              errorMaxLines: 3,
              errorStyle: VpType.small.copyWith(
                color: c.statusBad,
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation('wght', 700)],
              ),
              errorBorder: border(c.statusBad, 2),
              focusedErrorBorder: border(c.focus, 2),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.warning100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VpSvgIcon(VpIcon.lock, size: 18, colour: c.text),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: VpType.small.copyWith(color: c.text, height: 18 / 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

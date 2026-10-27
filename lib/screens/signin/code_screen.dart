import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth.dart';
import '../../nav/routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';

/// AppCode: "Check your email". Six boxes over one field (so paste and SMS
/// style one-time-code autofill work), the Send again timer, and the note
/// that a forwarded link won't work.
class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key});

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _tick;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onChanged);
    _startTicker();
  }

  /// Redraws the Send again countdown each second, and stops at 0:00.
  void _startTicker() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {});
      final p = ref.read(pendingSignInProvider);
      if (p == null || !p.resendAt.isAfter(ref.read(clockProvider)())) {
        t.cancel();
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    if (_code.text.length == 6 && !_busy) _submit();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).completeWithCode(_code.text);
    } on SignInFailure catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.message.isNotEmpty) _error = e.message;
        _code.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authProvider.notifier).resend();
      if (mounted) {
        setState(() => _error = null);
        _startTicker();
      }
    } on SignInFailure catch (e) {
      if (mounted && e.message.isNotEmpty) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final pending = ref.watch(pendingSignInProvider);
    if (pending == null) return const SizedBox.shrink();
    final now = ref.read(clockProvider)();
    final wait = pending.resendAt.difference(now);
    final secs = wait.inMilliseconds <= 0
        ? 0
        : (wait.inMilliseconds / 1000).ceil();
    final linkStyle = VpType.small.copyWith(
      fontSize: 13,
      height: 20 / 13,
      color: c.brandText,
      fontWeight: FontWeight.w700,
      fontVariations: const [FontVariation('wght', 700)],
      decoration: TextDecoration.underline,
      decorationColor: c.brandText,
    );

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
                    12,
                    28,
                    20 + vpBottomInset(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        button: true,
                        label: 'Back',
                        excludeSemantics: true,
                        onTap: _back,
                        child: InkResponse(
                          onTap: _back,
                          radius: 24,
                          // The artboard's inline icon sits in a 27 px line box.
                          child: SizedBox(
                            width: 24,
                            height: 27,
                            child: VpSvgIcon(
                              VpIcon.back,
                              size: 24,
                              colour: c.text,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18 + 20),
                      VpIconTile(
                        icon: VpIcon.mail,
                        size: 64,
                        radius: 18,
                        iconSize: 30,
                        background: c.brandTint,
                        colour: c.brandText,
                      ),
                      const SizedBox(height: 18),
                      Semantics(
                        header: true,
                        child: Text(
                          'Check your email',
                          style: vpTitle(context),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'We sent a link to '),
                            TextSpan(
                              text: pending.email,
                              style: TextStyle(
                                color: c.text,
                                fontWeight: FontWeight.w700,
                                fontVariations: const [
                                  FontVariation('wght', 700),
                                ],
                              ),
                            ),
                            const TextSpan(
                              text: '. Tap it on this phone, or type the 6-digit code.',
                            ),
                          ],
                        ),
                        style: vpMuted(context),
                      ),
                      const SizedBox(height: 18),
                      _CodeBoxes(
                        controller: _code,
                        focus: _focus,
                        enabled: !_busy,
                        error: _error != null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: VpType.small.copyWith(
                              color: c.statusBad,
                              fontWeight: FontWeight.w700,
                              fontVariations: const [
                                FontVariation('wght', 700),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: 'The code works once and expires in 10 minutes.\n',
                            ),
                            const TextSpan(text: "Didn't get it? "),
                            if (secs > 0)
                              TextSpan(
                                text:
                                    'Send again in ${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
                                style: linkStyle,
                                semanticsLabel: 'Send again in $secs seconds',
                              )
                            else
                              WidgetSpan(
                                alignment: PlaceholderAlignment.baseline,
                                baseline: TextBaseline.alphabetic,
                                child: Semantics(
                                  button: true,
                                  child: GestureDetector(
                                    onTap: _resend,
                                    child: Text('Send again', style: linkStyle),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        style: vpMuted(context, size: 13, line: 20),
                      ),
                      const Spacer(),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: c.surface,
                          border: Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            VpSvgIcon(VpIcon.lock, size: 18, colour: c.text),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "The link only signs in the phone that asked for it. A forwarded link won't work.",
                                style: VpType.small.copyWith(
                                  color: c.text,
                                  height: 18 / 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.signIn);
    }
  }
}

/// Six 44 x 56 boxes drawn from one hidden field. The next empty box has the
/// 2 px orange border (`brand`), as the artboard shows.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.error,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final text = controller.text;
    final digit = VpType.body.copyWith(
      fontSize: 26,
      height: 1,
      fontWeight: FontWeight.w700,
      fontVariations: const [FontVariation('wght', 700)],
      color: c.text,
    );
    return Stack(
      children: [
        // The real input: transparent, the size of the row, on top for taps.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            alwaysIncludeSemantics: true,
            child: TextField(
              controller: controller,
              focusNode: focus,
              enabled: enabled,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              showCursor: false,
              enableInteractiveSelection: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
                labelText: '6-digit code',
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 6; i++)
                  _box(
                    c,
                    digit,
                    i < text.length ? text[i] : '',
                    active: i == text.length && enabled,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _box(VpColors c, TextStyle style, String d, {required bool active}) {
    final border = active
        ? BorderSide(color: c.brand, width: 2)
        : BorderSide(color: error ? c.statusBad : c.borderStrong);
    return Container(
      width: 44,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.fromBorderSide(border),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(d, style: style),
      ),
    );
  }
}

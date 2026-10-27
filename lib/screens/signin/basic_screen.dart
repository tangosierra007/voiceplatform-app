import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';

/// AppBasic: the extension is on Basic. Says what keeps working, then
/// "Ask my admin to upgrade" (A6) or "Use a different email".
class BasicScreen extends ConsumerStatefulWidget {
  const BasicScreen({super.key});

  @override
  ConsumerState<BasicScreen> createState() => _BasicScreenState();
}

class _BasicScreenState extends ConsumerState<BasicScreen> {
  bool _busy = false;
  bool _sent = false;
  String? _error;

  Future<void> _ask() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).askAdminToUpgrade();
      if (mounted) setState(() => _sent = true);
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
    final refusal = auth is LicenceRefused ? auth.refusal : null;
    final ext = [
      refusal?.extensionValue,
      refusal?.extensionName,
    ].whereType<String>().join(' ');
    final tick = VpSvgIcon(VpIcon.check, size: 18, colour: c.statusOk);
    final row = VpType.body.copyWith(
      fontSize: 14,
      // The artboard's rows sit on the inherited 22 px line.
      height: 22 / 14,
      color: c.text,
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
                    60,
                    28,
                    20 + vpBottomInset(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: VpIconTile(
                          icon: VpIcon.lock,
                          size: 64,
                          radius: 18,
                          iconSize: 30,
                          background: c.surface,
                          border: c.border,
                          colour: c.text,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        header: true,
                        child: Text(
                          'This app needs an Advanced licence',
                          style: vpTitle(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Your extension${ext.isEmpty ? '' : ', $ext,'} is on Basic. '
                        'Basic covers a desk phone with calls charged as they go. '
                        'The mobile and desktop app comes with Advanced.',
                        style: vpMuted(context),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: c.surface,
                          border: Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                tick,
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Your desk phone keeps working',
                                    style: row,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                tick,
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Voicemail still arrives by email',
                                    style: row,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 16),
                      if (_sent)
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: c.success100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              "We've asked your admin. They'll get a notification and an email.",
                              style: VpType.bodyStrong.copyWith(color: c.text),
                            ),
                          ),
                        )
                      else
                        VpButton(
                          label: 'Ask my admin to upgrade',
                          busy: _busy,
                          onPressed: _ask,
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: VpType.small.copyWith(
                            color: c.statusBad,
                            fontWeight: FontWeight.w700,
                            fontVariations: const [FontVariation('wght', 700)],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      VpButton(
                        label: 'Use a different email',
                        kind: VpButtonKind.ghost,
                        large: false,
                        height: VpSize.controlHeight,
                        onPressed: () =>
                            ref.read(authProvider.notifier).useDifferentEmail(),
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
}

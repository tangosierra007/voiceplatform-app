import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth.dart';
import '../../calls/numbers.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';

/// "Priya Shah, your admin, signed this phone out at 3:12 pm today." (the
/// contract's revokedBy carries the name and role).
String signedOutLine(SignedOut info, DateTime now) {
  final who = info.revokedBy;
  final at = info.revokedAt?.toLocal();
  String? when;
  if (at != null) {
    final n = now.toLocal();
    final days = DateTime(
      n.year,
      n.month,
      n.day,
    ).difference(DateTime(at.year, at.month, at.day)).inDays;
    when = days == 0
        ? 'at ${clockTime(at)} today'
        : days == 1
        ? 'at ${clockTime(at)} yesterday'
        : 'on ${whenShort(at, now)}'; // on Tue 3:12 pm, on 14 Oct
  }
  final subject = who == null || who.isEmpty
      ? 'Your admin signed this phone out'
      // revokedBy is name and role, as the contract says: Priya Shah, your admin.
      : '$who, signed this phone out';
  return '$subject${when == null ? '' : ' $when'}. This usually happens '
      'when a phone is replaced or lost.';
}

/// AppSignedOut: the phone was signed out from elsewhere. Everything local
/// has already been cleared; this says who, when, and whom to ask.
class SignedOutScreen extends ConsumerWidget {
  const SignedOutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final auth = ref.watch(authProvider);
    final info = auth is SignedOutRemotely ? auth.info : null;
    final now = ref.watch(clockProvider)();
    final ext = info?.extensionValue;
    final support = info?.support;
    final who = info?.revokedBy;
    final ask = [
      if (who != null && who.isNotEmpty)
        'Ask ${who.split(RegExp('[ ,]')).first}',
      if (support != null)
        'call ${support.name}${support.phone == null ? '' : ' on ${formatAuNumber(support.phone!)}'}',
    ];
    String sentence(List<String> parts) {
      final s = parts.join(', or ');
      return s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}.';
    }

    Widget tick(String text) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VpSvgIcon(VpIcon.check, size: 18, colour: c.statusOk),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: VpType.body.copyWith(fontSize: 14, color: c.text),
          ),
        ),
      ],
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
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
                      70,
                      28,
                      20 + vpBottomInset(context),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        VpIconTile(
                          icon: VpIcon.signOut,
                          size: 64,
                          radius: 18,
                          iconSize: 30,
                          background: c.surface,
                          colour: c.text,
                          border: c.border,
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          header: true,
                          child: Text(
                            "You've been signed out",
                            style: vpTitle(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          info == null
                              ? 'This phone was signed out.'
                              : signedOutLine(info, now),
                          style: vpMuted(context),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: c.border),
                          ),
                          child: Column(
                            children: [
                              tick(
                                ext == null
                                    ? 'Calls to your extension still ring your desk phone'
                                    : 'Calls to $ext still ring your desk phone',
                              ),
                              const SizedBox(height: 8),
                              tick(
                                'Nothing from your calls or voicemail is kept '
                                'on this phone',
                              ),
                            ],
                          ),
                        ),
                        if (ask.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Not expecting this? ${sentence(ask)}',
                            style: vpMuted(context, size: 13, line: 20),
                          ),
                        ],
                        const Spacer(),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: VpButton(
                            label: 'Sign in again',
                            onPressed: () => ref
                                .read(authProvider.notifier)
                                .acknowledgeSignedOut(),
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
      ),
    );
  }
}

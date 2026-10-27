import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vp_linphone/vp_linphone.dart' show CallDiagnostics, NoCallLog;

import '../../auth/app_lock.dart';
import '../../auth/auth.dart';
import '../../calls/me_state.dart';
import '../../calls/numbers.dart';
import '../../engine/engine_provider.dart';
import '../../engine/phone_extras.dart';
import '../../features/me/me_data.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_preference.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';
import '../../widgets/vp_list.dart';

/// "Send call logs to support": WS3's `CallDiagnostics.sendCallLogs()` with
/// the last call's scrubbed, gzipped log, uploaded to `POST
/// /diagnostics/call-logs` (`application/gzip`, with the bearer and
/// X-VP-App). Answers the reference to quote, or null when no call has been
/// logged on this phone yet.
final sendCallLogsProvider = Provider<Future<String?> Function()>((ref) {
  return () async {
    final d = CallDiagnostics(
      engine: ref.read(callEngineProvider),
      upload: (gz) async {
        final r = await ref
            .read(dioProvider)
            .post<Map<String, Object?>>(
              '/diagnostics/call-logs',
              data: Stream.fromIterable([gz]),
              options: Options(
                contentType: 'application/gzip',
                headers: {Headers.contentLengthHeader: gz.length},
              ),
            );
        return PostDiagnosticsCallLogsResponse.fromJson(r.data!).reference;
      },
    );
    try {
      return await d.sendCallLogs();
    } on NoCallLog {
      return null;
    }
  };
});

/// AppMe: status, what happens to calls, recordings, this phone, sign out.
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  static const callSettingsPath = '/me/call-settings';
  static const recordingsPath = '/me/recordings';
  static const devicesPath = '/me/devices';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final me = ref.watch(meProvider).value;
    final settings = ref.watch(callSettingsProvider).value;
    final hours = ref.watch(officeHoursProvider).value;
    final devices = ref.watch(devicesProvider).value;
    final battery = ref.watch(batteryCardProvider).value;
    final version = ref.watch(apiConfigProvider).appVersion;
    final canHours = me?.permissions.officeHours ?? false;
    final canRecordings = me?.permissions.recordings ?? false;
    final licence = switch (me?.licence) {
      MeLicence.advanced => 'Advanced',
      _ => null,
    };
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.ink900,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      me?.initials ?? initialsOf(me?.name ?? ''),
                      textScaler: TextScaler.noScaling,
                      style: VpType.body.copyWith(
                        fontSize: 14,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        fontVariations: const [FontVariation('wght', 800)],
                        color: c.grey100,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          me?.name ?? '',
                          style: vpTitle(context, size: 22, line: 28),
                        ),
                      ),
                      Text(
                        [
                          me?.extensionValue,
                          me?.tenantName,
                          licence,
                        ].whereType<String>().join(' · '),
                        style: vpMuted(context, size: 13, line: 18),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _StatusPicker(),
          if (battery != null) _BatteryCard(status: battery),
          const _Band('Calls'),
          _MeRow(
            icon: VpIcon.phone,
            title: "When I don't answer",
            subtitle: settings == null ? null : callSettingsSummary(settings),
            onTap: () => context.push(callSettingsPath),
          ),
          // Only with permissions.officeHours: the row and its fetch.
          if (canHours && hours != null)
            _MeRow(
              icon: VpIcon.update,
              title: 'Office hours',
              subtitle:
                  hours.summary ?? (hours.openNow ? 'Open now' : 'Closed now'),
              trailing: _Chip(
                'Change',
                onTap: () => _changeHours(context, ref, hours),
              ),
            ),
          if (canRecordings)
            _MeRow(
              icon: VpIcon.mic,
              title: 'Recordings',
              subtitle: 'Your recorded calls, last 90 days',
              onTap: () => context.push(recordingsPath),
            ),
          const _Band('This phone'),
          _MeRow(
            icon: VpIcon.keypad,
            title: 'Signed-in devices',
            subtitle: devices == null ? null : devicesSummary(devices),
            onTap: () => context.push(devicesPath),
          ),
          _MeRow(
            icon: VpIcon.info,
            title: 'Send call logs to support',
            subtitle: 'For the last call, no passwords included',
            onTap: () => _sendLogs(context, ref),
          ),
          const _Band('Appearance'),
          const _Appearance(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SignOutButton(onPressed: () => _signOut(context, ref)),
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Version $version · ',
                      style: vpMuted(context, size: 12, line: 18),
                    ),
                    VpLink(
                      'Open source licences',
                      size: 12,
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'VoicePlatform',
                        applicationVersion: version,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeHours(
    BuildContext context,
    WidgetRef ref,
    OfficeHours hours,
  ) async {
    final mode = await showModalBottomSheet<OverrideInputMode>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.vp.surface,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                hours.name,
                style: vpTitle(sheet, size: 20, line: 26),
              ),
            ),
            for (final (m, label) in const [
              (OverrideInputMode.schedule, 'Follow the schedule'),
              (OverrideInputMode.open, 'Open until changed back'),
              (OverrideInputMode.closed, 'Closed until changed back'),
            ])
              VpRow(
                onTap: () => Navigator.of(sheet).pop(m),
                semanticLabel: label,
                children: [
                  Expanded(child: VpRowText(title: label, subtitle: null)),
                  if (hours.mode.json == m.json)
                    VpSvgIcon(
                      VpIcon.check,
                      size: 20,
                      colour: sheet.vp.brandText,
                    ),
                ],
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (mode == null) return;
    try {
      await ref
          .read(appApiProvider)
          .me
          .postMeOfficeHoursIdOverride(
            id: hours.id,
            body: OverrideInput(mode: mode),
          );
      ref.invalidate(officeHoursProvider);
    } catch (_) {
      if (context.mounted) _say(context, "That didn't save. Try again.");
    }
  }

  Future<void> _sendLogs(BuildContext context, WidgetRef ref) async {
    try {
      final reference = await ref.read(sendCallLogsProvider)();
      if (!context.mounted) return;
      _say(
        context,
        reference == null
            ? 'There is no call on this phone to send yet.'
            : 'Sent. Quote $reference to support.',
      );
    } catch (_) {
      if (context.mounted) _say(context, "The logs didn't send. Try again.");
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Sign out of this phone?'),
        content: const Text(
          'Calls stop ringing here. Your desk phone and other devices keep '
          'ringing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (yes == true) await ref.read(authProvider.notifier).signOut();
  }
}

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));

class _Band extends StatelessWidget {
  const _Band(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: VpType.label.copyWith(
          fontWeight: FontWeight.w800,
          fontVariations: const [FontVariation('wght', 800)],
          color: context.vp.textMuted,
        ),
      ),
    ),
  );
}

class _MeRow extends StatelessWidget {
  const _MeRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });
  final VpIcon icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return VpRow(
      background: c.surface,
      onTap: onTap,
      semanticLabel: [title, subtitle].whereType<String>().join(', '),
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
          ),
          child: VpSvgIcon(icon, size: 18, colour: c.text),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ExcludeSemantics(
            excluding: onTap != null,
            child: VpRowText(title: title, subtitle: subtitle),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ] else if (onTap != null)
          Transform.rotate(
            angle: -1.5708,
            child: VpSvgIcon(VpIcon.chevronDown, size: 18, colour: c.textMuted),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Semantics(
      container: true,
      button: true,
      label: text,
      excludeSemantics: true,
      onTap: onTap,
      child: VpTapPad(
        height: 28,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 28, minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: c.borderStrong),
          ),
          child: Text(
            text,
            style: VpType.body.copyWith(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              color: c.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// Available, Do not disturb (with an end), Away.
class _StatusPicker extends ConsumerWidget {
  const _StatusPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final status = ref.watch(myStatusProvider) ?? StatusStatus.available;
    final until = ref.watch(dndUntilProvider);
    Future<void> pick(StatusInputStatus s) async {
      DateTime? end;
      if (s == StatusInputStatus.dnd) {
        final choice = await _dndUntil(context, ref);
        if (choice == null) return;
        end = choice.$1;
      }
      try {
        await ref.read(myStatusProvider.notifier).set(s, dndUntil: end);
        ref.read(dndUntilProvider.notifier).set(end);
      } catch (_) {
        if (context.mounted) _say(context, "That didn't save. Try again.");
      }
    }

    final options = [
      (
        StatusInputStatus.available,
        StatusStatus.available,
        'Available',
        c.statusOk,
      ),
      (StatusInputStatus.dnd, StatusStatus.dnd, 'Do not disturb', c.statusBad),
      (StatusInputStatus.away, StatusStatus.away, 'Away', c.borderStrong),
    ];
    final note = status == StatusStatus.dnd && until != null
        ? 'Do not disturb until ${_untilText(until, ref.read(clockProvider)())}. '
              'Your desk phone shows the same status.'
        : 'Your desk phone shows the same status.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Semantics(
            container: true,
            label: 'Status',
            explicitChildNodes: true,
            child: Row(
              children: [
                for (final (input, value, label, dot) in options) ...[
                  if (input != StatusInputStatus.available)
                    const SizedBox(width: 4),
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: status == value,
                      label: label,
                      excludeSemantics: true,
                      onTap: () => pick(input),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => pick(input),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          alignment: Alignment.center,
                          decoration: status == value
                              ? BoxDecoration(
                                  color: c.surface,
                                  borderRadius: BorderRadius.circular(9),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x14000000),
                                      blurRadius: 2,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                )
                              : null,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (status == value) ...[
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: dot,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  style: VpType.body.copyWith(
                                    fontSize: 13,
                                    height: 1.2,
                                    fontWeight: FontWeight.w700,
                                    fontVariations: const [
                                      FontVariation('wght', 700),
                                    ],
                                    color: status == value
                                        ? c.text
                                        : c.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Text(note, style: vpMuted(context, size: 12, line: 18)),
        ),
      ],
    );
  }
}

String _untilText(DateTime until, DateTime now) {
  final u = until.toLocal(), n = now.toLocal();
  final sameDay = u.year == n.year && u.month == n.month && u.day == n.day;
  return sameDay ? clockTime(u) : whenShort(u, now);
}

/// How long Do not disturb lasts: (end or null for until changed,).
Future<(DateTime?,)?> _dndUntil(BuildContext context, WidgetRef ref) {
  final now = ref.read(clockProvider)().toLocal();
  final tomorrow = DateTime(now.year, now.month, now.day + 1, 8);
  final choices = <(String, DateTime?)>[
    ('For 1 hour', now.add(const Duration(hours: 1))),
    ('For 2 hours', now.add(const Duration(hours: 2))),
    ('Until 8 am tomorrow', tomorrow),
    ('Until I change it', null),
  ];
  return showModalBottomSheet<(DateTime?,)>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.vp.surface,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Do not disturb',
              style: vpTitle(sheet, size: 20, line: 26),
            ),
          ),
          for (final (label, end) in choices)
            VpRow(
              onTap: () => Navigator.of(sheet).pop((end,)),
              semanticLabel: label,
              children: [
                Expanded(child: VpRowText(title: label, subtitle: null)),
              ],
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

class _BatteryCard extends ConsumerWidget {
  const _BatteryCard({required this.status});
  final VpBatteryStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.statusWarn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calls may ring late on this phone',
            style: VpType.body.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              color: c.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${status.lateWakesLastWeek} calls this week reached this phone '
            'late because Android was saving battery. Let the app run in the '
            'background so calls ring on time.',
            style: vpMuted(context, size: 13, line: 19),
          ),
          VpLink(
            'Open battery settings',
            onTap: () => ref.read(phoneExtrasProvider).openBatterySettings(),
          ),
        ],
      ),
    );
  }
}

class _Appearance extends ConsumerWidget {
  const _Appearance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final theme = ref.watch(themePreferenceProvider);
    final bio = ref.watch(biometricUnlockProvider);
    return Material(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VpRowText(title: 'Dark mode', subtitle: null),
                const SizedBox(height: 8),
                VpSeg<ThemePreference>(
                  label: 'Dark mode',
                  options: const [
                    (ThemePreference.system, 'System'),
                    (ThemePreference.light, 'Light'),
                    (ThemePreference.dark, 'Dark'),
                  ],
                  value: theme,
                  onChanged: (t) =>
                      ref.read(themePreferenceProvider.notifier).set(t),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.border),
          MergeSemantics(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
              title: const VpRowText(
                title: 'Unlock with fingerprint or face',
                subtitle: 'Asked when the app opens',
              ),
              value: bio,
              onChanged: (on) async {
                final ok = await ref
                    .read(biometricUnlockProvider.notifier)
                    .set(on);
                if (!ok && context.mounted) {
                  _say(context, "This phone can't unlock the app that way.");
                }
              },
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.border),
        ],
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Semantics(
      container: true,
      button: true,
      label: 'Sign out',
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VpRadius.md),
          side: BorderSide(color: c.statusBad, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 54,
            child: Center(
              child: Text(
                'Sign out',
                style: TextStyle(
                  fontFamily: VpFonts.headline,
                  fontSize: 15,
                  height: 20 / 15,
                  fontWeight: FontWeight.w700,
                  fontVariations: const [FontVariation('wght', 700)],
                  color: c.statusBad,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

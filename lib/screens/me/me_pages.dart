import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth.dart';
import '../../calls/numbers.dart';
import '../../features/me/me_data.dart';
import '../../features/recents/media_player.dart';
import '../../features/recents/recents_format.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';
import '../../widgets/vp_list.dart';

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));

/// A page under Me: back, title, then [children], scrolling.
class _MePage extends StatelessWidget {
  const _MePage({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Material(
      color: c.canvas,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: 'Back',
                  excludeSemantics: true,
                  onTap: () => context.pop(),
                  child: InkWell(
                    onTap: () => context.pop(),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: VpSvgIcon(VpIcon.back, size: 22, colour: c.text),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: VpPageTitle(title),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// "When I don't answer": how long the desk phone and app ring, then a
/// mobile, then voicemail; or forward everything.
class CallSettingsScreen extends ConsumerStatefulWidget {
  const CallSettingsScreen({super.key});

  @override
  ConsumerState<CallSettingsScreen> createState() => _CallSettingsState();
}

class _CallSettingsState extends ConsumerState<CallSettingsScreen> {
  int? _ring;
  final _mobile = TextEditingController();
  int? _mobileSeconds;
  bool? _confirm;
  final _forward = TextEditingController();
  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    _mobile.dispose();
    _forward.dispose();
    super.dispose();
  }

  void _seed(CallSettings s) {
    if (_seeded) return;
    _seeded = true;
    _ring = s.ringSeconds;
    _mobile.text = s.followMeTo == null ? '' : formatAuNumber(s.followMeTo!);
    _mobileSeconds = s.followMeSeconds ?? 20;
    _confirm = s.followMeConfirm ?? true;
    _forward.text = s.forwardAlwaysTo == null
        ? ''
        : formatAuNumber(s.forwardAlwaysTo!);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      String? digits(TextEditingController t) =>
          t.text.trim().isEmpty ? '' : dialDigits(t.text);
      await ref
          .read(appApiProvider)
          .me
          .patchMeCallSettings(
            body: CallSettingsPatch(
              ringSeconds: _ring,
              followMeTo: digits(_mobile),
              followMeSeconds: _mobileSeconds,
              followMeConfirm: _confirm,
              forwardAlwaysTo: digits(_forward),
            ),
          );
      ref.invalidate(callSettingsProvider);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) _say(context, "That didn't save. Try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final s = ref.watch(callSettingsProvider).value;
    if (s != null) _seed(s);
    InputDecoration field(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: VpType.body.copyWith(color: c.textMuted),
      filled: true,
      fillColor: c.surface,
      constraints: const BoxConstraints(minHeight: 48),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VpRadius.md),
        borderSide: BorderSide(color: c.borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VpRadius.md),
        borderSide: BorderSide(color: c.focus, width: 2),
      ),
    );
    Widget section(String title, String? help, List<Widget> body) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VpRowText(title: title, subtitle: null),
          if (help != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Text(help, style: vpMuted(context, size: 13, line: 18)),
            )
          else
            const SizedBox(height: 8),
          ...body,
        ],
      ),
    );
    return _MePage(
      title: "When I don't answer",
      children: [
        if (s == null)
          const VpEmpty('Loading your call settings.')
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              callSettingsSummary(s),
              style: vpMuted(context, size: 14, line: 20),
            ),
          ),
          section('Ring my desk phone and app for', null, [
            VpSeg<int>(
              label: 'Ring for',
              options: [
                for (final n in {10, 15, 20, 30, _ring ?? 15}.toList()..sort())
                  (n, '$n s'),
              ],
              value: _ring ?? 15,
              onChanged: (n) => setState(() => _ring = n),
            ),
          ]),
          section('Then ring my mobile', 'Leave empty to go straight on.', [
            TextField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              style: VpType.body.copyWith(color: c.text),
              decoration: field('Mobile number'),
              onChanged: (_) => setState(() {}),
            ),
            if (_mobile.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              VpSeg<int>(
                label: 'Mobile rings for',
                options: [
                  for (final n in {
                    15,
                    20,
                    30,
                    _mobileSeconds ?? 20,
                  }.toList()..sort())
                    (n, '$n s'),
                ],
                value: _mobileSeconds ?? 20,
                onChanged: (n) => setState(() => _mobileSeconds = n),
              ),
              MergeSemantics(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const VpRowText(
                    title: 'Ask me to press 1 to take it',
                    subtitle: "So calls don't land in my mobile voicemail",
                  ),
                  value: _confirm ?? true,
                  onChanged: (v) => setState(() => _confirm = v),
                ),
              ),
            ],
          ]),
          section(
            'Forward all calls to',
            'Nothing rings here while this is set. Leave empty to turn it '
                'off.',
            [
              TextField(
                controller: _forward,
                keyboardType: TextInputType.phone,
                style: VpType.body.copyWith(color: c.text),
                decoration: field('Number'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: VpButton(label: 'Save', busy: _saving, onPressed: _save),
          ),
        ],
      ],
    );
  }
}

/// Recordings: this user's recorded calls (90 days, by permission), each
/// streamed from a fresh signed URL and never saved (APP8).
class RecordingsScreen extends ConsumerStatefulWidget {
  const RecordingsScreen({super.key});

  @override
  ConsumerState<RecordingsScreen> createState() => _RecordingsState();
}

class _RecordingsState extends ConsumerState<RecordingsScreen> {
  String? _playing;
  late final MediaPlayer _player = ref.read(mediaPlayerProvider);

  @override
  void dispose() {
    if (_playing != null) unawaited(_player.stop().catchError((_) {}));
    super.dispose();
  }

  Future<void> _toggle(Recording r) async {
    try {
      if (_playing == r.id) {
        if (_player.state.playing) return await _player.pause();
        return await _player.play();
      }
      final signed = await ref
          .read(appApiProvider)
          .recordings
          .postRecordingsIdMediaUrl(id: r.id);
      final (url, headers) = mediaRequest(
        signed.url,
        ref.read(apiConfigProvider),
        ref.read(accessTokenProvider),
      );
      await _player.open(url, headers);
      await _player.setSpeaker(true);
      setState(() => _playing = r.id);
      unawaited(_player.play());
    } catch (_) {
      if (mounted) _say(context, "This recording didn't play. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final list = ref.watch(recordingsProvider);
    final playback = ref.watch(playbackProvider).value;
    final now = ref.watch(clockProvider)();
    final items = list.value;
    return _MePage(
      title: 'Recordings',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Your recorded calls from the last 90 days. They play here and '
            'are never saved on this phone.',
            style: vpMuted(context, size: 14, line: 20),
          ),
        ),
        if (items == null && list.hasError)
          const VpEmpty("Recordings didn't load. Try again in a moment.")
        else if (items != null && items.isEmpty)
          const VpEmpty('No recorded calls.'),
        for (final r in items ?? const <Recording>[])
          VpRow(
            background: c.surface,
            children: [
              Expanded(
                child: VpRowText(
                  title: r.name ?? formatAuNumber(r.number),
                  subtitle:
                      '${r.direction == RecordingDirection.outgoing ? 'Outgoing' : 'Incoming'}'
                      ' · ${recentsWhen(r.at, now)}'
                      ' · ${minutesSeconds(r.durationSeconds)}',
                ),
              ),
              VpRoundIconButton(
                icon: _playing == r.id && (playback?.playing ?? false)
                    ? VpIcon.pause
                    : VpIcon.play,
                label: _playing == r.id && (playback?.playing ?? false)
                    ? 'Pause'
                    : 'Play ${r.name ?? formatAuNumber(r.number)}',
                onPressed: () => _toggle(r),
              ),
            ],
          ),
      ],
    );
  }
}

/// Signed-in devices: which ring, and signing others out.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final list = ref.watch(devicesProvider);
    final now = ref.watch(clockProvider)();
    final items = list.value;
    Future<void> rings(DeviceSummary d, bool on) async {
      try {
        await ref
            .read(appApiProvider)
            .device
            .patchMeDevicesId(
              id: d.id,
              body: MeDevicesIdRequestBody(rings: on),
            );
        ref.invalidate(devicesProvider);
      } catch (_) {
        if (context.mounted) _say(context, "That didn't save. Try again.");
      }
    }

    Future<void> signOut(DeviceSummary d) async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (dlg) => AlertDialog(
          title: Text('Sign out ${d.label}?'),
          content: const Text('Calls stop ringing there straight away.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dlg).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dlg).pop(true),
              child: const Text('Sign out'),
            ),
          ],
        ),
      );
      if (yes != true) return;
      try {
        await ref.read(appApiProvider).device.postMeDevicesIdSignOut(id: d.id);
        ref.invalidate(devicesProvider);
      } catch (_) {
        if (context.mounted) _say(context, "That didn't work. Try again.");
      }
    }

    return _MePage(
      title: 'Signed-in devices',
      children: [
        if (items == null && list.hasError)
          const VpEmpty("Devices didn't load. Try again in a moment.")
        else if (items != null && items.isEmpty)
          const VpEmpty('No devices.'),
        for (final d in items ?? const <DeviceSummary>[])
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MergeSemantics(
                  child: Row(
                    children: [
                      Expanded(
                        child: VpRowText(
                          title: d.isThisDevice
                              ? '${d.label} (this phone)'
                              : d.label,
                          subtitle: d.isThisDevice
                              ? 'Rings for your calls'
                              : d.lastSeenAt == null
                              ? null
                              : 'Last used ${recentsWhen(d.lastSeenAt!, now)}',
                        ),
                      ),
                      Text(
                        'Rings',
                        style: VpType.caption.copyWith(color: c.textMuted),
                      ),
                      Switch(value: d.rings, onChanged: (on) => rings(d, on)),
                    ],
                  ),
                ),
                if (d.canSignOut)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: VpLink('Sign out', onTap: () => signOut(d)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

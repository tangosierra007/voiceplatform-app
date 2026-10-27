import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../calls/call_actions.dart';
import '../../features/recents/greetings.dart';
import '../../features/recents/media_player.dart';
import '../../features/recents/recents_format.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';
import '../../widgets/vp_list.dart';

String greetingTitle(GreetingKind k) => switch (k) {
  GreetingKind.unavailable => "When I can't answer",
  GreetingKind.busy => "When I'm on a call",
  _ => 'My name',
};

String greetingSubtitle(Greeting g) => g.isCustom
    ? 'Your recording${g.durationSeconds == null ? '' : ' · ${minutesSeconds(g.durationSeconds!)}'}'
    : g.kind == GreetingKind.name
    ? 'Not recorded'
    : 'The standard greeting';

/// The "Greeting" link from Voicemail: record each greeting in the app and
/// upload it (M4A, up to 2 minutes), play it back, or go back to the
/// standard one.
class GreetingScreen extends ConsumerWidget {
  const GreetingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final greetings = ref.watch(greetingsProvider);
    final byKind = {for (final g in greetings.value ?? const []) g.kind: g};
    return Material(
      color: c.canvas,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
              child: Row(
                children: [
                  Semantics(
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
                          child: VpSvgIcon(
                            VpIcon.back,
                            size: 22,
                            colour: c.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: VpPageTitle('Greeting'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                "Callers hear these when you don't pick up. Each can be up to "
                '2 minutes.',
                style: vpMuted(context, size: 14, line: 20),
              ),
            ),
            if (greetings.hasError && greetings.value == null)
              const VpEmpty("Greetings didn't load. Try again in a moment.")
            else
              for (final k in const [
                GreetingKind.unavailable,
                GreetingKind.busy,
                GreetingKind.name,
              ])
                _GreetingRow(
                  kind: k,
                  greeting: byKind[k] ?? Greeting(kind: k, isCustom: false),
                ),
          ],
        ),
      ),
    );
  }
}

class _GreetingRow extends ConsumerWidget {
  const _GreetingRow({required this.kind, required this.greeting});
  final GreetingKind kind;
  final Greeting greeting;

  VoicemailGreetingsKind get _apiKind =>
      VoicemailGreetingsKind.fromJson(kind.json!);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VpRowText(
            title: greetingTitle(kind),
            subtitle: greetingSubtitle(greeting),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              VpButton(
                label: greeting.isCustom ? 'Record again' : 'Record',
                icon: VpIcon.mic,
                kind: VpButtonKind.outline,
                large: false,
                height: 40,
                onPressed: () => _record(context, ref),
              ),
              if (greeting.isCustom) ...[
                VpButton(
                  label: 'Play',
                  icon: VpIcon.play,
                  kind: VpButtonKind.ghost,
                  large: false,
                  height: 40,
                  onPressed: () => _play(context, ref),
                ),
                if (kind != GreetingKind.name)
                  VpButton(
                    label: 'Use the standard one',
                    kind: VpButtonKind.ghost,
                    large: false,
                    height: 40,
                    onPressed: () => _reset(context, ref),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _play(BuildContext context, WidgetRef ref) async {
    try {
      final signed = await ref
          .read(appApiProvider)
          .voicemail
          .postVoicemailGreetingsKindMediaUrl(kind: _apiKind);
      final (url, headers) = mediaRequest(
        signed.url,
        ref.read(apiConfigProvider),
        ref.read(accessTokenProvider),
      );
      final p = ref.read(mediaPlayerProvider);
      await p.open(url, headers);
      ref.read(mediaOwnerProvider.notifier).set('greeting:${kind.json}');
      await p.setSpeaker(true);
      unawaited(p.play());
    } catch (_) {
      if (context.mounted) _say(context, "It didn't play. Try again.");
    }
  }

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(appApiProvider)
          .voicemail
          .deleteVoicemailGreetingsKind(kind: _apiKind);
      ref.invalidate(greetingsProvider);
    } catch (_) {
      if (context.mounted) _say(context, "That didn't save. Try again.");
    }
  }

  Future<void> _record(BuildContext context, WidgetRef ref) async {
    final mic = ref.read(micPermissionProvider);
    if (!await mic.isGranted() && !await mic.request()) {
      if (context.mounted) {
        _say(
          context,
          'Recording needs the microphone. Allow it in Settings, then try '
          'again.',
        );
      }
      return;
    }
    if (!context.mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: context.vp.surface,
      builder: (_) => RecordGreetingSheet(kind: kind),
    );
    if (saved == true) ref.invalidate(greetingsProvider);
  }
}

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));

enum _Step { recording, recorded, saving }

/// Recording one greeting: the time so far against 2:00 (it stops itself
/// there), then Save, Record again or Cancel.
class RecordGreetingSheet extends ConsumerStatefulWidget {
  const RecordGreetingSheet({super.key, required this.kind});
  final GreetingKind kind;

  @override
  ConsumerState<RecordGreetingSheet> createState() =>
      _RecordGreetingSheetState();
}

class _RecordGreetingSheetState extends ConsumerState<RecordGreetingSheet> {
  late final GreetingRecorder _rec = ref.read(greetingRecorderProvider);
  _Step _step = _Step.recording;
  final _clock = Stopwatch();
  Timer? _tick;
  File? _file;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _rec.start();
      _clock
        ..reset()
        ..start();
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_clock.elapsed >= greetingLimit) {
          unawaited(_stop());
        } else if (mounted) {
          setState(() {});
        }
      });
      if (mounted) setState(() => _step = _Step.recording);
    } catch (_) {
      if (mounted) setState(() => _error = "Recording didn't start.");
    }
  }

  Future<void> _stop() async {
    _tick?.cancel();
    _clock.stop();
    final f = await _rec.stop();
    if (!mounted) return;
    setState(() {
      _file = f;
      _step = _Step.recorded;
    });
  }

  Future<void> _again() async {
    await _discard();
    if (mounted) setState(() => _file = null);
    await _start();
  }

  Future<void> _discard() async {
    final f = _file;
    _file = null;
    if (f != null) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    setState(() {
      _step = _Step.saving;
      _error = null;
    });
    try {
      await ref.read(greetingUploadProvider)(widget.kind, f);
      _file = null;
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _step = _Step.recorded;
          _error = "It didn't upload. Try again.";
        });
      }
    }
  }

  Future<void> _cancel() async {
    _tick?.cancel();
    if (_step == _Step.recording) {
      try {
        await _rec.cancel();
      } catch (_) {}
    }
    await _discard();
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_discard());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final elapsed = _clock.elapsed > greetingLimit
        ? greetingLimit
        : _clock.elapsed;
    final recording = _step == _Step.recording;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                greetingTitle(widget.kind),
                style: vpTitle(context, size: 20, line: 26),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              label: recording
                  ? 'Recording, ${minutesSeconds(elapsed.inSeconds)} of 2:00'
                  : 'Recorded ${minutesSeconds(elapsed.inSeconds)}',
              excludeSemantics: true,
              child: Row(
                children: [
                  if (recording) ...[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: c.statusBad,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    '${minutesSeconds(elapsed.inSeconds)} / 2:00',
                    style: vpTitle(context, size: 24, line: 30).copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: VpType.body.copyWith(fontSize: 14, color: c.statusBad),
              ),
            ],
            const SizedBox(height: 16),
            if (recording)
              VpButton(
                label: 'Stop',
                icon: VpIcon.stop,
                large: false,
                height: VpSize.controlHeight,
                onPressed: _stop,
              )
            else ...[
              VpButton(
                label: 'Save',
                large: false,
                height: VpSize.controlHeight,
                busy: _step == _Step.saving,
                onPressed: _file == null ? null : _save,
              ),
              const SizedBox(height: 8),
              VpButton(
                label: 'Record again',
                kind: VpButtonKind.outline,
                large: false,
                height: VpSize.controlHeight,
                onPressed: _step == _Step.saving ? null : _again,
              ),
            ],
            const SizedBox(height: 4),
            VpButton(
              label: 'Cancel',
              kind: VpButtonKind.ghost,
              large: false,
              height: VpSize.controlHeight,
              onPressed: _step == _Step.saving ? null : _cancel,
            ),
          ],
        ),
      ),
    );
  }
}

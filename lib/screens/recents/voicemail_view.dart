import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth.dart';
import '../../calls/directory.dart';
import '../../emergency/emergency.dart';
import '../../features/recents/media_player.dart';
import '../../features/recents/recents_data.dart';
import '../../features/recents/recents_format.dart';
import '../../features/recents/voicemail_actions.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';
import '../../widgets/vp_list.dart';

/// AppVoicemail, inside Recents: the boxes (All boxes, Mine and the shared
/// ones, with new counts), the open message in the player, the rest below.
class VoicemailView extends ConsumerWidget {
  const VoicemailView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boxes = ref.watch(voicemailBoxesProvider).value ?? const [];
    final box = ref.watch(voicemailBoxProvider);
    final messages = ref.watch(voicemailMessagesProvider(box));
    final openId = ref.watch(openVoicemailProvider);
    final matcher = ref.watch(contactMatcherProvider);
    final now = ref.watch(clockProvider)();
    final items = messages.value;
    final open = items == null || items.isEmpty
        ? null
        : items.where((m) => m.id == openId).firstOrNull ?? items.first;

    String boxLabel(VoicemailBox b) {
      final name = b.kind == VoicemailBoxKind.own ? 'Mine' : b.name;
      return b.newCount > 0 ? '$name ${b.newCount}' : name;
    }

    // One scrolling list, so large text never pushes the player off screen.
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(voicemailBoxesProvider);
        ref.invalidate(voicemailMessagesProvider(box));
        try {
          await ref.read(voicemailMessagesProvider(box).future);
        } catch (_) {}
      },
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (boxes.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: VpSeg<String?>(
                label: 'Boxes',
                options: [
                  (null, 'All boxes'),
                  for (final b in boxes) (b.id, boxLabel(b)),
                ],
                value: box,
                onChanged: (id) {
                  ref.read(openVoicemailProvider.notifier).set(null);
                  ref.read(voicemailBoxProvider.notifier).set(id);
                },
              ),
            ),
          if (open != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: VoicemailPlayerCard(
                message: open,
                title: voicemailTitle(open, matcher),
                when: recentsWhen(open.at, now),
              ),
            ),
            Divider(height: 1, thickness: 1, color: context.vp.border),
          ],
          if (items == null && messages.hasError)
            const VpEmpty("Voicemail didn't load. Pull down to try again.")
          else if (items != null && items.isEmpty)
            const VpEmpty('No voicemail.')
          else if (items != null)
            for (final m in items)
              if (m.id != open?.id)
                _VoicemailRow(
                  message: m,
                  title: voicemailTitle(m, matcher),
                  when: recentsWhen(m.at, now),
                ),
        ],
      ),
    );
  }
}

class _VoicemailRow extends ConsumerWidget {
  const _VoicemailRow({
    required this.message,
    required this.title,
    required this.when,
  });
  final VoicemailMessage message;
  final String title;
  final String when;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final m = message;
    final sub = voicemailSubtitle(m, title);
    final meta = '$when · ${minutesSeconds(m.durationSeconds)}';
    final actions = ref.read(voicemailPlayerProvider.notifier);
    return Semantics(
      button: true,
      label: '${m.heard ? '' : 'New. '}$title, $sub, $meta',
      excludeSemantics: true,
      onTap: () => ref.read(openVoicemailProvider.notifier).set(m.id),
      customSemanticsActions: {
        CustomSemanticsAction(
          label: m.heard ? 'Mark as new' : 'Mark heard',
        ): () =>
            _markHeard(context, actions, m),
      },
      child: InkWell(
        onTap: () => ref.read(openVoicemailProvider.notifier).set(m.id),
        onLongPress: () => _markHeard(context, actions, m),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              _NewDot(visible: !m.heard),
              const SizedBox(width: 12),
              Expanded(
                child: VpRowText(
                  title: title,
                  subtitle: sub,
                  titleWeight: m.heard ? FontWeight.w600 : FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                meta,
                style: VpType.caption.copyWith(
                  color: c.textMuted,
                  fontWeight: FontWeight.w500,
                  fontVariations: const [FontVariation('wght', 500)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _markHeard(
  BuildContext context,
  VoicemailPlayerNotifier actions,
  VoicemailMessage m,
) async {
  try {
    await actions.markHeard(m, heard: !m.heard);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("That didn't save. Try again.")),
      );
    }
  }
}

class _NewDot extends StatelessWidget {
  const _NewDot({required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: visible
        ? BoxDecoration(color: context.vp.brand, shape: BoxShape.circle)
        : null,
  );
}

/// The open message: who and when, play or pause, the waveform, the times,
/// then Call back, Speaker and Delete.
class VoicemailPlayerCard extends ConsumerWidget {
  const VoicemailPlayerCard({
    super.key,
    required this.message,
    required this.title,
    required this.when,
  });
  final VoicemailMessage message;
  final String title;
  final String when;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final m = message;
    final player = ref.watch(voicemailPlayerProvider);
    final loaded = player.loadedId == m.id;
    final playback = loaded
        ? ref.watch(playbackProvider).value ??
              ref.read(mediaPlayerProvider).state
        : const PlaybackState();
    final total = playback.duration ?? Duration(seconds: m.durationSeconds);
    final position = playback.position > total ? total : playback.position;
    final fraction = total.inMilliseconds == 0
        ? 0.0
        : position.inMilliseconds / total.inMilliseconds;
    final actions = ref.read(voicemailPlayerProvider.notifier);
    final number = isPrivateNumber(m.number) ? null : m.number;
    final sub = voicemailSubtitle(m, title);

    return Semantics(
      container: true,
      label: '${m.heard ? '' : 'New. '}$title, $sub, $when',
      customSemanticsActions: {
        CustomSemanticsAction(
          label: m.heard ? 'Mark as new' : 'Mark heard',
        ): () =>
            _markHeard(context, actions, m),
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!m.heard) ...[
                    const _NewDot(visible: true),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VpType.body.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontVariations: const [FontVariation('wght', 700)],
                        color: c.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$when · ${m.boxName} box',
                    style: VpType.caption.copyWith(
                      color: c.textMuted,
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                  ),
                ],
              ),
            ),
            if (number != null && sub.contains(' · '))
              ExcludeSemantics(
                child: Text(
                  sub.split(' · ').first,
                  style: VpType.body.copyWith(
                    fontSize: 13,
                    height: 18 / 13,
                    color: c.textMuted,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                _PlayButton(
                  playing: playback.playing,
                  loading: loaded && playback.loading,
                  onTap: () => _toggle(context, actions, m),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Waveform(
                    values: m.waveform ?? const [],
                    played: fraction,
                    position: position,
                    total: total,
                    onSeek: loaded
                        ? (f) => actions.seek(
                            Duration(
                              milliseconds: (total.inMilliseconds * f).round(),
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    minutesSeconds(position.inSeconds),
                    style: _times(context),
                  ),
                  Text(minutesSeconds(total.inSeconds), style: _times(context)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Large text wraps a label and the button grows; its neighbour
            // grows with it.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: VpButton(
                      label: 'Call back',
                      icon: VpIcon.phone,
                      large: false,
                      dense: true,
                      height: 40,
                      onPressed: number == null
                          ? null
                          : () => dialNumber(context, ref, number),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: VpButton(
                      label: 'Speaker',
                      icon: VpIcon.speaker,
                      kind: VpButtonKind.outline,
                      large: false,
                      dense: true,
                      height: 40,
                      toggled: player.speaker,
                      onPressed: () => actions.setSpeaker(!player.speaker),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: 'Delete',
                    excludeSemantics: true,
                    onTap: () => _delete(context, actions, m, title),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(VpRadius.md),
                      onTap: () => _delete(context, actions, m, title),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: VpSvgIcon(
                            VpIcon.trash,
                            size: 18,
                            colour: c.statusBad,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _times(BuildContext context) => VpType.caption.copyWith(
    color: context.vp.textMuted,
    fontWeight: FontWeight.w500,
    fontVariations: const [FontVariation('wght', 500)],
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  Future<void> _toggle(
    BuildContext context,
    VoicemailPlayerNotifier actions,
    VoicemailMessage m,
  ) async {
    try {
      await actions.toggle(m);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text("This voicemail didn't play. Try again."),
          ),
        );
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    VoicemailPlayerNotifier actions,
    VoicemailMessage m,
    String title,
  ) async {
    final shared = m.boxName != 'Mine';
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete this voicemail?'),
        content: Text(
          shared
              ? 'The message from $title goes for everyone who shares the '
                    '${m.boxName} box.'
              : 'The message from $title goes for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await actions.delete(m);
    } on DioException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            e.response?.statusCode == 409
                ? "This voicemail is kept on hold, so it can't be deleted."
                : "It didn't delete. Try again.",
          ),
        ),
      );
    }
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.onTap,
  });
  final bool playing;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.onBrand,
                      ),
                    )
                  : VpSvgIcon(
                      playing ? VpIcon.pause : VpIcon.play,
                      size: 20,
                      colour: c.onBrand,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The message's waveform: played bars in brand, the rest border-strong.
/// A slider for screen readers; tap or drag to seek once loaded.
class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.values,
    required this.played,
    required this.position,
    required this.total,
    required this.onSeek,
  });
  final List<num> values;
  final double played;
  final Duration position;
  final Duration total;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final bars = values.isEmpty ? List<num>.filled(36, 0.3) : values;
    void seekAt(Offset local, double width) {
      if (onSeek == null || width <= 0) return;
      onSeek!((local.dx / width).clamp(0.0, 1.0));
    }

    final step = total.inMilliseconds == 0 ? 0.0 : 5000 / total.inMilliseconds;
    String at(double f) =>
        '${minutesSeconds((total.inSeconds * f.clamp(0.0, 1.0)).round())} of '
        '${minutesSeconds(total.inSeconds)}';
    return Semantics(
      slider: true,
      label: 'Position',
      value: at(played),
      increasedValue: onSeek == null ? null : at(played + step),
      decreasedValue: onSeek == null ? null : at(played - step),
      onIncrease: onSeek == null
          ? null
          : () => onSeek!((played + step).clamp(0.0, 1.0)),
      onDecrease: onSeek == null
          ? null
          : () => onSeek!((played - step).clamp(0.0, 1.0)),
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekAt(d.localPosition, box.maxWidth),
          onHorizontalDragUpdate: (d) => seekAt(d.localPosition, box.maxWidth),
          // 32 px of bars in a 48 px band to touch.
          child: SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < bars.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    child: Container(
                      height: 6 + 26 * bars[i].toDouble().clamp(0.0, 1.0),
                      decoration: BoxDecoration(
                        color: (i + 0.5) / bars.length <= played
                            ? c.brand
                            : c.borderStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

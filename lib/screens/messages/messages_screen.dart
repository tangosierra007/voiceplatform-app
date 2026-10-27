import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth.dart';
import '../../calls/directory.dart';
import '../../calls/numbers.dart';
import '../../features/messages/messages_data.dart';
import '../../features/recents/recents_format.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_icons.dart';
import '../../widgets/vp_list.dart';

/// AppMessages: texts on the user's SMS lines, with a chip per line.
class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  static String threadPath(String id) => '/thread/$id';
  static const newPath = '/new-message';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final lines = ref.watch(smsLinesProvider).value ?? const <SmsLine>[];
    final line = ref.watch(messagesLineProvider);
    final page = ref.watch(threadsProvider(line));
    final matcher = ref.watch(contactMatcherProvider);
    final now = ref.watch(clockProvider)();
    final items = page.value?.items;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VpPageTitle(
                  'Messages',
                  trailing: Semantics(
                    button: true,
                    label: 'New message',
                    excludeSemantics: true,
                    onTap: () => context.push(newPath),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => context.push(newPath),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: c.brand,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: VpSvgIcon(
                              VpIcon.plus,
                              size: 20,
                              colour: c.onBrand,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (lines.length > 1) ...[
                  const SizedBox(height: 12),
                  VpSeg<String?>(
                    label: 'Line',
                    options: [
                      (null, 'All'),
                      for (final l in lines) (l.id, l.label),
                    ],
                    value: line,
                    onChanged: (id) =>
                        ref.read(messagesLineProvider.notifier).set(id),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(threadsProvider(line));
                try {
                  await ref.read(threadsProvider(line).future);
                } catch (_) {}
              },
              child: ListView(
                padding: EdgeInsets.zero,
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (items == null && page.hasError)
                    const VpEmpty(
                      "Messages didn't load. Pull down to try again.",
                    )
                  else if (items != null && items.isEmpty)
                    const VpEmpty('No texts yet.'),
                  for (final t in items ?? const <Thread>[])
                    _ThreadRow(
                      thread: t,
                      title:
                          t.name ??
                          matcher.match(t.number)?.name ??
                          formatAuNumber(t.number),
                      when: recentsWhen(t.lastAt, now),
                    ),
                  if (items != null) const _WhatsAppCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.title,
    required this.when,
  });
  final Thread thread;
  final String title;
  final String when;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final t = thread;
    final unread = t.unread > 0;
    return VpRow(
      onTap: () => context.push(MessagesScreen.threadPath(t.id)),
      semanticLabel:
          '${unread ? 'Unread. ' : ''}$title, ${t.lastText}, $when, '
          '${t.lineLabel}',
      children: [
        ExcludeSemantics(
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              shape: BoxShape.circle,
            ),
            child: Text(
              initialsOf(title.startsWith(RegExp('[0-9+]')) ? '#' : title),
              textScaler: TextScaler.noScaling,
              style: VpType.body.copyWith(
                fontSize: 14,
                height: 1,
                fontWeight: FontWeight.w800,
                fontVariations: const [FontVariation('wght', 800)],
                color: c.text,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VpType.body.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontVariations: const [FontVariation('wght', 700)],
                          color: c.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      when,
                      style: VpType.caption.copyWith(color: c.textMuted),
                    ),
                  ],
                ),
                Text(
                  t.lastText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VpType.body.copyWith(
                    fontSize: 13,
                    height: 18 / 13,
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    fontVariations: [FontVariation('wght', unread ? 700 : 500)],
                    color: unread ? c.text : c.textMuted,
                  ),
                ),
                Text(
                  t.lineLabel,
                  style: VpType.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (unread) ...[
          const SizedBox(width: 12),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
          ),
        ],
      ],
    );
  }
}

class _WhatsAppCard extends StatelessWidget {
  const _WhatsAppCard();

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderStrong),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VpSvgIcon(VpIcon.whatsApp, size: 18, colour: c.statusOk),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'WhatsApp, coming later. ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontVariations: const [FontVariation('wght', 700)],
                      color: c.text,
                    ),
                  ),
                  TextSpan(
                    text: 'Chats will appear here with your texts.',
                    style: TextStyle(color: c.textMuted),
                  ),
                ],
              ),
              style: VpType.caption.copyWith(height: 17 / 12),
            ),
          ),
        ],
      ),
    );
  }
}

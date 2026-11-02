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
import '../../widgets/vp_wide.dart';
import '../../shell/layout.dart';
import '../../shell/list_detail.dart';
import '../../shell/vp_tab_bar.dart';
import 'thread_screen.dart';

/// AppMessages: texts on the user's SMS lines, with a chip per line. At
/// windows that split ([isListDetailLayout], about 680 dp), FoldMessages: the
/// list on the left, the conversation
/// beside it.
class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  static String threadPath(String id) => '/thread/$id';
  static const newPath = '/new-message';

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutSwitchListener(
    // Folded with a conversation open beside the list: it opens full
    // screen, as it would have on the phone. Only when Messages is the tab
    // on show.
    onChange: (wide) {
      final id = ref.read(pickedThreadProvider);
      if (!wide &&
          id != null &&
          TickerMode.valuesOf(context).enabled &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        context.push(threadPath(id));
      }
    },
    child: isListDetailLayout(context)
        ? const _WideMessages()
        : const _PhoneMessages(),
  );
}

class _PhoneMessages extends ConsumerWidget {
  const _PhoneMessages();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                VpPageTitle('Messages', trailing: const _NewMessageButton()),
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
                key: const PageStorageKey('messages-threads'),
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
                      title: threadTitle(t, matcher),
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

/// The "+" that starts a new text.
class _NewMessageButton extends StatelessWidget {
  const _NewMessageButton();

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Semantics(
      button: true,
      label: 'New message',
      excludeSemantics: true,
      onTap: () => context.push(MessagesScreen.newPath),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push(MessagesScreen.newPath),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: VpSvgIcon(VpIcon.plus, size: 20, colour: c.onBrand),
            ),
          ),
        ),
      ),
    );
  }
}

/// FoldMessages: the conversations (360 dp) and the one picked beside them.
/// Until the person picks one, the first is shown, and stays unread.
class _WideMessages extends ConsumerWidget {
  const _WideMessages();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(smsLinesProvider).value ?? const <SmsLine>[];
    final line = ref.watch(messagesLineProvider);
    final page = ref.watch(threadsProvider(line));
    final matcher = ref.watch(contactMatcherProvider);
    final now = ref.watch(clockProvider)();
    final picked = ref.watch(pickedThreadProvider);
    final items = page.value?.items;
    final shown = picked ?? items?.firstOrNull?.id;
    String title(Thread t) => threadTitle(t, matcher);
    return SafeArea(
      bottom: false,
      child: ListDetailLayout(
        list: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WideListHeader(
              title: 'Messages',
              trailing: const _NewMessageButton(),
              children: [
                if (lines.length > 1)
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
                  key: const PageStorageKey('messages-threads'),
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
                      _WideThreadRow(
                        thread: t,
                        title: title(t),
                        when: recentsWhen(t.lastAt, now),
                        selected: t.id == shown,
                        onTap: () =>
                            ref.read(pickedThreadProvider.notifier).pick(t.id),
                      ),
                    if (items != null) const _WhatsAppCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
        detail: shown == null
            ? const SizedBox.shrink()
            : ThreadView(
                key: ValueKey(shown),
                threadId: shown,
                wide: true,
                markRead: picked != null,
                onEngaged: picked == null
                    ? () => ref.read(pickedThreadProvider.notifier).pick(shown)
                    : null,
              ),
      ),
    );
  }
}

/// FoldMessages' `.lrow`: initials, name with the line pill, the last text
/// (bold when unread), the time, and the unread count.
class _WideThreadRow extends StatelessWidget {
  const _WideThreadRow({
    required this.thread,
    required this.title,
    required this.when,
    required this.selected,
    required this.onTap,
  });
  final Thread thread;
  final String title;
  final String when;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final t = thread;
    final unread = t.unread > 0;
    return WideListRow(
      selected: selected,
      onTap: onTap,
      semanticLabel:
          '${unread ? '${t.unread} unread. ' : ''}$title, ${t.lastText}, '
          '$when, ${t.lineLabel}',
      children: [
        ThreadAvatar(title: title),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The name with the line pill beside it, both in full when there's
              // room. With little room (large text, a narrow list) the pill
              // moves under the name rather than squeezing it.
              LayoutBuilder(
                builder: (context, box) {
                  final name = Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VpType.body.copyWith(
                      fontSize: 15,
                      height: 22 / 15,
                      fontWeight: FontWeight.w700,
                      fontVariations: const [FontVariation('wght', 700)],
                      color: c.text,
                    ),
                  );
                  final pill = VpOffPill(t.lineLabel);
                  if (box.maxWidth < 200) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        name,
                        const SizedBox(height: 2),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: box.maxWidth),
                          child: pill,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Flexible(child: name),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        // The name keeps at least 80 dp.
                        constraints: BoxConstraints(
                          maxWidth: box.maxWidth - 86,
                        ),
                        child: pill,
                      ),
                    ],
                  );
                },
              ),
              Text(
                t.lastText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VpType.caption.copyWith(
                  fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                  fontVariations: [FontVariation('wght', unread ? 700 : 500)],
                  color: unread ? c.text : c.textMuted,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(when, style: VpType.caption.copyWith(color: c.textMuted)),
            if (unread) ...[
              const SizedBox(height: 4),
              VpCountBadge(count: t.unread),
            ],
          ],
        ),
      ],
    );
  }
}

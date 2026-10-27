import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth.dart';
import '../../calls/directory.dart';
import '../../calls/numbers.dart';
import '../../emergency/emergency.dart';
import '../../features/messages/messages_data.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';
import '../../widgets/vp_list.dart';
import 'messages_screen.dart';

const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// `Today`, `Yesterday`, `Friday`, `14 Oct`.
String dayLabel(DateTime at, DateTime now) {
  final a = at.toLocal(), n = now.toLocal();
  final d = DateTime(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime(a.year, a.month, a.day)).inDays;
  if (d <= 0) return 'Today';
  if (d == 1) return 'Yesterday';
  if (d < 7) return _days[a.weekday - 1];
  return whenShort(at, now);
}

String _status(MessageStatus s) => switch (s) {
  MessageStatus.queued => 'Sending',
  MessageStatus.sent => 'Sent',
  MessageStatus.delivered => 'Delivered',
  MessageStatus.failed => 'Not delivered',
  _ => '',
};

/// AppThread: one conversation, with who sent each text and whether it was
/// delivered; the reply box says which line it goes from.
class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({super.key, required this.threadId});
  final String threadId;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final t = _thread();
      if (t != null && t.unread > 0) {
        unawaited(ref.read(messageActionsProvider).markRead(t.id));
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Thread? _thread() => (ref.read(threadsProvider(null)).value?.items ?? [])
      .where((t) => t.id == widget.threadId)
      .firstOrNull;

  Future<void> _send(Thread t) async {
    final text = _text.text.trim();
    if (text.isEmpty || smsCount(text).tooLong) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(messageActionsProvider)
          .send(lineId: t.lineId, to: t.number, text: text);
      _text.clear();
    } catch (_) {
      _error = "The text didn't send. Try again.";
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final threads = ref.watch(threadsProvider(null));
    final thread = (threads.value?.items ?? const <Thread>[])
        .where((t) => t.id == widget.threadId)
        .firstOrNull;
    final lines = ref.watch(smsLinesProvider).value ?? const <SmsLine>[];
    final messages = ref.watch(threadMessagesProvider(widget.threadId));
    final matcher = ref.watch(contactMatcherProvider);
    final now = ref.watch(clockProvider)();
    final title = thread == null
        ? ''
        : thread.name ??
              matcher.match(thread.number)?.name ??
              formatAuNumber(thread.number);
    final line = thread == null
        ? null
        : lines.where((l) => l.id == thread.lineId).firstOrNull;
    final items = messages.value ?? const <Message>[];

    final body = <Widget>[];
    String? lastDay;
    for (final m in items) {
      final day = dayLabel(m.at, now);
      if (day != lastDay) {
        body.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: Text(
                day,
                style: VpType.caption.copyWith(
                  color: c.textMuted,
                  fontWeight: FontWeight.w700,
                  fontVariations: const [FontVariation('wght', 700)],
                ),
              ),
            ),
          ),
        );
        lastDay = day;
      }
      body.add(_Bubble(message: m));
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border)),
              ),
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
                            colour: c.brandText,
                          ),
                        ),
                      ),
                    ),
                  ),
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
                        initialsOf(title),
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: VpRowText(
                        title: title,
                        subtitle: thread == null
                            ? null
                            : 'Texting ${thread.lineLabel}',
                      ),
                    ),
                  ),
                  if (thread != null)
                    VpRoundIconButton(
                      icon: VpIcon.phone,
                      label: 'Call $title',
                      onPressed: () => dialNumber(context, ref, thread.number),
                    ),
                ],
              ),
            ),
            Expanded(
              child: messages.hasError && items.isEmpty
                  ? const VpEmpty("This conversation didn't load.")
                  : ListView(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      children: [
                        for (final w in body.reversed)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: w,
                          ),
                      ],
                    ),
            ),
            if (thread != null)
              _ReplyBox(
                controller: _text,
                from: line == null
                    ? 'From ${thread.lineLabel}'
                    : 'From ${line.label} ${formatAuNumber(line.number)}',
                canSend: line?.canSend ?? true,
                sending: _sending,
                error: _error,
                onChanged: () => setState(() {}),
                onSend: () => _send(thread),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final Message message;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final m = message;
    final out = m.direction == MessageDirection.out;
    final text = m.kind == MessageKind.picture
        ? 'Picture message (not shown yet)'
        : (m.text ?? '');
    final meta = [
      if (out && m.senderName != null) m.senderName!,
      clockTime(m.at.toLocal()),
      if (out) _status(m.status),
    ].where((s) => s.isNotEmpty).join(' · ');
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.8,
        alignment: out ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: out
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                // Ink with light text; charcoal on the dark canvas, as the
                // dark artboard.
                color: out
                    ? (Theme.of(context).brightness == Brightness.dark
                          ? c.charcoal800
                          : c.ink900)
                    : c.surface,
                border: out ? null : Border.all(color: c.border),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(out ? 16 : 4),
                  bottomRight: Radius.circular(out ? 4 : 16),
                ),
              ),
              child: Text(
                text,
                style: VpType.body.copyWith(
                  fontSize: 15,
                  height: 1.4,
                  fontStyle: m.kind == MessageKind.picture
                      ? FontStyle.italic
                      : null,
                  color: out ? c.grey100 : c.text,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              meta,
              style: VpType.caption.copyWith(
                fontSize: 11,
                color: m.status == MessageStatus.failed
                    ? c.statusBad
                    : c.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyBox extends StatelessWidget {
  const _ReplyBox({
    required this.controller,
    required this.from,
    required this.canSend,
    required this.sending,
    required this.error,
    required this.onChanged,
    required this.onSend,
  });
  final TextEditingController controller;
  final String from;
  final bool canSend;
  final bool sending;
  final String? error;
  final VoidCallback onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final text = controller.text.trim();
    final count = smsCount(controller.text);
    final ready = canSend && !sending && text.isNotEmpty && !count.tooLong;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    canSend ? from : '$from · this line receives only',
                    style: VpType.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontVariations: const [FontVariation('wght', 700)],
                      color: c.textMuted,
                    ),
                  ),
                ),
                if (count.units > 0)
                  Semantics(
                    liveRegion: count.tooLong,
                    child: Text(
                      smsCountText(count),
                      style: VpType.caption.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontVariations: const [FontVariation('wght', 700)],
                        color: count.tooLong ? c.statusBad : c.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: canSend,
                  minLines: 1,
                  maxLines: 5,
                  onChanged: (_) => onChanged(),
                  style: VpType.body.copyWith(fontSize: 15, color: c.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Text message',
                    hintStyle: VpType.body.copyWith(
                      fontSize: 15,
                      color: c.textMuted,
                    ),
                    constraints: const BoxConstraints(minHeight: 48),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: c.borderStrong),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: c.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: c.focus, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                enabled: ready,
                label: 'Send',
                excludeSemantics: true,
                onTap: ready ? onSend : null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: ready ? onSend : null,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: ready ? c.brand : c.surfaceRaised,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: sending
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.onBrand,
                            ),
                          )
                        : VpSvgIcon(
                            VpIcon.send,
                            size: 20,
                            colour: ready ? c.onBrand : c.textDisabled,
                          ),
                  ),
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 6),
              child: Text(
                error!,
                style: VpType.caption.copyWith(color: c.statusBad),
              ),
            ),
        ],
      ),
    );
  }
}

/// A new text: to a number, from one of the user's lines.
class NewMessageScreen extends ConsumerStatefulWidget {
  const NewMessageScreen({super.key});

  @override
  ConsumerState<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends ConsumerState<NewMessageScreen> {
  final _to = TextEditingController();
  final _text = TextEditingController();
  String? _lineId;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _to.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String lineId) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final m = await ref
          .read(messageActionsProvider)
          .send(
            lineId: lineId,
            to: dialDigits(_to.text),
            text: _text.text.trim(),
          );
      if (mounted) {
        context.pushReplacement(MessagesScreen.threadPath(m.threadId));
      }
    } catch (_) {
      if (mounted) setState(() => _error = "The text didn't send. Try again.");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final lines = [
      for (final l in ref.watch(smsLinesProvider).value ?? const <SmsLine>[])
        if (l.canSend) l,
    ];
    final lineId =
        _lineId ?? ref.watch(messagesLineProvider) ?? lines.firstOrNull?.id;
    final count = smsCount(_text.text);
    final ready =
        !_sending &&
        lineId != null &&
        nationalDigits(_to.text).length >= 6 &&
        _text.text.trim().isNotEmpty &&
        !count.tooLong;
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
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 4, 20, 24),
          children: [
            Align(
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
                      child: VpSvgIcon(
                        VpIcon.back,
                        size: 22,
                        colour: c.brandText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const VpPageTitle('New message'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _to,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setState(() {}),
                    style: VpType.body.copyWith(color: c.text),
                    decoration: field('To: mobile number'),
                  ),
                  if (lines.length > 1) ...[
                    const SizedBox(height: 12),
                    VpSeg<String?>(
                      label: 'From',
                      options: [for (final l in lines) (l.id, l.label)],
                      value: lineId,
                      onChanged: (id) => setState(() => _lineId = id),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _text,
                    minLines: 3,
                    maxLines: 8,
                    onChanged: (_) => setState(() {}),
                    style: VpType.body.copyWith(color: c.text),
                    decoration: field('Text message'),
                  ),
                  if (count.units > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        smsCountText(count),
                        style: VpType.caption.copyWith(
                          color: count.tooLong ? c.statusBad : c.textMuted,
                        ),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _error!,
                        style: VpType.caption.copyWith(color: c.statusBad),
                      ),
                    ),
                  const SizedBox(height: 16),
                  VpButton(
                    label: 'Send',
                    busy: _sending,
                    onPressed: ready ? () => _send(lineId) : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synq/application/call/chat_controller.dart';
import 'package:synq/application/lobby/session_controller.dart';
import 'package:synq/core/call_code.dart';
import 'package:synq/data/models/chat_message.dart';
import 'package:synq/presentation/common/user_avatar.dart';

/// Shows the shared chat transcript. [onSend] forwards the typed text to the
/// active controller (1:1 call or meeting), so one sheet serves both. When
/// [showSender] is true (group meetings) incoming messages show the sender's
/// avatar and name; in a 1:1 call they stay plain.
Future<void> showChatSheet(
  BuildContext context, {
  required ValueChanged<String> onSend,
  bool showSender = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ChatSheet(onSend: onSend, showSender: showSender),
  );
}

class ChatSheet extends ConsumerStatefulWidget {
  const ChatSheet({required this.onSend, this.showSender = false, super.key});

  final ValueChanged<String> onSend;
  final bool showSender;

  @override
  ConsumerState<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends ConsumerState<ChatSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(chatUnreadProvider.notifier).reset(),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    widget.onSend(text);
    _input.clear();
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    unawaited(
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selfId = ref.watch(sessionControllerProvider)?.userId ?? '';
    final messages = ref.watch(chatControllerProvider);

    ref.listen(chatControllerProvider, (_, _) {
      // New messages are visible while the sheet is open, so keep it read.
      ref.read(chatUnreadProvider.notifier).reset();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    });

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Text('Chat', style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) => _Bubble(
                        message: messages[index],
                        isMine: messages[index].senderId == selfId,
                        showSender: widget.showSender,
                      ),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
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

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.isMine,
    required this.showSender,
  });

  final ChatMessage message;
  final bool isMine;
  final bool showSender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isMine
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isMine
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final width = MediaQuery.of(context).size.width;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: width * (showSender && !isMine ? 0.62 : 0.72),
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message.text, style: TextStyle(color: textColor)),
    );

    if (isMine) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 40),
          child: bubble,
        ),
      );
    }

    if (!showSender) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 40),
          child: bubble,
        ),
      );
    }

    final name = (message.senderName?.isNotEmpty ?? false)
        ? message.senderName!
        : CallCode.format(message.senderId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(name: name, radius: 14),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(
                    name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                bubble,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

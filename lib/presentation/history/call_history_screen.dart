import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:meet_videosdk/application/history/call_history_controller.dart';
import 'package:meet_videosdk/core/formatting.dart';
import 'package:meet_videosdk/data/models/call_record.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/presentation/common/app_router.dart';
import 'package:meet_videosdk/presentation/common/user_avatar.dart';

class CallHistoryScreen extends ConsumerWidget {
  const CallHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(callHistoryControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call history'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  ref.read(callHistoryControllerProvider.notifier).clear(),
            ),
        ],
      ),
      body: history.isEmpty
          ? const _EmptyHistory()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _HistoryTile(record: history[index]),
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record});

  final CallRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missed = record.outcome != CallOutcome.completed;
    final (icon, iconColor) = switch (record.direction) {
      CallDirection.outgoing => (
        Icons.call_made,
        missed ? theme.colorScheme.error : Colors.green,
      ),
      CallDirection.incoming => (
        missed ? Icons.call_missed : Icons.call_received,
        missed ? theme.colorScheme.error : Colors.green,
      ),
    };

    return Card(
      child: ListTile(
        onTap: () => unawaited(
          context.push(
            AppRoutes.prejoin,
            extra: User(userId: record.peerId, displayName: record.peerName),
          ),
        ),
        leading: UserAvatar(name: record.peerName),
        title: Text(
          record.peerName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 6),
            Expanded(child: Text(_subtitle(record))),
          ],
        ),
        trailing: const Icon(Icons.call, size: 18),
      ),
    );
  }

  String _subtitle(CallRecord record) {
    final when = Formatting.timestamp(record.startedAt);
    final detail = record.outcome == CallOutcome.completed
        ? Formatting.duration(Duration(seconds: record.durationSeconds))
        : _outcomeLabel(record.outcome);
    return '$when  ·  $detail';
  }

  String _outcomeLabel(CallOutcome outcome) => switch (outcome) {
    CallOutcome.completed => 'Completed',
    CallOutcome.missed => 'Missed',
    CallOutcome.declined => 'Declined',
    CallOutcome.failed => 'Failed',
    CallOutcome.unreachable => 'Unreachable',
  };
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No calls yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Your call history will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

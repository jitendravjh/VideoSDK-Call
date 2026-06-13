import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:meet_videosdk/core/formatting.dart';
import 'package:meet_videosdk/data/models/call_record.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/presentation/common/app_router.dart';
import 'package:meet_videosdk/presentation/common/user_avatar.dart';

/// A single call-history entry. Tapping it starts a call back to that peer.
class CallHistoryTile extends StatelessWidget {
  const CallHistoryTile({required this.record, super.key});

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

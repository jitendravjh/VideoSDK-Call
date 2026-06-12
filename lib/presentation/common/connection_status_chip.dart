import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meet_videosdk/data/signaling/signaling_providers.dart';
import 'package:meet_videosdk/data/signaling/signaling_transport.dart';

/// Compact live indicator of the signalling socket connection state.
class ConnectionStatusChip extends ConsumerWidget {
  const ConnectionStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionStateProvider).value ??
        SignalingConnectionState.connecting;
    final theme = Theme.of(context);

    final (color, label) = switch (state) {
      SignalingConnectionState.connected => (Colors.green, 'Online'),
      SignalingConnectionState.connecting => (Colors.amber, 'Connecting'),
      SignalingConnectionState.reconnecting => (Colors.amber, 'Reconnecting'),
      SignalingConnectionState.disconnected => (Colors.red, 'Offline'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

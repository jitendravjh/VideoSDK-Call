import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meet_videosdk/data/signaling/signaling_providers.dart';
import 'package:meet_videosdk/data/signaling/signaling_transport.dart';

/// Shows a thin banner whenever the signalling socket is not connected.
///
/// During a call this is informational only: an established peer-to-peer
/// connection keeps flowing while the signalling socket reconnects.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(connectionStateProvider).value ??
        SignalingConnectionState.connecting;
    if (state == SignalingConnectionState.connected) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final disconnected = state == SignalingConnectionState.disconnected;
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              disconnected
                  ? 'Connection lost. Reconnecting...'
                  : 'Connecting to server...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

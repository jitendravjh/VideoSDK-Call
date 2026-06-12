import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meet_videosdk/application/lobby/lobby_controller.dart';
import 'package:meet_videosdk/application/lobby/session_controller.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/presentation/common/connection_status_chip.dart';

class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final self = ref.watch(sessionControllerProvider);
    final users = ref.watch(lobbyControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: ConnectionStatusChip()),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (self != null) _SelfBanner(user: self),
          Expanded(
            child: users.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: users.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _UserTile(
                      user: users[index],
                      onCall: () => _startCall(context, users[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _startCall(BuildContext context, User peer) {
    // Wired to the pre-join and call flow in a later step.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Calling ${peer.displayName}...')),
    );
  }
}

class _SelfBanner extends StatelessWidget {
  const _SelfBanner({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: theme.colorScheme.surfaceContainerLow,
      child: Text(
        'Signed in as ${user.displayName}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.onCall});

  final User user;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial =
        user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?';

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Text(initial),
        ),
        title: Text(
          user.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('Online'),
        trailing: FilledButton.tonalIcon(
          onPressed: onCall,
          icon: const Icon(Icons.call, size: 18),
          label: const Text('Call'),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              Icons.people_outline,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No one else is online',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Open the app on another device to start a call.',
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

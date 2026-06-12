import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:meet_videosdk/application/lobby/lobby_controller.dart';
import 'package:meet_videosdk/application/lobby/session_controller.dart';
import 'package:meet_videosdk/core/call_code.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/presentation/common/app_router.dart';
import 'package:meet_videosdk/presentation/common/connection_banner.dart';
import 'package:meet_videosdk/presentation/common/connection_status_chip.dart';

class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final self = ref.watch(sessionControllerProvider);
    final users = ref.watch(lobbyControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('VideoSDK Call'),
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
          const ConnectionBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _CodeCard(
                  code: self?.userId ?? '',
                  displayName: self?.displayName,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: (self != null && self.userId.isNotEmpty)
                      ? () => _showJoinDialog(context, ref, self)
                      : null,
                  icon: const Icon(Icons.dialpad),
                  label: const Text('Join with a code'),
                ),
                const SizedBox(height: 24),
                Text(
                  'People online',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if (users.isEmpty)
                  const _EmptyPeople()
                else
                  ...users.map(
                    (user) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _UserTile(
                        user: user,
                        onCall: () => _startCall(context, user),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showJoinDialog(
    BuildContext context,
    WidgetRef ref,
    User? self,
  ) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => _JoinDialog(controller: controller),
    );
    controller.dispose();
    if (code == null || !context.mounted) return;

    final normalized = CallCode.normalize(code);
    if (normalized.isEmpty) return;
    if (self != null && normalized == self.userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That is your own code.')),
      );
      return;
    }
    final peer = _resolvePeer(ref, normalized);
    _startCall(context, peer);
  }

  User _resolvePeer(WidgetRef ref, String code) {
    final users = ref.read(lobbyControllerProvider);
    return users.firstWhere(
      (u) => u.userId == code,
      orElse: () => User(userId: code, displayName: CallCode.format(code)),
    );
  }

  void _startCall(BuildContext context, User peer) {
    unawaited(context.push(AppRoutes.prejoin, extra: peer));
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.displayName});

  final String code;
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = code.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName == null
                        ? 'YOUR CODE'
                        : 'YOUR CODE  ·  $displayName',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (ready)
                    Text(
                      CallCode.format(code),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    )
                  else
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Assigning a code',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Share this code so anyone can call you.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (ready)
              IconButton(
                tooltip: 'Copy code',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () {
                  unawaited(
                    Clipboard.setData(
                      ClipboardData(text: CallCode.format(code)),
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code copied')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _JoinDialog extends StatelessWidget {
  const _JoinDialog({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join with a code'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.go,
        decoration: const InputDecoration(
          hintText: 'Enter code (e.g. ABC-DEF)',
          prefixIcon: Icon(Icons.dialpad),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Connect'),
        ),
      ],
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
    final initial = user.displayName.isNotEmpty
        ? user.displayName[0].toUpperCase()
        : '?';

    return Card(
      child: ListTile(
        onTap: onCall,
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
        subtitle: Text(CallCode.format(user.userId)),
        trailing: IconButton.filledTonal(
          onPressed: onCall,
          icon: const Icon(Icons.call),
          tooltip: 'Call ${user.displayName}',
        ),
      ),
    );
  }
}

class _EmptyPeople extends StatelessWidget {
  const _EmptyPeople();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.people_outline,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No one else is online',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Share your code or join with one to start a call.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

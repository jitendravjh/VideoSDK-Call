import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:synq/application/history/call_history_controller.dart';
import 'package:synq/application/lobby/lobby_controller.dart';
import 'package:synq/application/lobby/session_controller.dart';
import 'package:synq/application/meeting/meeting_controller.dart';
import 'package:synq/core/call_code.dart';
import 'package:synq/core/permissions.dart';
import 'package:synq/data/models/user.dart';
import 'package:synq/presentation/common/app_router.dart';
import 'package:synq/presentation/common/brand_logo.dart';
import 'package:synq/presentation/common/connection_banner.dart';
import 'package:synq/presentation/history/call_history_tile.dart';

class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final self = ref.watch(sessionControllerProvider);
    final users = ref.watch(lobbyControllerProvider);
    final history = ref.watch(callHistoryControllerProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(size: 28),
            const SizedBox(width: 10),
            Text(
              'Synq',
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
          ],
        ),
        actions: [
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
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: (self != null && self.userId.isNotEmpty)
                            ? () => _showJoinDialog(context, ref, self)
                            : null,
                        icon: const Icon(Icons.call),
                        label: const Text('Call'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: (self != null && self.userId.isNotEmpty)
                            ? () => _showMeetingDialog(context, ref)
                            : null,
                        icon: const Icon(Icons.groups),
                        label: const Text('Meeting'),
                      ),
                    ),
                  ],
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
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Call history',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (history.isNotEmpty)
                      TextButton(
                        onPressed: () => ref
                            .read(callHistoryControllerProvider.notifier)
                            .clear(),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (history.isEmpty)
                  const _EmptyHistory()
                else
                  ...history.map(
                    (record) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: CallHistoryTile(record: record),
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
    final code = await showDialog<String>(
      context: context,
      builder: (context) => const _JoinDialog(),
    );
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

  Future<void> _showMeetingDialog(BuildContext context, WidgetRef ref) async {
    final meeting = ref.read(meetingControllerProvider.notifier);
    final result = await showDialog<({String action, String code})>(
      context: context,
      builder: (context) => const _MeetingDialog(),
    );
    if (result == null || !context.mounted) return;

    // Meetings have no pre-join screen, so request the mic here; the camera is
    // requested only if the user turns it on mid-meeting.
    const permissions = MediaPermissions();
    final granted = await permissions.request(camera: false);
    if (granted != MediaPermissionResult.granted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required')),
        );
      }
      return;
    }

    if (result.action == 'host') {
      await meeting.host();
    } else {
      final code = CallCode.normalize(result.code);
      if (code.isNotEmpty) await meeting.join(code);
    }
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
    final scheme = theme.colorScheme;
    final ready = code.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
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
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (ready)
                  Text(
                    CallCode.format(code),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  )
                else
                  Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Assigning a code',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                Text(
                  'Share this code so anyone can call you.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          if (ready)
            IconButton(
              tooltip: 'Copy code',
              color: scheme.onPrimaryContainer,
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
    );
  }
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog();

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join with a code'),
      content: TextField(
        controller: _controller,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.go,
        decoration: const InputDecoration(
          hintText: 'Enter code (e.g. ABC-DEF)',
          prefixIcon: Icon(Icons.dialpad),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Connect'),
        ),
      ],
    );
  }
}

/// Popup for group meetings: host a new meeting (the server generates and
/// returns its code, shown in-meeting), or join an existing one by code. Pops a
/// record describing the chosen action; the lobby then requests permission and
/// drives the meeting controller.
class _MeetingDialog extends StatefulWidget {
  const _MeetingDialog();

  @override
  State<_MeetingDialog> createState() => _MeetingDialogState();
}

class _MeetingDialogState extends State<_MeetingDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _host() => Navigator.of(context).pop((action: 'host', code: ''));

  void _join() =>
      Navigator.of(context).pop((action: 'join', code: _controller.text));

  @override
  Widget build(BuildContext context) {
    // Compact, non-scrolling content: the dialog floats above the keyboard, so
    // a short body keeps the join field fully visible without scrolling.
    return AlertDialog(
      title: const Text('Meeting'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _host,
            icon: const Icon(Icons.groups),
            label: const Text('Host meeting'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.go,
            decoration: const InputDecoration(
              labelText: 'Or join with a code',
              hintText: 'Meeting code',
              prefixIcon: Icon(Icons.dialpad),
            ),
            onSubmitted: (_) => _join(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _join, child: const Text('Join')),
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

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'No calls yet.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

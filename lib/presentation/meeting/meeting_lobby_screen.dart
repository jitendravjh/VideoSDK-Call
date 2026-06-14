import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meet_videosdk/application/lobby/session_controller.dart';
import 'package:meet_videosdk/application/meeting/meeting_controller.dart';
import 'package:meet_videosdk/core/call_code.dart';
import 'package:meet_videosdk/core/permissions.dart';

/// Landing screen for group meetings: the local user's code with a Host button,
/// and a field to join an existing meeting by its code. Hosting or joining
/// moves the meeting state out of idle, and the router takes over to the
/// in-meeting screen.
class MeetingLobbyScreen extends ConsumerStatefulWidget {
  const MeetingLobbyScreen({super.key});

  @override
  ConsumerState<MeetingLobbyScreen> createState() => _MeetingLobbyScreenState();
}

class _MeetingLobbyScreenState extends ConsumerState<MeetingLobbyScreen> {
  static const _permissions = MediaPermissions();
  final _codeController = TextEditingController();
  bool _cameraOn = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermissions() async {
    final result = await _permissions.request(camera: _cameraOn);
    if (result == MediaPermissionResult.granted) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required')),
      );
    }
    return false;
  }

  Future<void> _host() async {
    if (!await _ensurePermissions()) return;
    await ref.read(meetingControllerProvider.notifier).host(video: _cameraOn);
  }

  Future<void> _join() async {
    final code = CallCode.normalize(_codeController.text);
    if (code.isEmpty) return;
    if (!await _ensurePermissions()) return;
    await ref
        .read(meetingControllerProvider.notifier)
        .join(code, video: _cameraOn);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final self = ref.watch(sessionControllerProvider);
    final code = self?.userId ?? '';
    final ready = code.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Meeting')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _MeetingCodeCard(code: code, ready: ready),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start with camera on'),
              value: _cameraOn,
              onChanged: (value) => setState(() => _cameraOn = value),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: ready ? _host : null,
              icon: const Icon(Icons.groups),
              label: const Text('Host meeting'),
            ),
            const SizedBox(height: 28),
            Text(
              'Join a meeting',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _join(),
                    decoration: const InputDecoration(
                      hintText: 'Enter meeting code',
                      prefixIcon: Icon(Icons.dialpad),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _join, child: const Text('Join')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetingCodeCard extends StatelessWidget {
  const _MeetingCodeCard({required this.code, required this.ready});

  final String code;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
                  'YOUR MEETING CODE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  ready ? CallCode.format(code) : '------',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Host, then share this code so others can join.',
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

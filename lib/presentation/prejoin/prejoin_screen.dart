import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:meet_videosdk/application/call/call_controller.dart';
import 'package:meet_videosdk/core/permissions.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/data/webrtc/webrtc_providers.dart';
import 'package:meet_videosdk/presentation/common/user_avatar.dart';

class PrejoinScreen extends ConsumerStatefulWidget {
  const PrejoinScreen({required this.peer, super.key});

  final User peer;

  @override
  ConsumerState<PrejoinScreen> createState() => _PrejoinScreenState();
}

class _PrejoinScreenState extends ConsumerState<PrejoinScreen>
    with WidgetsBindingObserver {
  static const _permissions = MediaPermissions();

  bool _micOn = true;
  bool _cameraOn = false;
  bool _ready = false;
  MediaPermissionResult _micPermission = MediaPermissionResult.granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ref.read(callControllerProvider.notifier).cancelPreview());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after the user may have granted permission in OS settings.
    if (state == AppLifecycleState.resumed &&
        _micPermission != MediaPermissionResult.granted) {
      unawaited(_setup());
    }
  }

  CallController get _call => ref.read(callControllerProvider.notifier);

  Future<void> _setup() async {
    final result = await _permissions.request(camera: false);
    if (!mounted) return;
    setState(() => _micPermission = result);
    if (result == MediaPermissionResult.granted) {
      await _call.openPreview(video: false);
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _toggleCamera() async {
    if (!_cameraOn) {
      final result = await _permissions.request(camera: true);
      if (!mounted) return;
      if (result != MediaPermissionResult.granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission denied')),
        );
        return;
      }
      setState(() => _cameraOn = true);
    } else {
      setState(() => _cameraOn = false);
    }
    await _call.openPreview(video: _cameraOn);
    await _call.setMicEnabled(enabled: _micOn);
  }

  Future<void> _toggleMic() async {
    setState(() => _micOn = !_micOn);
    await _call.setMicEnabled(enabled: _micOn);
  }

  Future<void> _start() async {
    await _call.startCall(widget.peer, video: _cameraOn);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final renderer = ref.watch(webRtcEngineProvider).localRenderer;
    final blocked = _micPermission != MediaPermissionResult.granted;

    return Scaffold(
      appBar: AppBar(title: Text('Call ${widget.peer.displayName}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: _cameraOn && _ready
                        ? RTCVideoView(
                            renderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          )
                        : Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                UserAvatar(
                                  name: widget.peer.displayName,
                                  radius: 44,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _cameraOn ? 'Starting camera' : 'Camera off',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
              if (blocked) ...[
                const SizedBox(height: 16),
                _PermissionBanner(
                  permanentlyDenied:
                      _micPermission == MediaPermissionResult.permanentlyDenied,
                  onGrant: _setup,
                  onOpenSettings: _permissions.openSettings,
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Toggle(
                    icon: _micOn ? Icons.mic : Icons.mic_off,
                    label: _micOn ? 'Mic on' : 'Mic off',
                    active: _micOn,
                    onPressed: blocked ? null : _toggleMic,
                  ),
                  const SizedBox(width: 24),
                  _Toggle(
                    icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
                    label: _cameraOn ? 'Camera on' : 'Camera off',
                    active: _cameraOn,
                    onPressed: blocked ? null : _toggleCamera,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: blocked ? null : _start,
                icon: const Icon(Icons.call),
                label: Text('Call ${widget.peer.displayName}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({
    required this.permanentlyDenied,
    required this.onGrant,
    required this.onOpenSettings,
  });

  final bool permanentlyDenied;
  final Future<void> Function() onGrant;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.mic_off, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              permanentlyDenied
                  ? 'Microphone access is blocked. Enable it in settings to call.'
                  : 'Microphone permission is required to start a call.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => permanentlyDenied ? onOpenSettings() : onGrant(),
            child: Text(permanentlyDenied ? 'Settings' : 'Grant'),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: active
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Icon(
                icon,
                color: active
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: theme.textTheme.labelMedium),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:synq/application/call/call_controller.dart';
import 'package:synq/core/call_code.dart';
import 'package:synq/core/permissions.dart';
import 'package:synq/data/models/user.dart';
import 'package:synq/data/webrtc/webrtc_providers.dart';
import 'package:synq/presentation/common/user_avatar.dart';

class PrejoinScreen extends ConsumerStatefulWidget {
  const PrejoinScreen({required this.peer, this.incoming = false, super.key});

  final User peer;

  /// `true` when shown to the callee before answering (adds an Answer/Decline
  /// pair); `false` for the caller's setup before placing the call.
  final bool incoming;

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

  // Captured while mounted so it can be used safely in dispose(); reading a
  // provider through `ref` during teardown is unsafe in Riverpod.
  late final CallController _call;

  @override
  void initState() {
    super.initState();
    _call = ref.read(callControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_call.cancelPreview());
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

  Future<void> _setup() async {
    final result = await _permissions.request(camera: false);
    if (!mounted) return;
    setState(() => _micPermission = result);
    if (result != MediaPermissionResult.granted) return;
    // On desktop/web the OS or browser prompts here, inside getUserMedia; a
    // denial throws rather than coming back through permission_handler.
    try {
      await _call.openPreview(video: false);
      if (mounted) setState(() => _ready = true);
    } on Object {
      if (mounted) {
        setState(() => _micPermission = MediaPermissionResult.denied);
      }
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
    try {
      await _call.openPreview(video: _cameraOn);
      await _call.setMicEnabled(enabled: _micOn);
    } on Object {
      if (!mounted) return;
      setState(() => _cameraOn = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the camera')),
      );
    }
  }

  Future<void> _toggleMic() async {
    setState(() => _micOn = !_micOn);
    await _call.setMicEnabled(enabled: _micOn);
  }

  Future<void> _start() async {
    // Starting the call moves the state out of Idle; the router redirect then
    // replaces this screen with the call screen.
    await _call.startCall(widget.peer, video: _cameraOn);
  }

  Future<void> _answer() async {
    // Reuses the preview's already-open media; the call screen takes over once
    // the state leaves Incoming.
    await _call.acceptCall(video: _cameraOn);
  }

  void _decline() => unawaited(_call.declineCall());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final renderer = ref.watch(webRtcEngineProvider).localRenderer;
    final blocked = _micPermission != MediaPermissionResult.granted;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.incoming,
        title: Text(
          widget.incoming
              ? '${widget.peer.displayName} is calling'
              : 'Call ${widget.peer.displayName}',
        ),
      ),
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
                                  widget.peer.displayName,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  CallCode.format(widget.peer.userId),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _cameraOn ? 'Starting camera' : 'Camera off',
                                  style: theme.textTheme.bodySmall?.copyWith(
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
              if (widget.incoming)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _decline,
                        icon: const Icon(Icons.call_end),
                        label: const Text('Decline'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: blocked ? null : _answer,
                        icon: const Icon(Icons.call),
                        label: const Text('Answer'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                        ),
                      ),
                    ),
                  ],
                )
              else
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
                  ? 'Microphone access is blocked. Enable it in settings.'
                  : 'Microphone permission is required for a call.',
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

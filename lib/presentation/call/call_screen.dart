import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:meet_videosdk/application/call/call_controller.dart';
import 'package:meet_videosdk/application/call/remote_media_controller.dart';
import 'package:meet_videosdk/core/permissions.dart';
import 'package:meet_videosdk/data/models/call_state.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/data/webrtc/webrtc_providers.dart';
import 'package:meet_videosdk/presentation/call/call_controls.dart';
import 'package:meet_videosdk/presentation/call/chat_sheet.dart';
import 'package:meet_videosdk/presentation/call/mic_level_bar.dart';
import 'package:meet_videosdk/presentation/common/connection_banner.dart';
import 'package:meet_videosdk/presentation/common/user_avatar.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  bool _muted = false;
  bool _speakerOn = false;
  bool _cameraOff = false;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _terminalHandled = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _onStateChange(CallState? previous, CallState next) {
    if (next is Connected && previous is! Connected) {
      _startTimer();
      final video = ref.read(webRtcEngineProvider).hasVideo;
      _speakerOn = video;
      unawaited(
        ref
            .read(callControllerProvider.notifier)
            .setSpeakerphone(enabled: _speakerOn),
      );
    }
    if ((next is Ended || next is Failed) && !_terminalHandled) {
      _terminalHandled = true;
      _ticker?.cancel();
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) ref.read(callControllerProvider.notifier).reset();
      });
    }
    if (next is Idle) {
      _terminalHandled = false;
      _elapsed = Duration.zero;
    }
  }

  void _startTimer() {
    _ticker?.cancel();
    _elapsed = Duration.zero;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _accept() async {
    const permissions = MediaPermissions();
    var video = true;
    var result = await permissions.request(camera: true);
    if (result != MediaPermissionResult.granted) {
      video = false;
      result = await permissions.request(camera: false);
    }
    if (!mounted) return;
    final notifier = ref.read(callControllerProvider.notifier);
    if (result != MediaPermissionResult.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required')),
      );
      unawaited(notifier.declineCall());
      return;
    }
    await notifier.acceptCall(video: video);
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    unawaited(
      ref.read(callControllerProvider.notifier).setMicEnabled(enabled: !_muted),
    );
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    unawaited(
      ref
          .read(callControllerProvider.notifier)
          .setSpeakerphone(enabled: _speakerOn),
    );
  }

  void _toggleCamera() {
    setState(() => _cameraOff = !_cameraOff);
    unawaited(
      ref
          .read(callControllerProvider.notifier)
          .setCameraEnabled(enabled: !_cameraOff),
    );
  }

  void _handleBack(CallState state) {
    final notifier = ref.read(callControllerProvider.notifier);
    switch (state) {
      case Incoming():
        unawaited(notifier.declineCall());
      case Outgoing() || Connecting() || Connected():
        unawaited(notifier.endCall());
      case Ended() || Failed() || Idle():
        notifier.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(callControllerProvider, _onStateChange);
    final state = ref.watch(callControllerProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack(state);
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: _phase(state)),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ConnectionBanner(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phase(CallState state) {
    return switch (state) {
      Incoming(:final peer) => _IncomingView(
        peer: peer,
        onAccept: _accept,
        onDecline: () =>
            ref.read(callControllerProvider.notifier).declineCall(),
      ),
      Outgoing(:final peer) => _PendingView(
        peer: peer,
        label: 'Calling',
        onCancel: () => ref.read(callControllerProvider.notifier).endCall(),
      ),
      Connecting(:final peer) => _PendingView(
        peer: peer,
        label: 'Connecting',
        onCancel: () => ref.read(callControllerProvider.notifier).endCall(),
      ),
      Connected(:final peer) => _ConnectedView(
        peer: peer,
        elapsed: _elapsed,
        muted: _muted,
        speakerOn: _speakerOn,
        cameraOff: _cameraOff,
        onToggleMute: _toggleMute,
        onToggleSpeaker: _toggleSpeaker,
        onToggleCamera: _toggleCamera,
        onEnd: () => ref.read(callControllerProvider.notifier).endCall(),
      ),
      Ended(:final reason) => _TerminalView(
        message: reason,
        onDone: () => ref.read(callControllerProvider.notifier).reset(),
      ),
      Failed(:final error) => _TerminalView(
        message: error,
        onDone: () => ref.read(callControllerProvider.notifier).reset(),
      ),
      Idle() => const SizedBox.shrink(),
    };
  }
}

class _IncomingView extends StatelessWidget {
  const _IncomingView({
    required this.peer,
    required this.onAccept,
    required this.onDecline,
  });

  final User peer;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Spacer(),
          UserAvatar(name: peer.displayName, radius: 56),
          const SizedBox(height: 24),
          Text(peer.displayName, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Incoming call',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CircleAction(
                icon: Icons.call_end,
                color: theme.colorScheme.error,
                label: 'Decline',
                onPressed: onDecline,
              ),
              _CircleAction(
                icon: Icons.call,
                color: Colors.green.shade600,
                label: 'Accept',
                onPressed: onAccept,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingView extends StatelessWidget {
  const _PendingView({
    required this.peer,
    required this.label,
    required this.onCancel,
  });

  final User peer;
  final String label;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Spacer(),
          UserAvatar(name: peer.displayName, radius: 56),
          const SizedBox(height: 24),
          Text(peer.displayName, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const Spacer(),
          _CircleAction(
            icon: Icons.call_end,
            color: theme.colorScheme.error,
            label: 'Cancel',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _ConnectedView extends ConsumerWidget {
  const _ConnectedView({
    required this.peer,
    required this.elapsed,
    required this.muted,
    required this.speakerOn,
    required this.cameraOff,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onToggleCamera,
    required this.onEnd,
  });

  final User peer;
  final Duration elapsed;
  final bool muted;
  final bool speakerOn;
  final bool cameraOff;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onToggleCamera;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final engine = ref.watch(webRtcEngineProvider);
    final localHasVideo = engine.hasVideo;
    final remoteHasVideo = ref.watch(remoteVideoProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (remoteHasVideo)
          RTCVideoView(
            engine.remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        else
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(name: peer.displayName, radius: 56),
                const SizedBox(height: 20),
                Text(peer.displayName, style: theme.textTheme.headlineSmall),
              ],
            ),
          ),
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Column(
            children: [
              if (remoteHasVideo)
                Text(
                  peer.displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
              Text(
                _formatDuration(elapsed),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: remoteHasVideo
                      ? Colors.white70
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 180,
                child: MicLevelBar(onLight: !remoteHasVideo),
              ),
            ],
          ),
        ),
        if (localHasVideo)
          Positioned(
            top: 12,
            right: 12,
            width: 96,
            height: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RTCVideoView(
                engine.localRenderer,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          ),
        Positioned(
          top: 8,
          left: 8,
          child: IconButton.filledTonal(
            tooltip: 'Chat',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => showChatSheet(context),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: CallControls(
              muted: muted,
              speakerOn: speakerOn,
              videoCall: localHasVideo,
              cameraOff: cameraOff,
              onToggleMute: onToggleMute,
              onToggleSpeaker: onToggleSpeaker,
              onToggleCamera: onToggleCamera,
              onFlipCamera: () =>
                  ref.read(callControllerProvider.notifier).switchCamera(),
              onEnd: onEnd,
            ),
          ),
        ),
      ],
    );
  }
}

class _TerminalView extends StatelessWidget {
  const _TerminalView({required this.message, required this.onDone});

  final String message;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.call_end,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(message, style: theme.textTheme.titleMedium),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: onDone,
            child: const Text('Back to home'),
          ),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

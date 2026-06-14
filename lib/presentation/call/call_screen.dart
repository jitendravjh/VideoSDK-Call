import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:meet_videosdk/application/call/call_controller.dart';
import 'package:meet_videosdk/application/call/chat_controller.dart';
import 'package:meet_videosdk/application/call/remote_media_controller.dart';
import 'package:meet_videosdk/core/call_code.dart';
import 'package:meet_videosdk/core/formatting.dart';
import 'package:meet_videosdk/data/models/call_state.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/data/webrtc/webrtc_providers.dart';
import 'package:meet_videosdk/presentation/call/call_controls.dart';
import 'package:meet_videosdk/presentation/call/chat_sheet.dart';
import 'package:meet_videosdk/presentation/call/mic_level_bar.dart';
import 'package:meet_videosdk/presentation/common/connection_banner.dart';
import 'package:meet_videosdk/presentation/common/user_avatar.dart';
import 'package:meet_videosdk/presentation/prejoin/prejoin_screen.dart';

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

    // The callee gets the shared pre-join screen (preview + mic/camera toggles)
    // before answering, mirroring the caller's setup.
    final Widget body = state is Incoming
        ? PrejoinScreen(peer: state.peer, incoming: true)
        : Scaffold(
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
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack(state);
      },
      child: body,
    );
  }

  Widget _phase(CallState state) {
    return switch (state) {
      // Incoming is handled by the pre-join screen in build().
      Incoming() => const SizedBox.shrink(),
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
        elapsed: _elapsed,
        onDone: () => ref.read(callControllerProvider.notifier).reset(),
      ),
      Failed(:final error) => _TerminalView(
        message: error,
        elapsed: _elapsed,
        onDone: () => ref.read(callControllerProvider.notifier).reset(),
      ),
      Idle() => const SizedBox.shrink(),
    };
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
          const SizedBox(height: 6),
          Text(
            'Code ${CallCode.format(peer.userId)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
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
    final remoteMicOn = ref.watch(remoteMicProvider);
    final unread = ref.watch(chatUnreadProvider);
    final onVideoBg = remoteHasVideo;

    return ColoredBox(
      color: remoteHasVideo ? Colors.black : theme.colorScheme.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (remoteHasVideo)
            RTCVideoView(engine.remoteRenderer)
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UserAvatar(name: peer.displayName, radius: 56),
                  const SizedBox(height: 20),
                  Text(peer.displayName, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Text(
                    'Code ${CallCode.format(peer.userId)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!remoteMicOn) ...[
                    const SizedBox(height: 10),
                    const _MutedChip(onVideoBg: false),
                  ],
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        peer.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      if (!remoteMicOn) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.mic_off,
                          size: 18,
                          color: Colors.white,
                        ),
                      ],
                    ],
                  ),
                Text(
                  _formatDuration(elapsed),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onVideoBg
                        ? Colors.white70
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 180,
                  child: MicLevelBar(onLight: !onVideoBg),
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
                child: cameraOff
                    ? const ColoredBox(
                        color: Colors.black54,
                        child: Center(
                          child: Icon(
                            Icons.videocam_off,
                            color: Colors.white70,
                          ),
                        ),
                      )
                    : RTCVideoView(
                        engine.localRenderer,
                        mirror: true,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
              ),
            ),
          Positioned(
            top: 8,
            left: 8,
            child: IconButton.filledTonal(
              tooltip: 'Chat',
              icon: Badge.count(
                count: unread,
                isLabelVisible: unread > 0,
                child: const Icon(Icons.chat_bubble_outline),
              ),
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
      ),
    );
  }
}

class _MutedChip extends StatelessWidget {
  const _MutedChip({required this.onVideoBg});

  final bool onVideoBg;

  @override
  Widget build(BuildContext context) {
    final color = onVideoBg ? Colors.white70 : Theme.of(context).hintColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mic_off, size: 16, color: color),
        const SizedBox(width: 6),
        Text('Muted', style: TextStyle(color: color)),
      ],
    );
  }
}

class _TerminalView extends StatelessWidget {
  const _TerminalView({
    required this.message,
    required this.elapsed,
    required this.onDone,
  });

  final String message;
  final Duration elapsed;
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
          if (elapsed > Duration.zero) ...[
            const SizedBox(height: 8),
            Text(
              'Duration ${Formatting.duration(elapsed)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:meet_videosdk/application/meeting/meeting_controller.dart';
import 'package:meet_videosdk/core/call_code.dart';
import 'package:meet_videosdk/core/permissions.dart';
import 'package:meet_videosdk/data/models/meeting_state.dart';
import 'package:meet_videosdk/data/webrtc/webrtc_providers.dart';
import 'package:meet_videosdk/presentation/call/call_controls.dart';
import 'package:meet_videosdk/presentation/common/back_home_button.dart';
import 'package:meet_videosdk/presentation/common/user_avatar.dart';

/// The in-meeting screen: a grid of the local preview plus every participant,
/// the shareable meeting code in the bar, and the call controls. Driven off
/// [MeetingState]; the router shows it whenever a meeting is not idle.
class MeetingScreen extends ConsumerStatefulWidget {
  const MeetingScreen({super.key});

  @override
  ConsumerState<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends ConsumerState<MeetingScreen> {
  static const _permissions = MediaPermissions();

  bool _muted = false;
  bool _speakerOn = true;
  bool _cameraOn = false;
  String? _focusedId;

  @override
  void initState() {
    super.initState();
    // Group meetings default to speakerphone.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(meetingControllerProvider.notifier)
            .setSpeakerphone(enabled: _speakerOn),
      );
    });
  }

  MeetingController get _meeting =>
      ref.read(meetingControllerProvider.notifier);

  void _toggleMute() {
    setState(() => _muted = !_muted);
    unawaited(_meeting.setMicEnabled(enabled: !_muted));
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    unawaited(_meeting.setSpeakerphone(enabled: _speakerOn));
  }

  Future<void> _toggleCamera() async {
    if (_cameraOn) {
      setState(() => _cameraOn = false);
      await _meeting.setCameraEnabled(enabled: false);
      return;
    }
    final result = await _permissions.request(camera: true);
    if (result != MediaPermissionResult.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission denied')),
        );
      }
      return;
    }
    try {
      await _meeting.enableCamera();
      if (mounted) setState(() => _cameraOn = true);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the camera')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(meetingControllerProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (state is MeetingEnded) {
          _meeting.reset();
        } else {
          unawaited(_meeting.leave());
        }
      },
      child: switch (state) {
        MeetingEnded(:final reason) => _TerminalScaffold(
          reason: reason,
          onDone: _meeting.reset,
        ),
        MeetingConnecting(:final roomCode) => _ConnectingScaffold(
          roomCode: roomCode,
        ),
        MeetingActive() => _ActiveScaffold(
          state: state,
          muted: _muted,
          speakerOn: _speakerOn,
          cameraOn: _cameraOn,
          focusedId: _focusedId,
          onFocus: (id) => setState(() => _focusedId = id),
          onToggleMute: _toggleMute,
          onToggleSpeaker: _toggleSpeaker,
          onToggleCamera: _toggleCamera,
          onFlip: () => unawaited(_meeting.switchCamera()),
          onLeave: () => unawaited(_meeting.leave()),
        ),
        MeetingIdle() => const SizedBox.shrink(),
      },
    );
  }
}

class _ConnectingScaffold extends StatelessWidget {
  const _ConnectingScaffold({required this.roomCode});

  final String roomCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Meeting')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              roomCode.isEmpty ? 'Starting meeting' : 'Joining meeting',
              style: theme.textTheme.titleMedium,
            ),
            if (roomCode.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                CallCode.format(roomCode),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TerminalScaffold extends StatelessWidget {
  const _TerminalScaffold({required this.reason, required this.onDone});

  final String reason;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.groups,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(reason, style: theme.textTheme.titleMedium),
              const SizedBox(height: 24),
              BackHomeButton(onPressed: onDone),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveScaffold extends ConsumerWidget {
  const _ActiveScaffold({
    required this.state,
    required this.muted,
    required this.speakerOn,
    required this.cameraOn,
    required this.focusedId,
    required this.onFocus,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onToggleCamera,
    required this.onFlip,
    required this.onLeave,
  });

  final MeetingState state;
  final bool muted;
  final bool speakerOn;
  final bool cameraOn;
  final String? focusedId;
  final ValueChanged<String?> onFocus;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onToggleCamera;
  final VoidCallback onFlip;
  final VoidCallback onLeave;

  static const _selfId = '__you__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(meshEngineProvider);
    final participants = state.participants;
    final roomCode = state.roomCode ?? '';

    // "You" is always pinned first.
    final tiles = <_TileData>[
      _TileData(
        id: _selfId,
        name: 'You',
        renderer: engine.localRenderer,
        showVideo: cameraOn,
        mirror: true,
        micOn: !muted,
      ),
      for (final p in participants)
        _TileData(
          id: p.userId,
          name: p.displayName,
          renderer: engine.rendererFor(p.userId),
          showVideo: p.hasVideo,
          mirror: false,
          micOn: p.micOn,
        ),
    ];

    // Resolve the focused tile, ignoring a stale id for someone who left.
    _TileData? focused;
    for (final t in tiles) {
      if (t.id == focusedId) {
        focused = t;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meeting'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: const Icon(Icons.copy, size: 16),
              label: Text(CallCode.format(roomCode)),
              onPressed: () => _copyCode(context, roomCode),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (participants.isEmpty) _CodeBanner(roomCode: roomCode),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: focused != null
                    ? _focusedLayout(tiles, focused)
                    : _gridLayout(tiles),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24, top: 8),
              child: CallControls(
                muted: muted,
                speakerOn: speakerOn,
                cameraOn: cameraOn,
                onToggleMute: onToggleMute,
                onToggleSpeaker: onToggleSpeaker,
                onToggleCamera: onToggleCamera,
                onFlipCamera: onFlip,
                onEnd: onLeave,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Tap to expand any tile to fill the screen; the rest become a strip.
  Widget _focusedLayout(List<_TileData> tiles, _TileData focused) {
    final others = [
      for (final t in tiles)
        if (t.id != focused.id) t,
    ];
    return Column(
      children: [
        Expanded(
          child: _Tile(data: focused, onTap: () => onFocus(null)),
        ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: others.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => AspectRatio(
                aspectRatio: 0.8,
                child: _Tile(
                  data: others[i],
                  onTap: () => onFocus(others[i].id),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _gridLayout(List<_TileData> tiles) {
    // Alone: a single tile that fills the available height.
    if (tiles.length == 1) {
      return _Tile(data: tiles.first);
    }
    // Two participants: stacked, each half the height, no scrolling.
    if (tiles.length == 2) {
      return Column(
        children: [
          Expanded(
            child: _Tile(data: tiles[0], onTap: () => onFocus(tiles[0].id)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _Tile(data: tiles[1], onTap: () => onFocus(tiles[1].id)),
          ),
        ],
      );
    }
    // More: a two-per-row grid that scrolls when it overflows.
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.85,
      children: [
        for (final t in tiles) _Tile(data: t, onTap: () => onFocus(t.id)),
      ],
    );
  }

  void _copyCode(BuildContext context, String roomCode) {
    unawaited(
      Clipboard.setData(ClipboardData(text: CallCode.format(roomCode))),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Meeting code copied')),
    );
  }
}

/// A compact, single-row banner shown while the host is alone, so the local
/// preview tile gets the rest of the height.
class _CodeBanner extends StatelessWidget {
  const _CodeBanner({required this.roomCode});

  final String roomCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Icon(Icons.groups, size: 18, color: scheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Share code ${CallCode.format(roomCode)} to invite others',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Copy code',
                color: scheme.onSecondaryContainer,
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  unawaited(
                    Clipboard.setData(
                      ClipboardData(text: CallCode.format(roomCode)),
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Meeting code copied')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One meeting tile: shows the participant's video when available, otherwise
/// their avatar (no spinner — an audio-only or still-connecting peer simply
/// shows their avatar). Optionally tappable to toggle the focused full view.
class _TileData {
  const _TileData({
    required this.id,
    required this.name,
    required this.renderer,
    required this.showVideo,
    required this.mirror,
    required this.micOn,
  });

  final String id;
  final String name;
  final RTCVideoRenderer? renderer;
  final bool showVideo;
  final bool mirror;
  final bool micOn;
}

class _Tile extends StatelessWidget {
  const _Tile({required this.data, this.onTap});

  final _TileData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final renderer = data.renderer;
    final tile = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (data.showVideo && renderer != null)
              RTCVideoView(
                renderer,
                mirror: data.mirror,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              Center(child: UserAvatar(name: data.name, radius: 32)),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!data.micOn) ...[
                            const Icon(
                              Icons.mic_off,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              data.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return tile;
    return GestureDetector(onTap: onTap, child: tile);
  }
}

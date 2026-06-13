import 'package:flutter/material.dart';
import 'package:meet_videosdk/presentation/common/adaptive.dart';
import 'package:meet_videosdk/presentation/common/liquid_glass.dart';

class CallControls extends StatelessWidget {
  const CallControls({
    required this.muted,
    required this.speakerOn,
    required this.videoCall,
    required this.cameraOff,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onToggleCamera,
    required this.onFlipCamera,
    required this.onEnd,
    super.key,
  });

  final bool muted;
  final bool speakerOn;
  final bool videoCall;
  final bool cameraOff;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onToggleCamera;
  final VoidCallback onFlipCamera;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = isCupertino;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ControlButton(
          icon: muted ? Icons.mic_off : Icons.mic,
          active: muted,
          glass: glass,
          tooltip: muted ? 'Unmute' : 'Mute',
          onPressed: onToggleMute,
        ),
        const SizedBox(width: 12),
        _ControlButton(
          icon: speakerOn ? Icons.volume_up : Icons.hearing,
          active: speakerOn,
          glass: glass,
          tooltip: speakerOn ? 'Speaker on' : 'Speaker off',
          onPressed: onToggleSpeaker,
        ),
        if (videoCall) ...[
          const SizedBox(width: 12),
          _ControlButton(
            icon: cameraOff ? Icons.videocam_off : Icons.videocam,
            active: cameraOff,
            glass: glass,
            tooltip: cameraOff ? 'Turn camera on' : 'Turn camera off',
            onPressed: onToggleCamera,
          ),
          const SizedBox(width: 12),
          _ControlButton(
            icon: Icons.cameraswitch,
            active: false,
            glass: glass,
            tooltip: 'Flip camera',
            onPressed: onFlipCamera,
          ),
        ],
        const SizedBox(width: 12),
        Material(
          color: theme.colorScheme.error,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onEnd,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Icon(Icons.call_end, color: Colors.white, size: 26),
            ),
          ),
        ),
      ],
    );

    if (glass) {
      // A dark glass pill reads well over both a video feed and the lighter
      // audio-call background.
      return LiquidGlass(
        color: Colors.black,
        opacity: 0.32,
        blur: 24,
        borderColor: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: row,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(40),
      ),
      child: row,
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.active,
    required this.glass,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final bool active;
  final bool glass;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color background;
    final Color foreground;
    if (glass) {
      background = active ? Colors.white : Colors.white.withValues(alpha: 0.16);
      foreground = active ? Colors.black : Colors.white;
    } else {
      background = active
          ? theme.colorScheme.primary
          : theme.colorScheme.surface;
      foreground = active
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onSurface;
    }
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(icon, color: foreground, size: 24),
          ),
        ),
      ),
    );
  }
}

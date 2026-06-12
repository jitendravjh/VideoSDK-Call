import 'package:flutter/material.dart';

class CallControls extends StatelessWidget {
  const CallControls({
    required this.muted,
    required this.speakerOn,
    required this.showCameraFlip,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onFlipCamera,
    required this.onEnd,
    super.key,
  });

  final bool muted;
  final bool speakerOn;
  final bool showCameraFlip;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onFlipCamera;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            icon: muted ? Icons.mic_off : Icons.mic,
            active: muted,
            tooltip: muted ? 'Unmute' : 'Mute',
            onPressed: onToggleMute,
          ),
          const SizedBox(width: 12),
          _ControlButton(
            icon: speakerOn ? Icons.volume_up : Icons.hearing,
            active: speakerOn,
            tooltip: speakerOn ? 'Speaker on' : 'Speaker off',
            onPressed: onToggleSpeaker,
          ),
          if (showCameraFlip) ...[
            const SizedBox(width: 12),
            _ControlButton(
              icon: Icons.cameraswitch,
              active: false,
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
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = active
        ? theme.colorScheme.primary
        : theme.colorScheme.surface;
    final foreground = active
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
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

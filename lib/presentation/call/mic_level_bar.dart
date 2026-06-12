import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meet_videosdk/data/native/mic_level_service.dart';

/// Live microphone level driven by the native Kotlin meter. Hidden on platforms
/// without the native bridge.
class MicLevelBar extends ConsumerWidget {
  const MicLevelBar({this.onLight, super.key});

  /// Whether the bar sits on a light surface (audio call) or a dark/video
  /// background, which selects readable colours.
  final bool? onLight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!const MicLevelService().isSupported) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final level = ref.watch(micLevelProvider).value ?? 0.0;
    final light = onLight ?? true;
    final trackColor = light
        ? theme.colorScheme.surfaceContainerHighest
        : Colors.white24;
    final labelColor = light
        ? theme.colorScheme.onSurfaceVariant
        : Colors.white70;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.graphic_eq, size: 14, color: labelColor),
            const SizedBox(width: 6),
            Text(
              'Mic level (native)',
              style: theme.textTheme.labelSmall?.copyWith(color: labelColor),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: level,
            minHeight: 8,
            backgroundColor: trackColor,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

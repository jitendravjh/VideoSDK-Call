import 'dart:ui';

import 'package:flutter/material.dart';

/// A translucent, backdrop-blurred surface approximating the iOS "Liquid Glass"
/// material. Flutter paints its own widgets, so it does not inherit the native
/// iOS 26 glass; this rebuilds the look with a blur, a translucent fill, and a
/// hairline highlight along the edge.
///
/// The blur only reveals content sitting behind the surface, so glass reads
/// strongest over video or a scrolling list and is intentionally subtle over a
/// flat background.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding = EdgeInsets.zero,
    this.color,
    this.opacity,
    this.blur = 18,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  /// Fill colour before [opacity] is applied. Defaults to a neutral frost; pass
  /// a brand colour for a tinted primary surface.
  final Color? color;
  final double? opacity;
  final double blur;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = (color ?? Colors.white).withValues(
      alpha: opacity ?? (isDark ? 0.16 : 0.5),
    );
    final stroke =
        borderColor ?? Colors.white.withValues(alpha: isDark ? 0.2 : 0.65);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: borderRadius,
            border: Border.all(color: stroke, width: 0.8),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

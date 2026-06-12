import 'package:flutter/material.dart';

/// Minimal app mark: a clean white video-camera glyph on a rounded primary
/// tile. Flat, no gradients, scales to any size.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 72, this.background, this.glyph});

  final double size;
  final Color? background;
  final Color? glyph;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BrandPainter(
          background: background ?? scheme.primary,
          glyph: glyph ?? scheme.onPrimary,
        ),
      ),
    );
  }
}

class _BrandPainter extends CustomPainter {
  _BrandPainter({required this.background, required this.glyph});

  final Color background;
  final Color glyph;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final tilePaint = Paint()..color = background;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.24)),
      tilePaint,
    );

    final glyphPaint = Paint()..color = glyph;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.23, s * 0.36, s * 0.35, s * 0.28),
        Radius.circular(s * 0.07),
      ),
      glyphPaint,
    );
    final lens = Path()
      ..moveTo(s * 0.62, s * 0.44)
      ..lineTo(s * 0.77, s * 0.37)
      ..lineTo(s * 0.77, s * 0.63)
      ..lineTo(s * 0.62, s * 0.56)
      ..close();
    canvas.drawPath(lens, glyphPaint);
  }

  @override
  bool shouldRepaint(covariant _BrandPainter oldDelegate) =>
      oldDelegate.background != background || oldDelegate.glyph != glyph;
}

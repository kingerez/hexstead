import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/art_store.dart';

/// The bandit's entrance, in three beats:
///  1. blackout - a grungy dark layer drops over the board and the bandit
///     looms huge at center screen for 500ms
///  2. fly - the bandit shrinks and glides onto its hex while the grunge
///     layer fades away
///  3. a beat of rest, then [onDone] hands back to the painted board.
class BanditFlyOverlay extends StatefulWidget {
  final Offset start;
  final Offset target;
  final double endSize;
  final VoidCallback onDone;

  const BanditFlyOverlay({
    super.key,
    required this.start,
    required this.target,
    required this.endSize,
    required this.onDone,
  });

  @override
  State<BanditFlyOverlay> createState() => _BanditFlyOverlayState();
}

class _BanditFlyOverlayState extends State<BanditFlyOverlay>
    with SingleTickerProviderStateMixin {
  static const _holdMs = 500;
  static const _flyMs = 650;
  static const _restMs = 120;
  static const _totalMs = _holdMs + _flyMs + _restMs;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _totalMs),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const startSize = 120.0;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final ms = _controller.value * _totalMs;

        // Entrance pop during the hold: quick overshoot then settle.
        final popT = (ms / 220).clamp(0.0, 1.0);
        final pop = Curves.easeOutBack.transform(popT);

        // Flight progress after the hold.
        final flyT = ms <= _holdMs
            ? 0.0
            : Curves.easeInOutCubic
                .transform(((ms - _holdMs) / _flyMs).clamp(0.0, 1.0));

        // Grunge layer: snaps in fast, holds, fades out with the flight.
        final layerIn = (ms / 150).clamp(0.0, 1.0);
        final layerOpacity = layerIn * (1.0 - flyT);

        final pos = Offset.lerp(widget.start, widget.target, flyT)!;
        final size =
            (startSize + (widget.endSize - startSize) * flyT) * pop;

        return Positioned.fill(
          child: IgnorePointer(
            child: Stack(
              children: [
                if (layerOpacity > 0.005)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GrungePainter(opacity: layerOpacity),
                    ),
                  ),
                Positioned(
                  left: pos.dx - size / 2,
                  top: pos.dy - size / 2,
                  // Same sprite the painter lands on, so the handoff at the
                  // end of the flight is invisible.
                  child: ArtStore.instance.image(
                    ArtStore.banditPath,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    placeholder: Text('🦹', style: TextStyle(fontSize: size)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Procedural grunge: a dark wash covered in seeded splotches and scratches,
/// so no texture asset is needed and it fits any screen size.
class _GrungePainter extends CustomPainter {
  final double opacity;

  const _GrungePainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(7);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.62 * opacity),
    );

    // Mottled splotches, a mix of lighter and darker stains.
    for (var i = 0; i < 130; i++) {
      final cx = rng.nextDouble() * size.width;
      final cy = rng.nextDouble() * size.height;
      final r = 6 + rng.nextDouble() * 46;
      final light = rng.nextBool();
      final alpha = (0.015 + rng.nextDouble() * 0.05) * opacity;
      final paint = Paint()
        ..color = (light ? Colors.white : Colors.black)
            .withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: r * (0.7 + rng.nextDouble()),
          height: r * (0.7 + rng.nextDouble()),
        ),
        paint,
      );
    }

    // Thin scratches.
    for (var i = 0; i < 36; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final angle = rng.nextDouble() * math.pi;
      final length = 24 + rng.nextDouble() * 130;
      final paint = Paint()
        ..color = Colors.white
            .withValues(alpha: (0.02 + rng.nextDouble() * 0.05) * opacity)
        ..strokeWidth = 0.6 + rng.nextDouble() * 1.2;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + math.cos(angle) * length, y + math.sin(angle) * length),
        paint,
      );
    }

    // Darkened vignette edges for that worn-poster feel.
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.5 * opacity),
        ],
        stops: const [0.62, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(_GrungePainter old) => old.opacity != opacity;
}

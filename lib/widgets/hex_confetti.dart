import 'dart:math';

import 'package:flutter/material.dart';

import '../board/board_painter.dart';

/// Victory shower: small hexes drift down past the scoreboard once and stop.
/// One controller, one painter, no packages - and no loop, so the screen
/// still settles for widget tests.
class HexConfetti extends StatefulWidget {
  final int count;

  const HexConfetti({super.key, this.count = 42});

  @override
  State<HexConfetti> createState() => _HexConfettiState();
}

class _HexConfettiState extends State<HexConfetti>
    with SingleTickerProviderStateMixin {
  static const _durationMs = 2800;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _durationMs),
  )..forward();

  /// Fixed seed: the shower looks the same every time it plays, which keeps
  /// it out of the "why did that test flake" pile.
  late final List<_Flake> _flakes = _buildFlakes(Random(7));

  List<_Flake> _buildFlakes(Random rng) {
    const gold = Color(0xFFFFCA28);
    final colors = [gold, gold, ...BoardPainter.playerColors];
    return [
      for (var i = 0; i < widget.count; i++)
        _Flake(
          x: rng.nextDouble(),
          // Staggered starts, so the fall reads as a shower and not a curtain.
          delay: rng.nextDouble() * 0.35,
          radius: 5 + rng.nextDouble() * 7,
          drift: (rng.nextDouble() - 0.5) * 0.18,
          wobbles: 1 + rng.nextDouble() * 1.5,
          spins: (rng.nextDouble() - 0.5) * 3,
          color: colors[rng.nextInt(colors.length)],
        ),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ConfettiPainter(flakes: _flakes, animation: _controller),
        size: Size.infinite,
      ),
    );
  }
}

class _Flake {
  /// Horizontal start, as a fraction of the width.
  final double x;

  /// Fraction of the timeline to wait before falling.
  final double delay;
  final double radius;

  /// Sideways sway amplitude (fraction of the width) and its wave count.
  final double drift;
  final double wobbles;

  /// Full turns over the fall; negative spins the other way.
  final double spins;
  final Color color;

  const _Flake({
    required this.x,
    required this.delay,
    required this.radius,
    required this.drift,
    required this.wobbles,
    required this.spins,
    required this.color,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Flake> flakes;
  final Animation<double> animation;

  _ConfettiPainter({required this.flakes, required this.animation})
      : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    for (final flake in flakes) {
      if (t < flake.delay) continue;
      final p = ((t - flake.delay) / (1 - flake.delay)).clamp(0.0, 1.0);
      // Starts just above the top edge and falls clear of the bottom.
      final y = (-0.1 + p * 1.2) * size.height;
      final x = (flake.x + sin(p * 2 * pi * flake.wobbles) * flake.drift) *
          size.width;
      // Fades over the last stretch so nothing pops out of existence.
      final fade = 1 - ((p - 0.75) / 0.25).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p * 2 * pi * flake.spins);
      canvas.drawPath(
        _hexPath(flake.radius),
        Paint()..color = flake.color.withValues(alpha: 0.85 * fade),
      );
      canvas.restore();
    }
  }

  /// Flat-top hexagon centered on the origin, matching the board's shape.
  Path _hexPath(double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = pi / 180 * (60 * i);
      final point = Offset(radius * cos(angle), radius * sin(angle));
      i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.flakes != flakes || old.animation != animation;
}

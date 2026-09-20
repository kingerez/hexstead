import 'dart:math';

import 'package:flutter/material.dart';

import '../board/board_painter.dart';

/// Victory fireworks: a handful of staggered bursts over the upper board,
/// each a ring of sparks flung outward and slowing as it fades. One
/// controller, one painter, no packages - and no loop, so the screen still
/// settles for widget tests.
class Fireworks extends StatefulWidget {
  final int bursts;

  const Fireworks({super.key, this.bursts = 6});

  @override
  State<Fireworks> createState() => _FireworksState();
}

class _FireworksState extends State<Fireworks>
    with SingleTickerProviderStateMixin {
  /// Roughly the banner's hold, so the sky is busy for as long as the line
  /// is up and quiet again before it fades.
  static const _durationMs = 3000;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _durationMs),
  )..forward();

  /// Fixed seed: the show looks the same every time, which keeps it out of
  /// the "why did that test flake" pile.
  late final List<_Burst> _bursts = _buildBursts(Random(11));

  List<_Burst> _buildBursts(Random rng) {
    const gold = Color(0xFFFFCA28);
    // Gold-weighted: the player colors are board colors, chosen to sit
    // quietly under sprites, and a night sky wants the bright one.
    final colors = [gold, gold, gold, ...BoardPainter.playerColors];
    // One burst per column of sky, in a shuffled order: an even spread beats
    // a random one, which piles them all in the middle, and shuffling stops
    // the staggered starts from sweeping tidily left to right.
    final columns = [for (var i = 0; i < widget.bursts; i++) i]..shuffle(rng);
    return [
      for (var i = 0; i < widget.bursts; i++)
        _Burst(
          // Inset from both edges so a wide burst stays on screen, and in the
          // top two fifths: the banner owns the center of the screen.
          center: Offset(
            0.15 +
                0.70 * (columns[i] + 0.2 + rng.nextDouble() * 0.6) /
                    widget.bursts,
            0.16 + rng.nextDouble() * 0.26,
          ),
          // Staggered, and never so late that a burst is cut off.
          delay: (i / widget.bursts) * 0.55 + rng.nextDouble() * 0.06,
          span: 0.30 + rng.nextDouble() * 0.10,
          reach: 0.20 + rng.nextDouble() * 0.12,
          sparks: 12 + rng.nextInt(5),
          spin: rng.nextDouble() * pi,
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
        painter: _FireworksPainter(bursts: _bursts, animation: _controller),
        size: Size.infinite,
      ),
    );
  }
}

class _Burst {
  /// Where it goes off, as fractions of the canvas.
  final Offset center;

  /// Fraction of the timeline it waits, and how much of it the burst lasts.
  final double delay;
  final double span;

  /// Furthest a spark travels, as a fraction of the shorter canvas side.
  final double reach;
  final int sparks;

  /// Rotates the ring so the bursts do not all line up.
  final double spin;
  final Color color;

  const _Burst({
    required this.center,
    required this.delay,
    required this.span,
    required this.reach,
    required this.sparks,
    required this.spin,
    required this.color,
  });
}

class _FireworksPainter extends CustomPainter {
  final List<_Burst> bursts;
  final Animation<double> animation;

  _FireworksPainter({required this.bursts, required this.animation})
      : super(repaint: animation);

  /// Gold sparks among the burst's own color, so every ring glints.
  static const _glint = Color(0xFFFFE9A8);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final scale = min(size.width, size.height);
    for (final burst in bursts) {
      final p = ((t - burst.delay) / burst.span).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final center =
          Offset(burst.center.dx * size.width, burst.center.dy * size.height);
      // Flung out fast and slowing to a stop, drooping as it goes.
      final reach = Curves.easeOutCubic.transform(p) * burst.reach * scale;
      final droop = Offset(0, p * p * 0.05 * scale);
      // Fades from the tail end, so the ring is bright while it is growing.
      final fade = 1 - Curves.easeInQuad.transform(p);
      for (var i = 0; i < burst.sparks; i++) {
        final angle = burst.spin + i / burst.sparks * 2 * pi;
        final dir = Offset(cos(angle), sin(angle));
        final head = center + dir * reach + droop;
        final color = i.isEven ? burst.color : _glint;
        // A short trail behind each spark, dimmer than its head.
        canvas.drawLine(
          head - dir * (reach * 0.16),
          head,
          Paint()
            ..color = color.withValues(alpha: 0.45 * fade)
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(
          head,
          3,
          Paint()..color = color.withValues(alpha: fade),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter old) =>
      old.bursts != bursts || old.animation != animation;
}

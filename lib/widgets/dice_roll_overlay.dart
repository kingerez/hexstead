import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Center-screen 2D dice roll: both faces cycle rapidly, decelerate, and
/// settle on the actual rolled values, then call [onDone].
class DiceRollOverlay extends StatefulWidget {
  final int d1;
  final int d2;
  final Duration duration;
  final VoidCallback onDone;

  const DiceRollOverlay({
    super.key,
    required this.d1,
    required this.d2,
    required this.onDone,
    this.duration = const Duration(milliseconds: 2000),
  });

  @override
  State<DiceRollOverlay> createState() => _DiceRollOverlayState();
}

class _DiceRollOverlayState extends State<DiceRollOverlay>
    with SingleTickerProviderStateMixin {
  // The tumble takes widget.duration; the settled result then holds on
  // screen briefly before onDone. The hold lives INSIDE the animation so
  // the whole sequence is frame-driven (no stray timers).
  static const _settleHold = Duration(milliseconds: 400);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration + _settleHold,
  );

  late final double _rollFraction = widget.duration.inMilliseconds /
      (widget.duration + _settleHold).inMilliseconds;

  // Fixed shuffled sequences so the tumble looks random but is repeatable.
  static const _seqA = [3, 6, 1, 4, 2, 5];
  static const _seqB = [5, 2, 4, 1, 6, 3];
  static const _swaps = 14;

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

  int _face(List<int> seq, int finalFace, double t) {
    final idx = (_swaps * Curves.decelerate.transform(t)).floor();
    if (idx >= _swaps - 1) return finalFace;
    return seq[idx % seq.length];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = (_controller.value / _rollFraction).clamp(0.0, 1.0);
        final settled = t >= 1.0;
        final scale = 1.0 + 0.12 * math.sin(math.pi * t);
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: scale,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _die(_face(_seqA, widget.d1, t), t, phase: 0),
                    const SizedBox(width: 20),
                    _die(_face(_seqB, widget.d2, t), t, phase: 2.1),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                settled ? '${widget.d1 + widget.d2}' : ' ',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _die(int face, double t, {required double phase}) {
    // Wobble that dies out as the roll settles.
    final angle = (1 - t) * 0.28 * math.sin(t * 22 + phase);
    return Transform.rotate(
      angle: angle,
      child: CustomPaint(
        size: const Size(72, 72),
        painter: _DieFacePainter(face),
      ),
    );
  }
}

class _DieFacePainter extends CustomPainter {
  final int face;

  const _DieFacePainter(this.face);

  static const _pipLayouts = {
    1: [(0.5, 0.5)],
    2: [(0.28, 0.28), (0.72, 0.72)],
    3: [(0.28, 0.28), (0.5, 0.5), (0.72, 0.72)],
    4: [(0.28, 0.28), (0.72, 0.28), (0.28, 0.72), (0.72, 0.72)],
    5: [(0.28, 0.28), (0.72, 0.28), (0.5, 0.5), (0.28, 0.72), (0.72, 0.72)],
    6: [
      (0.28, 0.26),
      (0.72, 0.26),
      (0.28, 0.5),
      (0.72, 0.5),
      (0.28, 0.74),
      (0.72, 0.74),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.2),
    );
    canvas.drawRRect(
      rect.shift(const Offset(0, 3)),
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xFFF7F1E1));
    final pip = Paint()..color = const Color(0xFF3A2E20);
    for (final (x, y) in _pipLayouts[face]!) {
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        size.width * 0.075,
        pip,
      );
    }
  }

  @override
  bool shouldRepaint(_DieFacePainter old) => old.face != face;
}

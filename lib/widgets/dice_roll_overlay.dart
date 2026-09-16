import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Center-screen 2D dice roll in three phases:
///  1. tumble — faces cycle rapidly and decelerate onto the real values
///  2. hold — the settled result stays put so it can be read
///  3. fly — the panel shrinks and glides down toward the HUD, then [onDone]
class DiceRollOverlay extends StatefulWidget {
  final int d1;
  final int d2;
  final Duration rollDuration;
  final Duration holdDuration;

  /// Where the panel flies to, relative to its centered start position.
  final Offset flyOffset;
  final VoidCallback onDone;

  const DiceRollOverlay({
    super.key,
    required this.d1,
    required this.d2,
    required this.onDone,
    required this.flyOffset,
    this.rollDuration = const Duration(milliseconds: 1200),
    this.holdDuration = const Duration(milliseconds: 1500),
  });

  @override
  State<DiceRollOverlay> createState() => _DiceRollOverlayState();
}

class _DiceRollOverlayState extends State<DiceRollOverlay>
    with SingleTickerProviderStateMixin {
  static const _flyDuration = Duration(milliseconds: 380);

  late final int _totalMs = widget.rollDuration.inMilliseconds +
      widget.holdDuration.inMilliseconds +
      _flyDuration.inMilliseconds;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _totalMs),
  );

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

  int _face(List<int> seq, int finalFace, double rollT) {
    final idx = (_swaps * Curves.decelerate.transform(rollT)).floor();
    if (idx >= _swaps - 1) return finalFace;
    return seq[idx % seq.length];
  }

  @override
  Widget build(BuildContext context) {
    final rollMs = widget.rollDuration.inMilliseconds;
    final flyStartFraction = 1 - _flyDuration.inMilliseconds / _totalMs;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final elapsed = _controller.value * _totalMs;
        final rollT = (elapsed / rollMs).clamp(0.0, 1.0);
        final flyT = _controller.value <= flyStartFraction
            ? 0.0
            : Curves.easeInCubic.transform(
                (_controller.value - flyStartFraction) /
                    (1 - flyStartFraction));

        final wobbleScale = 1.0 + 0.12 * math.sin(math.pi * rollT);
        final flyScale = 1.0 - 0.65 * flyT;
        return Transform.translate(
          offset: widget.flyOffset * flyT,
          child: Transform.scale(
            scale: wobbleScale * flyScale,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black
                    .withValues(alpha: 0.35 * (1 - flyT)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _die(_face(_seqA, widget.d1, rollT), rollT, phase: 0),
                  const SizedBox(width: 18),
                  _die(_face(_seqB, widget.d2, rollT), rollT, phase: 2.1),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _die(int face, double rollT, {required double phase}) {
    // Wobble that dies out as the roll settles.
    final angle = (1 - rollT) * 0.28 * math.sin(rollT * 22 + phase);
    return Transform.rotate(
      angle: angle,
      child: CustomPaint(
        size: const Size(68, 68),
        painter: DieFacePainter(face),
      ),
    );
  }
}

/// A small static die, used in the HUD to show the current roll.
class MiniDie extends StatelessWidget {
  final int face;
  final double size;

  const MiniDie(this.face, {super.key, this.size = 26});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: DieFacePainter(face),
    );
  }
}

class DieFacePainter extends CustomPainter {
  final int face;

  const DieFacePainter(this.face);

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
      rect.shift(Offset(0, size.width * 0.04)),
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
  bool shouldRepaint(DieFacePainter old) => old.face != face;
}

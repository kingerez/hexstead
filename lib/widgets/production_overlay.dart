import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../board/board_geometry.dart';
import '../board/board_painter.dart';

/// After an activation, floats "+N icon" chips up from every producing hex
/// in the producer's color - or a "no hexes matched" notice when the roll
/// paid nobody. Awaited by the game loop so the payout is always seen.
class ProductionOverlay extends StatefulWidget {
  final BoardGeometry geometry;
  final List<ProductionGrant> grants;

  /// The activated numbers, shown when nothing produced.
  final List<int> activatedNumbers;
  final VoidCallback onDone;

  const ProductionOverlay({
    super.key,
    required this.geometry,
    required this.grants,
    required this.activatedNumbers,
    required this.onDone,
  });

  @override
  State<ProductionOverlay> createState() => _ProductionOverlayState();
}

class _ProductionOverlayState extends State<ProductionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.grants.isEmpty ? 900 : 1200),
  );

  static const _resourceEmoji = {
    Resource.wood: '🪵',
    Resource.grain: '🌾',
    Resource.brick: '🧱',
    Resource.stone: '🪨',
  };

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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // Ease in fast, linger, fade near the end.
        final opacity = t < 0.15
            ? t / 0.15
            : t > 0.75
                ? (1 - t) / 0.25
                : 1.0;
        final rise = Curves.easeOutCubic.transform(t) * 34;

        if (widget.grants.isEmpty) {
          return Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'No hexes matched '
                      '${widget.activatedNumbers.join(' & ')}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 15),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Positioned.fill(
          child: IgnorePointer(
            child: Stack(
              children: [
                for (final (i, grant) in widget.grants.indexed)
                  _chip(grant, i, opacity, rise),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(ProductionGrant grant, int index, double opacity, double rise) {
    final center = widget.geometry.centerOf(grant.hex);
    // Tiny horizontal stagger so stacked chips never fully overlap.
    final jitter = math.sin(index * 2.4) * 6;
    return Positioned(
      left: center.dx - 34 + jitter,
      top: center.dy - widget.geometry.hexSize * 0.4 - rise,
      child: Opacity(
        opacity: opacity,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: BoardPainter.playerColors[grant.playerId],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 6),
            ],
          ),
          child: Text(
            '+${grant.count} ${_resourceEmoji[grant.resource]}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

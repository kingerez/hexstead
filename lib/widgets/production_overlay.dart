import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../board/board_geometry.dart';
import '../board/board_painter.dart';

/// After an activation, floats "+N icon" chips up from every producing hex
/// in the producer's color - or a "no hexes matched" notice when the roll
/// paid nobody. Drought-relief payouts float as centered chips since they
/// come from the bank, not a hex. Awaited by the game loop so the payout is
/// always seen.
class ProductionOverlay extends StatefulWidget {
  final BoardGeometry geometry;
  final List<ProductionGrant> grants;

  /// Explanation shown when nothing produced; empty string suppresses it.
  final String emptyMessage;
  final List<DroughtRelief> reliefs;
  final List<String> playerNames;
  final VoidCallback onDone;

  const ProductionOverlay({
    super.key,
    required this.geometry,
    required this.grants,
    required this.emptyMessage,
    this.reliefs = const [],
    this.playerNames = const [],
    required this.onDone,
  });

  @override
  State<ProductionOverlay> createState() => _ProductionOverlayState();
}

class _ProductionOverlayState extends State<ProductionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.grants.isEmpty ? 1800 : 1450),
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
        final opacity = t < 0.12
            ? t / 0.12
            : t > 0.82
                ? (1 - t) / 0.18
                : 1.0;
        // Gentle drift upward across the whole display.
        final rise = Curves.easeOut.transform(t) * 30;

        return Positioned.fill(
          child: IgnorePointer(
            child: Stack(
              children: [
                for (final (i, grant) in widget.grants.indexed)
                  _chip(grant, i, opacity, rise),
                if ((widget.grants.isEmpty &&
                        widget.emptyMessage.isNotEmpty) ||
                    widget.reliefs.isNotEmpty)
                  Center(
                    child: Opacity(
                      opacity: opacity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.grants.isEmpty &&
                              widget.emptyMessage.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                widget.emptyMessage,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 15),
                              ),
                            ),
                          for (final relief in widget.reliefs)
                            _reliefChip(relief),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Bank payout for a starving player: no source hex, so it floats center.
  Widget _reliefChip(DroughtRelief relief) {
    final name = relief.playerId < widget.playerNames.length
        ? widget.playerNames[relief.playerId]
        : '?';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: BoardPainter.playerColors[relief.playerId],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 6),
        ],
      ),
      child: Text(
        '🍀 $name +1 ${_resourceEmoji[relief.resource]}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
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

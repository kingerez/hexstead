import 'package:flutter/material.dart';

import 'card_fan_overlay.dart';

/// Warns that someone is within a few points of the victory target: one
/// outlined line over a pill in that player's board color, edged crimson.
/// Fades in, holds, fades out in 1600ms total. Controller-driven (no timers)
/// so pumpAndSettle fast-forwards it.
class MatchPointOverlay extends StatefulWidget {
  final String text;
  final Color playerColor;
  final VoidCallback onDone;

  const MatchPointOverlay({
    super.key,
    required this.text,
    required this.playerColor,
    required this.onDone,
  });

  @override
  State<MatchPointOverlay> createState() => _MatchPointOverlayState();
}

class _MatchPointOverlayState extends State<MatchPointOverlay>
    with SingleTickerProviderStateMixin {
  /// The crimson the board uses for seizable hexes - one warning color.
  static const _warning = Color(0xFFE05252);

  // Phases in absolute ms, so lengthening the total only lengthens the hold.
  static const _totalMs = 1600;
  static const _enterMs = 150;
  static const _exitMs = 200;

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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final ms = _controller.value * _totalMs;
        final double opacity;
        final double scale;
        if (ms < _enterMs) {
          final enter = (ms / _enterMs).clamp(0.0, 1.0);
          opacity = enter;
          scale = 0.85 + 0.15 * Curves.easeOutBack.transform(enter);
        } else if (ms > _totalMs - _exitMs) {
          final exit = ((ms - (_totalMs - _exitMs)) / _exitMs).clamp(0.0, 1.0);
          opacity = 1 - exit;
          scale = 1.0 + 0.06 * exit;
        } else {
          opacity = 1.0;
          scale = 1.0;
        }

        return Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 10),
                      decoration: BoxDecoration(
                        color: widget.playerColor.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _warning, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: _warning.withValues(alpha: 0.45),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: OutlinedTitle(widget.text, size: 21),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

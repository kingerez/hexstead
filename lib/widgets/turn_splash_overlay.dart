import 'package:flutter/material.dart';

import 'card_fan_overlay.dart';

/// Announces the incoming turn center-screen: a large outlined name over a
/// pill in that player's board color. Fades in, holds, fades out in 1250ms
/// total. Controller-driven (no timers) so pumpAndSettle fast-forwards it.
class TurnSplashOverlay extends StatefulWidget {
  final String text;
  final Color playerColor;
  final VoidCallback onDone;

  const TurnSplashOverlay({
    super.key,
    required this.text,
    required this.playerColor,
    required this.onDone,
  });

  @override
  State<TurnSplashOverlay> createState() => _TurnSplashOverlayState();
}

class _TurnSplashOverlayState extends State<TurnSplashOverlay>
    with SingleTickerProviderStateMixin {
  // Phases in absolute ms, so lengthening the total only lengthens the
  // hold - the fades keep their snappy feel whatever _totalMs becomes.
  static const _totalMs = 1250;
  static const _enterMs = 150;
  static const _exitMs = 188;

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
          scale = 0.8 + 0.2 * Curves.easeOutBack.transform(enter);
        } else if (ms > _totalMs - _exitMs) {
          final exit =
              ((ms - (_totalMs - _exitMs)) / _exitMs).clamp(0.0, 1.0);
          opacity = 1 - exit;
          scale = 1.0 + 0.08 * exit;
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
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 12),
                    decoration: BoxDecoration(
                      color: widget.playerColor.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 14),
                      ],
                    ),
                    child: OutlinedTitle(widget.text, size: 34),
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

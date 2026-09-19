import 'package:flutter/material.dart';

import 'card_fan_overlay.dart';

/// Announces the incoming turn center-screen: a large outlined name over a
/// pill in that player's board color. Fades in, holds, fades out in 750ms
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
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
        final t = _controller.value;
        final double opacity;
        final double scale;
        if (t < 0.2) {
          final enter = (t / 0.2).clamp(0.0, 1.0);
          opacity = enter;
          scale = 0.8 + 0.2 * Curves.easeOutBack.transform(enter);
        } else if (t > 0.75) {
          final exit = ((t - 0.75) / 0.25).clamp(0.0, 1.0);
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

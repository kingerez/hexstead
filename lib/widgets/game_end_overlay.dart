import 'package:flutter/material.dart';

import 'card_fan_overlay.dart';
import 'fireworks.dart';

/// The beat between the last move and the scoreboard: one outlined line over
/// a darkening board saying how the game ended, held long enough to land.
/// A tap cuts the hold short. Controller-driven (no timers) so pumpAndSettle
/// fast-forwards it.
class GameEndOverlay extends StatefulWidget {
  final String text;

  /// Sets off fireworks behind the line - the human's wins only.
  final bool celebrate;
  final VoidCallback onDone;

  const GameEndOverlay({
    super.key,
    required this.text,
    required this.onDone,
    this.celebrate = false,
  });

  @override
  State<GameEndOverlay> createState() => _GameEndOverlayState();
}

class _GameEndOverlayState extends State<GameEndOverlay>
    with SingleTickerProviderStateMixin {
  // Phases in absolute ms, so lengthening the total only lengthens the hold:
  // the line reads for 3.2s between the two fades.
  static const _totalMs = 3700;
  static const _enterMs = 200;
  static const _exitMs = 300;

  /// Timeline fraction where the exit begins; a tap jumps here.
  static const _exitStart = (_totalMs - _exitMs) / _totalMs;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _totalMs),
  );

  @override
  void initState() {
    super.initState();
    // A status listener, not the forward() future: skipping the hold cancels
    // that future, which would report the moment as over mid-fade.
    _controller.addStatusListener(_onStatus);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) widget.onDone();
  }

  void _skipToExit() {
    if (_controller.value >= _exitStart) return;
    _controller.forward(from: _exitStart);
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
          scale = 0.88 + 0.12 * Curves.easeOutBack.transform(enter);
        } else if (ms > _totalMs - _exitMs) {
          final exit = ((ms - (_totalMs - _exitMs)) / _exitMs).clamp(0.0, 1.0);
          opacity = 1 - exit;
          scale = 1.0 + 0.05 * exit;
        } else {
          opacity = 1.0;
          scale = 1.0;
        }

        // Opaque: the game is over, so nothing behind this should take taps.
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _skipToExit,
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.35 * opacity),
              // Scrim, then the sky, then the line: the fireworks go off
              // behind the text and never over it.
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.celebrate)
                    Opacity(opacity: opacity, child: const Fireworks()),
                  Center(
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: scale,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: OutlinedTitle(widget.text, size: 32),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

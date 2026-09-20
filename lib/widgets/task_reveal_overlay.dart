import 'package:flutter/material.dart';

import 'card_fan_overlay.dart';
import 'resource_icon.dart';

/// Game-start secret-task reveal: the task reads large over the board, holds
/// long enough to take in, then flies down into the HUD's task chip so the
/// player learns where it lives from now on. A tap cuts the hold short.
class TaskRevealOverlay extends StatefulWidget {
  /// The objective's one-line description.
  final String description;

  /// Chip center in the root stack's coordinate space: where the banner
  /// shrinks to.
  final Offset target;
  final VoidCallback onDone;

  const TaskRevealOverlay({
    super.key,
    required this.description,
    required this.target,
    required this.onDone,
  });

  @override
  State<TaskRevealOverlay> createState() => _TaskRevealOverlayState();
}

class _TaskRevealOverlayState extends State<TaskRevealOverlay>
    with SingleTickerProviderStateMixin {
  // One controller drives the whole timeline, so there is no hold timer to
  // wait on separately: fade in, hold, then fly to the chip.
  static const _enterMs = 250;
  static const _holdMs = 2200;
  static const _flightMs = 600;
  static const _totalMs = _enterMs + _holdMs + _flightMs;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _totalMs),
  );

  /// Timeline fraction where the flight begins; a tap jumps here.
  static const _flightStart = (_enterMs + _holdMs) / _totalMs;

  @override
  void initState() {
    super.initState();
    // A status listener, not the forward() future: skipping the hold cancels
    // that future, which would report the reveal as finished mid-flight.
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

  void _skipToFlight() {
    if (_controller.value >= _flightStart) return;
    _controller.forward(from: _flightStart);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final elapsed = _controller.value * _totalMs;
        final enterT = (elapsed / _enterMs).clamp(0.0, 1.0);
        final flightT =
            ((elapsed - _enterMs - _holdMs) / _flightMs).clamp(0.0, 1.0);
        final flyT = Curves.easeInCubic.transform(flightT);
        final scale =
            0.9 + 0.1 * Curves.easeOutCubic.transform(enterT) - 0.45 * flyT;
        // Fades only over the last stretch of the flight: the banner should
        // still read while it travels.
        final opacity = enterT * (1 - ((flightT - 0.6) / 0.4).clamp(0.0, 1.0));

        // Translucent, not opaque: the reveal owns the eye but must not eat
        // taps meant for the HUD underneath.
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _skipToFlight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final center =
                    Offset(constraints.maxWidth, constraints.maxHeight) / 2;
                return Center(
                  child: Transform.translate(
                    offset: (widget.target - center) * flyT,
                    child: Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity.clamp(0.0, 1.0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: OutlinedTitle.rich(
                            TextSpan(children: [
                              taskSpan(20),
                              TextSpan(
                                  text: ' Secret task: ${widget.description}'),
                            ]),
                            size: 21,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

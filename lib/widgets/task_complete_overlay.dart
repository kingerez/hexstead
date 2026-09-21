import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import 'chrome.dart';
import 'resource_icon.dart';

/// The one beat the secret task is allowed to be loud: the moment it is
/// fulfilled. A parchment card over a dimmed board naming the task and what
/// it will be worth - the bonus itself stays off the live scores, so the copy
/// says plainly when it lands. Waits for a tap, then hands back via [onDone].
class TaskCompleteOverlay extends StatefulWidget {
  final ObjectiveSpec objective;
  final VoidCallback onDone;

  const TaskCompleteOverlay({
    super.key,
    required this.objective,
    required this.onDone,
  });

  @override
  State<TaskCompleteOverlay> createState() => _TaskCompleteOverlayState();
}

class _TaskCompleteOverlayState extends State<TaskCompleteOverlay>
    with SingleTickerProviderStateMixin {
  /// Entrance only - nothing times the card away, the player does.
  static const _enterMs = 220;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _enterMs),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final objective = widget.objective;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final enter = _controller.value;
        final scale = 0.85 + 0.15 * Curves.easeOutBack.transform(enter);
        // Opaque: the ceremony owns the screen until it is tapped away, and
        // the game is waiting on that tap.
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDone,
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.55 * enter),
              child: Center(
                child: Opacity(
                  opacity: enter,
                  child: Transform.scale(
                    scale: scale,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
                        decoration: parchmentPanel(radius: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text.rich(
                              TextSpan(children: [
                                taskSpan(20),
                                const TextSpan(
                                    text: ' Secret task fulfilled!'),
                              ]),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF3A2E20),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              objective.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF7A6647),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              objective.description,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.3,
                                color: Color(0xFF3A2E20),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '+${objective.bonusVp} bonus points at the '
                              'final tally',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF9A6B1F),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Tap to continue',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7A6647),
                              ),
                            ),
                          ],
                        ),
                      ),
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

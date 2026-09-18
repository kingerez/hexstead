import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import 'card_fan_overlay.dart';

/// Reveal shown when a bot plays an action card: the card face pops up
/// center-screen under a "`<name> plays <card>`" banner in the bot's color,
/// holds long enough to read, then fades away. Awaited by the game loop so
/// the card is always seen before its effects animate.
class BotCardOverlay extends StatefulWidget {
  final String cardId;
  final String playerName;
  final Color playerColor;
  final VoidCallback onDone;

  const BotCardOverlay({
    super.key,
    required this.cardId,
    required this.playerName,
    required this.playerColor,
    required this.onDone,
  });

  @override
  State<BotCardOverlay> createState() => _BotCardOverlayState();
}

class _BotCardOverlayState extends State<BotCardOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
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
        // Pop in with a little overshoot, hold, then shrink away.
        final double scale;
        final double opacity;
        if (t < 0.18) {
          final enter =
              Curves.easeOutBack.transform((t / 0.18).clamp(0.0, 1.0));
          scale = 0.4 + 0.6 * enter;
          opacity = (t / 0.10).clamp(0.0, 1.0);
        } else if (t > 0.85) {
          final exit = ((t - 0.85) / 0.15).clamp(0.0, 1.0);
          scale = 1.0 - 0.2 * Curves.easeIn.transform(exit);
          opacity = 1.0 - exit;
        } else {
          scale = 1.0;
          opacity = 1.0;
        }

        return Positioned.fill(
          child: IgnorePointer(
            child: Container(
              color: Colors.black.withValues(alpha: 0.45 * opacity),
              alignment: Alignment.center,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: widget.playerColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 8),
                          ],
                        ),
                        child: Text(
                          '${widget.playerName} plays '
                          '${cardCatalog[widget.cardId]!.name}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Transform.scale(
                        scale: 1.25,
                        child: ActionCardFace(cardId: widget.cardId),
                      ),
                    ],
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

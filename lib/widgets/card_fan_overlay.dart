import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

/// Right after the welcome briefing: presents the player's starting hand
/// as a fan at center screen for 2 seconds, then sweeps the cards down
/// toward the Cards button and hands off via [onDone].
class CardFanOverlay extends StatefulWidget {
  final List<String> cardIds;
  final VoidCallback onDone;

  const CardFanOverlay({super.key, required this.cardIds, required this.onDone});

  @override
  State<CardFanOverlay> createState() => _CardFanOverlayState();
}

class _CardFanOverlayState extends State<CardFanOverlay>
    with SingleTickerProviderStateMixin {
  static const _holdMs = 2000;
  static const _flyMs = 550;
  static const _totalMs = _holdMs + _flyMs;

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
    final screen = MediaQuery.sizeOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final ms = _controller.value * _totalMs;
        final inT = Curves.easeOutBack
            .transform((ms / 350).clamp(0.0, 1.0));
        final flyT = ms <= _holdMs
            ? 0.0
            : Curves.easeInCubic
                .transform(((ms - _holdMs) / _flyMs).clamp(0.0, 1.0));

        // Sweep down-left toward the Cards button in the HUD.
        final flyOffset =
            Offset(-screen.width * 0.05, screen.height * 0.38) * flyT;
        final scale = (0.6 + 0.4 * inT) * (1.0 - 0.72 * flyT);

        return Positioned.fill(
          child: IgnorePointer(
            child: Container(
              color: Colors.black.withValues(alpha: 0.5 * (1 - flyT)),
              alignment: Alignment.center,
              child: Transform.translate(
                offset: flyOffset,
                child: Transform.scale(
                  scale: scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: (1 - flyT).clamp(0.0, 1.0),
                        child: const Text(
                          'Your cards',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          for (final (i, id) in widget.cardIds.indexed)
                            Transform.translate(
                              offset: Offset(
                                  0, i == widget.cardIds.length ~/ 2 ? -8 : 4),
                              child: Transform.rotate(
                                angle: (i - (widget.cardIds.length - 1) / 2) *
                                    0.14,
                                child: _card(id),
                              ),
                            ),
                        ],
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

  Widget _card(String id) {
    final spec = cardCatalog[id]!;
    return Container(
      width: 108,
      height: 156,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4EAD4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8A6F4D), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            spec.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3A2E20),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              spec.description,
              overflow: TextOverflow.fade,
              style:
                  const TextStyle(fontSize: 11, color: Color(0xFF5A4A34)),
            ),
          ),
        ],
      ),
    );
  }
}

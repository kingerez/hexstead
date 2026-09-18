import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

/// The hand as a centered fan of cards. Enters by scaling up from the HUD
/// fan icon, leaves by shrinking back to it. Tap outside to dismiss; each
/// playable card carries its own Play button.
class CardFanOverlay extends StatefulWidget {
  final List<String> cardIds;

  /// Card ids with at least one legal play right now.
  final Set<String> playableCardIds;

  /// Card ids that may be swapped via the once-per-game replacement.
  final Set<String> replaceableCardIds;
  final void Function(String cardId)? onReplace;

  /// Where the fan shrinks to / grows from, relative to the fan's centered
  /// position (i.e. icon center minus screen center).
  final Offset flyOffset;
  final void Function(String cardId)? onPlay;
  final VoidCallback onDone;

  const CardFanOverlay({
    super.key,
    required this.cardIds,
    required this.onDone,
    required this.flyOffset,
    this.playableCardIds = const {},
    this.replaceableCardIds = const {},
    this.onPlay,
    this.onReplace,
  });

  @override
  State<CardFanOverlay> createState() => _CardFanOverlayState();
}

class _CardFanOverlayState extends State<CardFanOverlay>
    with SingleTickerProviderStateMixin {
  // flyT: 0 = fan open at center, 1 = shrunk down at the HUD icon.
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1.0,
  );

  String? _playedCardId;

  @override
  void initState() {
    super.initState();
    _fly.reverse(); // enter: icon -> center
  }

  @override
  void dispose() {
    _fly.dispose();
    super.dispose();
  }

  Future<void> _close({String? play}) async {
    if (_fly.status == AnimationStatus.forward) return;
    _playedCardId = play;
    await _fly.forward();
    if (!mounted) return;
    widget.onDone();
    if (play != null) widget.onPlay?.call(play);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fly,
      builder: (context, _) {
        final flyT = Curves.easeInOutCubic.transform(_fly.value);
        final settled = _fly.value == 0;

        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _playedCardId == null ? () => _close() : null,
            child: Container(
              color: Colors.black.withValues(alpha: 0.5 * (1 - flyT)),
              alignment: Alignment.center,
              child: Transform.translate(
                offset: widget.flyOffset * flyT,
                child: Transform.scale(
                  scale: 1.0 - 0.78 * flyT,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: (1 - flyT).clamp(0.0, 1.0),
                        child: const _OutlinedTitle('Your cards'),
                      ),
                      if (widget.replaceableCardIds.isNotEmpty)
                        Opacity(
                          opacity: (1 - flyT).clamp(0.0, 1.0),
                          child: const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Tap a card\'s ⇄ to swap it - once per game',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      if (widget.cardIds.isEmpty)
                        const Text(
                          'No cards left.',
                          style: TextStyle(color: Colors.white70),
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            for (final (i, id) in widget.cardIds.indexed)
                              Transform.translate(
                                offset: Offset(0,
                                    i == widget.cardIds.length ~/ 2 ? -8 : 4),
                                child: Transform.rotate(
                                  angle:
                                      (i - (widget.cardIds.length - 1) / 2) *
                                          0.14,
                                  child: _card(id, settled),
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

  Widget _card(String id, bool settled) {
    final spec = cardCatalog[id]!;
    final playable = widget.playableCardIds.contains(id);
    final replaceable = widget.replaceableCardIds.contains(id);
    return ActionCardFace(
      cardId: id,
      trailing: replaceable
          ? InkWell(
              onTap: settled ? () => widget.onReplace?.call(id) : null,
              child: const Padding(
                padding: EdgeInsets.only(left: 2),
                child: Icon(Icons.swap_horiz,
                    size: 18, color: Color(0xFF9A6B1F)),
              ),
            )
          : null,
      footer: SizedBox(
        width: double.infinity,
        height: 30,
        child: playable
            ? FilledButton(
                onPressed: settled ? () => _close(play: id) : null,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Play'),
              )
            : Center(
                child: Text(
                  spec.timing == CardTiming.diceChoice
                      ? 'playable right after rolling'
                      : 'playable after dice resolve',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(
                      fontSize: 9.5, color: Color(0xFF9A8A6A)),
                ),
              ),
      ),
    );
  }
}

/// One action card's parchment face: name, description, and optional
/// interactive slots. Shared by the hand fan and the bot-play reveal so a
/// card always looks the same wherever it appears.
class ActionCardFace extends StatelessWidget {
  final String cardId;

  /// Top-right corner slot (the fan's swap icon).
  final Widget? trailing;

  /// Bottom slot (the fan's Play button or timing hint).
  final Widget? footer;

  const ActionCardFace({
    super.key,
    required this.cardId,
    this.trailing,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final spec = cardCatalog[cardId]!;
    return Container(
      width: 108,
      height: 176,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4EAD4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8A6F4D), width: 2),
        boxShadow: const [
          BoxShadow(
              color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  spec.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3A2E20),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              spec.description,
              overflow: TextOverflow.fade,
              style: const TextStyle(fontSize: 11, color: Color(0xFF5A4A34)),
            ),
          ),
          ?footer,
        ],
      ),
    );
  }
}

/// White title with a dark stroke so it reads over any board colors.
class _OutlinedTitle extends StatelessWidget {
  final String text;

  const _OutlinedTitle(this.text);

  @override
  Widget build(BuildContext context) {
    const size = 24.0;
    const weight = FontWeight.w800;
    return Stack(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: size,
            fontWeight: weight,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..color = Colors.black87,
          ),
        ),
        Text(
          text,
          style: const TextStyle(
            fontSize: size,
            fontWeight: weight,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

/// HUD button: a little fan of card backs; the number of cards drawn IS the
/// number of cards in hand.
class CardFanIcon extends StatelessWidget {
  final int count;

  const CardFanIcon({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(44, 32),
      painter: _CardFanIconPainter(count),
    );
  }
}

class _CardFanIconPainter extends CustomPainter {
  final int count;

  const _CardFanIconPainter(this.count);

  @override
  void paint(Canvas canvas, Size size) {
    final n = count.clamp(0, 5);
    final center = Offset(size.width / 2, size.height * 0.95);
    if (n == 0) {
      _paintCard(canvas, center, 0, const Color(0x33FFFFFF), outline: true);
      return;
    }
    for (var i = 0; i < n; i++) {
      final angle = (i - (n - 1) / 2) * 0.30;
      _paintCard(canvas, center, angle, const Color(0xFFF4EAD4));
    }
  }

  void _paintCard(Canvas canvas, Offset pivot, double angle, Color color,
      {bool outline = false}) {
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);
    final rect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-7, -26, 14, 24),
      const Radius.circular(3),
    );
    final paint = Paint()
      ..color = color
      ..style = outline ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = 1.4;
    if (!outline) {
      canvas.drawRRect(
          rect,
          Paint()
            ..color = const Color(0xFF8A6F4D)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6);
    }
    canvas.drawRRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardFanIconPainter old) => old.count != count;
}

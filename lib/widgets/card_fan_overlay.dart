import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../art/art_store.dart';
import 'chrome.dart';

/// Tablets (>= 600dp shortest side) get larger cards; 1.4 keeps a 5-card
/// fan inside an iPad portrait width.
double cardScaleOf(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= 600 ? 1.4 : 1.0;

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
        final cardScale = cardScaleOf(context);

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
                  scale: cardScale - (cardScale - 0.22) * flyT,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: (1 - flyT).clamp(0.0, 1.0),
                        child: const OutlinedTitle('Your cards'),
                      ),
                      const SizedBox(height: 18),
                      if (widget.cardIds.isEmpty)
                        const Text(
                          'No cards left.',
                          style: TextStyle(color: Colors.white70),
                        )
                      else
                        // Scale the whole fan down when a wide hand outgrows
                        // a narrow screen; natural size when it fits.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                for (final (i, id) in widget.cardIds.indexed)
                                  Transform.translate(
                                    offset: Offset(
                                        0,
                                        i == widget.cardIds.length ~/ 2
                                            ? -8
                                            : 4),
                                    child: Transform.rotate(
                                      angle: (i -
                                              (widget.cardIds.length - 1) / 2) *
                                          0.14,
                                      child: _card(id, settled),
                                    ),
                                  ),
                              ],
                            ),
                          ),
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
  /// Natural size of the face, margins excluded; [layoutScale] multiplies it.
  static const _width = 108.0;
  static const _height = 176.0;

  final String cardId;

  /// Top-right corner slot (the fan's swap icon).
  final Widget? trailing;

  /// Bottom slot (the fan's Play button or timing hint).
  final Widget? footer;

  /// Blows the card's box, paddings and art up by this factor - for a card
  /// shown alone (the bot-play reveal) rather than in the hand fan. The text
  /// deliberately does NOT follow it: see [_textScale].
  final double layoutScale;

  const ActionCardFace({
    super.key,
    required this.cardId,
    this.trailing,
    this.footer,
    this.layoutScale = 1,
  });

  /// A blown-up card is about giving the rules room, not shouting them, so
  /// the type grows a fraction of what the card does - roughly a fifth bump
  /// at the reveal's 1.9x, against text almost twice hand size before.
  double get _textScale => 1 + (layoutScale - 1) * 0.22;

  @override
  Widget build(BuildContext context) {
    final spec = cardCatalog[cardId]!;
    return Container(
      width: _width * layoutScale,
      height: _height * layoutScale,
      margin: EdgeInsets.symmetric(horizontal: 3 * layoutScale),
      padding: EdgeInsets.all(10 * layoutScale),
      clipBehavior: Clip.antiAlias,
      decoration: parchmentPanel(
        shadows: const [
          BoxShadow(
              color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      // The swap icon floats over the top-right corner instead of sharing
      // the title row - single-word names like Cutpurse need the full
      // card width to avoid a mid-word break.
      child: Stack(
        // Expand: the Column carries an Expanded, so it needs the card's
        // fixed height rather than the Stack's loose constraints.
        fit: StackFit.expand,
        children: [
          // Faded art bleeding off the bottom-right corner; plain parchment
          // when the card has no art bundled.
          Positioned(
            right: -14 * layoutScale,
            bottom: -8 * layoutScale,
            child: Opacity(
              opacity: 0.18,
              child: ArtStore.instance.image(
                'assets/images/cards/art_$cardId.png',
                width: 92 * layoutScale,
                height: 92 * layoutScale,
                fit: BoxFit.contain,
                placeholder: const SizedBox.shrink(),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spec.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13 * _textScale,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF3A2E20),
                ),
              ),
              SizedBox(height: 6 * layoutScale),
              Expanded(
                child: Text(
                  spec.description,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                      fontSize: 11 * _textScale,
                      color: const Color(0xFF5A4A34)),
                ),
              ),
              ?footer,
            ],
          ),
          if (trailing != null)
            Positioned(top: 0, right: 0, child: trailing!),
        ],
      ),
    );
  }
}

/// White title with a dark stroke so it reads over any board colors.
class OutlinedTitle extends StatelessWidget {
  final String? text;

  /// Set instead of [text] when the title carries inline icons.
  final InlineSpan? span;
  final double size;

  const OutlinedTitle(this.text, {super.key, this.size = 24}) : span = null;

  const OutlinedTitle.rich(this.span, {super.key, this.size = 24})
      : text = null;

  @override
  Widget build(BuildContext context) {
    const weight = FontWeight.w800;
    // Drawn twice: a fat dark stroke under the white fill.
    Widget layer(TextStyle style) => span != null
        ? Text.rich(span!, textAlign: TextAlign.center, style: style)
        : Text(text!, textAlign: TextAlign.center, style: style);
    return Stack(
      children: [
        layer(TextStyle(
          fontSize: size,
          fontWeight: weight,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.2
            ..color = Colors.black87,
        )),
        layer(TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: Colors.white,
        )),
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

import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../art/art_store.dart';
import '../board/board_geometry.dart';
import '../board/board_painter.dart';
import 'chrome.dart';
import 'resource_icon.dart';

/// Persistent detail panel under the board: what the selected hex is, what
/// it yields, how often it pays, and the only place upgrades are bought.
class TileInspector extends StatelessWidget {
  final GameState state;

  /// The selected tile; null means nothing is selected.
  final Tile? tile;
  final int humanPlayerId;

  /// Whether the upgrade is legal right now (affordable, your turn, main
  /// phase) - the button still renders, greyed out, when it is not.
  final bool upgradeEnabled;
  final VoidCallback onUpgrade;

  const TileInspector({
    super.key,
    required this.state,
    required this.tile,
    required this.humanPlayerId,
    required this.upgradeEnabled,
    required this.onUpgrade,
  });

  /// Fixed height: the board above must not shift as tiles are selected.
  static const height = 104.0;

  static const _terrainNames = {
    TerrainType.forest: 'Forest',
    TerrainType.field: 'Field',
    TerrainType.hill: 'Hill',
    TerrainType.mountain: 'Mountain',
    TerrainType.desert: 'Desert',
  };

  static const _lineStyle =
      TextStyle(color: Colors.white, fontSize: 12.5, height: 1.2);
  static const _dimStyle =
      TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.2);

  PlayerState get _human =>
      state.players.firstWhere((p) => p.id == humanPlayerId);

  static List<InlineSpan> _costSpans(Map<Resource, int> cost) =>
      costSpans(cost, _lineStyle.fontSize!);

  @override
  Widget build(BuildContext context) {
    final t = tile;
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: chromePill(),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            height: double.infinity,
            child: CustomPaint(
              painter: _HexPreviewPainter(tile: t, round: state.round),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: t == null
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select a tile to view it',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  )
                : _details(t),
          ),
          if (t != null && t.ownerId == humanPlayerId) ...[
            const SizedBox(width: 8),
            _upgradeBlock(t),
          ],
        ],
      ),
    );
  }

  Widget _details(Tile t) {
    final owned = t.ownerId != null;
    final resource = t.terrain.resource;
    final number = t.number;
    final blocked =
        t.blockedUntilRound != null && state.round < t.blockedUntilRound!;
    final status = t.hasBandit
        ? '🦹 Bandit - blocked'
        : blocked
            ? '🌵 Drought until round ${t.blockedUntilRound}'
            : null;
    // Unowned tiles quote the base yield: level 1, nobody's landmarks.
    final amount = owned ? productionFor(state, t) : 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line(
          '${_terrainNames[t.terrain]}${owned ? ' · Level ${t.level}' : ''}',
          style: _lineStyle.copyWith(fontWeight: FontWeight.w700),
        ),
        _line(
          resource == null
              ? 'Produces nothing'
              : 'Produces ${BoardPainter.terrainEmoji[t.terrain]} $amount',
        ),
        if (resource != null && number != null)
          Tooltip(
            message: 'Chance a roll can activate this hex: the sum, or '
                'either die on a split.',
            child: _line(
              'Rolls $number · '
              '${(activationOdds(number) * 100).round()}% per roll',
              style: _dimStyle,
            ),
          ),
        if (owned)
          _line(
            'Owner: ${t.ownerId == humanPlayerId ? 'You' : state.players[t.ownerId!].name}',
            style: _dimStyle,
          )
        else
          _richLine(
            [
              const TextSpan(text: 'Unclaimed · pay '),
              ..._costSpans(Rules.effectiveClaimCost(_human)),
              const TextSpan(text: ' to claim'),
            ],
            style: _dimStyle,
          ),
        if (status != null) _line(status, style: _dimStyle),
      ],
    );
  }

  /// Every detail is one line: the panel's height is fixed, so anything too
  /// wide for the column trims rather than wraps.
  Widget _line(String text, {TextStyle? style}) => Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: style ?? _lineStyle,
      );

  /// Same line, with inline icons among the words.
  Widget _richLine(List<InlineSpan> spans, {TextStyle? style}) => Text.rich(
        TextSpan(children: spans),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: style ?? _lineStyle,
      );

  Widget _upgradeBlock(Tile t) {
    if (t.level >= 2) {
      return const Text(
        'Max level',
        style: TextStyle(color: Colors.white54, fontSize: 12.5),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(children: _costSpans(Rules.upgradeCost)),
          style: _dimStyle,
        ),
        const SizedBox(height: 4),
        FilledButton(
          onPressed: upgradeEnabled ? onUpgrade : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: const Text('Upgrade'),
        ),
      ],
    );
  }
}

/// One pointy-top hex drawn with the board's own geometry: sprite art when
/// it is bundled, the flat color plus emoji otherwise.
class _HexPreviewPainter extends CustomPainter {
  final Tile? tile;

  /// Drought expiry is round-relative, so a round change redraws the dimming.
  final int round;

  const _HexPreviewPainter({required this.tile, required this.round});

  @override
  void paint(Canvas canvas, Size size) {
    // Pointy-top: width is sqrt(3)*s, height 2*s. Leave room for the number
    // token that hangs below center.
    final hexSize = (size.width / 1.74).clamp(0.0, size.height / 2.05);
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path()
      ..addPolygon(BoardGeometry.hexCorners(center, hexSize), true);

    final t = tile;
    if (t == null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white30,
      );
      return;
    }

    final sprite = ArtStore.instance.tileImage(t.terrain);
    if (sprite != null) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawImageRect(
        sprite,
        Rect.fromLTWH(0, 0, sprite.width.toDouble(), sprite.height.toDouble()),
        path.getBounds(),
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    } else {
      canvas.drawPath(
          path, Paint()..color = BoardPainter.terrainColors[t.terrain]!);
      _text(canvas, BoardPainter.terrainEmoji[t.terrain]!,
          center - Offset(0, hexSize * 0.14), hexSize * 0.9);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = t.ownerId != null ? hexSize * 0.14 : hexSize * 0.07
        ..color = t.ownerId != null
            ? BoardPainter.playerColors[t.ownerId!]
            : const Color(0xFFF4EAD4),
    );

    final number = t.number;
    if (number != null) {
      final tokenCenter = center + Offset(0, hexSize * 0.58);
      final hot = number == 6 || number == 8;
      final owned = t.ownerId != null;
      canvas.drawCircle(
        tokenCenter,
        hexSize * 0.26,
        Paint()
          ..color = owned
              ? BoardPainter.playerColors[t.ownerId!]
              : const Color(0xFFF4EAD4),
      );
      if (owned) {
        canvas.drawCircle(
          tokenCenter,
          hexSize * 0.26,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.white,
        );
        if (t.level >= 2) {
          canvas.drawCircle(
            tokenCenter,
            hexSize * 0.34,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = Colors.white,
          );
        }
      }
      _text(
        canvas,
        '$number',
        tokenCenter,
        hexSize * 0.32,
        color: owned
            ? Colors.white
            : hot
                ? const Color(0xFFB33D3D)
                : const Color(0xFF4A3B28),
        bold: hot,
      );
    }
  }

  void _text(Canvas canvas, String text, Offset center, double fontSize,
      {Color? color, bool bold = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
        canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(_HexPreviewPainter old) =>
      old.tile != tile || old.round != round;
}

import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../art/art_store.dart';
import 'board_geometry.dart';

/// Placeholder-art board: colored hex polygons, emoji buildings, number
/// tokens with probability pips. Sprite art replaces this in the art phase.
class BoardPainter extends CustomPainter {
  final GameState state;
  final Set<Hex> highlighted;

  /// Rival hexes that can be seized (board full): crimson glow.
  final Set<Hex> seizeHighlighted;
  final Hex? selected;

  /// Suppresses the painted bandit on this hex while its fly-in animation
  /// is still in flight.
  final Hex? hideBanditAt;

  /// Whose tiles carry the upgrade badge; null hides badges entirely.
  final int? humanPlayerId;

  /// Drives the badge's two states: grey (save up) vs blue (upgrade now).
  final bool upgradeAffordable;

  const BoardPainter({
    required this.state,
    this.highlighted = const {},
    this.seizeHighlighted = const {},
    this.selected,
    this.hideBanditAt,
    this.humanPlayerId,
    this.upgradeAffordable = false,
  });

  static const terrainColors = {
    TerrainType.forest: Color(0xFF6B8F4E),
    TerrainType.field: Color(0xFFD9B45B),
    TerrainType.hill: Color(0xFFC17B54),
    TerrainType.mountain: Color(0xFF9A9BA5),
    TerrainType.desert: Color(0xFFD8C9A3),
  };

  static const playerColors = [
    Color(0xFF3D6BB3), // you: blue
    Color(0xFFB33D3D), // red
    Color(0xFF7A3DB3), // purple
    Color(0xFF3DB39E), // teal
  ];

  /// Tiles show the resource they yield, matching the HUD icons, so "what
  /// does this hex give me" needs no legend. Desert shows scenery.
  static const terrainEmoji = {
    TerrainType.forest: '🪵',
    TerrainType.field: '🌾',
    TerrainType.hill: '🧱',
    TerrainType.mountain: '🪨',
    TerrainType.desert: '🌵',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = BoardGeometry(size);
    // Shadow pass first so no tile's shadow falls on a neighbor's art.
    for (final tile in state.tiles.values) {
      final corners = geometry.cornersOf(tile.coord);
      final path = Path()..addPolygon(corners, true);
      canvas.drawPath(
        path.shift(Offset(0, geometry.hexSize * 0.08)),
        Paint()
          ..color = const Color(0x59000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    for (final tile in state.tiles.values) {
      _paintTile(canvas, geometry, tile);
    }
    // Badges last: they hang over the hex rim, so a neighbor painted later
    // must not clip them.
    for (final tile in state.tiles.values) {
      _paintUpgradeBadge(canvas, geometry, tile);
    }
  }

  /// Level-1 tiles of the human player advertise their upgrade: muted grey
  /// while the cost is out of reach, vivid blue the moment it is in hand.
  void _paintUpgradeBadge(Canvas canvas, BoardGeometry geometry, Tile tile) {
    if (humanPlayerId == null ||
        tile.ownerId != humanPlayerId ||
        tile.level != 1) {
      return;
    }
    final hexSize = geometry.hexSize;
    final center = geometry.centerOf(tile.coord) +
        Offset(hexSize * 0.35, -hexSize * 0.43);
    final radius = hexSize * 0.17;

    if (upgradeAffordable) {
      canvas.drawCircle(
        center,
        radius * 1.5,
        Paint()
          ..color = const Color(0xFF2F8FE8).withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = upgradeAffordable
            ? const Color(0xFF2F8FE8)
            : const Color(0xCC757575),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.16
        ..color = const Color(0x99000000),
    );

    // Arrow drawn as geometry, not glyphs: emoji and icon fonts render
    // inconsistently on canvas across platforms.
    final arrow = Paint()
      ..color = upgradeAffordable ? Colors.white : Colors.white70;
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, center.dy - radius * 0.58)
        ..lineTo(center.dx - radius * 0.52, center.dy + radius * 0.02)
        ..lineTo(center.dx + radius * 0.52, center.dy + radius * 0.02)
        ..close(),
      arrow,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        center.dx - radius * 0.18,
        center.dy - radius * 0.02,
        center.dx + radius * 0.18,
        center.dy + radius * 0.55,
      ),
      arrow,
    );
  }

  void _paintTile(Canvas canvas, BoardGeometry geometry, Tile tile) {
    final corners = geometry.cornersOf(tile.coord);
    final path = Path()..addPolygon(corners, true);
    final center = geometry.centerOf(tile.coord);
    final hexSize = geometry.hexSize;

    final sprite = ArtStore.instance.tileImage(tile.terrain);
    if (sprite != null) {
      // Real art: fill the hex with the sprite, clipped to the hex shape.
      canvas.save();
      canvas.clipPath(path);
      final bounds = path.getBounds();
      final spriteW = sprite.width.toDouble();
      final spriteH = sprite.height.toDouble();
      // Forest only: a per-hex sub-window breaks up the stamped repeat of a
      // canopy. Every other terrain reads as a landform, and sliding its
      // art around just looks like the hex is misaligned.
      var src = Rect.fromLTWH(0, 0, spriteW, spriteH);
      if (tile.terrain == TerrainType.forest) {
        const window = 0.75;
        final seed = (tile.coord.q * 92837111) ^ (tile.coord.r * 689287499);
        final dx = (seed.abs() & 0xFF) / 255 * spriteW * (1 - window);
        final dy = ((seed.abs() >> 8) & 0xFF) / 255 * spriteH * (1 - window);
        src = Rect.fromLTWH(dx, dy, spriteW * window, spriteH * window);
      }
      canvas.drawImageRect(
        sprite,
        src,
        bounds,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    } else {
      canvas.drawPath(
        path,
        Paint()..color = terrainColors[tile.terrain]!,
      );
    }

    if (highlighted.contains(tile.coord)) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.30)
          ..style = PaintingStyle.fill,
      );
    }

    // Rim: player color when owned, cream (matching the number tokens)
    // when neutral - full-bleed art needs an edge to read as a piece.
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tile.ownerId != null ? hexSize * 0.14 : hexSize * 0.07
      ..color = tile.ownerId != null
          ? playerColors[tile.ownerId!]
          : const Color(0xFFF4EAD4);
    canvas.drawPath(path, border);

    if (selected == tile.coord) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hexSize * 0.08
          ..color = Colors.white,
      );
    }

    // Resource icon fills the hex - the tile IS its resource. With real
    // tile art the sprite already depicts the resource, so skip the emoji.
    if (sprite == null) {
      _text(canvas, terrainEmoji[tile.terrain]!,
          center - Offset(0, hexSize * 0.14), hexSize * 0.95);
    }

    // Number token at the bottom. Ownership lives in the token itself:
    // owner-colored disc with white text; unowned stays cream with the
    // classic red 6/8. A village (x2 production) gets a double ring.
    final number = tile.number;
    if (number != null) {
      final tokenCenter = center + Offset(0, hexSize * 0.58);
      final hot = number == 6 || number == 8;
      final owned = tile.ownerId != null;
      canvas.drawCircle(
        tokenCenter,
        hexSize * 0.26,
        Paint()
          ..color =
              owned ? playerColors[tile.ownerId!] : const Color(0xFFF4EAD4),
      );
      if (owned) {
        canvas.drawCircle(
          tokenCenter,
          hexSize * 0.26,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white,
        );
        if (tile.level >= 2) {
          canvas.drawCircle(
            tokenCenter,
            hexSize * 0.34,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
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

    // A blocked hex (bandit or drought) is visibly "switched off": the whole
    // tile dims so the resource icon recedes and the bandit stands out.
    final blocked = tile.blockedUntilRound != null &&
        state.round < tile.blockedUntilRound!;
    if (tile.hasBandit || blocked) {
      canvas.drawPath(
        path,
        Paint()..color = Colors.black.withValues(alpha: 0.45),
      );
    }
    if (tile.hasBandit && tile.coord != hideBanditAt) {
      final banditSprite = ArtStore.instance.banditImage;
      if (banditSprite != null) {
        final side = hexSize * 1.1;
        canvas.drawImageRect(
          banditSprite,
          Rect.fromLTWH(0, 0, banditSprite.width.toDouble(),
              banditSprite.height.toDouble()),
          Rect.fromCenter(
              center: center - Offset(0, hexSize * 0.02),
              width: side,
              height: side),
          Paint()..filterQuality = FilterQuality.medium,
        );
      } else {
        _text(canvas, '🦹', center - Offset(0, hexSize * 0.02),
            hexSize * 0.80);
      }
    }

    // Seizable rival tiles burn crimson - late-game aggression.
    if (seizeHighlighted.contains(tile.coord)) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hexSize * 0.16
          ..color = const Color(0xFFE05252)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hexSize * 0.05
          ..color = const Color(0xFFFFDADA),
      );
    }

    // Claimable (and targetable) tiles get an unmissable amber glow.
    if (highlighted.contains(tile.coord)) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hexSize * 0.16
          ..color = const Color(0xFFFFD54F)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hexSize * 0.06
          ..color = const Color(0xFFFFF3D6),
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
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.state != state ||
      old.highlighted != highlighted ||
      old.seizeHighlighted != seizeHighlighted ||
      old.selected != selected ||
      old.hideBanditAt != hideBanditAt ||
      old.humanPlayerId != humanPlayerId ||
      old.upgradeAffordable != upgradeAffordable;
}

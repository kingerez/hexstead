import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import 'board_geometry.dart';

/// Placeholder-art board: colored hex polygons, emoji buildings, number
/// tokens with probability pips. Sprite art replaces this in the art phase.
class BoardPainter extends CustomPainter {
  final GameState state;
  final Set<Hex> highlighted;
  final Hex? selected;

  const BoardPainter({
    required this.state,
    this.highlighted = const {},
    this.selected,
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
    for (final tile in state.tiles.values) {
      _paintTile(canvas, geometry, tile);
    }
  }

  void _paintTile(Canvas canvas, BoardGeometry geometry, Tile tile) {
    final corners = geometry.cornersOf(tile.coord);
    final path = Path()..addPolygon(corners, true);
    final center = geometry.centerOf(tile.coord);
    final hexSize = geometry.hexSize;

    canvas.drawPath(
      path,
      Paint()..color = terrainColors[tile.terrain]!,
    );

    if (highlighted.contains(tile.coord)) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill,
      );
    }

    // Owner border.
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tile.ownerId != null ? hexSize * 0.14 : 1.5
      ..color = tile.ownerId != null
          ? playerColors[tile.ownerId!]
          : const Color(0x33000000);
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

    // Resource icon: big and unobstructed in the upper half.
    _text(canvas, terrainEmoji[tile.terrain]!,
        center - Offset(0, hexSize * 0.36), hexSize * 0.48);

    // Number token in the lower half; 6/8 are the frequent rolls, in red.
    final number = tile.number;
    if (number != null) {
      final tokenCenter = center + Offset(0, hexSize * 0.32);
      final hot = number == 6 || number == 8;
      canvas.drawCircle(
        tokenCenter,
        hexSize * 0.24,
        Paint()..color = const Color(0xFFF4EAD4),
      );
      _text(
        canvas,
        '$number',
        tokenCenter,
        hexSize * 0.30,
        color: hot ? const Color(0xFFB33D3D) : const Color(0xFF4A3B28),
        bold: hot,
      );
    }

    // Building badge beside the number token.
    if (tile.level == 1) {
      _text(canvas, '⛺', center + Offset(-hexSize * 0.42, hexSize * 0.32),
          hexSize * 0.36);
    } else if (tile.level == 2) {
      _text(canvas, '🏘️', center + Offset(-hexSize * 0.42, hexSize * 0.32),
          hexSize * 0.40);
    }

    if (tile.hasBandit) {
      _text(canvas, '🦹', center - Offset(0, hexSize * 0.02), hexSize * 0.62);
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
      old.selected != selected;
}

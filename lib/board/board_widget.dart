import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import 'board_geometry.dart';
import 'board_painter.dart';

class BoardWidget extends StatelessWidget {
  final GameState state;
  final Set<Hex> highlighted;
  final Set<Hex> seizeHighlighted;
  final Hex? selected;
  final void Function(Hex)? onTapHex;
  final void Function(Hex)? onLongPressHex;
  final Hex? hideBanditAt;

  /// Upgrade badges: painted on [humanPlayerId]'s level-1 tiles only.
  final int? humanPlayerId;
  final bool upgradeAffordable;

  const BoardWidget({
    super.key,
    required this.state,
    this.highlighted = const {},
    this.seizeHighlighted = const {},
    this.selected,
    this.onTapHex,
    this.onLongPressHex,
    this.hideBanditAt,
    this.humanPlayerId,
    this.upgradeAffordable = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onTapUp: (details) {
            final hex = BoardGeometry(size).hexAt(details.localPosition);
            if (state.tiles.containsKey(hex)) onTapHex?.call(hex);
          },
          onLongPressStart: (details) {
            final hex = BoardGeometry(size).hexAt(details.localPosition);
            if (state.tiles.containsKey(hex)) onLongPressHex?.call(hex);
          },
          child: CustomPaint(
            size: size,
            painter: BoardPainter(
              state: state,
              highlighted: highlighted,
              seizeHighlighted: seizeHighlighted,
              selected: selected,
              hideBanditAt: hideBanditAt,
              humanPlayerId: humanPlayerId,
              upgradeAffordable: upgradeAffordable,
            ),
          ),
        );
      },
    );
  }
}

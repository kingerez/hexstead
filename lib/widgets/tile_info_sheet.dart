import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../board/board_painter.dart';

/// Long-press detail view for one tile: what it is, what it yields, who
/// holds it, and how likely its number is to roll.
class TileInfoSheet extends StatelessWidget {
  final GameState state;
  final Tile tile;

  const TileInfoSheet({super.key, required this.state, required this.tile});

  static const _terrainNames = {
    TerrainType.forest: 'Forest',
    TerrainType.field: 'Field',
    TerrainType.hill: 'Hill',
    TerrainType.mountain: 'Mountain',
    TerrainType.desert: 'Desert',
  };

  static const _resourceNames = {
    Resource.wood: 'Wood',
    Resource.grain: 'Grain',
    Resource.brick: 'Brick',
    Resource.stone: 'Stone',
  };

  @override
  Widget build(BuildContext context) {
    final owner = tile.ownerId == null ? null : state.players[tile.ownerId!];
    final resource = tile.terrain.resource;
    final number = tile.number;
    final pips = number == null ? 0 : pipsFor(number);
    final blocked = tile.blockedUntilRound != null &&
        state.round < tile.blockedUntilRound!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Enlarged tile.
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: BoardPainter.terrainColors[tile.terrain],
                borderRadius: BorderRadius.circular(20),
                border: owner == null
                    ? null
                    : Border.all(
                        color: BoardPainter.playerColors[owner.id], width: 5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(BoardPainter.terrainEmoji[tile.terrain]!,
                      style: const TextStyle(fontSize: 34)),
                  if (number != null)
                    Text('$number',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: number == 6 || number == 8
                              ? const Color(0xFFB33D3D)
                              : Colors.black87,
                        )),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _terrainNames[tile.terrain]!,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  if (resource == null)
                    const Text('Produces nothing. Pure elbow room.')
                  else ...[
                    Text('Produces ${BoardPainter.terrainEmoji[tile.terrain]} '
                        '${_resourceNames[resource]}'
                        '${tile.level == 2 ? ' ×2 (village)' : ''}'),
                    const SizedBox(height: 4),
                    Text(
                      'Pays out when ANY player rolls $number '
                      '($pips of 36 rolls, '
                      '${(pips / 36 * 100).round()}% per roll)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (owner == null)
                    const Text('Unclaimed - claim it from an adjacent tile '
                        'for 🪵1 🧱1')
                  else
                    Row(
                      children: [
                        Icon(Icons.circle,
                            size: 12,
                            color: BoardPainter.playerColors[owner.id]),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${owner.isBot ? owner.name : 'Yours'} - '
                            '${tile.level == 1 ? 'camp (upgrade to village: 🌾2 🪨1)' : 'village - ×2 production (double ring)'}',
                          ),
                        ),
                      ],
                    ),
                  if (tile.hasBandit)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('🦹 Bandit here - no production until '
                          'the owner pays 2 resources'),
                    ),
                  if (blocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('🌵 Drought - no production until round '
                          '${tile.blockedUntilRound}'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

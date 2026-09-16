import 'hex/hex.dart';
import 'model/game_state.dart';
import 'model/tile.dart';

/// A player's live score: region-multiplier territory score plus landmark
/// points. Secret objectives are added separately at game end.
int scoreFor(GameState state, int playerId) {
  var score = territoryScore(state, playerId);
  // Landmark VP is added once the landmark catalog lands (kept separate so
  // territory tests stay exact).
  score += landmarkScore(state, playerId);
  return score;
}

/// Kingdomino-style: each connected same-terrain region scores
/// (hex count) x (1 + villages in it).
int territoryScore(GameState state, int playerId) {
  final owned = <Hex, Tile>{
    for (final t in state.tiles.values)
      if (t.ownerId == playerId) t.coord: t,
  };
  final visited = <Hex>{};
  var total = 0;
  for (final start in owned.keys) {
    if (visited.contains(start)) continue;
    final terrain = owned[start]!.terrain;
    var size = 0;
    var villages = 0;
    final stack = [start];
    visited.add(start);
    while (stack.isNotEmpty) {
      final hex = stack.removeLast();
      final tile = owned[hex]!;
      size++;
      if (tile.level >= 2) villages++;
      for (final nb in hex.neighbors) {
        final nbTile = owned[nb];
        if (nbTile != null && nbTile.terrain == terrain && visited.add(nb)) {
          stack.add(nb);
        }
      }
    }
    total += size * (1 + villages);
  }
  return total;
}

int landmarkScore(GameState state, int playerId) => 0;

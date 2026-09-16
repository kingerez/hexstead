import 'hex/hex.dart';
import 'model/game_state.dart';
import 'model/landmarks.dart';
import 'model/objectives.dart';
import 'model/tile.dart';

/// A player's live score: region-multiplier territory score plus landmark
/// points. Secret objectives are added separately at game end.
int scoreFor(GameState state, int playerId) {
  return territoryScore(state, playerId) + landmarkScore(state, playerId);
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

/// Final total shown at game end: live score plus any completed secret
/// objective's bonus.
int finalScoreFor(GameState state, int playerId) {
  final player = state.players[playerId];
  final spec = objectiveCatalog[player.objectiveId];
  final bonus =
      spec != null && spec.isComplete(state, playerId) ? spec.bonusVp : 0;
  return scoreFor(state, playerId) + bonus;
}

int landmarkScore(GameState state, int playerId) {
  final player = state.players[playerId];
  var score = 0;
  for (final id in player.landmarkIds) {
    score += landmarkCatalog[id]!.vp;
  }
  if (player.hasLandmark('keep')) {
    score += state.tiles.values
        .where((t) => t.ownerId == playerId && t.level >= 2)
        .length;
  }
  return score;
}

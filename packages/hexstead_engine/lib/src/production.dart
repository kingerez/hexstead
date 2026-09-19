import 'model/game_state.dart';
import 'model/landmarks.dart';
import 'model/tile.dart';

/// Yield for one producing tile, including landmark modifiers. Public so the
/// UI can quote a tile's output without restating the rules.
int productionFor(GameState state, Tile tile, {int hits = 1}) {
  final owner = state.players[tile.ownerId!];
  var perHit = tile.level;
  if (owner.hasLandmark(terrainBoostLandmarks[tile.terrain] ?? '')) {
    perHit += 1;
  }
  var count = hits * perHit;
  if (owner.hasLandmark('high_roller') && (tile.number ?? 0) >= 9) {
    count *= 2;
  }
  return count;
}

import 'hex/hex.dart';
import 'model/terrain.dart';
import 'model/tile.dart';
import 'rng.dart';

final _terrainBag = [
  ...List.filled(5, TerrainType.forest),
  ...List.filled(5, TerrainType.field),
  ...List.filled(4, TerrainType.hill),
  ...List.filled(4, TerrainType.mountain),
  TerrainType.desert,
];

const _numberBag = [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12];

/// Generates the 19-hex board. Rejects layouts where two 6/8 tiles touch,
/// so every seed yields a tournament-fair number spread.
Map<Hex, Tile> generateMap(GameRng rng) {
  final coords = Hex.spiral(const Hex(0, 0), 2);
  while (true) {
    final terrains = [..._terrainBag]..let(rng.shuffle);
    final numbers = [..._numberBag]..let(rng.shuffle);

    final tiles = <Hex, Tile>{};
    var numberIndex = 0;
    for (var i = 0; i < coords.length; i++) {
      final terrain = terrains[i];
      tiles[coords[i]] = Tile(
        coord: coords[i],
        terrain: terrain,
        number: terrain == TerrainType.desert ? null : numbers[numberIndex++],
      );
    }
    if (!_hasAdjacentHotNumbers(tiles)) return tiles;
  }
}

bool _hasAdjacentHotNumbers(Map<Hex, Tile> tiles) {
  for (final entry in tiles.entries) {
    final n = entry.value.number;
    if (n != 6 && n != 8) continue;
    for (final nb in entry.key.neighbors) {
      final other = tiles[nb]?.number;
      if (other == 6 || other == 8) return true;
    }
  }
  return false;
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}

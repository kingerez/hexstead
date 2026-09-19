import 'package:meta/meta.dart';

import '../hex/hex.dart';
import 'game_state.dart';
import 'terrain.dart';

/// A secret objective: hidden during play, scored once at game end.
@immutable
class ObjectiveSpec {
  final String id;
  final String name;
  final String description;
  final int bonusVp;

  /// Live (current, target) pair for the HUD. Current may exceed target.
  final (int, int) Function(GameState, int playerId) progress;

  /// 1-2 word noun for the compact HUD line, e.g. '4/8 tiles'.
  final String shortLabel;

  const ObjectiveSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.bonusVp,
    required this.progress,
    required this.shortLabel,
  });

  /// Derived from [progress] so the two can never disagree.
  bool isComplete(GameState state, int playerId) {
    final (current, target) = progress(state, playerId);
    return current >= target;
  }
}

int _terrainCount(GameState s, int playerId, TerrainType terrain) => s
    .tiles.values
    .where((t) => t.ownerId == playerId && t.terrain == terrain)
    .length;

final objectiveCatalog = <String, ObjectiveSpec>{
  'forester': ObjectiveSpec(
    id: 'forester',
    name: 'Forester',
    description: 'Own 4 or more forest tiles.',
    bonusVp: 4,
    shortLabel: 'forests',
    progress: (s, p) => (_terrainCount(s, p, TerrainType.forest), 4),
  ),
  'wheat_king': ObjectiveSpec(
    id: 'wheat_king',
    name: 'Wheat Sovereign',
    description: 'Own 4 or more field tiles.',
    bonusVp: 4,
    shortLabel: 'fields',
    progress: (s, p) => (_terrainCount(s, p, TerrainType.field), 4),
  ),
  'mayor': ObjectiveSpec(
    id: 'mayor',
    name: 'Lord Mayor',
    description: 'Own 3 or more Level-2 hexes.',
    bonusVp: 5,
    shortLabel: 'Lvl-2 hexes',
    progress: (s, p) => (
      s.tiles.values.where((t) => t.ownerId == p && t.level >= 2).length,
      3,
    ),
  ),
  'sprawl': ObjectiveSpec(
    id: 'sprawl',
    name: 'Sprawling Realm',
    description: 'Own 8 or more tiles.',
    bonusVp: 5,
    shortLabel: 'tiles',
    progress: (s, p) =>
        (s.tiles.values.where((t) => t.ownerId == p).length, 8),
  ),
  'hoarder': ObjectiveSpec(
    id: 'hoarder',
    name: 'Hoarder',
    description: 'End the game holding 6 or more resources.',
    bonusVp: 3,
    shortLabel: 'resources',
    progress: (s, p) => (s.players[p].totalResources, 6),
  ),
  'landmark_lover': ObjectiveSpec(
    id: 'landmark_lover',
    name: 'Patron of Works',
    description: 'Own 2 or more landmarks.',
    bonusVp: 4,
    shortLabel: 'landmarks',
    progress: (s, p) => (s.players[p].landmarkIds.length, 2),
  ),
  'straight_line': ObjectiveSpec(
    id: 'straight_line',
    name: 'The King\'s Road',
    description: 'Own 3 tiles in a straight line.',
    bonusVp: 3,
    shortLabel: 'in a line',
    progress: (s, p) => (_longestStraightRun(s, p), 3),
  ),
  'centrist': ObjectiveSpec(
    id: 'centrist',
    name: 'Heart of the Realm',
    description: 'Own the center tile.',
    bonusVp: 3,
    shortLabel: 'center tile',
    progress: (s, p) => (s.tiles[const Hex(0, 0)]?.ownerId == p ? 1 : 0, 1),
  ),
};

/// Longest run of collinear owned tiles, capped at 3 - the objective needs
/// no more, and the cap keeps the HUD fraction honest.
int _longestStraightRun(GameState s, int playerId) {
  final owned = {
    for (final t in s.tiles.values)
      if (t.ownerId == playerId) t.coord,
  };
  var best = owned.isEmpty ? 0 : 1;
  for (final start in owned) {
    for (final d in Hex.directions) {
      var run = 1;
      var cursor = start + d;
      while (owned.contains(cursor) && run < 3) {
        run += 1;
        cursor = cursor + d;
      }
      if (run > best) best = run;
    }
  }
  return best;
}

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
  final bool Function(GameState, int playerId) isComplete;

  const ObjectiveSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.bonusVp,
    required this.isComplete,
  });
}

bool _ownsTerrain(GameState s, int playerId, TerrainType terrain, int count) =>
    s.tiles.values
        .where((t) => t.ownerId == playerId && t.terrain == terrain)
        .length >=
    count;

final objectiveCatalog = <String, ObjectiveSpec>{
  'forester': ObjectiveSpec(
    id: 'forester',
    name: 'Forester',
    description: 'Own 4 or more forest tiles.',
    bonusVp: 4,
    isComplete: (s, p) => _ownsTerrain(s, p, TerrainType.forest, 4),
  ),
  'wheat_king': ObjectiveSpec(
    id: 'wheat_king',
    name: 'Wheat Sovereign',
    description: 'Own 4 or more field tiles.',
    bonusVp: 4,
    isComplete: (s, p) => _ownsTerrain(s, p, TerrainType.field, 4),
  ),
  'mayor': ObjectiveSpec(
    id: 'mayor',
    name: 'Lord Mayor',
    description: 'Own 3 or more villages.',
    bonusVp: 5,
    isComplete: (s, p) =>
        s.tiles.values.where((t) => t.ownerId == p && t.level >= 2).length >=
        3,
  ),
  'sprawl': ObjectiveSpec(
    id: 'sprawl',
    name: 'Sprawling Realm',
    description: 'Own 8 or more tiles.',
    bonusVp: 5,
    isComplete: (s, p) =>
        s.tiles.values.where((t) => t.ownerId == p).length >= 8,
  ),
  'hoarder': ObjectiveSpec(
    id: 'hoarder',
    name: 'Hoarder',
    description: 'End the game holding 6 or more resources.',
    bonusVp: 3,
    isComplete: (s, p) => s.players[p].totalResources >= 6,
  ),
  'landmark_lover': ObjectiveSpec(
    id: 'landmark_lover',
    name: 'Patron of Works',
    description: 'Own 2 or more landmarks.',
    bonusVp: 4,
    isComplete: (s, p) => s.players[p].landmarkIds.length >= 2,
  ),
  'straight_line': ObjectiveSpec(
    id: 'straight_line',
    name: 'The King\'s Road',
    description: 'Own 3 tiles in a straight line.',
    bonusVp: 3,
    isComplete: _hasStraightLine,
  ),
  'centrist': ObjectiveSpec(
    id: 'centrist',
    name: 'Heart of the Realm',
    description: 'Own the center tile.',
    bonusVp: 3,
    isComplete: (s, p) => s.tiles[const Hex(0, 0)]?.ownerId == p,
  ),
};

bool _hasStraightLine(GameState s, int playerId) {
  final owned = {
    for (final t in s.tiles.values)
      if (t.ownerId == playerId) t.coord,
  };
  for (final start in owned) {
    for (final d in Hex.directions) {
      if (owned.contains(start + d) && owned.contains(start + d + d)) {
        return true;
      }
    }
  }
  return false;
}

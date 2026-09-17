import 'package:meta/meta.dart';

import 'terrain.dart';

/// Landmarks offered per game, drawn from [landmarkCatalog].
const landmarkOfferSize = 4;

@immutable
class LandmarkSpec {
  final String id;
  final String name;
  final String description;
  final Map<Resource, int> cost;
  final int vp;

  const LandmarkSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.cost,
    required this.vp,
  });
}

const landmarkCatalog = <String, LandmarkSpec>{
  'high_roller': LandmarkSpec(
    id: 'high_roller',
    name: 'Gambling Hall',
    description: 'Your tiles numbered 9-12 produce double.',
    cost: {Resource.wood: 2, Resource.brick: 2, Resource.grain: 2},
    vp: 1,
  ),
  'trade_post': LandmarkSpec(
    id: 'trade_post',
    name: 'Trade Post',
    description: 'Bank trades cost 2 instead of 3.',
    cost: {Resource.wood: 2, Resource.brick: 2},
    vp: 1,
  ),
  'cheap_claims': LandmarkSpec(
    id: 'cheap_claims',
    name: 'Surveyor\'s Guild',
    description: 'Claiming a tile costs only 1 wood.',
    cost: {Resource.grain: 2, Resource.brick: 2},
    vp: 1,
  ),
  'bandit_ward': LandmarkSpec(
    id: 'bandit_ward',
    name: 'Bandit Ward',
    description: 'The bandit can never enter your lands.',
    cost: {Resource.stone: 2, Resource.wood: 1},
    vp: 1,
  ),
  'granary': LandmarkSpec(
    id: 'granary',
    name: 'Granary',
    description: 'Your fields yield +1 grain when they produce.',
    cost: {Resource.wood: 1, Resource.brick: 1, Resource.stone: 1},
    vp: 1,
  ),
  'lumber_mill': LandmarkSpec(
    id: 'lumber_mill',
    name: 'Lumber Mill',
    description: 'Your forests yield +1 wood when they produce.',
    cost: {Resource.grain: 1, Resource.brick: 1, Resource.stone: 1},
    vp: 1,
  ),
  'deep_mine': LandmarkSpec(
    id: 'deep_mine',
    name: 'Deep Mine',
    description: 'Your mountains yield +1 stone when they produce.',
    cost: {Resource.wood: 1, Resource.grain: 1, Resource.brick: 1},
    vp: 1,
  ),
  'kiln': LandmarkSpec(
    id: 'kiln',
    name: 'Kiln',
    description: 'Your hills yield +1 brick when they produce.',
    cost: {Resource.wood: 1, Resource.grain: 1, Resource.stone: 1},
    vp: 1,
  ),
  'cathedral': LandmarkSpec(
    id: 'cathedral',
    name: 'Cathedral',
    description: 'Worth 3 points. Nothing more. Nothing less.',
    cost: {Resource.grain: 3, Resource.stone: 3},
    vp: 3,
  ),
  'market_hall': LandmarkSpec(
    id: 'market_hall',
    name: 'Market Hall',
    description: 'Gain 1 grain at the start of each of your turns.',
    cost: {Resource.wood: 2, Resource.grain: 2},
    vp: 1,
  ),
  'watchtower': LandmarkSpec(
    id: 'watchtower',
    name: 'Watchtower',
    description: 'Rivals\' cards cannot target you or your tiles.',
    cost: {Resource.stone: 2, Resource.brick: 1},
    vp: 1,
  ),
  'keep': LandmarkSpec(
    id: 'keep',
    name: 'The Keep',
    description: 'Worth +1 point per Level-2 hex you own at game end.',
    cost: {Resource.stone: 3, Resource.brick: 2},
    vp: 1,
  ),
};

/// Terrain-boost landmarks: terrain -> landmark id.
const terrainBoostLandmarks = {
  TerrainType.field: 'granary',
  TerrainType.forest: 'lumber_mill',
  TerrainType.mountain: 'deep_mine',
  TerrainType.hill: 'kiln',
};

import 'hex/hex.dart';
import 'model/game_state.dart';
import 'model/player.dart';
import 'model/terrain.dart';
import 'model/tile.dart';
import 'rng.dart';

/// JSON codecs for the whole game state, including RNG internals, so an
/// autosaved game resumes bit-identically.

Map<String, dynamic> gameStateToJson(GameState s) => {
      'version': s.version,
      'seed': s.seed,
      'rng': s.rng.toJson(),
      'round': s.round,
      'roundCap': s.roundCap,
      'targetVp': s.targetVp,
      'currentPlayerIndex': s.currentPlayerIndex,
      'phase': s.phase.name,
      'tiles': [for (final t in s.tiles.values) _tileToJson(t)],
      'players': [for (final p in s.players) _playerToJson(p)],
      'landmarkOffer': s.landmarkOffer,
      'lastDice': s.lastDice == null ? null : [s.lastDice!.$1, s.lastDice!.$2],
      'diceHistory': [
        for (final (d1, d2) in s.diceHistory) [d1, d2],
      ],
      'winnerId': s.winnerId,
    };

GameState gameStateFromJson(Map<String, dynamic> json) {
  final tiles = <Hex, Tile>{};
  for (final t in json['tiles'] as List) {
    final tile = _tileFromJson(t as Map<String, dynamic>);
    tiles[tile.coord] = tile;
  }
  final lastDice = json['lastDice'] as List?;
  return GameState(
    version: json['version'] as int,
    seed: json['seed'] as int,
    rng: GameRng.fromJson(json['rng'] as Map<String, dynamic>),
    round: json['round'] as int,
    roundCap: json['roundCap'] as int,
    targetVp: json['targetVp'] as int,
    currentPlayerIndex: json['currentPlayerIndex'] as int,
    phase: Phase.values.byName(json['phase'] as String),
    tiles: tiles,
    players: [
      for (final p in json['players'] as List)
        _playerFromJson(p as Map<String, dynamic>),
    ],
    landmarkOffer: (json['landmarkOffer'] as List).cast<String>(),
    lastDice:
        lastDice == null ? null : (lastDice[0] as int, lastDice[1] as int),
    diceHistory: [
      for (final d in json['diceHistory'] as List)
        ((d as List)[0] as int, d[1] as int),
    ],
    winnerId: json['winnerId'] as int?,
  );
}

Map<String, dynamic> _tileToJson(Tile t) => {
      'q': t.coord.q,
      'r': t.coord.r,
      'terrain': t.terrain.name,
      'number': t.number,
      'ownerId': t.ownerId,
      'level': t.level,
      'hasBandit': t.hasBandit,
      'blockedUntilRound': t.blockedUntilRound,
    };

Tile _tileFromJson(Map<String, dynamic> json) => Tile(
      coord: Hex(json['q'] as int, json['r'] as int),
      terrain: TerrainType.values.byName(json['terrain'] as String),
      number: json['number'] as int?,
      ownerId: json['ownerId'] as int?,
      level: json['level'] as int,
      hasBandit: json['hasBandit'] as bool,
      blockedUntilRound: json['blockedUntilRound'] as int?,
    );

Map<String, dynamic> _playerToJson(PlayerState p) => {
      'id': p.id,
      'name': p.name,
      'isBot': p.isBot,
      'difficulty': p.difficulty.name,
      'resources': {
        for (final e in p.resources.entries) e.key.name: e.value,
      },
      'hand': p.hand,
      'objectiveId': p.objectiveId,
      'landmarkIds': p.landmarkIds,
      'cardPlayedThisTurn': p.cardPlayedThisTurn,
    };

PlayerState _playerFromJson(Map<String, dynamic> json) => PlayerState(
      id: json['id'] as int,
      name: json['name'] as String,
      isBot: json['isBot'] as bool,
      difficulty: BotDifficulty.values.byName(json['difficulty'] as String),
      resources: {
        for (final e in (json['resources'] as Map<String, dynamic>).entries)
          Resource.values.byName(e.key): e.value as int,
      },
      hand: (json['hand'] as List).cast<String>(),
      objectiveId: json['objectiveId'] as String?,
      landmarkIds: (json['landmarkIds'] as List).cast<String>(),
      cardPlayedThisTurn: json['cardPlayedThisTurn'] as bool,
    );

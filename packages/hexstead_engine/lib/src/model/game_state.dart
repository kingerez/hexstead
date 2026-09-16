import 'package:meta/meta.dart';

import '../hex/hex.dart';
import '../map_generator.dart';
import '../rng.dart';
import 'cards.dart';
import 'landmarks.dart';
import 'objectives.dart';
import 'player.dart';
import 'terrain.dart';
import 'tile.dart';

enum Phase { awaitingRoll, awaitingChoice, awaitingBandit, main, gameOver }

/// Build costs and other tunable rule constants.
abstract final class Rules {
  static const claimCost = {Resource.wood: 1, Resource.brick: 1};
  static const upgradeCost = {Resource.grain: 2, Resource.stone: 1};
  static const banditRemovalCount = 2;
  static const bankTradeRate = 3;
  static const startingResources = {Resource.wood: 1, Resource.brick: 1};
  static const defaultTargetVp = 25;
  static const defaultRoundCap = 15;

  static Map<Resource, int> effectiveClaimCost(PlayerState player) =>
      player.hasLandmark('cheap_claims') ? {Resource.wood: 1} : claimCost;

  static int effectiveTradeRate(PlayerState player) =>
      player.hasLandmark('trade_post') ? 2 : bankTradeRate;
}

@immutable
class GameState {
  final int seed;
  final GameRng rng;
  final int round;
  final int roundCap;
  final int targetVp;
  final int currentPlayerIndex;
  final Phase phase;
  final Map<Hex, Tile> tiles;
  final List<PlayerState> players;

  /// Landmark ids purchasable this game, first come first served.
  final List<String> landmarkOffer;
  final (int, int)? lastDice;
  final List<(int, int)> diceHistory;
  final int? winnerId;

  /// Save-format version for future migrations.
  final int version;

  const GameState({
    required this.seed,
    required this.rng,
    required this.round,
    required this.roundCap,
    required this.targetVp,
    required this.currentPlayerIndex,
    required this.phase,
    required this.tiles,
    required this.players,
    required this.landmarkOffer,
    this.lastDice,
    this.diceHistory = const [],
    this.winnerId,
    this.version = 1,
  });

  PlayerState get currentPlayer => players[currentPlayerIndex];

  factory GameState.newGame({
    required int seed,
    required List<PlayerSetup> players,
    int targetVp = Rules.defaultTargetVp,
    int roundCap = Rules.defaultRoundCap,
  }) {
    final rng = GameRng(seed);
    var tiles = generateMap(rng);
    final camps = _pickStartingCamps(tiles, players.length, rng);
    for (final (playerId, coord) in camps.indexed) {
      tiles = {
        ...tiles,
        coord: tiles[coord]!.copyWith(ownerId: playerId, level: 1),
      };
    }
    final deck = [
      for (final id in cardCatalog.keys)
        for (var copy = 0; copy < cardCopies; copy++) id,
    ];
    rng.shuffle(deck);
    final hands = [
      for (var i = 0; i < players.length; i++)
        deck.sublist(i * startingHandSize, (i + 1) * startingHandSize),
    ];
    final landmarkPool = landmarkCatalog.keys.toList();
    rng.shuffle(landmarkPool);
    final offer = landmarkPool.take(landmarkOfferSize).toList();
    final objectivePool = objectiveCatalog.keys.toList();
    rng.shuffle(objectivePool);
    return GameState(
      seed: seed,
      rng: rng,
      round: 1,
      roundCap: roundCap,
      targetVp: targetVp,
      currentPlayerIndex: 0,
      phase: Phase.awaitingRoll,
      tiles: tiles,
      players: [
        for (final (id, setup) in players.indexed)
          PlayerState(
            id: id,
            name: setup.name,
            isBot: setup.isBot,
            difficulty: setup.difficulty,
            resources: Rules.startingResources,
            hand: hands[id],
            objectiveId: objectivePool[id],
          ),
      ],
      landmarkOffer: offer,
    );
  }

  /// Picks one numbered tile per player, pairwise at least 2 hexes apart.
  static List<Hex> _pickStartingCamps(
      Map<Hex, Tile> tiles, int playerCount, GameRng rng) {
    final candidates = tiles.values
        .where((t) => t.number != null)
        .map((t) => t.coord)
        .toList();
    for (var minDistance = 2; minDistance >= 1; minDistance--) {
      for (var attempt = 0; attempt < 40; attempt++) {
        final shuffled = [...candidates];
        rng.shuffle(shuffled);
        final picked = <Hex>[];
        for (final c in shuffled) {
          if (picked.every((p) => p.distanceTo(c) >= minDistance)) {
            picked.add(c);
            if (picked.length == playerCount) return picked;
          }
        }
      }
    }
    throw StateError('cannot place $playerCount starting camps');
  }

  GameState copyWith({
    GameRng? rng,
    int? round,
    int? currentPlayerIndex,
    Phase? phase,
    Map<Hex, Tile>? tiles,
    List<PlayerState>? players,
    List<String>? landmarkOffer,
    (int, int)? Function()? lastDice,
    List<(int, int)>? diceHistory,
    int? Function()? winnerId,
  }) =>
      GameState(
        seed: seed,
        rng: rng ?? this.rng,
        round: round ?? this.round,
        roundCap: roundCap,
        targetVp: targetVp,
        currentPlayerIndex: currentPlayerIndex ?? this.currentPlayerIndex,
        phase: phase ?? this.phase,
        tiles: tiles ?? this.tiles,
        players: players ?? this.players,
        landmarkOffer: landmarkOffer ?? this.landmarkOffer,
        lastDice: lastDice != null ? lastDice() : this.lastDice,
        diceHistory: diceHistory ?? this.diceHistory,
        winnerId: winnerId != null ? winnerId() : this.winnerId,
        version: version,
      );

  GameState withPlayer(int id, PlayerState Function(PlayerState) update) =>
      copyWith(players: [
        for (final p in players) p.id == id ? update(p) : p,
      ]);
}

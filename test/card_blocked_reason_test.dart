import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/state/card_blocked_reason.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

/// Human (id 0) holding [hand] with [resources]; one free tile unless
/// [boardFull].
GameState fixture({
  required List<String> hand,
  Phase phase = Phase.main,
  int current = 0,
  Map<Resource, int> resources = const {Resource.wood: 1},
  bool cardPlayed = false,
  bool boardFull = false,
}) {
  final tilesSpec = [
    (const Hex(0, 0), TerrainType.forest, 8, 0),
    (const Hex(1, 0), TerrainType.field, 9, 1),
    (const Hex(0, 1), TerrainType.hill, 4, 0),
    (const Hex(1, -1), TerrainType.mountain, 6, boardFull ? 1 : null),
  ];
  return GameState(
    seed: 1,
    rng: GameRng(1),
    round: 3,
    roundCap: 15,
    targetVp: 99,
    currentPlayerIndex: current,
    phase: phase,
    tiles: {
      for (final (coord, terrain, number, owner) in tilesSpec)
        coord: Tile(
          coord: coord,
          terrain: terrain,
          number: number,
          ownerId: owner,
          level: owner == null ? 0 : 1,
        ),
    },
    players: [
      PlayerState(
        id: 0,
        name: 'You',
        isBot: false,
        resources: resources,
        hand: hand,
        cardPlayedThisTurn: cardPlayed,
      ),
      PlayerState(
          id: 1,
          name: 'Bot',
          isBot: true,
          resources: const {Resource.grain: 2},
          hand: const []),
    ],
    landmarkOffer: const [],
    lastDice: (3, 5),
    diceHistory: [(3, 5)],
  );
}

void main() {
  test('charter in main phase without the claim cost names the price', () {
    final s = fixture(hand: ['charter']);
    expect(legalActions(s).whereType<PlayCard>(), isEmpty);
    final cost = costText(Rules.effectiveClaimCost(s.players[0]));
    expect(cost, 'wood + brick');
    expect(cardBlockedReason(s, 0, 'charter'), 'need $cost');
  });

  test('cost text keeps counts above one', () {
    expect(costText({Resource.grain: 2, Resource.stone: 1}),
        '2 grain + stone');
  });

  test('charter with no free tile says so', () {
    final s = fixture(
      hand: ['charter'],
      boardFull: true,
      resources: const {Resource.wood: 3, Resource.brick: 3},
    );
    expect(cardBlockedReason(s, 0, 'charter'), 'no free tiles');
  });

  test('main card before the roll waits for the dice', () {
    final s = fixture(hand: ['harvest'], phase: Phase.awaitingRoll);
    expect(cardBlockedReason(s, 0, 'harvest'), 'playable after dice resolve');
  });

  test('dice card in the main phase is past its window', () {
    final s = fixture(hand: ['omen']);
    expect(cardBlockedReason(s, 0, 'omen'), 'playable right after rolling');
  });

  test('a second card in one turn is blocked', () {
    final s = fixture(hand: ['harvest'], cardPlayed: true);
    expect(cardBlockedReason(s, 0, 'harvest'), 'one card per turn');
  });

  test("on a rival's turn every card waits", () {
    final s = fixture(hand: ['harvest'], current: 1);
    expect(cardBlockedReason(s, 0, 'harvest'), 'playable on your turn');
  });

  test('banish without a bandit on own tiles', () {
    final s = fixture(hand: ['banish']);
    expect(cardBlockedReason(s, 0, 'banish'), 'no bandit on your tiles');
  });
}

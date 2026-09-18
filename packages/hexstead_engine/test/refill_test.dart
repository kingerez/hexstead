import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

/// Same board as cards_test, plus a settable deck and seat so a round wrap
/// can be driven with one EndTurn.
GameState fixture({
  int round = 4,
  int currentPlayerIndex = 1,
  List<String> deck = const [],
  List<String> p0Hand = const [],
  List<String> p1Hand = const [],
}) {
  const tilesSpec = [
    (Hex(0, 0), TerrainType.forest, 8, 0, 1),
    (Hex(1, 0), TerrainType.field, 8, 1, 2),
    (Hex(0, 1), TerrainType.hill, 4, 0, 1),
    (Hex(1, -1), TerrainType.mountain, 6, null, 0),
  ];
  return GameState(
    seed: 1,
    rng: GameRng(1),
    round: round,
    roundCap: 15,
    targetVp: 99,
    currentPlayerIndex: currentPlayerIndex,
    phase: Phase.main,
    tiles: {
      for (final (coord, terrain, number, owner, level) in tilesSpec)
        coord: Tile(
          coord: coord,
          terrain: terrain,
          number: number,
          ownerId: owner,
          level: level,
        ),
    },
    players: [
      PlayerState(
        id: 0,
        name: 'You',
        isBot: false,
        resources: {Resource.wood: 3, Resource.brick: 3},
        hand: p0Hand,
      ),
      PlayerState(
        id: 1,
        name: 'Bot',
        isBot: true,
        resources: {Resource.grain: 2},
        hand: p1Hand,
      ),
    ],
    landmarkOffer: const [],
    deck: deck,
  );
}

void main() {
  group('refill rounds', () {
    test('rounds 5 and 10 refill', () {
      expect(refillRounds, {5, 10});
    });

    test('wrapping into round 5 deals one card to every player', () {
      final s = fixture(
        round: 4,
        deck: ['bounty', 'harvest', 'tithe', 'omen'],
        p0Hand: ['drought'],
        p1Hand: ['banish', 'brigand'],
      );
      final r = apply(s, const EndTurn());
      expect(r.state.round, 5);
      expect(r.state.players[0].hand.length, 2);
      expect(r.state.players[1].hand.length, 3);
      expect(r.state.deck.length, 2);
      final dealt = r.events.whereType<CardsDealt>().toList();
      expect(dealt.length, 1);
      expect(dealt.first.round, 5);
      expect(dealt.first.playerIds, [0, 1]);
    });

    test('wrapping into a non-refill round deals nothing', () {
      final s = fixture(
        round: 5,
        deck: ['bounty', 'harvest', 'tithe', 'omen'],
        p0Hand: ['drought'],
      );
      final r = apply(s, const EndTurn());
      expect(r.state.round, 6);
      expect(r.state.players[0].hand, ['drought']);
      expect(r.state.players[1].hand, isEmpty);
      expect(r.state.deck.length, 4);
      expect(r.events.whereType<CardsDealt>(), isEmpty);
    });

    test('a short deck serves players in seat order and skips the rest', () {
      final s = fixture(round: 4, deck: ['bounty']);
      final r = apply(s, const EndTurn());
      expect(r.state.round, 5);
      expect(r.state.players[0].hand, ['bounty']);
      expect(r.state.players[1].hand, isEmpty);
      expect(r.state.deck, isEmpty);
      final dealt = r.events.whereType<CardsDealt>().toList();
      expect(dealt.length, 1);
      expect(dealt.first.playerIds, [0]);
    });

    test('an empty deck deals nothing and emits no event', () {
      final s = fixture(round: 4, deck: const []);
      final r = apply(s, const EndTurn());
      expect(r.state.round, 5);
      expect(r.state.players.every((p) => p.hand.isEmpty), isTrue);
      expect(r.events.whereType<CardsDealt>(), isEmpty);
    });
  });
}

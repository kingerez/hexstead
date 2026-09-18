import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

/// Same 4-tile board as reducer_core_test:
///   (0,0) forest #8  owned p0 camp
///   (1,0) field  #8  owned p1 village
///   (0,1) hill   #4  owned p0 camp
///   (1,-1) mountain #6 unowned
GameState fixtureState({
  Phase phase = Phase.awaitingChoice,
  (int, int)? lastDice,
  int p0Streak = 0,
  int p1Streak = 0,
}) {
  const tilesSpec = [
    (Hex(0, 0), TerrainType.forest, 8, 0, 1),
    (Hex(1, 0), TerrainType.field, 8, 1, 2),
    (Hex(0, 1), TerrainType.hill, 4, 0, 1),
    (Hex(1, -1), TerrainType.mountain, 6, null, 0),
  ];
  final tiles = {
    for (final (coord, terrain, number, owner, level) in tilesSpec)
      coord: Tile(
        coord: coord,
        terrain: terrain,
        number: number,
        ownerId: owner,
        level: level,
      ),
  };
  return GameState(
    seed: 1,
    rng: GameRng(1),
    round: 1,
    roundCap: 15,
    targetVp: 25,
    currentPlayerIndex: 0,
    phase: phase,
    tiles: tiles,
    players: [
      PlayerState(
        id: 0,
        name: 'You',
        isBot: false,
        resources: const {Resource.wood: 3, Resource.brick: 3},
        droughtStreak: p0Streak,
      ),
      PlayerState(
        id: 1,
        name: 'Bot',
        isBot: true,
        resources: const {},
        droughtStreak: p1Streak,
      ),
    ],
    landmarkOffer: const [],
    lastDice: lastDice,
  );
}

void main() {
  group('drought streak tracking', () {
    test('an activation that pays nobody increments every streak', () {
      // sum=5 matches no tile
      final s0 = fixtureState(lastDice: (2, 3));
      final r = apply(s0, const ChooseActivation(ActivationMode.sum));
      expect(r.state.players[0].droughtStreak, 1);
      expect(r.state.players[1].droughtStreak, 1);
      expect(r.events.whereType<DroughtRelief>(), isEmpty);
    });

    test('producing resets the streak; dry players still increment', () {
      // sum=4 pays p0's hill only
      final s0 = fixtureState(lastDice: (2, 2), p0Streak: 2, p1Streak: 1);
      final r = apply(s0, const ChooseActivation(ActivationMode.sum));
      expect(r.state.players[0].droughtStreak, 0);
      expect(r.state.players[1].droughtStreak, 2);
    });

    test('a rolled 7 counts as dry for everyone', () {
      final s0 = fixtureState(lastDice: (3, 4));
      final r = apply(s0, const ChooseActivation(ActivationMode.sum));
      expect(r.state.phase, Phase.awaitingBandit);
      expect(r.state.players[0].droughtStreak, 1);
      expect(r.state.players[1].droughtStreak, 1);
    });
  });

  group('drought relief', () {
    test('third consecutive dry activation grants 1 random resource', () {
      final s0 = fixtureState(lastDice: (2, 3), p1Streak: 2);
      final r = apply(s0, const ChooseActivation(ActivationMode.sum));
      final reliefs = r.events.whereType<DroughtRelief>().toList();
      expect(reliefs.length, 1);
      expect(reliefs.single.playerId, 1);
      expect(r.state.players[1].totalResources, 1);
      expect(r.state.players[1].countOf(reliefs.single.resource), 1);
      expect(r.state.players[1].droughtStreak, 0);
      // p0 was only at streak 0 -> 1, no relief
      expect(r.state.players[0].droughtStreak, 1);
      expect(r.state.players[0].totalResources, 6);
    });

    test('relief also fires on a 7 while heading into bandit placement', () {
      final s0 = fixtureState(lastDice: (3, 4), p0Streak: 2, p1Streak: 2);
      final r = apply(s0, const ChooseActivation(ActivationMode.sum));
      expect(r.state.phase, Phase.awaitingBandit);
      final reliefs = r.events.whereType<DroughtRelief>().toList();
      expect(reliefs.map((e) => e.playerId).toSet(), {0, 1});
      expect(r.state.players[0].droughtStreak, 0);
      expect(r.state.players[1].droughtStreak, 0);
    });

    test('relief resource is deterministic for a given rng state', () {
      DroughtRelief run() {
        final s0 = fixtureState(lastDice: (2, 3), p1Streak: 2);
        final r = apply(s0, const ChooseActivation(ActivationMode.sum));
        return r.events.whereType<DroughtRelief>().single;
      }

      expect(run().resource, run().resource);
    });
  });

  group('serialization', () {
    test('droughtStreak survives a JSON roundtrip', () {
      final s0 = fixtureState(lastDice: (2, 3), p0Streak: 1, p1Streak: 2);
      final restored = gameStateFromJson(gameStateToJson(s0));
      expect(restored.players[0].droughtStreak, 1);
      expect(restored.players[1].droughtStreak, 2);
    });

    test('legacy saves without the field default to 0', () {
      final json = gameStateToJson(fixtureState(lastDice: (2, 3)));
      for (final p in json['players'] as List) {
        (p as Map<String, dynamic>).remove('droughtStreak');
      }
      final restored = gameStateFromJson(json);
      expect(restored.players[0].droughtStreak, 0);
      expect(restored.players[1].droughtStreak, 0);
    });
  });
}

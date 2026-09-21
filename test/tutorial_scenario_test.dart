import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/tutorial/scripted_rng.dart';
import 'package:hexstead/tutorial/tutorial_scenario.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

/// Purse shorthand: wood/brick/grain/stone for one player.
List<int> purse(GameState s, int id) => [
      s.players[id].countOf(Resource.wood),
      s.players[id].countOf(Resource.brick),
      s.players[id].countOf(Resource.grain),
      s.players[id].countOf(Resource.stone),
    ];

void main() {
  test('the authored board matches the real generator\'s bags', () {
    final tiles = TutorialScenario().initialState().tiles;

    expect(tiles.length, 19);
    expect(tiles.keys.toSet(), Hex.spiral(const Hex(0, 0), 2).toSet());

    final terrains = <TerrainType, int>{};
    for (final t in tiles.values) {
      terrains[t.terrain] = (terrains[t.terrain] ?? 0) + 1;
    }
    expect(terrains, {
      TerrainType.forest: 5,
      TerrainType.field: 5,
      TerrainType.hill: 4,
      TerrainType.mountain: 4,
      TerrainType.desert: 1,
    });

    final numbers = [
      for (final t in tiles.values)
        if (t.number != null) t.number!,
    ]..sort();
    expect(numbers,
        [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12]);
    expect(tiles[const Hex(2, 0)]!.number, isNull, reason: 'desert');

    // The generator rejects touching 6/8 tiles; so must the hand-authored
    // board, or it is not a board the game could have dealt.
    final hot = [
      for (final t in tiles.values)
        if (t.number == 6 || t.number == 8) t.coord,
    ];
    for (final a in hot) {
      for (final b in hot) {
        if (a == b) continue;
        expect(a.distanceTo(b), greaterThanOrEqualTo(2));
      }
    }

    // Starting camps sit as far apart as the generator demands.
    expect(
      TutorialScenario.homeCamp.distanceTo(TutorialScenario.rivalCamp),
      greaterThanOrEqualTo(2),
    );
  });

  test('the script walks the whole rehearsed game with no illegal move', () {
    final scenario = TutorialScenario();
    var state = scenario.initialState();
    final rolled = <(int, int)>[];

    /// Applies one action through the reducer, keeping the dice log.
    void play(GameAction action) {
      final result = apply(state, action);
      state = result.state;
      for (final e in result.events.whereType<DiceRolled>()) {
        rolled.add((e.d1, e.d2));
      }
    }

    /// Runs Bertram until he is out of lines or it is your turn again.
    void runBot() {
      while (state.currentPlayer.isBot) {
        final action = scenario.nextBotAction(state);
        if (action == null) break;
        play(action);
      }
    }

    // A wood and a brick over the standard opening purse: the script needs
    // them for the King's Road claim, and spends them all.
    expect(purse(state, 0), [3, 3, 0, 0]);
    expect(purse(state, 1), [2, 2, 0, 0]);

    // --- Round 1, you -------------------------------------------------
    play(const RollDice());
    expect(state.lastDice, (3, 5));
    play(const ChooseActivation(ActivationMode.sum));
    // Sum 8: your forest camp is the only owned 8.
    expect(purse(state, 0), [4, 3, 0, 0]);
    play(const ClaimHex(TutorialScenario.claimTarget));
    expect(purse(state, 0), [3, 2, 0, 0]);
    expect(state.tiles[TutorialScenario.claimTarget]!.ownerId, 0);
    play(const EndTurn());

    // --- Round 1, Bertram ---------------------------------------------
    runBot();
    expect(rolled.last, (3, 2));
    expect(purse(state, 1), [1, 1, 1, 0]);
    expect(state.tiles[TutorialScenario.rivalClaim]!.ownerId, 1);
    expect(state.round, 2);
    expect(state.currentPlayerIndex, 0);

    // --- Round 2, you -------------------------------------------------
    play(const RollDice());
    expect(state.lastDice, (2, 4));
    // Sum 6 would pay no one - both 6s are unowned; the split's 4 pays.
    expect(
      state.tiles.values
          .where((t) => t.number == 6 && t.ownerId != null)
          .isEmpty,
      isTrue,
    );
    play(const ChooseActivation(ActivationMode.split));
    expect(purse(state, 0), [3, 3, 0, 0]);
    play(const PlayCard('bounty', resource: Resource.grain));
    expect(purse(state, 0), [3, 3, 2, 0]);
    play(const EndTurn());

    // --- Round 2, Bertram ---------------------------------------------
    runBot();
    expect(rolled.last, (1, 3));
    // His 4 pays YOUR hill, and nothing of his.
    expect(purse(state, 0), [3, 4, 2, 0]);
    expect(purse(state, 1), [1, 1, 1, 0]);
    expect(state.round, 3);

    // --- Round 3, you -------------------------------------------------
    play(const RollDice());
    expect(state.lastDice, (3, 4));
    play(const ChooseActivation(ActivationMode.sum));
    expect(state.phase, Phase.awaitingBandit);
    play(const PlaceBandit(TutorialScenario.rivalCamp));
    expect(state.tiles[TutorialScenario.rivalCamp]!.hasBandit, isTrue);
    play(const BuyLandmark('market_hall'));
    expect(purse(state, 0), [1, 4, 0, 0]);
    // The third hex of the King's Road, and the purse pays for it exactly.
    play(const ClaimHex(TutorialScenario.roadFinisher));
    expect(purse(state, 0), [0, 3, 0, 0]);
    expect(state.tiles[TutorialScenario.roadFinisher]!.ownerId, 0);
    play(const BankTrade(give: Resource.brick, get: Resource.stone));
    expect(purse(state, 0), [0, 0, 0, 1]);
    // Three territory points plus the landmark - nowhere near the target, so
    // the tutorial never trips an instant win or a match-point warning. The
    // secret task's bonus is not among them; it waits for the final tally.
    expect(scoreFor(state, 0), 4);
    expect(state.targetVp, 15);
    play(const EndTurn());

    // --- Round 3, Bertram ---------------------------------------------
    runBot();
    expect(rolled.last, (2, 3));
    // His 5 is blocked by the bandit, so he pays two to chase it off.
    expect(state.tiles[TutorialScenario.rivalCamp]!.hasBandit, isFalse);
    expect(purse(state, 1), [0, 0, 1, 0]);

    // He stops mid-turn: the round never wraps to 4, so no giveaway and no
    // refill ever fire, and the die queue is consumed exactly.
    expect(state.round, 3);
    expect(state.currentPlayerIndex, 1);
    expect(state.phase, Phase.main);
    expect(scenario.nextBotAction(state), isNull);
    expect(
      rolled,
      [(3, 5), (3, 2), (2, 4), (1, 3), (3, 4), (2, 3)],
    );
    expect((state.rng as ScriptedRng).remaining, 0);

    // Your King's Road is finished: three hexes in a line.
    expect(
      objectiveCatalog['straight_line']!.progress(state, 0),
      (3, 3),
    );
  });
}

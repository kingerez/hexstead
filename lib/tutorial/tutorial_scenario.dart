import 'package:hexstead_engine/hexstead_engine.dart';

import 'scripted_rng.dart';

/// The rehearsed game the tutorial plays out: a hand-authored board, a fixed
/// run of dice, and one opponent who does exactly as he is told.
///
/// Nothing here is random. The board uses the real generator's terrain and
/// number bags (5 forest, 5 field, 4 hill, 4 mountain, 1 desert; 2, 3x2,
/// 4x2, 5x2, 6x2, 8x2, 9x2, 10x2, 11x2, 12) and keeps every 6 and 8 two
/// hexes apart, so it is a board the generator could genuinely have dealt.
class TutorialScenario {
  /// Your camp, and the hill you are taught to claim beside it.
  static const homeCamp = Hex(0, 1);
  static const claimTarget = Hex(1, 1);

  /// The mountain at the centre: the hex step 2 asks you to inspect.
  static const inspectTarget = Hex(0, 0);

  /// Bertram's camp - the bandit's mark, and the tile he later pays to free.
  static const rivalCamp = Hex(0, -1);

  /// The field Bertram claims on his first turn.
  static const rivalClaim = Hex(0, -2);

  /// The third hex of your King's Road: the claim that fulfils your secret
  /// task, on the far side of your camp from the hill you took first.
  static const roadFinisher = Hex(-1, 1);

  /// Consumption order: you 3+5, Bertram 3+2, you 2+4, Bertram 1+3,
  /// you 3+4 (the bandit's seven), Bertram 2+3.
  static const dieQueue = [3, 5, 3, 2, 2, 4, 1, 3, 3, 4, 2, 3];

  /// (hex, terrain, number, owner) - owner null means unclaimed. Every owned
  /// tile is a level-1 camp.
  static const _board = <(Hex, TerrainType, int?, int?)>[
    // Centre.
    (Hex(0, 0), TerrainType.mountain, 11, null),
    // Ring 1: the two camps and four neighbours.
    (homeCamp, TerrainType.forest, 8, 0),
    (Hex(-1, 1), TerrainType.forest, 3, null),
    (Hex(1, 0), TerrainType.hill, 2, null),
    (Hex(1, -1), TerrainType.mountain, 8, null),
    (rivalCamp, TerrainType.field, 5, 1),
    (Hex(-1, 0), TerrainType.mountain, 4, null),
    // Ring 2.
    (Hex(-2, 2), TerrainType.hill, 6, null),
    (Hex(-1, 2), TerrainType.field, 10, null),
    (Hex(0, 2), TerrainType.mountain, 5, null),
    (claimTarget, TerrainType.hill, 4, null),
    (Hex(2, 0), TerrainType.desert, null, null),
    (Hex(2, -1), TerrainType.forest, 10, null),
    (Hex(2, -2), TerrainType.field, 3, null),
    (Hex(1, -2), TerrainType.forest, 12, null),
    (rivalClaim, TerrainType.field, 9, null),
    (Hex(-1, -1), TerrainType.hill, 9, null),
    (Hex(-2, 0), TerrainType.field, 6, null),
    (Hex(-2, 1), TerrainType.forest, 11, null),
  ];

  /// Bertram's whole game, in order. He stops after chasing the bandit off,
  /// which parks the game under the closing banner.
  final List<GameAction> _botActions = [
    // Turn 1: roll 3+2, take the sum, claim the field below his camp.
    const RollDice(),
    const ChooseActivation(ActivationMode.sum),
    const ClaimHex(rivalClaim),
    const EndTurn(),
    // Turn 2: roll 1+3 - his 4 pays your hill, not him.
    const RollDice(),
    const ChooseActivation(ActivationMode.sum),
    const EndTurn(),
    // Turn 3: roll 2+3, blocked by the bandit, so he buys it off.
    const RollDice(),
    const ChooseActivation(ActivationMode.sum),
    const RemoveBandit(spend: [Resource.wood, Resource.brick]),
  ];

  /// The opening position: your turn, round 1, nothing rolled yet.
  GameState initialState() => GameState(
        seed: 0,
        rng: ScriptedRng(dieQueue),
        round: 1,
        roundCap: Rules.defaultRoundCap,
        targetVp: Rules.defaultTargetVp,
        currentPlayerIndex: 0,
        phase: Phase.awaitingRoll,
        tiles: {
          for (final (coord, terrain, number, owner) in _board)
            coord: Tile(
              coord: coord,
              terrain: terrain,
              number: number,
              ownerId: owner,
              level: owner == null ? 0 : 1,
            ),
        },
        players: const [
          PlayerState(
            id: 0,
            name: 'You',
            isBot: false,
            // A wood and a brick over the usual opening purse: the script
            // spends every coin it is given, and the King's Road lesson
            // buys a third hex the real opening could not have paid for.
            resources: {Resource.wood: 3, Resource.brick: 3},
            hand: ['bounty', 'second_chance', 'harvest'],
            objectiveId: 'straight_line',
          ),
          PlayerState(
            id: 1,
            name: 'Bertram',
            isBot: true,
            resources: {Resource.wood: 2, Resource.brick: 2},
            objectiveId: 'sprawl',
          ),
        ],
        // Only the Market Hall (2 wood + 2 grain) ever comes within reach.
        landmarkOffer: const [
          'market_hall',
          'kiln',
          'granary',
          'bandit_ward',
        ],
        // Empty: no card replacement, no refill draws, no stray rng calls
        // that would slide the die queue out from under the script.
        deck: const [],
      );

  /// The bot brain handed to the controller: the next rehearsed move, or
  /// null once Bertram is out of lines and the game should simply wait.
  GameAction? nextBotAction(GameState state) =>
      _botActions.isEmpty ? null : _botActions.removeAt(0);
}

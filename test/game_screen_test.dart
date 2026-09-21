import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/board/board_geometry.dart';
import 'package:hexstead/board/board_widget.dart';
import 'package:hexstead/screens/game_over_screen.dart';
import 'package:hexstead/screens/game_screen.dart';
import 'package:hexstead/widgets/card_fan_overlay.dart';
import 'package:hexstead/widgets/dice_roll_overlay.dart';
import 'package:hexstead/widgets/fireworks.dart';
import 'package:hexstead/widgets/game_end_overlay.dart';
import 'package:hexstead/widgets/task_reveal_overlay.dart';
import 'package:hexstead/widgets/tile_inspector.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InMemorySaveStore implements SaveStore {
  String? saved;

  @override
  Future<void> save(String json) async => saved = json;

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> clear() async => saved = null;
}

/// Fresh games show the welcome briefing after 500ms, then the card fan;
/// dismiss both so play can start.
Future<void> dismissWelcome(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
  // The starting-hand fan dismisses with a tap anywhere outside the cards.
  await tester.tapAt(const Offset(10, 100));
  await tester.pumpAndSettle();
}

/// A fresh game pumped up to the opening card fan: welcome card dismissed,
/// the hand on screen, the task reveal still queued behind it.
Future<GameController> startFreshGame(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final controller = GameController(
    saveStore: InMemorySaveStore(),
    botStepDelay: Duration.zero,
  );
  await controller.startNewGame(seed: 12, players: const [
    PlayerSetup(name: 'You', isBot: false),
    PlayerSetup(name: 'Bot', isBot: true),
  ]);
  await tester.pumpWidget(
    MaterialApp(home: GameScreen(controller: controller)),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
  return controller;
}

/// Taps the opening fan away and stops on the frame where the task reveal
/// has just taken over - no pumpAndSettle, the reveal is still running.
Future<void> closeOpeningFan(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 100));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// Whether the HUD's task chip is painting: the game-start reveal keeps it
/// laid out but hidden while its banner is still in flight.
bool taskChipVisible(WidgetTester tester, String chipNeedle) {
  final chip = find.textContaining(chipNeedle, findRichText: true);
  expect(chip, findsWidgets);
  return tester
      .widget<Visibility>(
        find.ancestor(of: chip.first, matching: find.byType(Visibility)).first,
      )
      .visible;
}

/// Resumed mid-game state (so no welcome card): human to act in the main
/// phase, owning two forests, with whatever purse and offer a test needs.
GameState fixture({
  Map<Resource, int> resources = const {},
  List<String> landmarkOffer = const [],
  String objectiveId = 'forester',
  // Out of reach by default, so scoring never trips the endgame chrome; the
  // match-point tests pull it down within a move or two of the human.
  int targetVp = 99,
}) {
  const tilesSpec = [
    (Hex(0, 0), TerrainType.forest, 8, 0, 1),
    (Hex(1, 0), TerrainType.forest, 9, 0, 1),
    (Hex(0, 1), TerrainType.hill, 4, 1, 1),
    (Hex(1, -1), TerrainType.mountain, 6, null, 0),
  ];
  return GameState(
    seed: 1,
    rng: GameRng(1),
    round: 3,
    roundCap: 15,
    targetVp: targetVp,
    currentPlayerIndex: 0,
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
        resources: resources,
        objectiveId: objectiveId,
      ),
      const PlayerState(id: 1, name: 'Bot', isBot: true),
    ],
    landmarkOffer: landmarkOffer,
    lastDice: (3, 5),
    diceHistory: [(3, 5)],
  );
}

/// Copied from test/card_target_test.dart: where on screen a hex sits.
Offset hexCenter(WidgetTester tester, Hex hex) {
  final rect = tester.getRect(find.byType(BoardWidget));
  return rect.topLeft + BoardGeometry(rect.size).centerOf(hex);
}

/// The inspector's claim button, found by the price tag it wears.
Finder claimButton() => find.ancestor(
      of: find.textContaining('Claim for', findRichText: true),
      matching: find.byType(FilledButton),
    );

Future<GameController> pumpResumed(WidgetTester tester, GameState s) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySaveStore()..saved = jsonEncode(gameStateToJson(s));
  final controller =
      GameController(saveStore: store, botStepDelay: Duration.zero);
  await controller.resume();
  await tester.pumpWidget(
    MaterialApp(home: GameScreen(controller: controller)),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('welcome card briefs the secret goal, Start reveals the HUD',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = GameController(
      saveStore: InMemorySaveStore(),
      botStepDelay: Duration.zero,
    );
    await controller.startNewGame(seed: 12, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Bot', isBot: true),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );

    // Board first, briefing after the 500ms beat.
    expect(find.text('Welcome to Hexstead'), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Welcome to Hexstead'), findsOneWidget);
    expect(find.textContaining('YOUR SECRET GOAL'), findsOneWidget);
    expect(find.textContaining('Bonus:'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Hexstead'), findsNothing);

    // The starting hand is revealed and waits for a dismissing tap.
    expect(find.text('Your cards'), findsWidgets);
    await tester.tapAt(const Offset(10, 100));
    await tester.pumpAndSettle();
    expect(find.text('Your cards'), findsNothing);
    expect(find.text('Roll the dice'), findsOneWidget);
  });

  testWidgets('tapping the fan icon reopens the hand as a card fan',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = GameController(
      saveStore: InMemorySaveStore(),
      botStepDelay: Duration.zero,
    );
    await controller.startNewGame(seed: 13, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Bot', isBot: true),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await dismissWelcome(tester);

    await tester.tap(find.byType(CardFanIcon));
    await tester.pumpAndSettle();
    expect(find.text('Your cards'), findsWidgets);
    // Cards show their names in the fan.
    final hand = controller.state!.players.first.hand;
    expect(find.text(cardCatalog[hand.first]!.name), findsOneWidget);

    // Tap outside to close.
    await tester.tapAt(const Offset(10, 200));
    await tester.pumpAndSettle();
    expect(find.text('Your cards'), findsNothing);
  });

  testWidgets('floating shop and trade buttons open their overlays',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = GameController(
      saveStore: InMemorySaveStore(),
      botStepDelay: Duration.zero,
    );
    await controller.startNewGame(seed: 14, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Bot', isBot: true),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await dismissWelcome(tester);

    // Shop: shows the landmark offer as cards.
    await tester.tap(find.text('🏛'));
    await tester.pumpAndSettle();
    expect(find.text('Landmarks for sale'), findsOneWidget);
    final offer = controller.state!.landmarkOffer;
    expect(find.text(landmarkCatalog[offer.first]!.name), findsOneWidget);
    await tester.tapAt(const Offset(10, 60));
    await tester.pumpAndSettle();
    expect(find.text('Landmarks for sale'), findsNothing);

    // Trade: shows the bank trade card.
    await tester.tap(find.byIcon(Icons.handshake));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bank trade'), findsOneWidget);
    await tester.tapAt(const Offset(10, 60));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bank trade'), findsNothing);
  });

  testWidgets('a card can be swapped once per game from the fan',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = GameController(
      saveStore: InMemorySaveStore(),
      botStepDelay: Duration.zero,
    );
    await controller.startNewGame(seed: 16, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Bot', isBot: true),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await dismissWelcome(tester);

    await tester.tap(find.byType(CardFanIcon));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.swap_horiz), findsNWidgets(3));

    final before = [...controller.state!.players.first.hand];
    await tester.tap(find.byIcon(Icons.swap_horiz).first);
    await tester.pumpAndSettle();

    final after = controller.state!.players.first.hand;
    expect(after, isNot(equals(before)));
    expect(after.length, 3);
    // One-shot: swap icons are gone.
    expect(find.byIcon(Icons.swap_horiz), findsNothing);
  });

  testWidgets('settings: gear opens card; Home asks before quitting',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = GameController(
      saveStore: InMemorySaveStore(),
      botStepDelay: Duration.zero,
    );
    await controller.startNewGame(seed: 15, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Bot', isBot: true),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await dismissWelcome(tester);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Sounds'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Leave the game?'), findsOneWidget);

    // Cancel keeps us in the game.
    await tester.tap(find.text('Keep playing'));
    await tester.pumpAndSettle();
    expect(find.text('Leave the game?'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('roll button rolls, choice buttons appear, sum resolves',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = GameController(
      saveStore: InMemorySaveStore(),
      botStepDelay: Duration.zero,
    );
    await controller.startNewGame(seed: 8, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Bot', isBot: true),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await dismissWelcome(tester);

    expect(find.text('Roll the dice'), findsOneWidget);
    await tester.tap(find.text('Roll the dice'));
    await tester.pumpAndSettle();

    expect(controller.state!.phase, Phase.awaitingChoice);
    final (d1, d2) = controller.state!.lastDice!;
    final sum = d1 + d2;
    expect(find.textContaining('Split'), findsOneWidget);

    await tester.tap(find.text(sum == 7 ? 'Bandit!' : 'Sum $sum'));
    await tester.pumpAndSettle();
    expect(
      controller.state!.phase,
      sum == 7 ? Phase.awaitingBandit : Phase.main,
    );
  });

  testWidgets('End Turn hands control to the bot and returns', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = GameController(
      saveStore: InMemorySaveStore(),
      botStepDelay: Duration.zero,
    );
    await controller.startNewGame(seed: 9, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Bot', isBot: true),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await dismissWelcome(tester);

    await tester.tap(find.text('Roll the dice'));
    await tester.pumpAndSettle();
    // resolve choice (avoid bandit branch by picking split)
    await tester.tap(find.textContaining('Split'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End Turn'));
    await tester.pumpAndSettle();

    expect(controller.state!.round, 2);
    expect(controller.isHumanTurn, isTrue);
  });

  testWidgets('the inspector starts empty and says so', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = GameController(
      saveStore: InMemorySaveStore(),
      botStepDelay: Duration.zero,
    );
    await controller.startNewGame(seed: 10, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Bot', isBot: true),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await dismissWelcome(tester);

    expect(find.byType(TileInspector), findsOneWidget);
    expect(find.text('Select a tile to view it'), findsOneWidget);
  });

  testWidgets('long-pressing a tile fills the inspector', (tester) async {
    await pumpResumed(tester, fixture());

    // The board's center is Hex(0, 0): the human's level-1 forest.
    await tester.longPress(find.byType(BoardWidget));
    await tester.pumpAndSettle();

    expect(find.text('Select a tile to view it'), findsNothing);
    expect(find.text('Forest · Level 1'), findsOneWidget);
    expect(find.text('Owner: You'), findsOneWidget);
    expect(find.text('Rolls 8 · 14% per roll'), findsOneWidget);
  });

  testWidgets('tapping your own hex selects it instead of upgrading it',
      (tester) async {
    final controller = await pumpResumed(
      tester,
      fixture(resources: const {Resource.grain: 2, Resource.stone: 1}),
    );

    await tester.tap(find.byType(BoardWidget));
    await tester.pumpAndSettle();

    expect(controller.state!.tiles[const Hex(0, 0)]!.level, 1);
    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Upgrade'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('the inspector Upgrade button upgrades the selected hex',
      (tester) async {
    final controller = await pumpResumed(
      tester,
      fixture(resources: const {Resource.grain: 2, Resource.stone: 1}),
    );

    await tester.tap(find.byType(BoardWidget));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Upgrade'));
    await tester.pumpAndSettle();

    expect(controller.state!.tiles[const Hex(0, 0)]!.level, 2);
    // Selection survives the dispatch, so the panel shows the new level.
    expect(find.text('Forest · Level 2'), findsOneWidget);
    expect(find.text('Max level'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Upgrade'), findsNothing);
  });

  testWidgets('the Upgrade button is disabled when the cost is out of reach',
      (tester) async {
    await pumpResumed(tester, fixture(resources: const {Resource.grain: 1}));

    await tester.tap(find.byType(BoardWidget));
    await tester.pumpAndSettle();

    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Upgrade'));
    expect(button.onPressed, isNull);
  });

  testWidgets('tapping an unclaimed hex selects it instead of claiming it',
      (tester) async {
    final controller = await pumpResumed(
      tester,
      fixture(resources: const {Resource.wood: 1, Resource.brick: 1}),
    );

    await tester.tapAt(hexCenter(tester, const Hex(1, -1)));
    await tester.pumpAndSettle();

    // The tap only fills the panel; the land is still nobody's.
    expect(controller.state!.tiles[const Hex(1, -1)]!.ownerId, isNull);
    expect(find.text('Mountain'), findsOneWidget);
    expect(find.text('Unclaimed'), findsOneWidget);
    expect(claimButton(), findsOneWidget);
    expect(tester.widget<FilledButton>(claimButton()).onPressed, isNotNull);
  });

  testWidgets('the inspector Claim button claims the selected hex',
      (tester) async {
    final controller = await pumpResumed(
      tester,
      fixture(resources: const {Resource.wood: 1, Resource.brick: 1}),
    );

    await tester.tapAt(hexCenter(tester, const Hex(1, -1)));
    await tester.pumpAndSettle();
    await tester.tap(claimButton());
    await tester.pumpAndSettle();

    expect(controller.state!.tiles[const Hex(1, -1)]!.ownerId, 0);
    expect(controller.state!.players.first.countOf(Resource.wood), 0);
    expect(claimButton(), findsNothing);
  });

  testWidgets('the Claim button greys out when the price is out of reach',
      (tester) async {
    await pumpResumed(tester, fixture(resources: const {Resource.wood: 1}));

    await tester.tapAt(hexCenter(tester, const Hex(1, -1)));
    await tester.pumpAndSettle();

    // The offer stays on screen with its price, dead until it can be paid.
    expect(find.text('Unclaimed'), findsOneWidget);
    expect(claimButton(), findsOneWidget);
    expect(tester.widget<FilledButton>(claimButton()).onPressed, isNull);
  });

  testWidgets('no Claim button on a hex that already has an owner',
      (tester) async {
    await pumpResumed(
      tester,
      fixture(resources: const {Resource.wood: 1, Resource.brick: 1}),
    );

    // Hex(0, 1) is the rival's hill.
    await tester.tapAt(hexCenter(tester, const Hex(0, 1)));
    await tester.pumpAndSettle();

    expect(find.text('Owner: Bot'), findsOneWidget);
    expect(claimButton(), findsNothing);
  });

  testWidgets('the panel greys the claim offer when the screen withholds it',
      (tester) async {
    final state = fixture(resources: const {Resource.wood: 1,
      Resource.brick: 1});
    Widget panel({required bool claimEnabled}) => MaterialApp(
          home: Scaffold(
            body: TileInspector(
              state: state,
              tile: state.tiles[const Hex(1, -1)],
              humanPlayerId: 0,
              upgradeEnabled: false,
              onUpgrade: () {},
              claimEnabled: claimEnabled,
              onClaim: () {},
            ),
          ),
        );

    // Standing in for the states the screen alone knows about - a bot's turn
    // among them: the button is there either way, live only when told.
    await tester.pumpWidget(panel(claimEnabled: false));
    await tester.pumpAndSettle();
    expect(claimButton(), findsOneWidget);
    expect(tester.widget<FilledButton>(claimButton()).onPressed, isNull);

    await tester.pumpWidget(panel(claimEnabled: true));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(claimButton()).onPressed, isNotNull);
  });

  testWidgets('rolling shows the dice animation, then the choice buttons',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = GameController(
      saveStore: InMemorySaveStore(),
      botStepDelay: Duration.zero,
    );
    await controller.startNewGame(seed: 11, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Bot', isBot: true),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );

    await dismissWelcome(tester);
    await tester.tap(find.text('Roll the dice'));
    await tester.pump(const Duration(milliseconds: 300));

    // Mid-roll: overlay is up, choice buttons are hidden.
    expect(find.byType(DiceRollOverlay), findsOneWidget);
    expect(find.textContaining('Split'), findsNothing);

    await tester.pumpAndSettle();

    // Settled: overlay gone, the sum-or-split decision is on screen.
    expect(find.byType(DiceRollOverlay), findsNothing);
    expect(find.textContaining('Split'), findsOneWidget);
  });

  testWidgets('ending a turn splashes the incoming player, then clears',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = GameController(
      saveStore: InMemorySaveStore(),
      botStepDelay: Duration.zero,
    );
    await controller.startNewGame(seed: 9, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Bot', isBot: true),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await dismissWelcome(tester);

    await tester.tap(find.text('Roll the dice'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Split'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End Turn'));

    // The splash queues behind the end-of-turn ceremonies, so step until
    // it shows rather than guessing its arrival.
    var found = false;
    for (var i = 0; i < 60 && !found; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      found = tester.any(find.text("Bot's turn"));
    }
    expect(found, isTrue, reason: 'ending a turn should name the bot');
    // The hand button stays put through a rival's turn - it dims, it does
    // not vanish.
    expect(find.byType(CardFanIcon), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text("Bot's turn"), findsNothing);
    expect(find.text('Your turn'), findsNothing);
  });

  testWidgets('the secret task line tracks live objective progress',
      (tester) async {
    await pumpResumed(tester, fixture(objectiveId: 'forester'));

    // The count alone: two forests of the four wanted.
    expect(find.text('🎯 2/4 forests'), findsOneWidget);
  });

  testWidgets('the secret task line marks a completed objective',
      (tester) async {
    await pumpResumed(tester, fixture(objectiveId: 'centrist'));

    // Hex(0, 0) is the human's, so the objective is already met.
    expect(find.text('🎯 1/1 center tile ✓'), findsOneWidget);
  });

  testWidgets('the shop glows only when a landmark is affordable',
      (tester) async {
    // Trade post costs 2 wood + 2 brick; the trade rate of 3 is out of
    // reach, so only the shop should light up.
    await pumpResumed(
      tester,
      fixture(
        resources: const {Resource.wood: 2, Resource.brick: 2},
        landmarkOffer: const ['trade_post'],
      ),
    );
    expect(find.byKey(const ValueKey('shop-glow')), findsOneWidget);
    expect(find.byKey(const ValueKey('trade-glow')), findsNothing);

    // One wood buys nothing: no glow anywhere.
    await pumpResumed(
      tester,
      fixture(
        resources: const {Resource.wood: 1},
        landmarkOffer: const ['trade_post'],
      ),
    );
    expect(find.byKey(const ValueKey('shop-glow')), findsNothing);
    expect(find.byKey(const ValueKey('shop')), findsOneWidget);
  });

  testWidgets('the game-start reveal flies the secret task into its chip',
      (tester) async {
    final controller = await startFreshGame(tester);

    final state = controller.state!;
    final objective = objectiveCatalog[state.players.first.objectiveId]!;
    final chipNeedle =
        '/${objective.progress(state, 0).$2} ${objective.shortLabel}';

    // The fan itself is plain now: the welcome card already said the task.
    expect(find.byType(CardFanOverlay), findsOneWidget);
    expect(
      find.textContaining('Secret task:', findRichText: true),
      findsNothing,
    );

    // Dismissing the fan hands over to the big reveal, and the chip holds
    // its spot unpainted until the banner lands on it.
    await closeOpeningFan(tester);
    expect(find.byType(TaskRevealOverlay), findsOneWidget);
    expect(
      find.textContaining('Secret task: ${objective.description}',
          findRichText: true),
      findsWidgets,
    );
    expect(taskChipVisible(tester, chipNeedle), isFalse);

    // Still up mid-hold: the point of the reveal is that it can be read.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byType(TaskRevealOverlay), findsOneWidget);

    // Entry, hold and flight over: banner gone, chip showing.
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pump();
    expect(find.byType(TaskRevealOverlay), findsNothing);
    expect(taskChipVisible(tester, chipNeedle), isTrue);

    // Reopening the hand mid-game replays none of it.
    await tester.tap(find.byType(CardFanIcon));
    await tester.pumpAndSettle();
    expect(find.byType(TaskRevealOverlay), findsNothing);
    expect(
      find.textContaining('Secret task:', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('a tap during the task reveal cuts straight to the flight',
      (tester) async {
    await startFreshGame(tester);
    await closeOpeningFan(tester);
    expect(find.byType(TaskRevealOverlay), findsOneWidget);

    // Tapped 500ms in, the banner flies at once: gone inside the 600ms
    // flight, long before the 2.2s hold would have run out.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(const Offset(5, 5));
    // The first frame after the tap only starts the restarted flight clock.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();
    expect(find.byType(TaskRevealOverlay), findsNothing);
  });

  testWidgets('crossing into match point warns once, and only once',
      (tester) async {
    // Two connected forests score 2; upgrading one to a village doubles the
    // region to 4, which is 3 short of this target.
    final controller = await pumpResumed(
      tester,
      fixture(
        resources: const {Resource.grain: 2, Resource.stone: 1, Resource.wood: 3},
        targetVp: 7,
      ),
    );
    expect(find.textContaining('from victory'), findsNothing);

    await tester.tap(find.byType(BoardWidget));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Upgrade'));
    // Mid-hold: the warning names the step, not the score.
    await tester.pump(const Duration(milliseconds: 200));
    expect(scoreFor(controller.state!, 0), 4);
    expect(find.text('You are 3 points from victory!'), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.textContaining('from victory'), findsNothing);

    // A trade leaves the score where it was, so the step is not re-announced.
    final trade = legalActions(controller.state!).whereType<BankTrade>().first;
    // Unawaited: the presentation queue only drains on pumped frames.
    unawaited(controller.dispatch(trade));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('from victory'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('a bot seizing your hex raises a banner, then clears',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = GameController(
      saveStore: InMemorySaveStore(),
      botStepDelay: Duration.zero,
    );
    await controller.startNewGame(seed: 9, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Bot', isBot: true),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await dismissWelcome(tester);

    // Straight down the presentation channel the controller uses, rather
    // than playing a whole game out to the one turn a bot can rob you.
    final hex = controller.state!.tiles.keys.first;
    final shown = controller.eventDelegate!([HexSeized(hex, 0, 1)]);
    await tester.pump();
    expect(find.text('Bot seized your hex!'), findsWidgets);

    await tester.pumpAndSettle();
    await shown;
    expect(find.text('Bot seized your hex!'), findsNothing);
  });

  testWidgets('seizing a bot hex yourself raises no banner', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = GameController(
      saveStore: InMemorySaveStore(),
      botStepDelay: Duration.zero,
    );
    await controller.startNewGame(seed: 9, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Bot', isBot: true),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await dismissWelcome(tester);

    final hex = controller.state!.tiles.keys.first;
    final shown = controller.eventDelegate!([HexSeized(hex, 1, 0)]);
    await tester.pump();
    expect(find.textContaining('seized your hex'), findsNothing);

    await tester.pumpAndSettle();
    await shown;
    expect(find.textContaining('seized your hex'), findsNothing);
  });

  testWidgets('the game-end moment holds, then the scoreboard takes over',
      (tester) async {
    // The upgrade takes the human to 4 points, which is this game's target.
    await pumpResumed(
      tester,
      fixture(
        resources: const {Resource.grain: 2, Resource.stone: 1},
        targetVp: 4,
      ),
    );

    await tester.tap(find.byType(BoardWidget));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Upgrade'));
    await tester.pump(const Duration(milliseconds: 300));

    // The moment owns the screen first; the scoreboard waits its turn.
    expect(find.byType(GameEndOverlay), findsOneWidget);
    expect(find.text('The realm is claimed!'), findsWidgets);
    expect(find.byType(GameOverScreen), findsNothing);
    // The human took the target, so the sky joins in.
    expect(find.byType(Fireworks), findsOneWidget);

    // Still holding well past the old 1.8s: the line has 3.2s to be read.
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.text('The realm is claimed!'), findsWidgets);
    expect(find.byType(GameOverScreen), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(GameEndOverlay), findsNothing);
    expect(find.byType(GameOverScreen), findsOneWidget);
  });

  testWidgets('a finished game leaves no autosave behind', (tester) async {
    // Same target-claiming upgrade as the beat above: the point here is what
    // it does to the save, so the menu cannot offer a dead Continue.
    final controller = await pumpResumed(
      tester,
      fixture(
        resources: const {Resource.grain: 2, Resource.stone: 1},
        targetVp: 4,
      ),
    );
    expect(await controller.hasResumableGame(), isTrue);

    await tester.tap(find.byType(BoardWidget));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Upgrade'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.state!.phase, Phase.gameOver);
    expect(await controller.hasResumableGame(), isFalse);
    // Let the end ceremony and the scoreboard hand-off drain.
    await tester.pumpAndSettle();
  });

  testWidgets('a rival win gets the banner without the fireworks',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Stack(
        children: [
          GameEndOverlay(text: 'The seasons have turned.', onDone: () {}),
        ],
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('The seasons have turned.'), findsWidgets);
    expect(find.byType(Fireworks), findsNothing);
    await tester.pumpAndSettle();
  });
}

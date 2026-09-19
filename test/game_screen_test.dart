import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/board/board_widget.dart';
import 'package:hexstead/screens/game_screen.dart';
import 'package:hexstead/widgets/card_fan_overlay.dart';
import 'package:hexstead/widgets/dice_roll_overlay.dart';
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

/// Resumed mid-game state (so no welcome card): human to act in the main
/// phase, owning two forests, with whatever purse and offer a test needs.
GameState fixture({
  Map<Resource, int> resources = const {},
  List<String> landmarkOffer = const [],
  String objectiveId = 'forester',
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
    targetVp: 99,
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

  testWidgets('the game-start card reveal restates the secret task',
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
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    final objective =
        objectiveCatalog[controller.state!.players.first.objectiveId]!;
    expect(
      find.text('🎯 Secret task: ${objective.description}'),
      findsWidgets,
    );

    // Only the opening reveal carries it: a later fan is plain.
    await tester.tapAt(const Offset(10, 100));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CardFanIcon));
    await tester.pumpAndSettle();
    expect(find.textContaining('Secret task:'), findsNothing);
  });
}

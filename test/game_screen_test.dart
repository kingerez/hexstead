import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/board/board_widget.dart';
import 'package:hexstead/screens/game_screen.dart';
import 'package:hexstead/widgets/card_fan_overlay.dart';
import 'package:hexstead/widgets/dice_roll_overlay.dart';
import 'package:hexstead/widgets/tile_info_sheet.dart';
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

  testWidgets('long-pressing a tile opens the tile info sheet',
      (tester) async {
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
    // Long-press the board's center (the middle hex always exists).
    final board = find.byType(BoardWidget);
    await tester.longPress(board);
    await tester.pumpAndSettle();

    expect(find.byType(TileInfoSheet), findsOneWidget);
    // Sheet names the terrain and explains ownership or claimability.
    expect(
      find.textContaining(RegExp('Forest|Field|Hill|Mountain|Desert')),
      findsWidgets,
    );
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
}

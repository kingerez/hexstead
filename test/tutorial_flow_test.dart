import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/board/board_geometry.dart';
import 'package:hexstead/board/board_widget.dart';
import 'package:hexstead/screens/game_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:hexstead/tutorial/tutorial_director.dart';
import 'package:hexstead/tutorial/tutorial_scenario.dart';
import 'package:hexstead/widgets/card_fan_overlay.dart';
import 'package:hexstead/widgets/trade_overlay.dart';
import 'package:hexstead/widgets/tutorial_banner.dart';
import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Copied from test/card_target_test.dart: where on screen a hex sits.
Offset hexCenter(WidgetTester tester, Hex hex) {
  final rect = tester.getRect(find.byType(BoardWidget));
  return rect.topLeft + BoardGeometry(rect.size).centerOf(hex);
}

/// The tutorial pushed over a stand-in menu route, exactly the way
/// MenuScreen launches it.
Future<(GameController, TutorialDirector)> pumpTutorial(
    WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final scenario = TutorialScenario();
  final controller = GameController(
    saveStore: NullSaveStore(),
    botStepDelay: Duration.zero,
    botBrainOverride: scenario.nextBotAction,
  );
  await controller.startFromState(scenario.initialState());
  final director = TutorialDirector();

  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: Center(child: Text('the menu'))),
  ));
  tester.state<NavigatorState>(find.byType(Navigator)).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              GameScreen(controller: controller, tutorial: director),
        ),
      );
  await tester.pumpAndSettle();
  return (controller, director);
}

/// The inspector's claim button, found by the price tag it wears.
Finder claimButton() => find.ancestor(
      of: find.textContaining('Claim for', findRichText: true),
      matching: find.byType(FilledButton),
    );

/// The FilledButton wrapping [label] (FilledButton.tonal builds one too).
FilledButton buttonFor(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(
      find
          .ancestor(of: find.text(label), matching: find.byType(FilledButton))
          .first,
    );

void main() {
  testWidgets('the guided game walks all 25 steps and hands back the menu',
      (tester) async {
    final (controller, director) = await pumpTutorial(tester);
    GameState state() => controller.state!;

    // --- 1. welcome ---------------------------------------------------
    expect(director.current.id, 'welcome');
    expect(find.byType(TutorialBanner), findsOneWidget);
    expect(find.textContaining('Nineteen hexes'), findsOneWidget);
    // No welcome card, no opening fan: the banner is the whole briefing.
    expect(find.text('Welcome to Hexstead'), findsNothing);
    // Nothing is allowed yet, so the roll button is dead.
    expect(buttonFor(tester, 'Roll the dice').onPressed, isNull);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // --- 2. inspect ---------------------------------------------------
    expect(director.current.id, 'inspect');
    expect(find.text('Select a tile to view it'), findsOneWidget);
    // A hex that is not the lesson's does nothing at all.
    await tester.tapAt(hexCenter(tester, const Hex(1, 0)));
    await tester.pumpAndSettle();
    expect(director.current.id, 'inspect');
    expect(find.text('Select a tile to view it'), findsOneWidget);

    await tester.tapAt(hexCenter(tester, TutorialScenario.inspectTarget));
    await tester.pumpAndSettle();

    // --- 3. inspectRead: the tile stays selected while the banner reads
    // the panel out loud.
    expect(director.current.id, 'inspectRead');
    expect(find.textContaining('The panel below tells all'), findsOneWidget);
    expect(find.text('Mountain'), findsOneWidget);
    expect(find.textContaining('Rolls 11'), findsOneWidget);
    expect(find.text('Unclaimed'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // --- 4. roll1 -----------------------------------------------------
    expect(director.current.id, 'roll1');
    // Moving on drops the selection again.
    expect(find.text('Select a tile to view it'), findsOneWidget);
    await tester.tap(find.text('Roll the dice'));
    await tester.pumpAndSettle();
    expect(state().lastDice, (3, 5));

    // --- 5. sum -------------------------------------------------------
    expect(director.current.id, 'sum');
    // Split stays on screen but goes dead: the lesson is about the sum.
    expect(buttonFor(tester, 'Split 3 & 5').onPressed, isNull);
    expect(buttonFor(tester, 'Sum 8').onPressed, isNotNull);
    await tester.tap(find.text('Sum 8'));
    await tester.pumpAndSettle();
    expect(state().players[0].countOf(Resource.wood), 3);

    // --- 6. claim -----------------------------------------------------
    expect(director.current.id, 'claim');
    // Another frontier hex is legal for the engine and refused by the guide.
    expect(
      legalActions(state()).contains(const ClaimHex(Hex(1, 0))),
      isTrue,
    );
    await tester.tapAt(hexCenter(tester, const Hex(1, 0)));
    await tester.pumpAndSettle();
    expect(state().tiles[const Hex(1, 0)]!.ownerId, isNull);
    expect(director.current.id, 'claim');
    // Not even the panel filled: the guide's tile is the only live one.
    expect(find.text('Select a tile to view it'), findsOneWidget);

    // The lesson's hex fills the inspector, and the claim is paid there.
    await tester.tapAt(hexCenter(tester, TutorialScenario.claimTarget));
    await tester.pumpAndSettle();
    expect(state().tiles[TutorialScenario.claimTarget]!.ownerId, isNull);
    expect(director.current.id, 'claim');
    await tester.tap(claimButton());
    await tester.pumpAndSettle();
    expect(state().tiles[TutorialScenario.claimTarget]!.ownerId, 0);

    // --- 7. endTurn1 --------------------------------------------------
    expect(director.current.id, 'endTurn1');
    await tester.tap(find.text('End Turn'));
    await tester.pumpAndSettle();

    // --- 8. botTurn1 runs itself, landing on 9. roll2 -----------------
    expect(director.current.id, 'roll2');
    expect(state().round, 2);
    expect(state().tiles[TutorialScenario.rivalClaim]!.ownerId, 1);
    await tester.tap(find.text('Roll the dice'));
    await tester.pumpAndSettle();

    // --- 10. split -----------------------------------------------------
    expect(director.current.id, 'split');
    expect(buttonFor(tester, 'Sum 6').onPressed, isNull);
    await tester.tap(find.text('Split 2 & 4'));
    await tester.pumpAndSettle();
    expect(state().players[0].countOf(Resource.brick), 2);

    // --- 11. cardsOpen / 12. cardsPlay --------------------------------
    expect(director.current.id, 'cardsOpen');
    expect(buttonFor(tester, 'End Turn').onPressed, isNull);
    await tester.tap(find.byType(CardFanIcon));
    await tester.pumpAndSettle();
    expect(director.current.id, 'cardsPlay');
    // Only the Bounty is playable - the other two cards carry no button.
    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    // One legal target survives the filter, so the picker offers grain only.
    expect(find.text('Take 2 of…'), findsOneWidget);
    expect(find.text('Grain'), findsOneWidget);
    expect(find.text('Wood'), findsNothing);
    await tester.tap(find.text('Grain'));
    await tester.pumpAndSettle();
    expect(state().players[0].countOf(Resource.grain), 2);

    // --- 13. endTurn2, 14. botTurn2, 15. roll3 ------------------------
    expect(director.current.id, 'endTurn2');
    await tester.tap(find.text('End Turn'));
    await tester.pumpAndSettle();
    expect(director.current.id, 'roll3');
    // Bertram's 4 paid your hill, not him.
    expect(state().players[0].countOf(Resource.brick), 3);
    expect(state().round, 3);
    await tester.tap(find.text('Roll the dice'));
    await tester.pumpAndSettle();

    // --- 16. seven / 17. placeBandit ----------------------------------
    expect(director.current.id, 'seven');
    await tester.tap(find.text('Bandit!'));
    await tester.pumpAndSettle();
    expect(director.current.id, 'placeBandit');
    expect(state().phase, Phase.awaitingBandit);
    // Your own camp is a legal bandit target, and the guide refuses it.
    await tester.tapAt(hexCenter(tester, TutorialScenario.homeCamp));
    await tester.pumpAndSettle();
    expect(state().phase, Phase.awaitingBandit);
    await tester.tapAt(hexCenter(tester, TutorialScenario.rivalCamp));
    await tester.pumpAndSettle();
    expect(state().tiles[TutorialScenario.rivalCamp]!.hasBandit, isTrue);

    // --- 18. shopOpen / 19. buyLandmark -------------------------------
    expect(director.current.id, 'shopOpen');
    await tester.tap(find.text('🏛'));
    await tester.pumpAndSettle();
    expect(director.current.id, 'buyLandmark');
    expect(find.text('Landmarks for sale'), findsOneWidget);
    // Only the Market Hall is on offer; the other three stay grey.
    expect(find.text('Buy'), findsOneWidget);
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    expect(state().players[0].landmarkIds, ['market_hall']);

    // --- 20. objective ------------------------------------------------
    expect(director.current.id, 'objective');
    expect(find.textContaining('King\'s Road'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // --- 21. tradeOpen / 22. trade ------------------------------------
    expect(director.current.id, 'tradeOpen');
    await tester.tap(find.byIcon(Icons.handshake));
    await tester.pumpAndSettle();
    expect(director.current.id, 'trade');
    await tester.tap(find.byType(ChoiceChip));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(TradeOverlay),
      matching: find.byType(FilledButton),
    ));
    await tester.pumpAndSettle();
    expect(state().players[0].countOf(Resource.stone), 1);
    expect(state().players[0].countOf(Resource.brick), 0);
    expect(find.byType(TradeOverlay), findsNothing);

    // --- 23. endTurn3, 24. botBandit ----------------------------------
    expect(director.current.id, 'endTurn3');
    await tester.tap(find.text('End Turn'));
    await tester.pumpAndSettle();

    // --- 25. closing --------------------------------------------------
    // Reaching here at all proves the bot loop parked on the null brain
    // instead of spinning: pumpAndSettle would never have returned.
    expect(director.current.id, 'closing');
    expect(state().tiles[TutorialScenario.rivalCamp]!.hasBandit, isFalse);
    expect(state().currentPlayerIndex, 1);
    expect(state().phase, Phase.main);
    expect(find.textContaining('Reach 15 points'), findsOneWidget);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    // Back on the menu route, with the first-run offer marked as made.
    expect(find.text('the menu'), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(tutorialPromptSeenKey), isTrue);

    // Nothing the tutorial did is resumable: its store forgets.
    expect(await controller.hasResumableGame(), isFalse);
  });

  testWidgets('quitting mid-tutorial asks in tutorial words', (tester) async {
    await pumpTutorial(tester);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Leave the tutorial?'), findsOneWidget);
    expect(find.textContaining('start it again from the menu'), findsOneWidget);

    await tester.tap(find.text('Keep playing'));
    await tester.pumpAndSettle();
    expect(find.text('Leave the tutorial?'), findsNothing);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('the menu'), findsOneWidget);
  });
}

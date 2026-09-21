import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/board/board_geometry.dart';
import 'package:hexstead/board/board_widget.dart';
import 'package:hexstead/screens/game_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:hexstead/widgets/task_complete_overlay.dart';
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

/// A mid-game board where the human's King's Road runs (0,0)-(1,0) and the
/// third hex, (2,0), is there for the taking. [roadDone] hands them that
/// third hex up front, so the task is already fulfilled on arrival.
GameState fixture({bool roadDone = false}) {
  final tilesSpec = [
    (const Hex(0, 0), TerrainType.forest, 8, 0),
    (const Hex(1, 0), TerrainType.forest, 9, 0),
    (const Hex(2, 0), TerrainType.field, 5, roadDone ? 0 : null),
    (const Hex(0, 1), TerrainType.hill, 4, 1),
  ];
  return GameState(
    seed: 1,
    rng: GameRng(1),
    round: 3,
    roundCap: 15,
    // Out of reach, so no endgame or match-point chrome steals the screen.
    targetVp: 99,
    currentPlayerIndex: 0,
    phase: Phase.main,
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
    players: const [
      PlayerState(
        id: 0,
        name: 'You',
        isBot: false,
        resources: {Resource.wood: 1, Resource.brick: 1},
        objectiveId: 'straight_line',
      ),
      PlayerState(id: 1, name: 'Bot', isBot: true),
    ],
    landmarkOffer: [],
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
  testWidgets('the claim that finishes the secret task is called out once',
      (tester) async {
    final controller = await pumpResumed(tester, fixture());
    expect(find.byType(TaskCompleteOverlay), findsNothing);

    await tester.tapAt(hexCenter(tester, const Hex(2, 0)));
    await tester.pumpAndSettle();
    await tester.tap(claimButton());
    await tester.pumpAndSettle();

    // The task is done, and says so - naming itself and where the bonus
    // lands, since it never shows up in the live scores.
    expect(
      objectiveCatalog['straight_line']!.isComplete(controller.state!, 0),
      isTrue,
    );
    expect(find.byType(TaskCompleteOverlay), findsOneWidget);
    expect(find.textContaining('Secret task fulfilled!',
        findRichText: true), findsOneWidget);
    expect(find.text('The King\'s Road'), findsOneWidget);
    expect(find.text('Own 3 tiles in a straight line.'), findsOneWidget);
    expect(
      find.text('+3 bonus points at the final tally'),
      findsOneWidget,
    );
    // The bonus stays off the live score: two hexes claimed, three tiles,
    // three points, and not a hint of the 3 waiting at the end.
    expect(scoreFor(controller.state!, 0), 3);

    // A tap dismisses it and lets the game carry on.
    await tester.tap(find.byType(TaskCompleteOverlay));
    await tester.pumpAndSettle();
    expect(find.byType(TaskCompleteOverlay), findsNothing);

    // Later events do not bring it back: it is news exactly once.
    await tester.tap(find.text('End Turn'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskCompleteOverlay), findsNothing);
  });

  testWidgets('a task already fulfilled when the screen opens stays quiet',
      (tester) async {
    await pumpResumed(tester, fixture(roadDone: true));

    expect(find.byType(TaskCompleteOverlay), findsNothing);
    await tester.tap(find.text('End Turn'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskCompleteOverlay), findsNothing);
  });
}

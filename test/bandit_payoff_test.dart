import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/screens/game_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:hexstead/widgets/option_picker_dialog.dart';
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

/// Resumed mid-game (so no welcome card): your turn, main phase, the bandit
/// squatting on your forest, and [resources] in the purse.
GameState fixture(Map<Resource, int> resources) {
  const tilesSpec = [
    (Hex(0, 0), TerrainType.forest, 8, 0, 1),
    (Hex(1, 0), TerrainType.field, 9, 1, 1),
    (Hex(0, 1), TerrainType.hill, 4, 0, 1),
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
          hasBandit: coord == const Hex(0, 0),
        ),
    },
    players: [
      PlayerState(
        id: 0,
        name: 'You',
        isBot: false,
        resources: resources,
        objectiveId: 'forester',
      ),
      const PlayerState(id: 1, name: 'Bot', isBot: true),
    ],
    landmarkOffer: const [],
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
  testWidgets('paying the bandit off asks first, and names a matched pair',
      (tester) async {
    final controller =
        await pumpResumed(tester, fixture({Resource.wood: 2}));

    await tester.tap(find.text('Pay off bandit'));
    await tester.pumpAndSettle();

    expect(find.text('Pay off the bandit?'), findsOneWidget);
    expect(find.text('Chase him off your land for:'), findsOneWidget);
    // The cheapest legal pair here is two wood, shown as one counted entry.
    expect(find.text('2 Wood'), findsOneWidget);
    expect(find.byType(ResourceCostRow), findsOneWidget);
    // Nothing is spent while the question is still on the table.
    expect(controller.state!.players.first.countOf(Resource.wood), 2);
    expect(controller.state!.tiles[const Hex(0, 0)]!.hasBandit, isTrue);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Pay off the bandit?'), findsNothing);
    expect(controller.state!.players.first.countOf(Resource.wood), 2);
    expect(controller.state!.tiles[const Hex(0, 0)]!.hasBandit, isTrue);

    // Pay, and the man leaves with exactly what the card promised.
    await tester.tap(find.text('Pay off bandit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();

    expect(controller.state!.tiles[const Hex(0, 0)]!.hasBandit, isFalse);
    expect(controller.state!.players.first.countOf(Resource.wood), 0);
    expect(find.text('Pay off bandit'), findsNothing);
  });

  testWidgets('a mixed pair names both resources', (tester) async {
    final controller = await pumpResumed(
        tester, fixture({Resource.wood: 1, Resource.brick: 1}));

    await tester.tap(find.text('Pay off bandit'));
    await tester.pumpAndSettle();

    expect(find.text('Wood'), findsOneWidget);
    expect(find.text('Brick'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);

    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();

    final purse = controller.state!.players.first;
    expect(controller.state!.tiles[const Hex(0, 0)]!.hasBandit, isFalse);
    expect(purse.countOf(Resource.wood), 0);
    expect(purse.countOf(Resource.brick), 0);
  });

  testWidgets('tapping outside the confirmation spends nothing',
      (tester) async {
    final controller =
        await pumpResumed(tester, fixture({Resource.wood: 2}));

    await tester.tap(find.text('Pay off bandit'));
    await tester.pumpAndSettle();
    expect(find.text('Pay off the bandit?'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Pay off the bandit?'), findsNothing);
    expect(controller.state!.players.first.countOf(Resource.wood), 2);
    expect(controller.state!.tiles[const Hex(0, 0)]!.hasBandit, isTrue);
  });
}

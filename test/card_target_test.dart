import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/board/board_geometry.dart';
import 'package:hexstead/board/board_widget.dart';
import 'package:hexstead/screens/game_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:hexstead/widgets/card_fan_overlay.dart';
import 'package:hexstead/widgets/production_overlay.dart';
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

/// Mid-game state (resumed, so no welcome card): human to act in the main
/// phase after a roll, with [hand] and optionally the bandit on their tile.
GameState fixture({required List<String> hand, bool banditOnOwnTile = false}) {
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
          hasBandit: banditOnOwnTile && coord == const Hex(0, 0),
        ),
    },
    players: [
      PlayerState(
        id: 0,
        name: 'You',
        isBot: false,
        resources: {Resource.wood: 1},
        hand: hand,
      ),
      PlayerState(
          id: 1,
          name: 'Bot',
          isBot: true,
          resources: {Resource.grain: 2},
          hand: const []),
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

Future<void> playFromFan(WidgetTester tester, String cardName) async {
  await tester.tap(find.byType(CardFanIcon));
  await tester.pumpAndSettle();
  expect(find.text(cardName), findsOneWidget);
  await tester.tap(find.text('Play'));
  await tester.pumpAndSettle();
}

Offset hexCenter(WidgetTester tester, Hex hex) {
  final rect = tester.getRect(find.byType(BoardWidget));
  return rect.topLeft + BoardGeometry(rect.size).centerOf(hex);
}

void main() {
  testWidgets('brigand: tapping a glowing tile dispatches the card',
      (tester) async {
    final controller =
        await pumpResumed(tester, fixture(hand: ['brigand']));

    await playFromFan(tester, 'Brigand');
    expect(find.textContaining('tap a glowing tile'), findsOneWidget);

    await tester.tapAt(hexCenter(tester, const Hex(1, 0)));
    await tester.pumpAndSettle();

    expect(controller.state!.tiles[const Hex(1, 0)]!.hasBandit, isTrue);
    expect(controller.state!.players.first.hand, isEmpty);
    expect(find.textContaining('tap a glowing tile'), findsNothing);
  });

  testWidgets('harvest: grants animate with the production overlay',
      (tester) async {
    final controller = await pumpResumed(tester, fixture(hand: ['harvest']));

    await tester.tap(find.byType(CardFanIcon));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));

    // The fan flies away, then the payout overlay floats the grant chip
    // over the forest#8 hex.
    var found = false;
    for (var i = 0; i < 40 && !found; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      found = tester.any(find.text('+1 🪵'));
    }
    expect(found, isTrue,
        reason: 'harvest should float a +1 wood chip over forest#8');

    await tester.pumpAndSettle();
    expect(find.byType(ProductionOverlay), findsNothing);
    expect(controller.state!.players.first.resources[Resource.wood], 2);
  });

  testWidgets('banish: plays immediately, no tile tap needed',
      (tester) async {
    final controller = await pumpResumed(
        tester, fixture(hand: ['banish'], banditOnOwnTile: true));

    await playFromFan(tester, 'Banish');

    expect(controller.state!.tiles[const Hex(0, 0)]!.hasBandit, isFalse);
    expect(controller.state!.players.first.hand, isEmpty);
    expect(find.textContaining('tap a glowing tile'), findsNothing);
  });
}

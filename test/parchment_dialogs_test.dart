import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/board/board_geometry.dart';
import 'package:hexstead/board/board_widget.dart';
import 'package:hexstead/screens/game_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:hexstead/widgets/adjust_die_dialog.dart';
import 'package:hexstead/widgets/card_fan_overlay.dart';
import 'package:hexstead/widgets/dice_roll_overlay.dart';
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

/// Copied from test/card_target_test.dart: where on screen a hex sits.
Offset hexCenter(WidgetTester tester, Hex hex) {
  final rect = tester.getRect(find.byType(BoardWidget));
  return rect.topLeft + BoardGeometry(rect.size).centerOf(hex);
}

/// A four-hex board with every tile owned - the state that opens seizing -
/// and two rival hexes bordering yours.
GameState fullBoard(Map<Resource, int> resources) {
  const tilesSpec = [
    (Hex(0, 0), TerrainType.forest, 8, 0),
    (Hex(1, 0), TerrainType.field, 9, 1),
    (Hex(0, 1), TerrainType.hill, 4, 0),
    (Hex(1, -1), TerrainType.mountain, 6, 1),
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
      for (final (coord, terrain, number, owner) in tilesSpec)
        coord: Tile(
          coord: coord,
          terrain: terrain,
          number: number,
          ownerId: owner,
          level: 1,
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

/// Mid-roll state with the Omen in hand: the dice are up and unresolved,
/// which is the only moment the card may be played.
GameState omenPending() {
  const tilesSpec = [
    (Hex(0, 0), TerrainType.forest, 8, 0),
    (Hex(1, 0), TerrainType.field, 9, 1),
  ];
  return GameState(
    seed: 1,
    rng: GameRng(1),
    round: 3,
    roundCap: 15,
    targetVp: 99,
    currentPlayerIndex: 0,
    phase: Phase.awaitingChoice,
    tiles: {
      for (final (coord, terrain, number, owner) in tilesSpec)
        coord: Tile(
          coord: coord,
          terrain: terrain,
          number: number,
          ownerId: owner,
          level: 1,
        ),
    },
    players: [
      const PlayerState(
        id: 0,
        name: 'You',
        isBot: false,
        hand: ['omen'],
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

/// The die faces the Omen dialog is showing right now.
List<int> dialogFaces(WidgetTester tester) => tester
    .widgetList<MiniDie>(find.descendant(
      of: find.byType(AdjustDieDialog),
      matching: find.byType(MiniDie),
    ))
    .map((d) => d.face)
    .toList();

void main() {
  group('seize confirmation', () {
    testWidgets('names the victim and the whole price', (tester) async {
      final controller = await pumpResumed(
          tester, fullBoard({Resource.wood: 3, Resource.brick: 2}));

      await tester.tapAt(hexCenter(tester, const Hex(1, 0)));
      await tester.pumpAndSettle();

      expect(find.text('Seize from Bot?'), findsOneWidget);
      expect(find.text('Take their Level-1 hex for:'), findsOneWidget);
      // The greedy spend takes the deepest piles first, shown as counts.
      expect(find.byType(ResourceCostRow), findsOneWidget);
      expect(find.text('3 Wood'), findsOneWidget);
      expect(find.text('2 Brick'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);

      // Cancel changes nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Seize from Bot?'), findsNothing);
      expect(controller.state!.tiles[const Hex(1, 0)]!.ownerId, 1);
      expect(controller.state!.players.first.countOf(Resource.wood), 3);
    });

    testWidgets('confirming takes the hex and the price', (tester) async {
      final controller = await pumpResumed(
          tester, fullBoard({Resource.wood: 3, Resource.brick: 2}));

      await tester.tapAt(hexCenter(tester, const Hex(1, 0)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seize'));
      await tester.pumpAndSettle();

      final purse = controller.state!.players.first;
      expect(controller.state!.tiles[const Hex(1, 0)]!.ownerId, 0);
      expect(purse.countOf(Resource.wood), 0);
      expect(purse.countOf(Resource.brick), 0);
    });

    testWidgets('tapping outside seizes nothing', (tester) async {
      final controller = await pumpResumed(
          tester, fullBoard({Resource.wood: 3, Resource.brick: 2}));

      await tester.tapAt(hexCenter(tester, const Hex(1, 0)));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Seize from Bot?'), findsNothing);
      expect(controller.state!.tiles[const Hex(1, 0)]!.ownerId, 1);
      expect(controller.state!.players.first.countOf(Resource.wood), 3);
    });
  });

  group('omen die-shifter', () {
    /// Opens the Omen from the hand fan.
    Future<void> openOmen(WidgetTester tester) async {
      await tester.tap(find.byType(CardFanIcon));
      await tester.pumpAndSettle();
      expect(find.text('Omen'), findsOneWidget);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
    }

    testWidgets('previews the nudge, then commits it', (tester) async {
      final controller = await pumpResumed(tester, omenPending());
      await openOmen(tester);

      expect(find.text('Adjust a die'), findsOneWidget);
      expect(dialogFaces(tester), [3, 5]);
      // Nothing to commit until a die is actually nudged.
      expect(
        tester
            .widget<FilledButton>(find
                .ancestor(
                    of: find.text('Done'), matching: find.byType(FilledButton))
                .first)
            .onPressed,
        isNull,
      );

      // Up on the first die: previewed in place, not yet dispatched.
      await tester.tap(find.byIcon(Icons.arrow_drop_up).first);
      await tester.pumpAndSettle();
      expect(dialogFaces(tester), [4, 5]);
      expect(controller.state!.lastDice, (3, 5));

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(controller.state!.lastDice, (4, 5));
      expect(controller.state!.players.first.hand, isEmpty);
    });

    testWidgets('one nudge only - a second arrow moves it', (tester) async {
      final controller = await pumpResumed(tester, omenPending());
      await openOmen(tester);

      await tester.tap(find.byIcon(Icons.arrow_drop_up).first);
      await tester.pumpAndSettle();
      expect(dialogFaces(tester), [4, 5]);

      // Down on the second die: the first goes back to where it was.
      await tester.tap(find.byIcon(Icons.arrow_drop_down).last);
      await tester.pumpAndSettle();
      expect(dialogFaces(tester), [3, 4]);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(controller.state!.lastDice, (3, 4));
    });

    testWidgets('Cancel plays no card, even after a nudge', (tester) async {
      final controller = await pumpResumed(tester, omenPending());
      await openOmen(tester);

      await tester.tap(find.byIcon(Icons.arrow_drop_up).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Adjust a die'), findsNothing);
      expect(controller.state!.lastDice, (3, 5));
      expect(controller.state!.players.first.hand, ['omen']);
    });

    testWidgets('tapping outside plays no card', (tester) async {
      final controller = await pumpResumed(tester, omenPending());
      await openOmen(tester);

      await tester.tap(find.byIcon(Icons.arrow_drop_up).first);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Adjust a die'), findsNothing);
      expect(controller.state!.lastDice, (3, 5));
      expect(controller.state!.players.first.hand, ['omen']);
    });
  });
}

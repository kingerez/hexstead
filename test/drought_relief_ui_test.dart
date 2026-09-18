import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/board/board_geometry.dart';
import 'package:hexstead/screens/game_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
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

void main() {
  testWidgets('production overlay floats a relief chip next to the whiff',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ProductionOverlay(
                geometry: BoardGeometry(const Size(400, 400)),
                grants: const [],
                emptyMessage: 'No one owns a hex numbered 5 yet',
                reliefs: const [DroughtRelief(1, Resource.wood)],
                playerNames: const ['You', 'Bot'],
                onDone: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No one owns a hex numbered 5 yet'), findsOneWidget);
    expect(find.text('🍀 Bot +1 🪵'), findsOneWidget);
  });

  testWidgets('relief chips can appear alone, without an empty-roll notice',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ProductionOverlay(
                geometry: BoardGeometry(const Size(400, 400)),
                grants: const [],
                emptyMessage: '',
                reliefs: const [DroughtRelief(0, Resource.grain)],
                playerNames: const ['You', 'Bot'],
                onDone: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('🍀 You +1 🌾'), findsOneWidget);
  });

  testWidgets('HUD shows the dry-streak meter only once a drought starts',
      (tester) async {
    SharedPreferences.setMockInitialValues({'seen_welcome': true});
    final store = InMemorySaveStore();
    final fresh = GameController(
        saveStore: store, botStepDelay: Duration.zero);
    await fresh.startNewGame(seed: 12, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Bot', isBot: true),
    ]);

    // Streak 0: no meter.
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: fresh)),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('🍀 2/3'), findsNothing);

    // Two dry rolls into a drought: the meter appears.
    final parched =
        fresh.state!.withPlayer(0, (p) => p.copyWith(droughtStreak: 2));
    store.saved = jsonEncode(gameStateToJson(parched));
    final resumed = GameController(
        saveStore: store, botStepDelay: Duration.zero);
    await resumed.resume();
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: resumed)),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('🍀 2/3'), findsOneWidget);
  });
}

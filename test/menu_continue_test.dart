import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/screens/menu_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

class InMemorySaveStore implements SaveStore {
  String? saved;

  @override
  Future<void> save(String json) async => saved = json;

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> clear() async => saved = null;
}

String midGameSave() => jsonEncode(gameStateToJson(GameState.newGame(
      seed: 7,
      players: const [
        PlayerSetup(name: 'You', isBot: false),
        PlayerSetup(name: 'Bot', isBot: true),
      ],
    )));

void main() {
  testWidgets('Continue shows for a live autosave and hides once it is gone',
      (tester) async {
    final store = InMemorySaveStore()..saved = midGameSave();
    final controller =
        GameController(saveStore: store, botStepDelay: Duration.zero);

    await tester.pumpWidget(
      MaterialApp(home: MenuScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);

    // Game over clears the autosave while the menu route is still alive.
    await store.clear();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsNothing);
  });
}

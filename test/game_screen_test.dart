import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/screens/game_screen.dart';
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

void main() {
  testWidgets('roll button rolls, choice buttons appear, sum resolves',
      (tester) async {
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

    expect(find.text('Roll'), findsOneWidget);
    await tester.tap(find.text('Roll'));
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

    await tester.tap(find.text('Roll'));
    await tester.pumpAndSettle();
    // resolve choice (avoid bandit branch by picking split)
    await tester.tap(find.textContaining('Split'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End Turn'));
    await tester.pumpAndSettle();

    expect(controller.state!.round, 2);
    expect(controller.isHumanTurn, isTrue);
  });
}

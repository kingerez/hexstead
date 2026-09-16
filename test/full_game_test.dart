import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/screens/game_over_screen.dart';
import 'package:hexstead/screens/game_screen.dart';
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

void main() {
  testWidgets('a full game reaches the game-over screen without crashing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = GameController(
      saveStore: InMemorySaveStore(),
      botStepDelay: Duration.zero,
    );
    await controller.startNewGame(seed: 77, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'Rosalind', isBot: true),
      PlayerSetup(name: 'Bertram', isBot: true),
    ]);

    // iPhone-ish logical size so narrow-screen overflows fail the test.
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    // Skip presentation animations: this test awaits dispatch() directly,
    // and the dice animation would wait forever for un-pumped frames.
    controller.eventDelegate = null;

    var guard = 0;
    while (controller.state!.phase != Phase.gameOver) {
      // Drive the human seat with the bot brain; bots run automatically.
      await controller.dispatch(SmartBot.chooseAction(controller.state!));
      await tester.pump();
      expect(++guard, lessThan(2000));
    }
    await tester.pumpAndSettle();

    expect(find.byType(GameOverScreen), findsOneWidget);
    expect(find.textContaining('pts'), findsWidgets);
    expect(find.textContaining('difficulty'), findsOneWidget);
  });
}

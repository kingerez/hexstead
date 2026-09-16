import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/board/board_widget.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

void main() {
  testWidgets('placeholder board golden', (tester) async {
    final state = GameState.newGame(seed: 12, players: const [
      PlayerSetup(name: 'You', isBot: false),
      PlayerSetup(name: 'A', isBot: true),
      PlayerSetup(name: 'B', isBot: true),
    ]);
    await tester.binding.setSurfaceSize(const Size(400, 500));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF2E4034),
          body: BoardWidget(state: state),
        ),
      ),
    );
    await expectLater(
      find.byType(BoardWidget),
      matchesGoldenFile('goldens/board_placeholder.png'),
    );
  });
}

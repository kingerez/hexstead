import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/widgets/bot_card_overlay.dart';

void main() {
  testWidgets('reveals the bot card with a banner, then completes',
      (tester) async {
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              BotCardOverlay(
                cardId: 'brigand',
                playerName: 'Rook',
                playerColor: Colors.deepOrange,
                onDone: () => done = true,
              ),
            ],
          ),
        ),
      ),
    );

    // Mid-hold: banner and the real card face are readable.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Rook plays Brigand'), findsOneWidget);
    expect(find.text('Brigand'), findsOneWidget); // card face title
    expect(done, isFalse);

    // Runs to completion and reports done exactly once.
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });
}

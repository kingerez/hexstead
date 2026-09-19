import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/widgets/card_fan_overlay.dart';

void main() {
  testWidgets('card face renders as plain parchment when art is missing',
      (tester) async {
    // ArtStore.load() never runs in tests, so no card art is bundled - the
    // face must fall back to the empty placeholder and still read fine.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: ActionCardFace(cardId: 'tithe')),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Tithe'), findsOneWidget);
    expect(find.text('Every rival hands you one random resource.'),
        findsOneWidget);
  });
}

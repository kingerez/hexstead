import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/board/board_geometry.dart';
import 'package:hexstead/widgets/production_overlay.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

Widget host(ProductionOverlay overlay) => MaterialApp(
      home: Scaffold(body: Stack(children: [overlay])),
    );

void main() {
  testWidgets('bonus chips float next to the whiff notice', (tester) async {
    await tester.pumpWidget(
      host(
        ProductionOverlay(
          geometry: BoardGeometry(const Size(400, 400)),
          grants: const [],
          emptyMessage: 'No one owns a hex numbered 5 yet',
          bonuses: const [(playerId: 1, resource: Resource.wood)],
          playerNames: const ['You', 'Bot'],
          onDone: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No one owns a hex numbered 5 yet'), findsOneWidget);
    expect(find.text('🎁 Bot +1 🪵'), findsOneWidget);
  });

  testWidgets('a giveaway names every player who was paid', (tester) async {
    await tester.pumpWidget(
      host(
        ProductionOverlay(
          geometry: BoardGeometry(const Size(400, 400)),
          grants: const [],
          emptyMessage: 'Round 4 - free resource giveaway!',
          bonuses: const [
            (playerId: 0, resource: Resource.grain),
            (playerId: 1, resource: Resource.stone),
          ],
          playerNames: const ['You', 'Bot'],
          onDone: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Round 4 - free resource giveaway!'), findsOneWidget);
    expect(find.text('🎁 You +1 🌾'), findsOneWidget);
    expect(find.text('🎁 Bot +1 🪨'), findsOneWidget);
  });
}

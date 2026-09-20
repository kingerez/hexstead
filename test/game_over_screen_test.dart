import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/board/board_painter.dart';
import 'package:hexstead/screens/game_over_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:hexstead/widgets/hex_confetti.dart';
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

/// A controller parked on a finished game: the real one only reaches
/// [Phase.gameOver] by playing one out, and the scoreboard just reads state.
class FinishedController extends GameController {
  final GameState finished;

  FinishedController(this.finished) : super(saveStore: InMemorySaveStore());

  @override
  GameState? get state => finished;
}

/// Game over with the human on two connected forests and the bot on a
/// village hill, so the two rows score differently.
GameState finishedGame({required int winnerId}) => GameState(
      seed: 1,
      rng: GameRng(1),
      round: 15,
      roundCap: 15,
      targetVp: 15,
      currentPlayerIndex: 0,
      phase: Phase.gameOver,
      tiles: {
        const Hex(0, 0): Tile(
          coord: const Hex(0, 0),
          terrain: TerrainType.forest,
          number: 8,
          ownerId: 0,
          level: 1,
        ),
        const Hex(1, 0): Tile(
          coord: const Hex(1, 0),
          terrain: TerrainType.hill,
          number: 4,
          ownerId: 1,
          level: 2,
        ),
      },
      players: const [
        PlayerState(id: 0, name: 'You', isBot: false, objectiveId: 'forester'),
        PlayerState(id: 1, name: 'Rosalind', isBot: true),
      ],
      landmarkOffer: const [],
      winnerId: winnerId,
    );

Future<void> pumpScoreboard(WidgetTester tester, int winnerId) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(MaterialApp(
    home: GameOverScreen(controller: FinishedController(
      finishedGame(winnerId: winnerId),
    )),
  ));
  await tester.pumpAndSettle();
}

/// The decoration of the innermost Container wrapping [name]'s row, or null
/// when the row is plain.
BoxDecoration? rowDecoration(WidgetTester tester, String name) {
  final container = tester.widget<Container>(
    find.ancestor(of: find.text(name), matching: find.byType(Container)).first,
  );
  return container.decoration as BoxDecoration?;
}

void main() {
  testWidgets('winning the game reads as a victory, with confetti',
      (tester) async {
    await pumpScoreboard(tester, 0);

    expect(find.text('Victory!'), findsOneWidget);
    expect(find.text('The realm slips away'), findsNothing);
    expect(find.byType(HexConfetti), findsOneWidget);
    // Nobody's row is singled out: the headline already says it.
    expect(rowDecoration(tester, 'You'), isNull);
    expect(rowDecoration(tester, 'Rosalind'), isNull);
    // The scoreboard itself is untouched.
    expect(find.textContaining('pts'), findsNWidgets(2));
    expect(find.textContaining('difficulty'), findsOneWidget);
  });

  testWidgets('losing reads muted, and points at the winner', (tester) async {
    await pumpScoreboard(tester, 1);

    expect(find.text('The realm slips away'), findsOneWidget);
    expect(find.text('Victory!'), findsNothing);
    expect(find.byType(HexConfetti), findsNothing);

    // The winner's row is backed in their own board color; yours is plain.
    final decoration = rowDecoration(tester, 'Rosalind');
    expect(decoration, isNotNull);
    expect(decoration!.color,
        BoardPainter.playerColors[1].withValues(alpha: 0.22));
    expect(rowDecoration(tester, 'You'), isNull);
  });
}

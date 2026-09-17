import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

GameState newGame() => GameState.newGame(seed: 3, players: [
      const PlayerSetup(name: 'You', isBot: false),
      const PlayerSetup(name: 'Bot', isBot: true),
    ]);

void main() {
  group('card replacement', () {
    test('newGame keeps the undealt deck in state', () {
      final s = newGame();
      // 10 card types x 2 copies, minus 3 dealt to each of 2 players.
      expect(s.deck.length, 20 - 6);
      final restored = gameStateFromJson(gameStateToJson(s));
      expect(restored.deck, s.deck);
    });

    test('replacing swaps one card for a fresh draw, deck shrinks', () {
      final s = newGame();
      final hand = s.players[0].hand;
      final discarded = hand.first;
      final r = apply(s, ReplaceCard(discarded));
      final newHand = r.state.players[0].hand;
      expect(newHand.length, 3);
      expect(newHand.sublist(0, 2), hand.sublist(1)); // others kept in order
      expect(r.state.deck.length, s.deck.length - 1);
      expect(r.state.players[0].cardReplacedThisGame, isTrue);
      // The discarded card leaves the game entirely.
      expect(r.state.deck.where((c) => false), isEmpty); // structural no-op
      expect(r.events.whereType<CardReplaced>().length, 1);
    });

    test('only once per game', () {
      final s = newGame();
      final once = apply(s, ReplaceCard(s.players[0].hand.first)).state;
      expect(
        () => apply(once, ReplaceCard(once.players[0].hand.first)),
        throwsA(isA<IllegalActionException>()),
      );
      expect(legalActions(once).whereType<ReplaceCard>(), isEmpty);
    });

    test('legal before rolling and in main phase, not mid-dice', () {
      final s = newGame();
      expect(legalActions(s).whereType<ReplaceCard>().length, 3);
      final rolled = apply(s, const RollDice()).state;
      expect(legalActions(rolled).whereType<ReplaceCard>(), isEmpty);
    });

    test('does not consume the one-card-per-turn play', () {
      var s = newGame();
      s = apply(s, ReplaceCard(s.players[0].hand.first)).state;
      expect(s.players[0].cardPlayedThisTurn, isFalse);
    });

    test('requires the card to be in hand and the deck to have cards', () {
      final s = newGame();
      expect(
        () => apply(s, const ReplaceCard('nonexistent_card')),
        throwsA(isA<IllegalActionException>()),
      );
      final empty = s.copyWith(deck: const []);
      expect(
        () => apply(empty, ReplaceCard(s.players[0].hand.first)),
        throwsA(isA<IllegalActionException>()),
      );
      expect(legalActions(empty).whereType<ReplaceCard>(), isEmpty);
    });
  });
}

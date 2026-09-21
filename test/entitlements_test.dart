import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/monetization/entitlements.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

void main() {
  group('setupChoiceAllowed', () {
    test('free tier is exactly 1 bot on easy', () {
      expect(
          setupChoiceAllowed(
              unlocked: false, botCount: 1, difficulty: BotDifficulty.easy),
          isTrue);
      expect(
          setupChoiceAllowed(
              unlocked: false, botCount: 2, difficulty: BotDifficulty.easy),
          isFalse);
      expect(
          setupChoiceAllowed(
              unlocked: false, botCount: 1, difficulty: BotDifficulty.medium),
          isFalse);
      expect(
          setupChoiceAllowed(
              unlocked: false, botCount: 3, difficulty: BotDifficulty.hard),
          isFalse);
    });

    test('unlocked allows everything', () {
      for (final count in [1, 2, 3]) {
        for (final diff in BotDifficulty.values) {
          expect(
              setupChoiceAllowed(
                  unlocked: true, botCount: count, difficulty: diff),
              isTrue);
        }
      }
    });
  });

  group('trialAvailable', () {
    test('only for locked players who have not spent it', () {
      expect(trialAvailable(unlocked: false, trialUsed: false), isTrue);
      expect(trialAvailable(unlocked: false, trialUsed: true), isFalse);
      expect(trialAvailable(unlocked: true, trialUsed: false), isFalse);
      expect(trialAvailable(unlocked: true, trialUsed: true), isFalse);
    });
  });

  group('shouldShowInterstitial', () {
    test('never for unlocked players', () {
      expect(shouldShowInterstitial(unlocked: true, gamesStartedBefore: 5),
          isFalse);
    });

    test('never before the first real game', () {
      expect(shouldShowInterstitial(unlocked: false, gamesStartedBefore: 0),
          isFalse);
    });

    test('shown from the second game on for free players', () {
      expect(shouldShowInterstitial(unlocked: false, gamesStartedBefore: 1),
          isTrue);
      expect(shouldShowInterstitial(unlocked: false, gamesStartedBefore: 7),
          isTrue);
    });
  });
}

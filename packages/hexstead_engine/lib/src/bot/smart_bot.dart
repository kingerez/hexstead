import '../actions.dart';
import '../legal_moves.dart';
import '../model/game_state.dart';
import '../model/player.dart';
import '../reducer.dart';
import '../rng.dart';
import 'evaluator.dart';

/// Greedy 1-ply bot: simulate each legal action, score the result, take the
/// best. Difficulty tiers differ only in noise and attention — the dice are
/// never touched.
abstract final class SmartBot {
  static GameAction chooseAction(GameState state) {
    final actions = legalActions(state);
    if (actions.length == 1) return actions.first;

    final me = state.currentPlayerIndex;
    final difficulty = state.currentPlayer.difficulty;

    GameAction? best;
    var bestValue = double.negativeInfinity;
    for (final (index, action) in actions.indexed) {
      if (_overlooked(state, difficulty, index, actions.length)) continue;
      final outcome = _speculate(state, action);
      if (outcome == null) continue;
      var value = evaluate(
        outcome,
        me,
        includeObjective: difficulty != BotDifficulty.easy,
      );
      value += _noise(state, index) * _noiseAmplitude(difficulty);
      if (value > bestValue) {
        bestValue = value;
        best = action;
      }
    }
    return best ?? actions.first;
  }

  /// Applies [action] on a state whose RNG is cloned, so speculation never
  /// advances the real dice stream.
  static GameState? _speculate(GameState state, GameAction action) {
    final sandbox =
        state.copyWith(rng: GameRng.fromJson(state.rng.toJson()));
    try {
      return apply(sandbox, action).state;
    } on IllegalActionException {
      return null;
    }
  }

  /// Easy bots overlook a stable ~40% of their options.
  static bool _overlooked(
      GameState state, BotDifficulty difficulty, int index, int count) {
    if (difficulty != BotDifficulty.easy || count <= 2) return false;
    return _hash(state.seed, state.round * 100 + index) % 2 == 0;
  }

  static double _noiseAmplitude(BotDifficulty difficulty) =>
      switch (difficulty) {
        BotDifficulty.easy => 25.0,
        BotDifficulty.medium => 5.0,
        BotDifficulty.hard => 0.5,
      };

  /// Deterministic pseudo-noise in [-1, 1] from the state identity — never
  /// the game RNG, so bot deliberation stays replay-safe.
  static double _noise(GameState state, int actionIndex) {
    final h = _hash(
      state.seed ^ state.round * 31 ^ state.currentPlayerIndex * 7,
      state.diceHistory.length * 131 + actionIndex,
    );
    return (h % 2001 - 1000) / 1000.0;
  }

  static int _hash(int a, int b) {
    var x = a * 0x9E3779B1 + b;
    x = ((x ^ (x >>> 16)) * 0x85EBCA6B) & 0xFFFFFFFF;
    x = ((x ^ (x >>> 13)) * 0xC2B2AE35) & 0xFFFFFFFF;
    return (x ^ (x >>> 16)) & 0x7FFFFFFF;
  }
}

import '../actions.dart';
import '../legal_moves.dart';
import '../model/game_state.dart';
import '../model/player.dart';
import '../reducer.dart';
import '../rng.dart';
import 'evaluator.dart';

/// Greedy 1-ply bot: simulate each legal action, score the result, take the
/// best. Difficulty tiers differ only in noise and attention - the dice are
/// never touched.
///
/// An action that leaves the bot mid-decision (a die-mod card keeps the
/// phase at `awaitingChoice`; a 7 sends it to `awaitingBandit`) is worthless
/// to score as-is, so speculation resolves the forced follow-ups greedily
/// before evaluating - a card play is then worth what it actually buys.
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
      final outcome = _valueOf(state, action, me, difficulty, 0);
      if (outcome == null) continue;
      final value =
          outcome + _noise(state, index) * _noiseAmplitude(difficulty);
      if (value > bestValue) {
        bestValue = value;
        best = action;
      }
    }
    return best ?? actions.first;
  }

  /// Chain resolution never runs deeper than card -> activation -> bandit,
  /// so this only guards against a rule change opening a longer loop.
  static const _chainDepthCap = 4;

  /// Value of taking [action], with any forced follow-up decision resolved.
  /// Null when the action turns out to be illegal.
  static double? _valueOf(GameState state, GameAction action, int me,
      BotDifficulty difficulty, int depth) {
    if (action is PlayCard &&
        action.cardId == 'second_chance' &&
        state.phase == Phase.awaitingChoice) {
      return _secondChanceValue(state, action, me, difficulty, depth);
    }
    final outcome = _speculate(state, action);
    if (outcome == null) return null;
    return _resolveChain(outcome, me, difficulty, depth);
  }

  /// Score of [state], resolving a decision the bot is still holding.
  /// Follow-ups are picked greedily by this same value, with no noise and no
  /// easy-difficulty overlooking: difficulty quirks belong to the choice the
  /// bot actually announces, not to its imagination.
  static double _resolveChain(
      GameState state, int me, BotDifficulty difficulty, int depth) {
    final pending = (state.phase == Phase.awaitingChoice ||
            state.phase == Phase.awaitingBandit) &&
        state.currentPlayerIndex == me;
    if (pending && depth < _chainDepthCap) {
      var best = double.negativeInfinity;
      for (final action in legalActions(state)) {
        final value = _valueOf(state, action, me, difficulty, depth + 1);
        if (value != null && value > best) best = value;
      }
      if (best.isFinite) return best;
    }
    return evaluate(
      state,
      me,
      includeObjective: difficulty != BotDifficulty.easy,
      includeRivals: difficulty != BotDifficulty.easy,
    );
  }

  /// Second Chance scored as an expectation over the 36 dice outcomes. The
  /// sandbox RNG is a clone of the real one, so its reroll is exactly the one
  /// the game would produce - using it would make the bot clairvoyant.
  ///
  /// Only the 21 unordered pairs are resolved, mixed ones weighted double:
  /// the card is spent, so no omen can follow, and both sum and split read
  /// the dice symmetrically - (a, b) and (b, a) resolve identically.
  static double? _secondChanceValue(GameState state, GameAction action, int me,
      BotDifficulty difficulty, int depth) {
    final played = _speculate(state, action);
    if (played == null) return null;
    var total = 0.0;
    for (var low = 1; low <= 6; low++) {
      for (var high = low; high <= 6; high++) {
        final rolled = played.copyWith(lastDice: () => (low, high));
        final value = _resolveChain(rolled, me, difficulty, depth);
        total += low == high ? value : value * 2;
      }
    }
    return total / 36.0;
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
    return _hash(state.seed, state.round * 100 + index) % 3 != 2;
  }

  /// Sized against the eval: a real sum-vs-split gap is a few points, so hard
  /// bots almost never misread one and medium bots slip only now and then.
  static double _noiseAmplitude(BotDifficulty difficulty) =>
      switch (difficulty) {
        BotDifficulty.easy => 45.0,
        BotDifficulty.medium => 4.0,
        BotDifficulty.hard => 0.3,
      };

  /// Deterministic pseudo-noise in [-1, 1] from the state identity - never
  /// the game RNG, so bot deliberation stays replay-safe.
  static double _noise(GameState state, int actionIndex) {
    final h = _hash(
      state.seed ^ state.round * 31 ^ state.currentPlayerIndex * 7,
      state.diceHistory.length * 131 + actionIndex,
    );
    return (h % 2001 - 1000) / 1000.0;
  }

  /// Web-safe mixer: xor/shift/add only, all intermediates 32-bit, so it is
  /// exact (and identical) on the VM and dart2js.
  static int _hash(int a, int b) {
    var x = ((a & 0xFFFFFFFF) ^ 0x9E3779B9) & 0xFFFFFFFF;
    x = (x + (b & 0xFFFFFFFF)) & 0xFFFFFFFF;
    x ^= x >>> 16;
    x = (x + ((x << 3) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    x ^= x >>> 13;
    x = (x + ((x << 9) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    x ^= x >>> 7;
    return x & 0x7FFFFFFF;
  }
}

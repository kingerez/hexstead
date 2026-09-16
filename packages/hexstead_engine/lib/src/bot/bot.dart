import '../actions.dart';
import '../legal_moves.dart';
import '../model/game_state.dart';
import '../model/tile.dart';
import '../scoring.dart';

/// Placeholder bot for early playtesting: greedy priorities, no evaluation.
/// Replaced by the weighted-eval bot in the AI phase.
abstract final class StubBot {
  static GameAction chooseAction(GameState state) {
    final actions = legalActions(state);
    switch (state.phase) {
      case Phase.awaitingRoll:
      case Phase.gameOver:
        return actions.first;
      case Phase.awaitingChoice:
        final (d1, d2) = state.lastDice!;
        // Skip the bandit detour; otherwise favor the sum (bigger numbers
        // live on better tiles).
        return d1 + d2 == 7
            ? const ChooseActivation(ActivationMode.split)
            : const ChooseActivation(ActivationMode.sum);
      case Phase.awaitingBandit:
        return _banditTarget(state, actions);
      case Phase.main:
        // Upgrade > claim > done; ignore trades and cards.
        final upgrade = actions.whereType<UpgradeHex>().firstOrNull;
        if (upgrade != null) return upgrade;
        final claim = actions.whereType<ClaimHex>().firstOrNull;
        if (claim != null) return claim;
        return const EndTurn();
    }
  }

  static GameAction _banditTarget(GameState state, List<GameAction> actions) {
    final me = state.currentPlayerIndex;
    PlaceBandit? best;
    var bestValue = -1;
    for (final action in actions.whereType<PlaceBandit>()) {
      final Tile tile = state.tiles[action.target]!;
      if (tile.ownerId == me) continue;
      final value = _pips(tile.number) * tile.level +
          scoreFor(state, tile.ownerId!);
      if (value > bestValue) {
        bestValue = value;
        best = action;
      }
    }
    return best ?? actions.first;
  }

  /// Ways to roll [number] with 2d6 - a cheap tile-quality proxy.
  static int _pips(int? number) =>
      number == null ? 0 : 6 - (number - 7).abs();
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

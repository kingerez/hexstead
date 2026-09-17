import 'dart:math' as math;

import '../model/game_state.dart';
import '../model/landmarks.dart';
import '../model/objectives.dart';
import '../model/tile.dart';
import '../scoring.dart';

/// Weighted heuristic evaluation of [state] from [playerId]'s seat.
/// Pure function: never touches the game RNG.
double evaluate(GameState state, int playerId,
    {bool includeObjective = true, bool includeRivals = true}) {
  final player = state.players[playerId];
  final roundsLeft = (state.roundCap - state.round + 1).clamp(1, 99);

  var value = 0.0;

  // Live score is the ground truth.
  value += scoreFor(state, playerId) * 10.0;

  // Expected production per round, worth more with more rounds left.
  value += _expectedProduction(state, playerId) * 2.0 * roundsLeft;

  // Rivals' engines hurt: this is what makes bandit placement (and the
  // sum-vs-split choice) consider what OTHERS gain, not just ourselves.
  // Easy bots are self-absorbed and skip it.
  if (includeRivals) {
    for (final rival in state.players) {
      if (rival.id == playerId) continue;
      value -= _expectedProduction(state, rival.id) * 0.6 * roundsLeft;
    }
  }

  // Room to grow: frontier tiles we could claim.
  value += _frontierSize(state, playerId) * 0.4;

  // Resources: useful but with diminishing returns; hoarding is waste.
  var totalResources = 0;
  for (final count in player.resources.values) {
    totalResources += count;
  }
  value += math.sqrt(totalResources) * 1.2;

  // Cards are options.
  value += player.hand.length * 0.8;

  // Secret objective: completed bonus counts as real points.
  if (includeObjective) {
    final objective = objectiveCatalog[player.objectiveId];
    if (objective != null && objective.isComplete(state, playerId)) {
      value += objective.bonusVp * 8.0;
    }
  }

  // Standing pressure: being behind the best rival hurts.
  var bestRival = 0;
  for (final rival in state.players) {
    if (rival.id == playerId) continue;
    final s = scoreFor(state, rival.id);
    if (s > bestRival) bestRival = s;
  }
  value -= bestRival * 3.0;

  // Holding the bandit-placement decision is an asset.
  if (state.phase == Phase.awaitingBandit &&
      state.currentPlayerIndex == playerId) {
    value += _banditOpportunity(state, playerId);
  }

  return value;
}

/// Expected resources per round from owned tiles (2d6 probabilities).
double _expectedProduction(GameState state, int playerId) {
  final player = state.players[playerId];
  var expected = 0.0;
  for (final tile in state.tiles.values) {
    if (tile.ownerId != playerId || tile.number == null) continue;
    if (tile.hasBandit) continue;
    if (tile.blockedUntilRound != null &&
        state.round < tile.blockedUntilRound!) {
      continue;
    }
    var perHit = tile.level.toDouble();
    if (player.hasLandmark(terrainBoostLandmarks[tile.terrain] ?? '')) {
      perHit += 1;
    }
    if (player.hasLandmark('high_roller') && tile.number! >= 9) {
      perHit *= 2;
    }
    expected += pipsFor(tile.number!) / 36.0 * perHit;
  }
  return expected;
}

int _frontierSize(GameState state, int playerId) {
  final frontier = <Tile>{};
  for (final tile in state.tiles.values) {
    if (tile.ownerId != playerId) continue;
    for (final nb in tile.coord.neighbors) {
      final nbTile = state.tiles[nb];
      if (nbTile != null && nbTile.ownerId == null) frontier.add(nbTile);
    }
  }
  return frontier.length;
}

/// Value of the best bandit placement available to [playerId].
double _banditOpportunity(GameState state, int playerId) {
  var best = 0.0;
  for (final tile in state.tiles.values) {
    if (tile.ownerId == null || tile.ownerId == playerId) continue;
    if (state.players[tile.ownerId!].hasLandmark('bandit_ward')) continue;
    final damage = pipsFor(tile.number ?? 0) * tile.level.toDouble();
    if (damage > best) best = damage;
  }
  return best * 0.5;
}

/// Ways to roll [number] on 2d6 (0 for off-board numbers).
int pipsFor(int number) =>
    number < 2 || number > 12 ? 0 : 6 - (number - 7).abs();

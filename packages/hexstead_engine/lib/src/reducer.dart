import 'actions.dart';
import 'events.dart';
import 'hex/hex.dart';
import 'model/game_state.dart';
import 'model/terrain.dart';
import 'scoring.dart';

class IllegalActionException implements Exception {
  final String message;

  IllegalActionException(this.message);

  @override
  String toString() => 'IllegalActionException: $message';
}

class ApplyResult {
  final GameState state;
  final List<GameEvent> events;

  const ApplyResult(this.state, this.events);
}

/// Applies one action, returning the next state and the facts that occurred.
/// Throws [IllegalActionException] on rule violations.
ApplyResult apply(GameState state, GameAction action) {
  if (state.phase == Phase.gameOver) {
    throw IllegalActionException('game is over');
  }
  return switch (action) {
    RollDice() => _rollDice(state),
    ChooseActivation(:final mode) => _chooseActivation(state, mode),
    PlaceBandit(:final target) => _placeBandit(state, target),
    RemoveBandit(:final spend) => _removeBandit(state, spend),
    ClaimHex(:final target) => _claim(state, target),
    UpgradeHex(:final target) => _upgrade(state, target),
    BankTrade(:final give, :final get) => _bankTrade(state, give, get),
    BuyLandmark() => throw IllegalActionException('landmarks not in play yet'),
    PlayCard() => throw IllegalActionException('cards not in play yet'),
    EndTurn() => _endTurn(state),
  };
}

ApplyResult _rollDice(GameState state) {
  _requirePhase(state, Phase.awaitingRoll, 'roll');
  final d1 = state.rng.rollDie();
  final d2 = state.rng.rollDie();
  final next = state.copyWith(
    phase: Phase.awaitingChoice,
    lastDice: () => (d1, d2),
    diceHistory: [...state.diceHistory, (d1, d2)],
  );
  return ApplyResult(next, [DiceRolled(d1, d2)]);
}

ApplyResult _chooseActivation(GameState state, ActivationMode mode) {
  _requirePhase(state, Phase.awaitingChoice, 'choose activation');
  final (d1, d2) = state.lastDice!;
  final events = <GameEvent>[];

  if (mode == ActivationMode.sum && d1 + d2 == 7) {
    events.add(const NothingProduced());
    return ApplyResult(state.copyWith(phase: Phase.awaitingBandit), events);
  }

  final activated =
      mode == ActivationMode.sum ? [d1 + d2] : [d1, d2];
  events.add(ActivationChosen(activated));

  final grants = <ProductionGrant>[];
  var next = state;
  for (final tile in state.tiles.values) {
    if (tile.ownerId == null || tile.number == null) continue;
    if (tile.hasBandit) continue;
    if (tile.blockedUntilRound != null &&
        state.round < tile.blockedUntilRound!) {
      continue;
    }
    final hits = activated.where((n) => n == tile.number).length;
    if (hits == 0) continue;
    final resource = tile.terrain.resource!;
    final count = hits * tile.level;
    grants.add((
      hex: tile.coord,
      playerId: tile.ownerId!,
      resource: resource,
      count: count,
    ));
    next = next.withPlayer(
      tile.ownerId!,
      (p) => p.copyWith(resources: p.resourcesApplying({resource: count})),
    );
  }
  events.add(grants.isEmpty
      ? const NothingProduced()
      : ResourcesProduced(grants));
  return ApplyResult(next.copyWith(phase: Phase.main), events);
}

ApplyResult _placeBandit(GameState state, Hex target) {
  _requirePhase(state, Phase.awaitingBandit, 'place bandit');
  final tile = state.tiles[target];
  if (tile == null || tile.ownerId == null) {
    throw IllegalActionException('bandit must target an owned tile');
  }
  final tiles = {
    for (final t in state.tiles.values)
      t.coord: t.coord == target
          ? t.copyWith(hasBandit: true)
          : (t.hasBandit ? t.copyWith(hasBandit: false) : t),
  };
  final next = state.copyWith(tiles: tiles, phase: Phase.main);
  return ApplyResult(next, [BanditPlaced(target)]);
}

ApplyResult _removeBandit(GameState state, List<Resource> spend) {
  _requirePhase(state, Phase.main, 'remove bandit');
  if (spend.length != Rules.banditRemovalCount) {
    throw IllegalActionException(
        'bandit removal costs ${Rules.banditRemovalCount} resources');
  }
  final player = state.currentPlayer;
  final target = state.tiles.values
      .where((t) => t.ownerId == player.id && t.hasBandit)
      .firstOrNull;
  if (target == null) {
    throw IllegalActionException('no bandit on your territory');
  }
  final cost = <Resource, int>{};
  for (final r in spend) {
    cost[r] = (cost[r] ?? 0) + 1;
  }
  if (!player.canAfford(cost)) {
    throw IllegalActionException('cannot afford bandit removal');
  }
  var next = state.withPlayer(
    player.id,
    (p) => p.copyWith(
        resources:
            p.resourcesApplying(cost.map((k, v) => MapEntry(k, -v)))),
  );
  next = next.copyWith(tiles: {
    ...next.tiles,
    target.coord: next.tiles[target.coord]!.copyWith(hasBandit: false),
  });
  return ApplyResult(next, [BanditRemoved(target.coord)]);
}

ApplyResult _claim(GameState state, Hex target) {
  _requirePhase(state, Phase.main, 'claim');
  final player = state.currentPlayer;
  final tile = state.tiles[target];
  if (tile == null) throw IllegalActionException('no such tile');
  if (tile.ownerId != null) throw IllegalActionException('tile already owned');
  final adjacent = target.neighbors
      .any((nb) => state.tiles[nb]?.ownerId == player.id);
  if (!adjacent) {
    throw IllegalActionException('claim must border your territory');
  }
  if (!player.canAfford(Rules.claimCost)) {
    throw IllegalActionException('cannot afford claim');
  }
  var next = state.withPlayer(
    player.id,
    (p) => p.copyWith(
        resources: p.resourcesApplying(
            Rules.claimCost.map((k, v) => MapEntry(k, -v)))),
  );
  next = next.copyWith(tiles: {
    ...next.tiles,
    target: tile.copyWith(ownerId: player.id, level: 1),
  });
  final events = <GameEvent>[HexClaimed(target, player.id)];
  return _checkInstantWin(next, events);
}

ApplyResult _upgrade(GameState state, Hex target) {
  _requirePhase(state, Phase.main, 'upgrade');
  final player = state.currentPlayer;
  final tile = state.tiles[target];
  if (tile == null || tile.ownerId != player.id) {
    throw IllegalActionException('you do not own this tile');
  }
  if (tile.level != 1) {
    throw IllegalActionException('only camps can be upgraded');
  }
  if (!player.canAfford(Rules.upgradeCost)) {
    throw IllegalActionException('cannot afford upgrade');
  }
  var next = state.withPlayer(
    player.id,
    (p) => p.copyWith(
        resources: p.resourcesApplying(
            Rules.upgradeCost.map((k, v) => MapEntry(k, -v)))),
  );
  next = next.copyWith(tiles: {
    ...next.tiles,
    target: tile.copyWith(level: 2),
  });
  final events = <GameEvent>[HexUpgraded(target, player.id)];
  return _checkInstantWin(next, events);
}

ApplyResult _bankTrade(GameState state, Resource give, Resource get) {
  _requirePhase(state, Phase.main, 'trade');
  final player = state.currentPlayer;
  if (give == get) throw IllegalActionException('pointless trade');
  final rate = Rules.bankTradeRate;
  if (player.countOf(give) < rate) {
    throw IllegalActionException('need $rate ${give.name} to trade');
  }
  final next = state.withPlayer(
    player.id,
    (p) => p.copyWith(resources: p.resourcesApplying({give: -rate, get: 1})),
  );
  return ApplyResult(next, [TradeCompleted(player.id, give, get)]);
}

ApplyResult _endTurn(GameState state) {
  _requirePhase(state, Phase.main, 'end turn');
  final events = <GameEvent>[];
  final nextIndex = (state.currentPlayerIndex + 1) % state.players.length;
  final wrapped = nextIndex == 0;

  if (wrapped && state.round >= state.roundCap) {
    return _finishGame(state, events);
  }

  var next = state.withPlayer(
    state.currentPlayerIndex,
    (p) => p.copyWith(cardPlayedThisTurn: false),
  );
  next = next.copyWith(
    currentPlayerIndex: nextIndex,
    round: wrapped ? state.round + 1 : state.round,
    phase: Phase.awaitingRoll,
    lastDice: () => null,
  );
  events.add(TurnEnded(nextIndex));
  if (wrapped) events.add(RoundAdvanced(next.round));
  return ApplyResult(next, events);
}

ApplyResult _checkInstantWin(GameState state, List<GameEvent> events) {
  final player = state.currentPlayer;
  if (scoreFor(state, player.id) >= state.targetVp) {
    return _finishGame(state, events, instantWinner: player.id);
  }
  return ApplyResult(state, events);
}

ApplyResult _finishGame(GameState state, List<GameEvent> events,
    {int? instantWinner}) {
  final scores = {
    for (final p in state.players) p.id: scoreFor(state, p.id),
  };
  final winner = instantWinner ??
      (state.players.map((p) => p.id).toList()
            ..sort((a, b) {
              final byScore = scores[b]!.compareTo(scores[a]!);
              return byScore != 0 ? byScore : a.compareTo(b);
            }))
          .first;
  final next = state.copyWith(phase: Phase.gameOver, winnerId: () => winner);
  return ApplyResult(next, [...events, GameEnded(winner, scores)]);
}

void _requirePhase(GameState state, Phase phase, String what) {
  if (state.phase != phase) {
    throw IllegalActionException('cannot $what during ${state.phase.name}');
  }
}

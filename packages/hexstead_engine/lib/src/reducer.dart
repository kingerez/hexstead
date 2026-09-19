import 'actions.dart';
import 'events.dart';
import 'hex/hex.dart';
import 'model/game_state.dart';
import 'model/cards.dart';
import 'model/landmarks.dart';
import 'model/objectives.dart';
import 'model/player.dart';
import 'model/terrain.dart';
import 'model/tile.dart';
import 'production.dart';
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
    BuyLandmark(:final landmarkId) => _buyLandmark(state, landmarkId),
    SeizeHex(:final target, :final spend) => _seize(state, target, spend),
    ReplaceCard(:final cardId) => _replaceCard(state, cardId),
    PlayCard() => _playCard(state, action),
    EndTurn() => _endTurn(state),
  };
}

ApplyResult _rollDice(GameState state) {
  _requirePhase(state, Phase.awaitingRoll, 'roll');
  final d1 = state.rng.rollDie();
  final d2 = state.rng.rollDie();
  var next = state.copyWith(
    phase: Phase.awaitingChoice,
    lastDice: () => (d1, d2),
    diceHistory: [...state.diceHistory, (d1, d2)],
  );
  final events = <GameEvent>[DiceRolled(d1, d2)];
  if (next.currentPlayer.hasLandmark('market_hall')) {
    next = next.withPlayer(
      next.currentPlayerIndex,
      (p) => p.copyWith(resources: p.resourcesApplying({Resource.grain: 1})),
    );
    events.add(LandmarkIncome(next.currentPlayerIndex, Resource.grain));
  }
  return ApplyResult(next, events);
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
    final count = productionFor(state, tile, hits: hits);
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

void _requireBanditAllowed(GameState state, Tile tile) {
  if (tile.ownerId != null &&
      state.players[tile.ownerId!].hasLandmark('bandit_ward')) {
    throw IllegalActionException('those lands are warded against the bandit');
  }
}

void _requireCardTargetable(GameState state, int actorId, int targetId) {
  if (targetId != actorId &&
      state.players[targetId].hasLandmark('watchtower')) {
    throw IllegalActionException('the watchtower blocks your card');
  }
}

ApplyResult _placeBandit(GameState state, Hex target) {
  _requirePhase(state, Phase.awaitingBandit, 'place bandit');
  final tile = state.tiles[target];
  if (tile == null || tile.ownerId == null) {
    throw IllegalActionException('bandit must target an owned tile');
  }
  _requireBanditAllowed(state, tile);
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
  final cost = Rules.effectiveClaimCost(player);
  if (!player.canAfford(cost)) {
    throw IllegalActionException('cannot afford claim');
  }
  var next = state.withPlayer(
    player.id,
    (p) => p.copyWith(
        resources:
            p.resourcesApplying(cost.map((k, v) => MapEntry(k, -v)))),
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

/// True when every tile on the board has an owner - the trigger that opens
/// late-game aggression.
bool _boardFull(GameState state) =>
    state.tiles.values.every((t) => t.ownerId != null);

ApplyResult _seize(GameState state, Hex target, List<Resource> spend) {
  _requirePhase(state, Phase.main, 'seize');
  if (!_boardFull(state)) {
    throw IllegalActionException('seizing opens once all land is claimed');
  }
  final player = state.currentPlayer;
  final tile = state.tiles[target];
  if (tile == null || tile.ownerId == null || tile.ownerId == player.id) {
    throw IllegalActionException('seize targets a rival hex');
  }
  if (state.players[tile.ownerId!].hasLandmark('watchtower')) {
    throw IllegalActionException('the watchtower protects those lands');
  }
  final adjacent =
      target.neighbors.any((nb) => state.tiles[nb]?.ownerId == player.id);
  if (!adjacent) {
    throw IllegalActionException('seize must border your territory');
  }
  final cost = Rules.seizeCost(tile.level);
  if (spend.length != cost) {
    throw IllegalActionException('seizing this hex costs $cost resources');
  }
  final costMap = <Resource, int>{};
  for (final r in spend) {
    costMap[r] = (costMap[r] ?? 0) + 1;
  }
  if (!player.canAfford(costMap)) {
    throw IllegalActionException('cannot afford the seizure');
  }
  final previousOwner = tile.ownerId!;
  var next = state.withPlayer(
    player.id,
    (p) => p.copyWith(
        resources:
            p.resourcesApplying(costMap.map((k, v) => MapEntry(k, -v)))),
  );
  next = next.copyWith(tiles: {
    ...next.tiles,
    target: tile.copyWith(ownerId: player.id),
  });
  final events = <GameEvent>[HexSeized(target, previousOwner, player.id)];
  return _checkInstantWin(next, events);
}

ApplyResult _bankTrade(GameState state, Resource give, Resource get) {
  _requireBankPhase(state, 'trade');
  final player = state.currentPlayer;
  if (give == get) throw IllegalActionException('pointless trade');
  final rate = Rules.effectiveTradeRate(player);
  if (player.countOf(give) < rate) {
    throw IllegalActionException('need $rate ${give.name} to trade');
  }
  final next = state.withPlayer(
    player.id,
    (p) => p.copyWith(resources: p.resourcesApplying({give: -rate, get: 1})),
  );
  return ApplyResult(next, [TradeCompleted(player.id, give, get)]);
}

ApplyResult _buyLandmark(GameState state, String landmarkId) {
  _requireBankPhase(state, 'buy landmark');
  final spec = landmarkCatalog[landmarkId];
  if (spec == null || !state.landmarkOffer.contains(landmarkId)) {
    throw IllegalActionException('landmark not available');
  }
  final player = state.currentPlayer;
  if (!player.canAfford(spec.cost)) {
    throw IllegalActionException('cannot afford ${spec.name}');
  }
  var next = state.withPlayer(
    player.id,
    (p) => p.copyWith(
      resources:
          p.resourcesApplying(spec.cost.map((k, v) => MapEntry(k, -v))),
      landmarkIds: [...p.landmarkIds, landmarkId],
    ),
  );
  next = next.copyWith(
    landmarkOffer:
        next.landmarkOffer.where((id) => id != landmarkId).toList(),
  );
  final events = <GameEvent>[LandmarkPurchased(landmarkId, player.id)];
  return _checkInstantWin(next, events);
}

/// The once-per-game mulligan: discard one card, draw a fresh one from the
/// deck. Free, and separate from the one-card-per-turn play limit.
ApplyResult _replaceCard(GameState state, String cardId) {
  _requireBankPhase(state, 'replace a card');
  final player = state.currentPlayer;
  if (player.cardReplacedThisGame) {
    throw IllegalActionException('you already replaced a card this game');
  }
  if (!player.hand.contains(cardId)) {
    throw IllegalActionException('card not in hand');
  }
  if (state.deck.isEmpty) {
    throw IllegalActionException('the deck is empty');
  }
  final drawIndex = state.rng.nextInt(state.deck.length);
  final drawn = state.deck[drawIndex];
  final deck = [...state.deck]..removeAt(drawIndex);
  var next = state.withPlayer(player.id, (p) {
    final hand = [...p.hand]..remove(cardId);
    return p.copyWith(hand: [...hand, drawn], cardReplacedThisGame: true);
  });
  next = next.copyWith(deck: deck);
  return ApplyResult(next, [CardReplaced(player.id)]);
}

ApplyResult _playCard(GameState state, PlayCard action) {
  final player = state.currentPlayer;
  final spec = cardCatalog[action.cardId];
  if (spec == null) throw IllegalActionException('unknown card');
  if (!player.hand.contains(action.cardId)) {
    throw IllegalActionException('card not in hand');
  }
  if (player.cardPlayedThisTurn) {
    throw IllegalActionException('only one card per turn');
  }
  final expectedPhase =
      spec.timing == CardTiming.diceChoice ? Phase.awaitingChoice : Phase.main;
  if (state.phase != expectedPhase) {
    throw IllegalActionException(
        '${spec.name} cannot be played during ${state.phase.name}');
  }

  // Consume the card first; effects below build on `next`.
  var next = state.withPlayer(player.id, (p) {
    final hand = [...p.hand]..remove(action.cardId);
    return p.copyWith(hand: hand, cardPlayedThisTurn: true);
  });
  final events = <GameEvent>[CardPlayed(action.cardId, player.id)];

  switch (action.cardId) {
    case 'second_chance':
      final d1 = next.rng.rollDie();
      final d2 = next.rng.rollDie();
      next = next.copyWith(
        lastDice: () => (d1, d2),
        diceHistory: [...next.diceHistory, (d1, d2)],
      );
      events.add(DiceRolled(d1, d2));

    case 'omen':
      final index = action.dieIndex;
      final delta = action.delta;
      if (index == null || delta == null || delta.abs() != 1) {
        throw IllegalActionException('omen needs a die and a direction');
      }
      final (d1, d2) = next.lastDice!;
      final values = [d1, d2];
      final shifted = values[index] + delta;
      if (shifted < 1 || shifted > 6) {
        throw IllegalActionException('die cannot leave 1..6');
      }
      values[index] = shifted;
      next = next.copyWith(lastDice: () => (values[0], values[1]));

    case 'drought':
      final tile = _cardTile(next, action, needNumber: true);
      if (tile.ownerId != null) {
        _requireCardTargetable(next, player.id, tile.ownerId!);
      }
      next = next.copyWith(tiles: {
        ...next.tiles,
        tile.coord:
            tile.copyWith(blockedUntilRound: () => next.round + 2),
      });

    case 'charter':
      final tile = _cardTile(next, action);
      if (tile.ownerId != null) {
        throw IllegalActionException('tile already claimed');
      }
      final buyer = next.currentPlayer;
      final claimCost = Rules.effectiveClaimCost(buyer);
      if (!buyer.canAfford(claimCost)) {
        throw IllegalActionException('cannot afford claim');
      }
      next = next.withPlayer(
        buyer.id,
        (p) => p.copyWith(
            resources: p
                .resourcesApplying(claimCost.map((k, v) => MapEntry(k, -v)))),
      );
      next = next.copyWith(tiles: {
        ...next.tiles,
        tile.coord: tile.copyWith(ownerId: buyer.id, level: 1),
      });
      events.add(HexClaimed(tile.coord, buyer.id));
      return _checkInstantWin(next, events);

    case 'cutpurse':
      final targetId = action.targetPlayer;
      if (targetId == null || targetId == player.id) {
        throw IllegalActionException('cutpurse needs a rival target');
      }
      _requireCardTargetable(next, player.id, targetId);
      final stolen = _stealRandom(next, from: targetId, to: player.id);
      if (stolen == null) {
        throw IllegalActionException('target has nothing to steal');
      }
      next = stolen.$1;
      events.add(ResourceStolen(targetId, player.id, stolen.$2));

    case 'bounty':
      final resource = action.resource;
      if (resource == null) {
        throw IllegalActionException('bounty needs a resource');
      }
      next = next.withPlayer(player.id,
          (p) => p.copyWith(resources: p.resourcesApplying({resource: 2})));

    case 'banish':
      final tile = _cardTile(next, action);
      if (tile.ownerId != player.id || !tile.hasBandit) {
        throw IllegalActionException('banish targets your bandit tile');
      }
      next = next.copyWith(tiles: {
        ...next.tiles,
        tile.coord: tile.copyWith(hasBandit: false),
      });
      events.add(BanditRemoved(tile.coord));

    case 'brigand':
      final tile = _cardTile(next, action);
      if (tile.ownerId == null) {
        throw IllegalActionException('bandit must target a claimed tile');
      }
      _requireBanditAllowed(next, tile);
      next = next.copyWith(tiles: {
        for (final t in next.tiles.values)
          t.coord: t.coord == tile.coord
              ? t.copyWith(hasBandit: true)
              : (t.hasBandit ? t.copyWith(hasBandit: false) : t),
      });
      events.add(BanditPlaced(tile.coord));

    case 'harvest':
      final grants = <ProductionGrant>[];
      for (final tile in next.tiles.values) {
        if (tile.ownerId != player.id) continue;
        if (!harvestNumbers.contains(tile.number)) continue;
        if (tile.hasBandit) continue;
        if (tile.blockedUntilRound != null &&
            next.round < tile.blockedUntilRound!) {
          continue;
        }
        final resource = tile.terrain.resource!;
        final count = productionFor(next, tile);
        grants.add((
          hex: tile.coord,
          playerId: player.id,
          resource: resource,
          count: count,
        ));
        next = next.withPlayer(
          player.id,
          (p) =>
              p.copyWith(resources: p.resourcesApplying({resource: count})),
        );
      }
      events.add(grants.isEmpty
          ? const NothingProduced()
          : ResourcesProduced(grants));

    case 'tithe':
      for (final opponent in state.players) {
        if (opponent.id == player.id) continue;
        if (opponent.hasLandmark('watchtower')) continue;
        final stolen = _stealRandom(next, from: opponent.id, to: player.id);
        if (stolen != null) {
          next = stolen.$1;
          events.add(ResourceStolen(opponent.id, player.id, stolen.$2));
        }
      }
  }

  return ApplyResult(next, events);
}

Tile _cardTile(GameState state, PlayCard action, {bool needNumber = false}) {
  final hex = action.targetHex;
  final tile = hex == null ? null : state.tiles[hex];
  if (tile == null) throw IllegalActionException('card needs a target tile');
  if (needNumber && tile.number == null) {
    throw IllegalActionException('target must be a numbered tile');
  }
  return tile;
}

/// Moves one random resource between players; null if [from] is broke.
(GameState, Resource)? _stealRandom(GameState state,
    {required int from, required int to}) {
  final victim = state.players[from];
  final total = victim.totalResources;
  if (total == 0) return null;
  var pick = state.rng.nextInt(total);
  late Resource chosen;
  for (final entry in victim.resources.entries) {
    if (pick < entry.value) {
      chosen = entry.key;
      break;
    }
    pick -= entry.value;
  }
  var next = state.withPlayer(
      from, (p) => p.copyWith(resources: p.resourcesApplying({chosen: -1})));
  next = next.withPlayer(
      to, (p) => p.copyWith(resources: p.resourcesApplying({chosen: 1})));
  return (next, chosen);
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
  if (wrapped) {
    events.add(RoundAdvanced(next.round));
    next = _dealRefill(next, events);
    if ((next.round - 1) % Rules.giveawayInterval == 0 && next.round > 1) {
      next = _applyGiveaway(next, events);
    }
  }
  return ApplyResult(next, events);
}

/// The bank's periodic stimulus: one random resource per player, in seat
/// order, so a cold streak of dice never leaves anyone stranded.
GameState _applyGiveaway(GameState state, List<GameEvent> events) {
  var next = state;
  final grants = <({int playerId, Resource resource})>[];
  for (final player in state.players) {
    final resource = Resource.values[next.rng.nextInt(Resource.values.length)];
    next = next.withPlayer(
      player.id,
      (p) => p.copyWith(resources: p.resourcesApplying({resource: 1})),
    );
    grants.add((playerId: player.id, resource: resource));
  }
  events.add(ResourceGiveaway(next.round, grants));
  return next;
}

/// Rounds 5 and 10 hand every player a card. The deck is finite, so players
/// the deck cannot cover are skipped silently.
GameState _dealRefill(GameState state, List<GameEvent> events) {
  if (!refillRounds.contains(state.round)) return state;
  var next = state;
  final drew = <int>[];
  for (final player in state.players) {
    if (next.deck.isEmpty) break;
    final drawIndex = next.rng.nextInt(next.deck.length);
    final drawn = next.deck[drawIndex];
    final deck = [...next.deck]..removeAt(drawIndex);
    next = next.withPlayer(
        player.id, (p) => p.copyWith(hand: [...p.hand, drawn]));
    next = next.copyWith(deck: deck);
    drew.add(player.id);
  }
  if (drew.isNotEmpty) events.add(CardsDealt(next.round, drew));
  return next;
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
  // Final totals reveal secret objectives; live scores never include them.
  final scores = {
    for (final p in state.players)
      p.id: scoreFor(state, p.id) + _objectiveBonus(state, p),
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

int _objectiveBonus(GameState state, PlayerState player) {
  final spec = objectiveCatalog[player.objectiveId];
  if (spec == null) return 0;
  return spec.isComplete(state, player.id) ? spec.bonusVp : 0;
}

/// Bank actions are allowed while awaiting a roll or in the main phase.
void _requireBankPhase(GameState state, String what) {
  if (state.phase != Phase.awaitingRoll && state.phase != Phase.main) {
    throw IllegalActionException('cannot $what during ${state.phase.name}');
  }
}

void _requirePhase(GameState state, Phase phase, String what) {
  if (state.phase != phase) {
    throw IllegalActionException('cannot $what during ${state.phase.name}');
  }
}

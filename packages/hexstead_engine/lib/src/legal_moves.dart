import 'actions.dart';
import 'hex/hex.dart';
import 'model/cards.dart';
import 'model/game_state.dart';
import 'model/player.dart';
import 'model/tile.dart';
import 'model/landmarks.dart';
import 'model/terrain.dart';

/// Every action the current player may legally take. Shared by UI button
/// enablement, bot enumeration, and fuzz tests.
List<GameAction> legalActions(GameState state) {
  switch (state.phase) {
    case Phase.awaitingRoll:
      // Bank actions (trade, landmark purchase) are open before rolling too.
      return [const RollDice(), ..._bankActions(state)];
    case Phase.awaitingChoice:
      return [
        const ChooseActivation(ActivationMode.sum),
        const ChooseActivation(ActivationMode.split),
        ..._cardActions(state, CardTiming.diceChoice),
      ];
    case Phase.awaitingBandit:
      return [
        for (final tile in state.tiles.values)
          if (tile.ownerId != null &&
              !state.players[tile.ownerId!].hasLandmark('bandit_ward'))
            PlaceBandit(tile.coord),
      ];
    case Phase.main:
      return _mainActions(state);
    case Phase.gameOver:
      return const [];
  }
}

List<GameAction> _mainActions(GameState state) {
  final player = state.currentPlayer;
  final actions = <GameAction>[const EndTurn()];

  if (player.canAfford(Rules.effectiveClaimCost(player))) {
    final frontier = <GameAction>{};
    for (final tile in state.tiles.values) {
      if (tile.ownerId != player.id) continue;
      for (final nb in tile.coord.neighbors) {
        final nbTile = state.tiles[nb];
        if (nbTile != null && nbTile.ownerId == null) {
          frontier.add(ClaimHex(nb));
        }
      }
    }
    actions.addAll(frontier);
  }

  if (player.canAfford(Rules.upgradeCost)) {
    for (final tile in state.tiles.values) {
      if (tile.ownerId == player.id && tile.level == 1) {
        actions.add(UpgradeHex(tile.coord));
      }
    }
  }

  actions.addAll(_bankActions(state));

  // Bandit removal: enumerate distinct spend pairs the player can afford.
  final banditTiles = state.tiles.values
      .where((t) => t.ownerId == player.id && t.hasBandit)
      .toList();
  if (banditTiles.isNotEmpty) {
    for (var i = 0; i < Resource.values.length; i++) {
      for (var j = i; j < Resource.values.length; j++) {
        final a = Resource.values[i];
        final b = Resource.values[j];
        final needed = a == b ? {a: 2} : {a: 1, b: 1};
        if (player.canAfford(needed)) {
          actions.add(RemoveBandit(spend: [a, b]));
        }
      }
    }
  }

  actions.addAll(_cardActions(state, CardTiming.main));
  actions.addAll(_seizeActions(state));

  return actions;
}

/// Once all land is claimed: one seize per adjacent rival hex, paid with a
/// canonical greedy spend (most abundant resources first).
List<GameAction> _seizeActions(GameState state) {
  if (state.tiles.values.any((t) => t.ownerId == null)) return const [];
  final player = state.currentPlayer;
  final actions = <GameAction>[];
  final targets = <Hex>{};
  for (final tile in state.tiles.values) {
    if (tile.ownerId != player.id) continue;
    for (final nb in tile.coord.neighbors) {
      final nbTile = state.tiles[nb];
      if (nbTile == null || nbTile.ownerId == null) continue;
      if (nbTile.ownerId == player.id) continue;
      if (state.players[nbTile.ownerId!].hasLandmark('watchtower')) continue;
      targets.add(nb);
    }
  }
  for (final target in targets) {
    final cost = Rules.seizeCost(state.tiles[target]!.level);
    final spend = _greedySpend(player, cost);
    if (spend != null) actions.add(SeizeHex(target, spend: spend));
  }
  return actions;
}

/// Picks [count] resources from the most abundant piles first; null when
/// the player cannot pay.
List<Resource>? _greedySpend(PlayerState player, int count) {
  if (player.totalResources < count) return null;
  final piles = [
    for (final r in Resource.values) (r, player.countOf(r)),
  ]..sort((a, b) => b.$2 != a.$2 ? b.$2 - a.$2 : a.$1.index - b.$1.index);
  final spend = <Resource>[];
  for (final (resource, available) in piles) {
    for (var i = 0; i < available && spend.length < count; i++) {
      spend.add(resource);
    }
  }
  return spend.length == count ? spend : null;
}

/// Landmark purchases and bank trades - legal before rolling and during
/// the main phase alike.
List<GameAction> _bankActions(GameState state) {
  final player = state.currentPlayer;
  final actions = <GameAction>[];
  for (final id in state.landmarkOffer) {
    if (player.canAfford(landmarkCatalog[id]!.cost)) {
      actions.add(BuyLandmark(id));
    }
  }
  for (final give in Resource.values) {
    if (player.countOf(give) >= Rules.effectiveTradeRate(player)) {
      for (final get in Resource.values) {
        if (get != give) actions.add(BankTrade(give: give, get: get));
      }
    }
  }
  return actions;
}

List<GameAction> _cardActions(GameState state, CardTiming timing) {
  final player = state.currentPlayer;
  if (player.cardPlayedThisTurn) return const [];
  final actions = <GameAction>[];
  for (final cardId in player.hand.toSet()) {
    final spec = cardCatalog[cardId];
    if (spec == null || spec.timing != timing) continue;
    switch (cardId) {
      case 'second_chance':
        actions.add(const PlayCard('second_chance'));
      case 'omen':
        final (d1, d2) = state.lastDice!;
        for (final (index, value) in [d1, d2].indexed) {
          for (final delta in const [-1, 1]) {
            final shifted = value + delta;
            if (shifted >= 1 && shifted <= 6) {
              actions.add(PlayCard('omen', dieIndex: index, delta: delta));
            }
          }
        }
      case 'drought':
        for (final tile in state.tiles.values) {
          if (tile.number != null && !_watchtowerProtects(state, player, tile)) {
            actions.add(PlayCard('drought', targetHex: tile.coord));
          }
        }
      case 'charter':
        if (player.canAfford(Rules.effectiveClaimCost(player))) {
          for (final tile in state.tiles.values) {
            if (tile.ownerId == null) {
              actions.add(PlayCard('charter', targetHex: tile.coord));
            }
          }
        }
      case 'cutpurse':
        for (final rival in state.players) {
          if (rival.id != player.id &&
              rival.totalResources > 0 &&
              !rival.hasLandmark('watchtower')) {
            actions.add(PlayCard('cutpurse', targetPlayer: rival.id));
          }
        }
      case 'bounty':
        for (final resource in Resource.values) {
          actions.add(PlayCard('bounty', resource: resource));
        }
      case 'banish':
        for (final tile in state.tiles.values) {
          if (tile.ownerId == player.id && tile.hasBandit) {
            actions.add(PlayCard('banish', targetHex: tile.coord));
          }
        }
      case 'brigand':
        for (final tile in state.tiles.values) {
          if (tile.ownerId != null &&
              !state.players[tile.ownerId!].hasLandmark('bandit_ward')) {
            actions.add(PlayCard('brigand', targetHex: tile.coord));
          }
        }
      case 'harvest':
        actions.add(const PlayCard('harvest'));
      case 'tithe':
        if (state.players.any((p) =>
            p.id != player.id &&
            p.totalResources > 0 &&
            !p.hasLandmark('watchtower'))) {
          actions.add(const PlayCard('tithe'));
        }
    }
  }
  return actions;
}

bool _watchtowerProtects(GameState state, PlayerState actor, Tile tile) =>
    tile.ownerId != null &&
    tile.ownerId != actor.id &&
    state.players[tile.ownerId!].hasLandmark('watchtower');

import 'actions.dart';
import 'model/game_state.dart';
import 'model/terrain.dart';

/// Every action the current player may legally take. Shared by UI button
/// enablement, bot enumeration, and fuzz tests.
List<GameAction> legalActions(GameState state) {
  switch (state.phase) {
    case Phase.awaitingRoll:
      return const [RollDice()];
    case Phase.awaitingChoice:
      return const [
        ChooseActivation(ActivationMode.sum),
        ChooseActivation(ActivationMode.split),
      ];
    case Phase.awaitingBandit:
      return [
        for (final tile in state.tiles.values)
          if (tile.ownerId != null) PlaceBandit(tile.coord),
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

  if (player.canAfford(Rules.claimCost)) {
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

  for (final give in Resource.values) {
    if (player.countOf(give) >= Rules.bankTradeRate) {
      for (final get in Resource.values) {
        if (get != give) actions.add(BankTrade(give: give, get: get));
      }
    }
  }

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

  return actions;
}

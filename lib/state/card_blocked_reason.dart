import 'package:hexstead_engine/hexstead_engine.dart';

/// Short footer hint for a card in [playerId]'s hand that has no legal play
/// right now. Legality itself stays with the engine's legal moves; this only
/// explains the most likely reason, so the hint never promises a card will
/// work "after dice resolve" when the real block is the purse or the board.
String cardBlockedReason(GameState state, int playerId, String cardId) {
  final spec = cardCatalog[cardId];
  final player = state.players.firstWhere((p) => p.id == playerId);
  if (state.phase == Phase.gameOver || state.currentPlayer.id != playerId) {
    return 'playable on your turn';
  }
  if (player.cardPlayedThisTurn) return 'one card per turn';
  if (spec == null) return "can't be played now";
  final rightPhase = switch (spec.timing) {
    CardTiming.diceChoice => state.phase == Phase.awaitingChoice,
    CardTiming.main => state.phase == Phase.main,
  };
  if (!rightPhase) {
    return spec.timing == CardTiming.diceChoice
        ? 'playable right after rolling'
        : 'playable after dice resolve';
  }
  switch (cardId) {
    case 'charter':
      // No free land beats the price: paying up would not help.
      if (state.tiles.values.every((t) => t.ownerId != null)) {
        return 'no free tiles';
      }
      final cost = Rules.effectiveClaimCost(player);
      if (!player.canAfford(cost)) return 'need ${costText(cost)}';
    case 'cutpurse':
    case 'tithe':
      return 'no rival to rob';
    case 'banish':
      return 'no bandit on your tiles';
    case 'drought':
    case 'brigand':
      return 'no valid target';
  }
  return "can't be played now";
}

/// "wood + brick", "2 grain + stone" - a cost in words, resources in enum
/// order. A lone 1 is dropped so the hint fits the card's footer.
String costText(Map<Resource, int> cost) => [
      for (final r in Resource.values)
        if ((cost[r] ?? 0) == 1)
          r.name
        else if ((cost[r] ?? 0) > 1)
          '${cost[r]} ${r.name}',
    ].join(' + ');

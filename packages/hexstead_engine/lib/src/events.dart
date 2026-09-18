import 'package:meta/meta.dart';

import 'hex/hex.dart';
import 'model/terrain.dart';

/// One tile's payout from a production step.
typedef ProductionGrant = ({Hex hex, int playerId, Resource resource, int count});

/// A fact emitted by the reducer. Drives animation and the game log; UI must
/// never re-derive state from events.
@immutable
sealed class GameEvent {
  const GameEvent();
}

class DiceRolled extends GameEvent {
  final int d1;
  final int d2;

  const DiceRolled(this.d1, this.d2);
}

class ActivationChosen extends GameEvent {
  final List<int> activatedNumbers;

  const ActivationChosen(this.activatedNumbers);
}

class ResourcesProduced extends GameEvent {
  final List<ProductionGrant> grants;

  const ResourcesProduced(this.grants);
}

class NothingProduced extends GameEvent {
  const NothingProduced();
}

class BanditPlaced extends GameEvent {
  final Hex target;

  const BanditPlaced(this.target);
}

class BanditRemoved extends GameEvent {
  final Hex target;

  const BanditRemoved(this.target);
}

class HexClaimed extends GameEvent {
  final Hex target;
  final int playerId;

  const HexClaimed(this.target, this.playerId);
}

class HexUpgraded extends GameEvent {
  final Hex target;
  final int playerId;

  const HexUpgraded(this.target, this.playerId);
}

class TradeCompleted extends GameEvent {
  final int playerId;
  final Resource gave;
  final Resource got;

  const TradeCompleted(this.playerId, this.gave, this.got);
}

class LandmarkPurchased extends GameEvent {
  final String landmarkId;
  final int playerId;

  const LandmarkPurchased(this.landmarkId, this.playerId);
}

class CardPlayed extends GameEvent {
  final String cardId;
  final int playerId;

  const CardPlayed(this.cardId, this.playerId);
}

class ResourceStolen extends GameEvent {
  final int fromPlayer;
  final int toPlayer;
  final Resource resource;

  const ResourceStolen(this.fromPlayer, this.toPlayer, this.resource);
}

/// Bad-luck insurance payout: [Rules.droughtReliefThreshold] consecutive
/// dry activations earn the player one random resource from the bank.
class DroughtRelief extends GameEvent {
  final int playerId;
  final Resource resource;

  const DroughtRelief(this.playerId, this.resource);
}

class LandmarkIncome extends GameEvent {
  final int playerId;
  final Resource resource;

  const LandmarkIncome(this.playerId, this.resource);
}

class HexSeized extends GameEvent {
  final Hex target;
  final int fromPlayer;
  final int toPlayer;

  const HexSeized(this.target, this.fromPlayer, this.toPlayer);
}

class CardReplaced extends GameEvent {
  final int playerId;

  const CardReplaced(this.playerId);
}

class TurnEnded extends GameEvent {
  final int nextPlayerIndex;

  const TurnEnded(this.nextPlayerIndex);
}

/// A refill round began: [playerIds] each drew one card, in seat order.
/// Players the deck ran out on are absent.
class CardsDealt extends GameEvent {
  final int round;
  final List<int> playerIds;

  const CardsDealt(this.round, this.playerIds);
}

class RoundAdvanced extends GameEvent {
  final int round;

  const RoundAdvanced(this.round);
}

class GameEnded extends GameEvent {
  final int winnerId;
  final Map<int, int> finalScores;

  const GameEnded(this.winnerId, this.finalScores);
}

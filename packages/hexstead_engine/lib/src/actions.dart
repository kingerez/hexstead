import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'hex/hex.dart';
import 'model/terrain.dart';

enum ActivationMode { sum, split }

/// A player intent. Applying actions through the reducer is the only way
/// game state changes.
@immutable
sealed class GameAction {
  const GameAction();
}

class RollDice extends GameAction {
  const RollDice();

  @override
  bool operator ==(Object other) => other is RollDice;

  @override
  int get hashCode => (RollDice).hashCode;
}

class ChooseActivation extends GameAction {
  final ActivationMode mode;

  const ChooseActivation(this.mode);

  @override
  bool operator ==(Object other) =>
      other is ChooseActivation && other.mode == mode;

  @override
  int get hashCode => Object.hash(ChooseActivation, mode);
}

class PlaceBandit extends GameAction {
  final Hex target;

  const PlaceBandit(this.target);

  @override
  bool operator ==(Object other) =>
      other is PlaceBandit && other.target == target;

  @override
  int get hashCode => Object.hash(PlaceBandit, target);
}

class RemoveBandit extends GameAction {
  /// The resources spent (any [Rules.banditRemovalCount] of them).
  final List<Resource> spend;

  const RemoveBandit({required this.spend});

  @override
  bool operator ==(Object other) =>
      other is RemoveBandit &&
      const ListEquality<Resource>().equals(other.spend, spend);

  @override
  int get hashCode => Object.hash(RemoveBandit, Object.hashAll(spend));
}

class ClaimHex extends GameAction {
  final Hex target;

  const ClaimHex(this.target);

  @override
  bool operator ==(Object other) => other is ClaimHex && other.target == target;

  @override
  int get hashCode => Object.hash(ClaimHex, target);
}

class UpgradeHex extends GameAction {
  final Hex target;

  const UpgradeHex(this.target);

  @override
  bool operator ==(Object other) =>
      other is UpgradeHex && other.target == target;

  @override
  int get hashCode => Object.hash(UpgradeHex, target);
}

class BankTrade extends GameAction {
  final Resource give;
  final Resource get;

  const BankTrade({required this.give, required this.get});

  @override
  bool operator ==(Object other) =>
      other is BankTrade && other.give == give && other.get == get;

  @override
  int get hashCode => Object.hash(BankTrade, give, get);
}

class BuyLandmark extends GameAction {
  final String landmarkId;

  const BuyLandmark(this.landmarkId);

  @override
  bool operator ==(Object other) =>
      other is BuyLandmark && other.landmarkId == landmarkId;

  @override
  int get hashCode => Object.hash(BuyLandmark, landmarkId);
}

class PlayCard extends GameAction {
  final String cardId;
  final Hex? targetHex;
  final int? targetPlayer;

  /// For 'omen': which die (0 or 1) and shift (+1 or -1).
  final int? dieIndex;
  final int? delta;

  /// For 'bounty': which resource to take.
  final Resource? resource;

  const PlayCard(
    this.cardId, {
    this.targetHex,
    this.targetPlayer,
    this.dieIndex,
    this.delta,
    this.resource,
  });

  @override
  bool operator ==(Object other) =>
      other is PlayCard &&
      other.cardId == cardId &&
      other.targetHex == targetHex &&
      other.targetPlayer == targetPlayer &&
      other.dieIndex == dieIndex &&
      other.delta == delta &&
      other.resource == resource;

  @override
  int get hashCode => Object.hash(
      PlayCard, cardId, targetHex, targetPlayer, dieIndex, delta, resource);
}

class SeizeHex extends GameAction {
  final Hex target;

  /// The resources paid (seize cost depends on the hex's level).
  final List<Resource> spend;

  const SeizeHex(this.target, {required this.spend});

  @override
  bool operator ==(Object other) =>
      other is SeizeHex &&
      other.target == target &&
      const ListEquality<Resource>().equals(other.spend, spend);

  @override
  int get hashCode => Object.hash(SeizeHex, target, Object.hashAll(spend));
}

class ReplaceCard extends GameAction {
  final String cardId;

  const ReplaceCard(this.cardId);

  @override
  bool operator ==(Object other) =>
      other is ReplaceCard && other.cardId == cardId;

  @override
  int get hashCode => Object.hash(ReplaceCard, cardId);
}

class EndTurn extends GameAction {
  const EndTurn();

  @override
  bool operator ==(Object other) => other is EndTurn;

  @override
  int get hashCode => (EndTurn).hashCode;
}

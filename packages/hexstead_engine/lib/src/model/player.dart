import 'package:meta/meta.dart';

import 'terrain.dart';

enum BotDifficulty { easy, medium, hard }

/// Setup-time player description.
@immutable
class PlayerSetup {
  final String name;
  final bool isBot;
  final BotDifficulty difficulty;

  const PlayerSetup({
    required this.name,
    required this.isBot,
    this.difficulty = BotDifficulty.medium,
  });
}

@immutable
class PlayerState {
  final int id;
  final String name;
  final bool isBot;
  final BotDifficulty difficulty;
  final Map<Resource, int> resources;

  /// Unplayed action card ids (hidden information).
  final List<String> hand;

  /// Secret objective id (hidden until game end); null before objectives deal.
  final String? objectiveId;
  final List<String> landmarkIds;
  final bool cardPlayedThisTurn;

  /// The once-per-game card mulligan.
  final bool cardReplacedThisGame;

  const PlayerState({
    required this.id,
    required this.name,
    required this.isBot,
    this.difficulty = BotDifficulty.medium,
    this.resources = const {},
    this.hand = const [],
    this.objectiveId,
    this.landmarkIds = const [],
    this.cardPlayedThisTurn = false,
    this.cardReplacedThisGame = false,
  });

  int countOf(Resource r) => resources[r] ?? 0;

  bool hasLandmark(String id) => landmarkIds.contains(id);

  int get totalResources =>
      resources.values.fold(0, (sum, count) => sum + count);

  PlayerState copyWith({
    Map<Resource, int>? resources,
    List<String>? hand,
    String? objectiveId,
    List<String>? landmarkIds,
    bool? cardPlayedThisTurn,
    bool? cardReplacedThisGame,
  }) =>
      PlayerState(
        id: id,
        name: name,
        isBot: isBot,
        difficulty: difficulty,
        resources: resources ?? this.resources,
        hand: hand ?? this.hand,
        objectiveId: objectiveId ?? this.objectiveId,
        landmarkIds: landmarkIds ?? this.landmarkIds,
        cardPlayedThisTurn: cardPlayedThisTurn ?? this.cardPlayedThisTurn,
        cardReplacedThisGame:
            cardReplacedThisGame ?? this.cardReplacedThisGame,
      );

  /// Returns resources with [delta] applied (negative to spend).
  Map<Resource, int> resourcesApplying(Map<Resource, int> delta) {
    final next = {...resources};
    for (final entry in delta.entries) {
      final value = (next[entry.key] ?? 0) + entry.value;
      assert(value >= 0, 'resource ${entry.key} went negative');
      next[entry.key] = value;
    }
    return next;
  }

  bool canAfford(Map<Resource, int> cost) =>
      cost.entries.every((e) => countOf(e.key) >= e.value);
}

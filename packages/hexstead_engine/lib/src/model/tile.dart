import 'package:meta/meta.dart';

import '../hex/hex.dart';
import 'terrain.dart';

/// One board tile. Immutable; level 0 = unowned, 1 = camp, 2 = village.
@immutable
class Tile {
  final Hex coord;
  final TerrainType terrain;

  /// Production number 2-12 (never 7); null for desert.
  final int? number;
  final int? ownerId;
  final int level;
  final bool hasBandit;

  /// Production is suppressed while `round < blockedUntilRound` (card effect).
  final int? blockedUntilRound;

  const Tile({
    required this.coord,
    required this.terrain,
    this.number,
    this.ownerId,
    this.level = 0,
    this.hasBandit = false,
    this.blockedUntilRound,
  });

  Tile copyWith({
    int? ownerId,
    int? level,
    bool? hasBandit,
    int? Function()? blockedUntilRound,
  }) =>
      Tile(
        coord: coord,
        terrain: terrain,
        number: number,
        ownerId: ownerId ?? this.ownerId,
        level: level ?? this.level,
        hasBandit: hasBandit ?? this.hasBandit,
        blockedUntilRound: blockedUntilRound != null
            ? blockedUntilRound()
            : this.blockedUntilRound,
      );
}

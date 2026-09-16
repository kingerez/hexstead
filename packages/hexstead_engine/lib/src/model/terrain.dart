enum TerrainType { forest, field, hill, mountain, desert }

enum Resource { wood, grain, brick, stone }

extension TerrainProduction on TerrainType {
  /// What this terrain produces, or null for desert.
  Resource? get resource => switch (this) {
        TerrainType.forest => Resource.wood,
        TerrainType.field => Resource.grain,
        TerrainType.hill => Resource.brick,
        TerrainType.mountain => Resource.stone,
        TerrainType.desert => null,
      };
}

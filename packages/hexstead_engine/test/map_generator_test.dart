import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

void main() {
  group('generateMap', () {
    test('produces 19 tiles covering the radius-2 board', () {
      final tiles = generateMap(GameRng(1));
      expect(tiles.length, 19);
      expect(tiles.keys.toSet(), Hex.spiral(const Hex(0, 0), 2).toSet());
    });

    test('terrain bag: 5 forest, 5 field, 4 hill, 4 mountain, 1 desert', () {
      final tiles = generateMap(GameRng(2));
      final counts = <TerrainType, int>{};
      for (final t in tiles.values) {
        counts[t.terrain] = (counts[t.terrain] ?? 0) + 1;
      }
      expect(counts[TerrainType.forest], 5);
      expect(counts[TerrainType.field], 5);
      expect(counts[TerrainType.hill], 4);
      expect(counts[TerrainType.mountain], 4);
      expect(counts[TerrainType.desert], 1);
    });

    test('number bag matches Catan-like distribution, desert unnumbered', () {
      final tiles = generateMap(GameRng(3));
      final numbers = tiles.values
          .where((t) => t.terrain != TerrainType.desert)
          .map((t) => t.number)
          .toList();
      expect(numbers, everyElement(isNotNull));
      final sorted = numbers.cast<int>()..sort();
      expect(sorted, [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12]);
      final desert =
          tiles.values.firstWhere((t) => t.terrain == TerrainType.desert);
      expect(desert.number, isNull);
    });

    test('no two adjacent tiles both carry a 6 or 8', () {
      for (var seed = 0; seed < 50; seed++) {
        final tiles = generateMap(GameRng(seed));
        for (final entry in tiles.entries) {
          final n = entry.value.number;
          if (n != 6 && n != 8) continue;
          for (final nb in entry.key.neighbors) {
            final other = tiles[nb]?.number;
            expect(other == 6 || other == 8, isFalse,
                reason: 'seed $seed: adjacent hot numbers at ${entry.key}');
          }
        }
      }
    });

    test('same seed, same map; different seed, different map', () {
      final a = generateMap(GameRng(42));
      final b = generateMap(GameRng(42));
      final c = generateMap(GameRng(43));
      expect(a.map((k, v) => MapEntry(k, '${v.terrain} ${v.number}')),
          b.map((k, v) => MapEntry(k, '${v.terrain} ${v.number}')));
      expect(
        a.map((k, v) => MapEntry(k, '${v.terrain} ${v.number}')),
        isNot(equals(c.map((k, v) => MapEntry(k, '${v.terrain} ${v.number}')))),
      );
    });

    test('fresh tiles are unowned, level 0, bandit-free', () {
      final tiles = generateMap(GameRng(4));
      for (final t in tiles.values) {
        expect(t.ownerId, isNull);
        expect(t.level, 0);
        expect(t.hasBandit, isFalse);
      }
    });
  });
}

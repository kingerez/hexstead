import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

void main() {
  group('GameRng', () {
    test('same seed produces identical sequences', () {
      final a = GameRng(42);
      final b = GameRng(42);
      for (var i = 0; i < 100; i++) {
        expect(a.nextInt(1000), b.nextInt(1000));
      }
    });

    test('different seeds diverge', () {
      final a = GameRng(1);
      final b = GameRng(2);
      final seqA = [for (var i = 0; i < 20; i++) a.nextInt(1 << 30)];
      final seqB = [for (var i = 0; i < 20; i++) b.nextInt(1 << 30)];
      expect(seqA, isNot(equals(seqB)));
    });

    test('rollDie is always 1..6 and covers all faces', () {
      final rng = GameRng(7);
      final seen = <int>{};
      for (var i = 0; i < 500; i++) {
        final d = rng.rollDie();
        expect(d, inInclusiveRange(1, 6));
        seen.add(d);
      }
      expect(seen, {1, 2, 3, 4, 5, 6});
    });

    test('state round-trips through JSON mid-stream', () {
      final rng = GameRng(99);
      for (var i = 0; i < 37; i++) {
        rng.nextInt(100);
      }
      final restored = GameRng.fromJson(rng.toJson());
      for (var i = 0; i < 50; i++) {
        expect(restored.nextInt(1000), rng.nextInt(1000));
      }
    });

    test('shuffle is deterministic per seed', () {
      final items = List.generate(20, (i) => i);
      final a = [...items]..let((l) => GameRng(5).shuffle(l));
      final b = [...items]..let((l) => GameRng(5).shuffle(l));
      expect(a, b);
      expect(a, isNot(equals(items))); // vanishingly unlikely to be identity
    });
  });
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}

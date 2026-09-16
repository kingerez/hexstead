import 'dart:math' as math;

import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Hex', () {
    test('value equality and hashability', () {
      expect(const Hex(1, -2), equals(const Hex(1, -2)));
      expect(const Hex(1, -2), isNot(equals(const Hex(-2, 1))));
      expect({const Hex(0, 0), const Hex(0, 0)}.length, 1);
    });

    test('addition', () {
      expect(const Hex(1, 2) + const Hex(3, -1), const Hex(4, 1));
    });

    test('has exactly 6 distinct neighbors at distance 1', () {
      const h = Hex(2, -1);
      final n = h.neighbors;
      expect(n.length, 6);
      expect(n.toSet().length, 6);
      for (final other in n) {
        expect(h.distanceTo(other), 1);
      }
    });

    test('distance matches known axial values', () {
      expect(const Hex(0, 0).distanceTo(const Hex(0, 0)), 0);
      expect(const Hex(0, 0).distanceTo(const Hex(3, 0)), 3);
      expect(const Hex(0, 0).distanceTo(const Hex(-2, 2)), 2);
      expect(const Hex(1, -1).distanceTo(const Hex(-1, 1)), 2);
    });

    test('ring sizes: 1 at radius 0, 6r otherwise', () {
      expect(Hex.ring(const Hex(0, 0), 0), [const Hex(0, 0)]);
      expect(Hex.ring(const Hex(0, 0), 1).length, 6);
      expect(Hex.ring(const Hex(0, 0), 2).length, 12);
      for (final h in Hex.ring(const Hex(0, 0), 2)) {
        expect(const Hex(0, 0).distanceTo(h), 2);
      }
    });

    test('radius-2 board has exactly 19 hexes', () {
      final board = Hex.spiral(const Hex(0, 0), 2);
      expect(board.length, 19);
      expect(board.toSet().length, 19);
    });

    test('pointy-top pixel conversion round-trips', () {
      const size = 40.0;
      for (final h in Hex.spiral(const Hex(0, 0), 2)) {
        final (x, y) = h.toPixel(size);
        expect(Hex.fromPixel(x, y, size), h);
        // and a point nudged off-center still rounds to the same hex
        expect(Hex.fromPixel(x + size * 0.3, y - size * 0.2, size), h);
      }
    });

    test('pixel geometry is pointy-top (unit vertical pitch < horizontal)', () {
      // pointy-top: horizontal neighbor spacing = sqrt(3)*size, vertical rows 1.5*size apart
      const size = 10.0;
      final (x0, y0) = const Hex(0, 0).toPixel(size);
      final (x1, y1) = const Hex(1, 0).toPixel(size);
      final (x2, y2) = const Hex(0, 1).toPixel(size);
      expect(x1 - x0, closeTo(math.sqrt(3) * size, 1e-9));
      expect(y1 - y0, closeTo(0, 1e-9));
      expect(y2 - y0, closeTo(1.5 * size, 1e-9));
    });
  });
}

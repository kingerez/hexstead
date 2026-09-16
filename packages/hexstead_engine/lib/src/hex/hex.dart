import 'dart:math' as math;

/// Axial hex coordinate (pointy-top orientation).
///
/// See Red Blob Games' hexagonal grid reference for the math.
class Hex {
  final int q;
  final int r;

  const Hex(this.q, this.r);

  static const List<Hex> directions = [
    Hex(1, 0),
    Hex(1, -1),
    Hex(0, -1),
    Hex(-1, 0),
    Hex(-1, 1),
    Hex(0, 1),
  ];

  Hex operator +(Hex other) => Hex(q + other.q, r + other.r);

  List<Hex> get neighbors => [for (final d in directions) this + d];

  int distanceTo(Hex other) {
    final dq = q - other.q;
    final dr = r - other.r;
    return (dq.abs() + dr.abs() + (dq + dr).abs()) ~/ 2;
  }

  /// The hexes at exactly [radius] from [center].
  static List<Hex> ring(Hex center, int radius) {
    if (radius == 0) return [center];
    final results = <Hex>[];
    var hex = center + Hex(directions[4].q * radius, directions[4].r * radius);
    for (var side = 0; side < 6; side++) {
      for (var step = 0; step < radius; step++) {
        results.add(hex);
        hex = hex + directions[side];
      }
    }
    return results;
  }

  /// All hexes within [radius] of [center], center first.
  static List<Hex> spiral(Hex center, int radius) =>
      [for (var r = 0; r <= radius; r++) ...ring(center, r)];

  /// Center of this hex in pixels, for pointy-top hexes of the given [size]
  /// (center-to-vertex distance).
  (double, double) toPixel(double size) {
    final x = size * (math.sqrt(3) * q + math.sqrt(3) / 2 * r);
    final y = size * (3 / 2 * r);
    return (x, y);
  }

  /// The hex containing pixel ([x], [y]) for pointy-top hexes of [size].
  static Hex fromPixel(double x, double y, double size) {
    final fq = (math.sqrt(3) / 3 * x - 1 / 3 * y) / size;
    final fr = (2 / 3 * y) / size;
    return _round(fq, fr);
  }

  static Hex _round(double fq, double fr) {
    final fs = -fq - fr;
    var q = fq.round();
    var r = fr.round();
    final s = fs.round();
    final dq = (q - fq).abs();
    final dr = (r - fr).abs();
    final ds = (s - fs).abs();
    if (dq > dr && dq > ds) {
      q = -r - s;
    } else if (dr > ds) {
      r = -q - s;
    }
    return Hex(q, r);
  }

  @override
  bool operator ==(Object other) => other is Hex && other.q == q && other.r == r;

  @override
  int get hashCode => Object.hash(q, r);

  @override
  String toString() => 'Hex($q, $r)';
}

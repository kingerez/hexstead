import 'dart:math' as math;
import 'dart:ui';

import 'package:hexstead_engine/hexstead_engine.dart';

/// Maps engine axial coordinates onto screen pixels for a radius-2 board
/// centered in the available canvas.
class BoardGeometry {
  final Size canvas;
  final double hexSize;
  final Offset origin;

  factory BoardGeometry(Size canvas) {
    // Pointy-top radius-2 board: 5 columns of sqrt(3)*size, 4.5 rows of size.
    final byWidth = canvas.width / (math.sqrt(3) * 5.4);
    final byHeight = canvas.height / 8.2;
    final size = math.min(byWidth, byHeight);
    return BoardGeometry._(
      canvas,
      size,
      Offset(canvas.width / 2, canvas.height / 2),
    );
  }

  BoardGeometry._(this.canvas, this.hexSize, this.origin);

  Offset centerOf(Hex hex) {
    final (x, y) = hex.toPixel(hexSize);
    return origin + Offset(x, y);
  }

  Hex hexAt(Offset position) {
    final local = position - origin;
    return Hex.fromPixel(local.dx, local.dy, hexSize);
  }

  /// The 6 corners of a pointy-top hex of [size] around [center], slightly
  /// inset for tile gaps. Static so anything drawing a hex off the board
  /// (the inspector preview) shares this geometry.
  static List<Offset> hexCorners(Offset center, double size,
      {double inset = 0.94}) {
    return [
      for (var i = 0; i < 6; i++)
        center +
            Offset.fromDirection(
              (60.0 * i - 30) * math.pi / 180,
              size * inset,
            ),
    ];
  }

  /// The 6 corners of [hex] on this board.
  List<Offset> cornersOf(Hex hex, {double inset = 0.94}) =>
      hexCorners(centerOf(hex), hexSize, inset: inset);
}

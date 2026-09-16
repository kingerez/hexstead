/// Deterministic, serializable RNG (xorshift128).
///
/// Uses only 32-bit xor/shift arithmetic so results are bit-identical on
/// the Dart VM and on the web (dart2js has no exact 64-bit integers).
/// The full state serializes to JSON, so a resumed game continues the
/// exact dice sequence it would have had.
class GameRng {
  int _x;
  int _y;
  int _z;
  int _w;

  // Seed is split into 32-bit halves with ~/ (exact below 2^53 everywhere),
  // never with 64-bit shifts, which differ between the VM and dart2js.
  GameRng(int seed)
      : _x = ((seed & _mask32) ^ 0x9E3779B9) & _mask32,
        _y = (((seed & _mask32) >>> 16) + 0x85EBCA6B) & _mask32,
        _z = ((seed ~/ 0x100000000) ^ 0xC2B2AE35) & _mask32,
        _w = ((seed & _mask32) + 0x27D4EB2F) & _mask32 {
    if (_x == 0 && _y == 0 && _z == 0 && _w == 0) _w = 1;
    // Warm up so nearby seeds diverge quickly.
    for (var i = 0; i < 12; i++) {
      _next();
    }
  }

  GameRng.fromJson(Map<String, dynamic> json)
      : _x = json['x'] as int,
        _y = json['y'] as int,
        _z = json['z'] as int,
        _w = json['w'] as int;

  Map<String, dynamic> toJson() => {'x': _x, 'y': _y, 'z': _z, 'w': _w};

  int _next() {
    final t = (_x ^ ((_x << 11) & _mask32)) & _mask32;
    _x = _y;
    _y = _z;
    _z = _w;
    _w = (_w ^ (_w >>> 19)) ^ (t ^ (t >>> 8)) & _mask32;
    _w &= _mask32;
    return _w;
  }

  /// Uniform integer in [0, max).
  int nextInt(int max) => (_next() >>> 4) % max;

  /// One die face, 1..6.
  int rollDie() => nextInt(6) + 1;

  /// In-place Fisher-Yates shuffle.
  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }

  static const _mask32 = 0xFFFFFFFF;
}

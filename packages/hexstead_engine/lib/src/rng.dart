/// Deterministic, serializable RNG (splitmix64 core).
///
/// The full generator state is one 64-bit word that serializes to JSON, so a
/// resumed game continues the exact dice sequence it would have had.
class GameRng {
  int _state;

  GameRng(int seed) : _state = seed;

  GameRng.fromJson(Map<String, dynamic> json)
      : _state = int.parse(json['state'] as String, radix: 16);

  Map<String, dynamic> toJson() => {'state': _state.toRadixString(16)};

  int _next() {
    _state = (_state + 0x9E3779B97F4A7C15) & _mask64;
    var z = _state;
    z = ((z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9) & _mask64;
    z = ((z ^ (z >>> 27)) * 0x94D049BB133111EB) & _mask64;
    return (z ^ (z >>> 31)) & _mask64;
  }

  /// Uniform integer in [0, max).
  int nextInt(int max) => (_next() >>> 11) % max;

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

  static const _mask64 = 0xFFFFFFFFFFFFFFFF;
}

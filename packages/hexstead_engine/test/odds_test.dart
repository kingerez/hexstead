import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

void main() {
  group('activationOdds', () {
    test('a number a single die can show adds the split route', () {
      // Sum ways plus the 11 rolls where either die reads the number.
      expect(activationOdds(2), 12 / 36);
      expect(activationOdds(3), 13 / 36);
      expect(activationOdds(4), 14 / 36);
      expect(activationOdds(5), 15 / 36);
      expect(activationOdds(6), 16 / 36);
    });

    test('high numbers ride the sum alone', () {
      expect(activationOdds(8), 5 / 36);
      expect(activationOdds(9), 4 / 36);
      expect(activationOdds(10), 3 / 36);
      expect(activationOdds(11), 2 / 36);
      expect(activationOdds(12), 1 / 36);
    });

    test('7 never pays and a numberless hex never pays', () {
      expect(activationOdds(7), 0.0);
      expect(activationOdds(null), 0.0);
    });
  });
}

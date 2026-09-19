/// Chance that one 2d6 roll can activate [number]: the sum route, plus the
/// split route for numbers a single die can show. A sum of 7 unleashes the
/// bandit instead of producing, so a 7 hex never pays.
double activationOdds(int? number) {
  if (number == null || number == 7) return 0.0;
  final sumWays =
      (number >= 2 && number <= 12) ? 6 - (7 - number).abs() : 0;
  final singleDieWays = (number >= 1 && number <= 6) ? 11 : 0;
  // The two routes are disjoint - a die showing n alongside a sum of n would
  // need the other die to read 0 - so adding them is exact.
  return (sumWays + singleDieWays) / 36;
}

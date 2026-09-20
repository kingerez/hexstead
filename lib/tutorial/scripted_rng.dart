import 'package:hexstead_engine/hexstead_engine.dart';

/// A die that always comes up the way the lesson needs it.
///
/// Only [rollDie] is scripted; [nextInt] and therefore `shuffle` keep the
/// real xorshift behaviour, so nothing else about the engine changes. The
/// tutorial script consumes exactly as many faces as the queue holds; once
/// it runs dry the rolls go back to being random, which is the safe way to
/// fail rather than throwing at the player.
class ScriptedRng extends GameRng {
  final List<int> _dice;

  ScriptedRng(Iterable<int> dice)
      : _dice = List.of(dice),
        super(0);

  /// The faces still waiting in the queue, for tests.
  int get remaining => _dice.length;

  @override
  int rollDie() => _dice.isEmpty ? super.rollDie() : _dice.removeAt(0);
}

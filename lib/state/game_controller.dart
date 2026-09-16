import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import 'persistence.dart';

/// Owns the live [GameState]: applies human actions, drives bot turns with
/// visible pacing, and autosaves after every applied action.
class GameController extends ChangeNotifier {
  final SaveStore saveStore;

  /// Pause between visible bot steps; zero in tests.
  final Duration botStepDelay;

  GameState? _state;
  List<GameEvent> lastEvents = const [];
  bool _drivingBots = false;

  GameController({
    required this.saveStore,
    this.botStepDelay = const Duration(milliseconds: 500),
  });

  GameState? get state => _state;

  bool get isHumanTurn =>
      _state != null &&
      _state!.phase != Phase.gameOver &&
      !_state!.currentPlayer.isBot;

  Future<void> startNewGame({
    required int seed,
    required List<PlayerSetup> players,
    int targetVp = Rules.defaultTargetVp,
    int roundCap = Rules.defaultRoundCap,
  }) async {
    _state = GameState.newGame(
      seed: seed,
      players: players,
      targetVp: targetVp,
      roundCap: roundCap,
    );
    lastEvents = const [];
    await _persist();
    notifyListeners();
    await _driveBots();
  }

  /// Restores the autosave. Returns false when there is nothing to resume.
  Future<bool> resume() async {
    final json = await saveStore.load();
    if (json == null) return false;
    try {
      _state = gameStateFromJson(jsonDecode(json) as Map<String, dynamic>);
    } on FormatException {
      return false;
    }
    lastEvents = const [];
    notifyListeners();
    await _driveBots();
    return true;
  }

  /// Applies a human action. Throws [IllegalActionException] on rule
  /// violations (UI should prevent these via [legalActions]).
  Future<void> dispatch(GameAction action) async {
    final result = apply(_state!, action);
    _state = result.state;
    lastEvents = result.events;
    await _persist();
    notifyListeners();
    await _driveBots();
  }

  Future<void> _driveBots() async {
    if (_drivingBots) return;
    _drivingBots = true;
    try {
      while (_state != null &&
          _state!.phase != Phase.gameOver &&
          _state!.currentPlayer.isBot) {
        if (botStepDelay > Duration.zero) {
          await Future<void>.delayed(botStepDelay);
        }
        final action = StubBot.chooseAction(_state!);
        final result = apply(_state!, action);
        _state = result.state;
        lastEvents = result.events;
        await _persist();
        notifyListeners();
      }
    } finally {
      _drivingBots = false;
    }
  }

  Future<void> _persist() async {
    await saveStore.save(jsonEncode(gameStateToJson(_state!)));
  }
}

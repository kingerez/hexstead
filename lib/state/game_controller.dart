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

  /// Optional presentation hook, awaited after every applied action so the
  /// UI can play animations (dice roll) before the game continues - this is
  /// what makes bot turns wait for the on-screen dice to settle.
  Future<void> Function(List<GameEvent> events)? eventDelegate;

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
    final GameState decoded;
    try {
      decoded = gameStateFromJson(jsonDecode(json) as Map<String, dynamic>);
    } on FormatException {
      return false;
    }
    if (decoded.phase == Phase.gameOver) {
      // Defensive: devices in the field may hold stale finished-game saves.
      await saveStore.clear();
      return false;
    }
    _state = decoded;
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
    await eventDelegate?.call(result.events);
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
        final action = SmartBot.chooseAction(_state!);
        final result = apply(_state!, action);
        _state = result.state;
        lastEvents = result.events;
        await _persist();
        notifyListeners();
        await eventDelegate?.call(result.events);
      }
    } finally {
      _drivingBots = false;
    }
  }

  /// Whether the menu should offer Continue: a save exists, decodes, and is
  /// not a finished game. Never mutates [_state].
  Future<bool> hasResumableGame() async {
    final json = await saveStore.load();
    if (json == null) return false;
    try {
      final decoded =
          gameStateFromJson(jsonDecode(json) as Map<String, dynamic>);
      return decoded.phase != Phase.gameOver;
    } on FormatException {
      return false;
    }
  }

  Future<void> _persist() async {
    if (_state!.phase == Phase.gameOver) {
      // A finished game must not leave an autosave behind, or the menu
      // would keep offering a dead Continue.
      await saveStore.clear();
      return;
    }
    await saveStore.save(jsonEncode(gameStateToJson(_state!)));
  }
}

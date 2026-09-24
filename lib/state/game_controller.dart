import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../observability/analytics.dart';
import 'persistence.dart';

/// Owns the live [GameState]: applies human actions, drives bot turns with
/// visible pacing, and autosaves after every applied action.
class GameController extends ChangeNotifier {
  final SaveStore saveStore;

  /// Pause between visible bot steps; zero in tests.
  final Duration botStepDelay;

  /// Replaces [SmartBot] as the source of bot moves. The scripted tutorial
  /// feeds its rehearsed opponent this way; returning null stops the bot
  /// loop where it stands, leaving the game parked mid-turn.
  final GameAction? Function(GameState state)? botBrainOverride;

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
    this.botBrainOverride,
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
    Analytics.instance.capture('game_started', {
      'players': players.length,
      'bots': players.where((p) => p.isBot).length,
      'target_vp': targetVp,
      'round_cap': roundCap,
    });
    await _persist();
    notifyListeners();
    await _driveBots();
  }

  /// Starts from a hand-authored state instead of a generated one - the
  /// scripted tutorial's way in.
  Future<void> startFromState(GameState state) async {
    _state = state;
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
    Analytics.instance.capture('game_resumed', {'round': decoded.round});
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
    _trackEvents(result.events, humanAction: true);
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
        final action = botBrainOverride != null
            ? botBrainOverride!(_state!)
            : SmartBot.chooseAction(_state!);
        if (action == null) break;
        final result = apply(_state!, action);
        _state = result.state;
        lastEvents = result.events;
        _trackEvents(result.events, humanAction: false);
        await _persist();
        notifyListeners();
        await eventDelegate?.call(result.events);
      }
    } finally {
      _drivingBots = false;
    }
  }

  /// Analytics for what just happened. The end of the game is worth knowing
  /// whoever brought it about; the feature events are usage signal, so only
  /// the player's own moves count - a bot buying a landmark says nothing.
  void _trackEvents(List<GameEvent> events, {required bool humanAction}) {
    final state = _state!;
    for (final event in events) {
      if (event is GameEnded) {
        final humans = state.players.where((p) => !p.isBot);
        final human = humans.isEmpty ? null : humans.first;
        Analytics.instance.capture('game_finished', {
          'winner_id': event.winnerId,
          'human_won': !state.players[event.winnerId].isBot,
          'round': state.round,
          'human_score': human == null ? null : scoreFor(state, human.id),
          'human_landmarks': human?.landmarkIds.length,
        });
      }
      if (!humanAction) continue;
      if (event is LandmarkPurchased) {
        Analytics.instance
            .capture('landmark_bought', {'landmark_id': event.landmarkId});
      } else if (event is CardPlayed) {
        Analytics.instance.capture('card_played', {'card_id': event.cardId});
      } else if (event is TradeCompleted) {
        Analytics.instance.capture('trade_completed');
      }
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

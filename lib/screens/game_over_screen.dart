import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../board/board_painter.dart';
import '../state/game_controller.dart';
import '../state/high_scores.dart';
import 'setup_screen.dart';

class GameOverScreen extends StatefulWidget {
  final GameController controller;

  const GameOverScreen({super.key, required this.controller});

  @override
  State<GameOverScreen> createState() => _GameOverScreenState();
}

class _GameOverScreenState extends State<GameOverScreen> {
  bool? _newBest;
  int _multipliedScore = 0;
  double _multiplier = 1;

  GameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _recordScore();
  }

  Future<void> _recordScore() async {
    final state = controller.state!;
    final human = state.players.firstWhere((p) => !p.isBot);
    final raw = finalScoreFor(state, human.id);
    _multiplier = difficultyMultiplier(state.players);
    _multipliedScore = (raw * _multiplier).round();
    final bots = state.players.where((p) => p.isBot).toList();
    final isBest = await HighScoreStore().record(ScoreEntry(
      score: raw,
      multiplier: _multiplier,
      finalScore: _multipliedScore,
      botSummary: '${bots.length} bots · ${bots.first.difficulty.name}',
      date: DateTime.now(),
    ));
    if (mounted) setState(() => _newBest = isBest);
  }

  /// One scoreboard row: final total plus the revealed secret objective.
  Widget _playerRow(GameState state, PlayerState p) {
    final objective = objectiveCatalog[p.objectiveId];
    final complete = objective?.isComplete(state, p.id) ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle,
                  size: 12, color: BoardPainter.playerColors[p.id]),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: Text(
                  p.name,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
              Text(
                '${finalScoreFor(state, p.id)} pts',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (objective != null)
            Text(
              complete
                  ? '🎯 ${objective.name} fulfilled (+${objective.bonusVp})'
                  : '✗ ${objective.name} unfulfilled',
              style: TextStyle(
                color: complete ? Colors.amber : Colors.white38,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = controller.state!;
    final winner = state.players[state.winnerId!];
    final humanWon = !winner.isBot;
    final ranked = [...state.players]
      ..sort((a, b) =>
          finalScoreFor(state, b.id).compareTo(finalScoreFor(state, a.id)));

    return Scaffold(
      backgroundColor: const Color(0xFF2E4034),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                humanWon ? '🏆 Victory!' : '${winner.name} wins',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 24),
              for (final p in ranked) _playerRow(state, p),
              const SizedBox(height: 18),
              Text(
                'Your score ×${_multiplier.toStringAsFixed(2)} difficulty '
                '= $_multipliedScore',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              if (_newBest == true)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '✨ New personal best!',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => SetupScreen(controller: controller),
                  ),
                ),
                child: const Text('Play again'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Menu'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

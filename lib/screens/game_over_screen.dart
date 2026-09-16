import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../board/board_painter.dart';
import '../state/game_controller.dart';
import 'setup_screen.dart';

class GameOverScreen extends StatelessWidget {
  final GameController controller;

  const GameOverScreen({super.key, required this.controller});

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
              const SizedBox(height: 32),
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

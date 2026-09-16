import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../state/game_controller.dart';
import '../state/high_scores.dart';
import 'game_screen.dart';

class SetupScreen extends StatefulWidget {
  final GameController controller;

  const SetupScreen({super.key, required this.controller});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _botCount = 2;
  BotDifficulty _difficulty = BotDifficulty.medium;

  static const _botNames = ['Rosalind', 'Bertram', 'Wilhelmina'];

  Future<void> _start() async {
    final players = [
      const PlayerSetup(name: 'You', isBot: false),
      for (var i = 0; i < _botCount; i++)
        PlayerSetup(name: _botNames[i], isBot: true, difficulty: _difficulty),
    ];
    final navigator = Navigator.of(context);
    await widget.controller.startNewGame(
      seed: DateTime.now().millisecondsSinceEpoch,
      players: players,
    );
    if (!mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameScreen(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2E4034),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('New Game'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Rivals',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1 bot')),
                ButtonSegment(value: 2, label: Text('2 bots')),
                ButtonSegment(value: 3, label: Text('3 bots')),
              ],
              selected: {_botCount},
              onSelectionChanged: (s) => setState(() => _botCount = s.first),
            ),
            const SizedBox(height: 24),
            const Text('Difficulty',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 12),
            SegmentedButton<BotDifficulty>(
              segments: const [
                ButtonSegment(
                    value: BotDifficulty.easy, label: Text('Easy')),
                ButtonSegment(
                    value: BotDifficulty.medium, label: Text('Fair')),
                ButtonSegment(
                    value: BotDifficulty.hard, label: Text('Cruel')),
              ],
              selected: {_difficulty},
              onSelectionChanged: (s) =>
                  setState(() => _difficulty = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              'Score ×${difficultyMultiplier([
                for (var i = 0; i < _botCount; i++)
                  PlayerState(
                      id: i,
                      name: '',
                      isBot: true,
                      difficulty: _difficulty),
              ]).toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.amber, fontSize: 13),
            ),
            const SizedBox(height: 40),
            FilledButton(
              onPressed: _start,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              ),
              child: const Text('Begin', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

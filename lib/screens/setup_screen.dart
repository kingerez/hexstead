import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../state/game_controller.dart';
import 'game_screen.dart';

class SetupScreen extends StatefulWidget {
  final GameController controller;

  const SetupScreen({super.key, required this.controller});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _botCount = 2;

  static const _botNames = ['Rosalind', 'Bertram', 'Wilhelmina'];

  Future<void> _start() async {
    final players = [
      const PlayerSetup(name: 'You', isBot: false),
      for (var i = 0; i < _botCount; i++)
        PlayerSetup(name: _botNames[i], isBot: true),
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

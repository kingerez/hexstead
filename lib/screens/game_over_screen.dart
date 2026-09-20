import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../art/art_store.dart';
import '../audio/sound_store.dart';
import '../board/board_painter.dart';
import '../state/game_controller.dart';
import '../state/high_scores.dart';
import '../widgets/hex_confetti.dart';
import '../widgets/resource_icon.dart';
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
  int _multiplier = 1;

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
    _multipliedScore = raw * _multiplier;
    final bots = state.players.where((p) => p.isBot).toList();
    final isBest = await HighScoreStore().record(ScoreEntry(
      score: raw,
      multiplier: _multiplier.toDouble(),
      finalScore: _multipliedScore,
      botSummary: '${bots.length} bots · ${bots.first.difficulty.name}',
      date: DateTime.now(),
    ));
    if (mounted) setState(() => _newBest = isBest);
  }

  /// One scoreboard row: final total plus the revealed secret objective.
  /// [highlight] backs the row in the player's color - used to point at the
  /// winner when it is not you.
  Widget _playerRow(GameState state, PlayerState p, {bool highlight = false}) {
    final objective = objectiveCatalog[p.objectiveId];
    final complete = objective?.isComplete(state, p.id) ?? false;
    final color = BoardPainter.playerColors[p.id];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: highlight
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
            : EdgeInsets.zero,
        decoration: highlight
            ? BoxDecoration(
                color: color.withValues(alpha: 0.22),
                border: Border.all(color: color, width: 1.5),
                borderRadius: BorderRadius.circular(14),
              )
            : null,
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 12, color: color),
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
              Text.rich(
                TextSpan(
                  children: complete
                      ? [
                          taskSpan(12),
                          TextSpan(
                              text: ' ${objective.name} fulfilled '
                                  '(+${objective.bonusVp})'),
                        ]
                      : [TextSpan(text: '✗ ${objective.name} unfulfilled')],
                ),
                style: TextStyle(
                  color: complete ? Colors.amber : Colors.white38,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Full-bleed backdrops, one per outcome; missing art leaves the flat
  /// green behind.
  static const _victoryBg = 'assets/images/ui/bg_victory.png';
  static const _defeatBg = 'assets/images/ui/bg_defeat.png';

  @override
  Widget build(BuildContext context) {
    final state = controller.state!;
    final winner = state.players[state.winnerId!];
    final humanWon = !winner.isBot;
    final ranked = [...state.players]
      ..sort((a, b) =>
          finalScoreFor(state, b.id).compareTo(finalScoreFor(state, a.id)));
    final bgPath = humanWon ? _victoryBg : _defeatBg;
    final hasArt = ArtStore.instance.has(bgPath);

    return Scaffold(
      backgroundColor: const Color(0xFF2E4034),
      // Art, scrim, confetti, scoreboard - in that order, so the falling
      // hexes stay behind the text and the text stays readable over the art.
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (hasArt) ...[
            Positioned.fill(
              child: Image.asset(bgPath, fit: BoxFit.cover),
            ),
            // Heavier than the setup screen's: this page is all small white
            // text, and it runs the full height of the art.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (humanWon) const Positioned.fill(child: HexConfetti()),
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Scaled down rather than wrapped: the headline is one line
                  // however narrow the phone.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        humanWon ? 'Victory!' : 'The realm slips away',
                        style: TextStyle(
                          color: humanWon
                              ? const Color(0xFFFFCA28)
                              : Colors.white54,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  for (final p in ranked)
                    _playerRow(state, p,
                        highlight: !humanWon && p.id == winner.id),
                  const SizedBox(height: 18),
                  Text(
                    'Your score ×$_multiplier difficulty bonus '
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
                    onPressed: () {
                      SoundStore.instance.startMusic(MusicTrack.menu);
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                    child: const Text('Menu'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

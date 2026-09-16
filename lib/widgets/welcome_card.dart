import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

/// Game-start overlay: dims the fresh board and briefs the player — the win
/// conditions and their secret goal — then hands off via [onStart].
class WelcomeOverlay extends StatelessWidget {
  final GameState state;
  final VoidCallback onStart;

  const WelcomeOverlay({super.key, required this.state, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final human = state.players.firstWhere((p) => !p.isBot);
    final objective = objectiveCatalog[human.objectiveId];
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        alignment: const Alignment(0, -0.55),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Card(
          color: const Color(0xFFF4EAD4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome to Hexstead',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3A2E20),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'First to ${state.targetVp} points wins — or the richest '
                  'realm when round ${state.roundCap} ends.',
                  style: const TextStyle(
                      fontSize: 15, color: Color(0xFF3A2E20)),
                ),
                if (objective != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7D9B8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🎯 Your secret goal: ${objective.name}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFF3A2E20),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${objective.description} Pull it off for '
                          '${objective.bonusVp} bonus points at game end — '
                          'your rivals can\'t see it.',
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xFF5A4A34)),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: onStart,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 36, vertical: 12),
                    ),
                    child: const Text('Start', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

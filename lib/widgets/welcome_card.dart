import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

/// Game-start overlay: dims the fresh board and briefs the player - the win
/// conditions and their secret goal - then hands off via [onStart].
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
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Card(
          color: const Color(0xFFF4EAD4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Welcome to Hexstead',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3A2E20),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'First to ${state.targetVp} points wins - or the richest '
                  'realm when round ${state.roundCap} ends.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: Color(0xFF3A2E20),
                  ),
                ),
                if (objective != null) ...[
                  const SizedBox(height: 28),
                  _goalPanel(objective),
                ],
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: onStart,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Start', style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _goalPanel(ObjectiveSpec objective) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: const Color(0xFFE7D9B8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Stack(
          children: [
            // Oversized target watermark behind the text.
            const Positioned(
              right: -30,
              top: -34,
              child: Opacity(
                opacity: 0.15,
                child: Text('🎯', style: TextStyle(fontSize: 130)),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR SECRET GOAL - ${objective.name.toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: Color(0xFF7A6647),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  objective.description,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3A2E20),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Bonus: ${objective.bonusVp} points',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF9A6B1F),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

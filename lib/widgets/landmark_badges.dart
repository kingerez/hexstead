import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import 'chrome.dart';

/// Placeholder "art" per landmark until the generated set lands.
const landmarkEmoji = {
  'high_roller': '🎲',
  'trade_post': '⚖️',
  'cheap_claims': '📜',
  'bandit_ward': '🛡️',
  'granary': '🌾',
  'lumber_mill': '🪚',
  'deep_mine': '⛏️',
  'kiln': '🔥',
  'cathedral': '⛪',
  'market_hall': '🏪',
  'watchtower': '🗼',
  'keep': '🏰',
};

/// How many emoji a chip shows before falling back to a count. Real games
/// end with 0-4 landmarks each; the cap only guards a narrow screen.
const _badgeCap = 5;

/// The emoji strip under a score chip: what this player has built. Keyed
/// rather than found by glyph, since emoji rendering is no test's business.
class LandmarkBadgeRow extends StatelessWidget {
  final List<String> landmarkIds;
  final int playerId;

  const LandmarkBadgeRow({
    super.key,
    required this.landmarkIds,
    required this.playerId,
  });

  @override
  Widget build(BuildContext context) {
    final shown = landmarkIds.take(_badgeCap);
    final extra = landmarkIds.length - shown.length;
    return Text(
      '${shown.map((id) => landmarkEmoji[id] ?? '🏛').join()}'
      '${extra > 0 ? ' +$extra' : ''}',
      key: ValueKey('landmark-badges-$playerId'),
      style: const TextStyle(fontSize: 10, color: Colors.white),
    );
  }
}

/// What a tapped score chip opens: the player's landmarks spelled out, name
/// and power each. Tap outside to close.
class LandmarkPopup extends StatelessWidget {
  final PlayerState player;
  final VoidCallback onClose;

  const LandmarkPopup({
    super.key,
    required this.player,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: GestureDetector(
              onTap: () {}, // absorb taps on the panel itself
              child: Container(
                constraints: const BoxConstraints(maxWidth: 340),
                padding: const EdgeInsets.all(14),
                decoration: parchmentPanel(
                  radius: 14,
                  shadows: const [
                    BoxShadow(
                        color: Colors.black45,
                        blurRadius: 10,
                        offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${player.isBot ? player.name : 'You'} - Landmarks',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3A2E20),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Bounded height: four landmarks with descriptions
                    // outgrow a short screen.
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final id in player.landmarkIds) _row(id),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String id) {
    final spec = landmarkCatalog[id];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(landmarkEmoji[id] ?? '🏛', style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec?.name ?? id,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3A2E20),
                  ),
                ),
                if (spec != null)
                  Text(
                    spec.description,
                    style: const TextStyle(
                        fontSize: 12, height: 1.25, color: Color(0xFF5A4A34)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../art/art_store.dart';

/// The landmark shop as a 2x2 spread of art cards. Tap outside to close;
/// affordable landmarks carry a live Buy button.
class ShopOverlay extends StatelessWidget {
  final GameState state;
  final Set<String> buyableIds;
  final void Function(String landmarkId) onBuy;
  final VoidCallback onClose;

  const ShopOverlay({
    super.key,
    required this.state,
    required this.buyableIds,
    required this.onBuy,
    required this.onClose,
  });

  /// Placeholder "art" per landmark until the generated set lands.
  static const landmarkEmoji = {
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

  static const _resourceEmoji = {
    Resource.wood: '🪵',
    Resource.grain: '🌾',
    Resource.brick: '🧱',
    Resource.stone: '🪨',
  };

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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Landmarks for sale',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Permanent powers - first come, first served',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  if (state.landmarkOffer.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('All sold out.',
                          style: TextStyle(color: Colors.white70)),
                    )
                  else
                    // Flexible + scroll view: on narrow screens the Wrap
                    // stacks one card per row and would run off the bottom.
                    Flexible(
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final id in state.landmarkOffer) _card(id),
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
    );
  }

  Widget _card(String id) {
    final spec = landmarkCatalog[id]!;
    final buyable = buyableIds.contains(id);
    return Container(
      width: 172,
      height: 196,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF4EAD4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF8A6F4D), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Stack(
        children: [
          // Big faded art in the background (generated art drops in here).
          Positioned(
            right: -18,
            bottom: -6,
            child: Opacity(
              opacity: 0.18,
              child: ArtStore.instance.image(
                'assets/images/landmarks/lm_$id.png',
                width: 130,
                height: 130,
                fit: BoxFit.contain,
                placeholder: Text(landmarkEmoji[id] ?? '🏛',
                    style: const TextStyle(fontSize: 110)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        spec.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3A2E20),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9A6B1F),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('+${spec.vp}pt',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    spec.description,
                    style: const TextStyle(
                        fontSize: 12, height: 1.25, color: Color(0xFF5A4A34)),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7D9B8),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: const Color(0xFF8A6F4D), width: 1),
                  ),
                  // Label above, resources below: a three-resource cost has
                  // the full card width to itself instead of wrapping
                  // mid-list beside a vertically centred "Cost:".
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cost:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Color(0xFF7A6647),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        spec.cost.entries
                            .map((e) => '${e.value} ${_resourceEmoji[e.key]}')
                            .join('   '),
                        maxLines: 1,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF3A2E20)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: FilledButton(
                    onPressed: buyable ? () => onBuy(id) : null,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    child: Text(buyable ? 'Buy' : 'Can\'t afford'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

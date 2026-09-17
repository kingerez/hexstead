import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

/// Bank trade as a centered card: one row per resource you can sell, with
/// a button for each resource you could buy with it.
class TradeOverlay extends StatelessWidget {
  final GameState state;

  /// The trades that are legal right now.
  final List<BankTrade> legalTrades;
  final void Function(BankTrade) onTrade;
  final VoidCallback onClose;

  const TradeOverlay({
    super.key,
    required this.state,
    required this.legalTrades,
    required this.onTrade,
    required this.onClose,
  });

  static const _resourceEmoji = {
    Resource.wood: '🪵',
    Resource.grain: '🌾',
    Resource.brick: '🧱',
    Resource.stone: '🪨',
  };

  @override
  Widget build(BuildContext context) {
    final human = state.players.firstWhere((p) => !p.isBot);
    final rate = Rules.effectiveTradeRate(human);
    final sellable =
        legalTrades.map((t) => t.give).toSet().toList()
          ..sort((a, b) => a.index.compareTo(b.index));

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(20),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 340,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4EAD4),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF8A6F4D), width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bank trade  ·  $rate:1',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3A2E20),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (sellable.isEmpty)
                      Text(
                        'You need at least $rate of one resource to trade '
                        'with the bank.',
                        style: const TextStyle(color: Color(0xFF5A4A34)),
                      )
                    else
                      for (final give in sellable) ...[
                        Text(
                          'Sell $rate ${_resourceEmoji[give]} to buy:',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3A2E20),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final t in legalTrades)
                              if (t.give == give)
                                FilledButton.tonal(
                                  onPressed: () => onTrade(t),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                  ),
                                  child: Text(
                                    '${_resourceEmoji[t.get]} +1',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

/// Bank trade in two steps: pick which resource to sell (only ones you hold
/// enough of are shown), then pick what to buy with it.
class TradeOverlay extends StatefulWidget {
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

  @override
  State<TradeOverlay> createState() => _TradeOverlayState();
}

class _TradeOverlayState extends State<TradeOverlay> {
  Resource? _give;

  static const _resourceEmoji = {
    Resource.wood: '🪵',
    Resource.grain: '🌾',
    Resource.brick: '🧱',
    Resource.stone: '🪨',
  };

  @override
  Widget build(BuildContext context) {
    final human = widget.state.players.firstWhere((p) => !p.isBot);
    final rate = Rules.effectiveTradeRate(human);
    final sellable = widget.legalTrades.map((t) => t.give).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (_give != null && !sellable.contains(_give)) _give = null;

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
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
                  border:
                      Border.all(color: const Color(0xFF8A6F4D), width: 2),
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
                        Resource.values
                                .any((r) => human.countOf(r) >= rate)
                            ? 'Finish resolving the dice first - then you '
                                'can trade.'
                            : 'You need at least $rate of one resource to '
                                'trade with the bank.',
                        style: const TextStyle(color: Color(0xFF5A4A34)),
                      )
                    else ...[
                      Text(
                        'Sell $rate of:',
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
                          for (final give in sellable)
                            _sellChip(give, human.countOf(give)),
                        ],
                      ),
                      if (_give != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Sell $rate ${_resourceEmoji[_give]} to buy:',
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
                            for (final t in widget.legalTrades)
                              if (t.give == _give)
                                FilledButton.tonal(
                                  onPressed: () => widget.onTrade(t),
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
                      ],
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

  Widget _sellChip(Resource give, int count) {
    final selected = _give == give;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => setState(() => _give = selected ? null : give),
      showCheckmark: false,
      selectedColor: const Color(0xFF9A6B1F),
      backgroundColor: const Color(0xFFE7D9B8),
      side: const BorderSide(color: Color(0xFF8A6F4D)),
      label: Text(
        '${_resourceEmoji[give]}  $count',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : const Color(0xFF3A2E20),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

/// Bottom sheet for the landmark market: the shared offer plus what each
/// player already owns.
class LandmarkSheet extends StatelessWidget {
  final GameState state;

  const LandmarkSheet({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final legal = legalActions(state).whereType<BuyLandmark>().toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Landmarks for sale',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (state.landmarkOffer.isEmpty) const Text('All sold out.'),
            for (final id in state.landmarkOffer)
              _offerTile(context, id, legal),
            for (final p in state.players)
              if (p.landmarkIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${p.name}: ${p.landmarkIds.map((id) => landmarkCatalog[id]!.name).join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  static const _resourceEmoji = {
    Resource.wood: '🪵',
    Resource.grain: '🌾',
    Resource.brick: '🧱',
    Resource.stone: '🪨',
  };

  Widget _offerTile(BuildContext context, String id, List<BuyLandmark> legal) {
    final spec = landmarkCatalog[id]!;
    final buyable = legal.any((a) => a.landmarkId == id);
    final cost = spec.cost.entries
        .map((e) => '${e.value}${_resourceEmoji[e.key]}')
        .join(' ');
    return Card(
      child: ListTile(
        title: Text('${spec.name}  ·  $cost'),
        subtitle: Text('${spec.description}  (+${spec.vp} pt)'),
        trailing: buyable
            ? FilledButton(
                onPressed: () => Navigator.pop(context, BuyLandmark(id)),
                child: const Text('Buy'),
              )
            : null,
        enabled: buyable,
      ),
    );
  }
}

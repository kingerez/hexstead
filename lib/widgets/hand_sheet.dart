import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

/// Bottom sheet showing the player's action cards. Returns the chosen
/// PlayCard when it needs no board target, or a "pending" PlayCard whose
/// targetHex is null for cards that want a tile tapped next.
class HandSheet extends StatelessWidget {
  final GameState state;

  const HandSheet({super.key, required this.state});

  static const _needsHexTarget = {'drought', 'charter', 'banish', 'brigand'};

  @override
  Widget build(BuildContext context) {
    final player = state.currentPlayer;
    final legal = legalActions(state).whereType<PlayCard>().toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your cards',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (player.hand.isEmpty)
              const Text('No cards left.'),
            for (final cardId in player.hand)
              _cardTile(context, cardId, legal),
          ],
        ),
      ),
    );
  }

  Widget _cardTile(BuildContext context, String cardId, List<PlayCard> legal) {
    final spec = cardCatalog[cardId]!;
    final playable = legal.any((a) => a.cardId == cardId);
    return Card(
      child: ListTile(
        title: Text(spec.name),
        subtitle: Text(spec.description),
        trailing: playable
            ? FilledButton(
                onPressed: () => _play(context, cardId, legal),
                child: const Text('Play'),
              )
            : null,
        enabled: playable,
      ),
    );
  }

  void _play(BuildContext context, String cardId, List<PlayCard> legal) {
    final options = legal.where((a) => a.cardId == cardId).toList();
    if (_needsHexTarget.contains(cardId)) {
      // Hand back a marker action; the game screen enters tap-a-tile mode.
      Navigator.pop(context, PlayCard(cardId));
      return;
    }
    if (cardId == 'cutpurse' && options.length > 1) {
      _pickOption(context, 'Steal from…',
          [for (final o in options) (state.players[o.targetPlayer!].name, o)]);
      return;
    }
    if (cardId == 'bounty') {
      _pickOption(context, 'Take 2 of…',
          [for (final o in options) (o.resource!.name, o)]);
      return;
    }
    if (cardId == 'omen') {
      final (d1, d2) = state.lastDice!;
      _pickOption(context, 'Shift a die', [
        for (final o in options)
          ('die ${o.dieIndex == 0 ? d1 : d2} ${o.delta! > 0 ? '+1' : '-1'}', o),
      ]);
      return;
    }
    Navigator.pop(context, options.first);
  }

  void _pickOption(
      BuildContext context, String title, List<(String, PlayCard)> options) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          for (final (label, action) in options)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pop(context, action);
              },
              child: Text(label),
            ),
        ],
      ),
    );
  }
}

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

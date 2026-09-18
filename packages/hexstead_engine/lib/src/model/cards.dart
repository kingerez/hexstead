import 'package:meta/meta.dart';

/// When a card may be played.
enum CardTiming { diceChoice, main }

@immutable
class CardSpec {
  final String id;
  final String name;
  final String description;
  final CardTiming timing;

  const CardSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.timing,
  });
}

/// Numbers considered "hot" by the harvest card (4+ ways to roll on 2d6).
const harvestNumbers = {5, 6, 8, 9};

/// Copies of each card in the deal deck.
const cardCopies = 2;

/// Cards dealt to each player at setup.
const startingHandSize = 3;

/// Rounds whose start deals every player one card.
const refillRounds = {5, 10};

const cardCatalog = <String, CardSpec>{
  'second_chance': CardSpec(
    id: 'second_chance',
    name: 'Second Chance',
    description: 'Reroll both dice.',
    timing: CardTiming.diceChoice,
  ),
  'omen': CardSpec(
    id: 'omen',
    name: 'Omen',
    description: 'Shift one die up or down by 1.',
    timing: CardTiming.diceChoice,
  ),
  'drought': CardSpec(
    id: 'drought',
    name: 'Drought',
    description: 'A tile produces nothing this round and next.',
    timing: CardTiming.main,
  ),
  'charter': CardSpec(
    id: 'charter',
    name: 'Royal Charter',
    description: 'Claim any free tile, no matter how far (normal cost).',
    timing: CardTiming.main,
  ),
  'cutpurse': CardSpec(
    id: 'cutpurse',
    name: 'Cutpurse',
    description: 'Steal a random resource from a rival.',
    timing: CardTiming.main,
  ),
  'bounty': CardSpec(
    id: 'bounty',
    name: 'Bounty',
    description: 'Take 2 resources of one kind from the bank.',
    timing: CardTiming.main,
  ),
  'banish': CardSpec(
    id: 'banish',
    name: 'Banish',
    description: 'Chase the bandit off one of your tiles for free.',
    timing: CardTiming.main,
  ),
  'brigand': CardSpec(
    id: 'brigand',
    name: 'Brigand',
    description: 'Move the bandit onto any claimed tile.',
    timing: CardTiming.main,
  ),
  'harvest': CardSpec(
    id: 'harvest',
    name: 'Harvest Feast',
    description: 'Your tiles numbered 5, 6, 8 or 9 produce right now.',
    timing: CardTiming.main,
  ),
  'tithe': CardSpec(
    id: 'tithe',
    name: 'Tithe',
    description: 'Every rival hands you one random resource.',
    timing: CardTiming.main,
  ),
};

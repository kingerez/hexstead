import 'package:flutter/foundation.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import 'tutorial_scenario.dart';

/// A piece of chrome the current step is pointing at: it glows, and it is
/// the only one of its kind the player can touch.
enum TutorialTarget {
  rollButton,
  sumButton,
  splitButton,
  endTurnButton,
  cardsButton,
  shopButton,
  tradeButton,
  taskChip,
}

/// Things the player does that the engine never hears about.
enum TutorialUiSignal { fanOpened, shopOpened, tradeOpened, next }

/// Set once the first-run "New to Hexstead?" offer has been made, however it
/// was answered. The menu reads it; the menu and the tutorial's last step
/// both write it.
const tutorialPromptSeenKey = 'tutorial_prompt_seen_v1';

/// One beat of the guided game: what the banner says, what glows, what the
/// player is allowed to do, and what finishes the lesson.
@immutable
class TutorialStep {
  final String id;

  /// Banner copy.
  final String text;

  /// Hexes wearing the amber claim glow while this step is up.
  final Set<Hex> highlightHexes;

  /// Chrome that glows and stays tappable; everything else goes dead.
  final Set<TutorialTarget> targets;

  /// The engine actions this step permits. Null means none at all.
  final bool Function(GameAction action)? allows;

  /// The one hex a tap may inspect (the inspect lesson only).
  final Hex? inspectHex;

  /// Keeps whatever tile the player has selected when this step opens.
  /// Steps normally clear it, so the inspector does not trail a stale hex
  /// from one lesson into the next - but the step that reads the inspector
  /// out loud needs the tile to stay put.
  final bool keepSelection;

  /// Explanation-only steps carry a Next button instead of a task.
  final bool showNext;

  /// Reads the facts the reducer just emitted; true advances the script.
  final bool Function(List<GameEvent> events, GameState state)?
      advanceOnEvents;

  /// Advances on a purely visual act - opening the hand, shop or trade.
  final TutorialUiSignal? advanceOnUi;

  const TutorialStep({
    required this.id,
    required this.text,
    this.highlightHexes = const {},
    this.targets = const {},
    this.allows,
    this.inspectHex,
    this.keepSelection = false,
    this.showNext = false,
    this.advanceOnEvents,
    this.advanceOnUi,
  });
}

/// Walks the player through [tutorialSteps], one beat at a time.
///
/// It never dispatches anything itself: it filters what the screen offers,
/// supplies the banner copy, and listens for the moment each lesson lands.
class TutorialDirector extends ChangeNotifier {
  final List<TutorialStep> steps;
  int _index = 0;

  TutorialDirector({List<TutorialStep>? steps})
      : steps = steps ?? tutorialSteps();

  /// The step the banner is showing. Once the script runs out this stays on
  /// the last one so the screen has something to draw while it pops.
  TutorialStep get current =>
      steps[_index < steps.length ? _index : steps.length - 1];

  bool get finished => _index >= steps.length;

  /// True on the closing beat, where Next becomes Finish.
  bool get isLastStep => _index == steps.length - 1;

  /// Zero-based position in the script, for tests.
  int get index => _index;

  /// Narrows the engine's legal moves down to the one lesson at hand.
  List<GameAction> filter(List<GameAction> actions) {
    if (finished) return const [];
    final allows = current.allows;
    if (allows == null) return const [];
    return actions.where(allows).toList();
  }

  /// Fed from the end of the screen's event presentation, so a step only
  /// turns over once its ceremony has finished playing.
  void notifyEvents(List<GameEvent> events, GameState state) {
    if (finished) return;
    final check = current.advanceOnEvents;
    if (check != null && check(events, state)) _advance();
  }

  void notifyUi(TutorialUiSignal signal) {
    if (finished) return;
    if (current.advanceOnUi == signal) _advance();
  }

  void notifyHexInspected(Hex hex) {
    if (finished) return;
    if (current.inspectHex == hex) _advance();
  }

  void _advance() {
    _index += 1;
    notifyListeners();
  }
}

/// True when [events] carries at least one fact of type [T].
bool _saw<T extends GameEvent>(List<GameEvent> events) =>
    events.whereType<T>().isNotEmpty;

/// The script. Twenty-five beats from "these are hexes" to "go win one".
List<TutorialStep> tutorialSteps() => [
      TutorialStep(
        id: 'welcome',
        text: 'Nineteen hexes make a realm. Each has a terrain and a '
            'number. The glowing forest is your camp - and an 8.',
        highlightHexes: {TutorialScenario.homeCamp},
        showNext: true,
        advanceOnUi: TutorialUiSignal.next,
      ),
      TutorialStep(
        id: 'inspect',
        text: 'Tap the mountain at the heart of the map to see what any '
            'hex holds.',
        highlightHexes: {TutorialScenario.inspectTarget},
        inspectHex: TutorialScenario.inspectTarget,
      ),
      TutorialStep(
        id: 'inspectRead',
        text: 'The panel below tells all: what a hex is, what it pays, how '
            'often its number turns up - and who holds it, if anyone.',
        keepSelection: true,
        showNext: true,
        advanceOnUi: TutorialUiSignal.next,
      ),
      TutorialStep(
        id: 'roll1',
        text: 'Two dice open every turn. Roll them.',
        targets: const {TutorialTarget.rollButton},
        allows: (a) => a is RollDice,
        advanceOnEvents: (events, _) => _saw<DiceRolled>(events),
      ),
      TutorialStep(
        id: 'sum',
        text: 'Three and five. Take the Sum - 8 - and your camp pays you '
            'a wood.',
        targets: const {TutorialTarget.sumButton},
        allows: (a) => a is ChooseActivation && a.mode == ActivationMode.sum,
        advanceOnEvents: (events, _) => _saw<ActivationChosen>(events),
      ),
      TutorialStep(
        id: 'claim',
        text: 'Land is how you score. Tap the glowing hill beside your camp, '
            'then press Claim below - 1 wood and 1 brick.',
        highlightHexes: {TutorialScenario.claimTarget},
        allows: (a) =>
            a is ClaimHex && a.target == TutorialScenario.claimTarget,
        advanceOnEvents: (events, _) => _saw<HexClaimed>(events),
      ),
      TutorialStep(
        id: 'endTurn1',
        text: 'Roll, resolve, build - that is a turn. End yours and let '
            'Bertram have his.',
        targets: const {TutorialTarget.endTurnButton},
        allows: (a) => a is EndTurn,
        advanceOnEvents: (events, _) => _saw<TurnEnded>(events),
      ),
      TutorialStep(
        id: 'botTurn1',
        text: 'Bertram rolls and claims land just as you do. Watch him '
            'work.',
        advanceOnEvents: (events, _) => _saw<TurnEnded>(events),
      ),
      TutorialStep(
        id: 'roll2',
        text: 'Round two, and the realm is yours again. Roll.',
        targets: const {TutorialTarget.rollButton},
        allows: (a) => a is RollDice,
        advanceOnEvents: (events, _) => _saw<DiceRolled>(events),
      ),
      TutorialStep(
        id: 'split',
        text: 'Two and four. Sum 6 pays nobody - but Split them and your '
            'new hill, a 4, yields brick.',
        targets: const {TutorialTarget.splitButton},
        allows: (a) => a is ChooseActivation && a.mode == ActivationMode.split,
        advanceOnEvents: (events, _) => _saw<ActivationChosen>(events),
      ),
      TutorialStep(
        id: 'cardsOpen',
        text: 'You keep three action cards up your sleeve. Tap your hand '
            'to look them over.',
        targets: const {TutorialTarget.cardsButton},
        allows: _allowsBounty,
        advanceOnUi: TutorialUiSignal.fanOpened,
      ),
      TutorialStep(
        id: 'cardsPlay',
        text: 'Play the Bounty and take 2 grain from the bank. One card '
            'per turn, no more.',
        allows: _allowsBounty,
        advanceOnEvents: (events, _) => _saw<CardPlayed>(events),
      ),
      TutorialStep(
        id: 'endTurn2',
        text: 'Grain in the barn. End your turn.',
        targets: const {TutorialTarget.endTurnButton},
        allows: (a) => a is EndTurn,
        advanceOnEvents: (events, _) => _saw<TurnEnded>(events),
      ),
      TutorialStep(
        id: 'botTurn2',
        text: 'Rival rolls pay you too - Bertram\'s 4 makes your hill '
            'produce.',
        advanceOnEvents: (events, _) => _saw<TurnEnded>(events),
      ),
      TutorialStep(
        id: 'roll3',
        text: 'One more roll.',
        targets: const {TutorialTarget.rollButton},
        allows: (a) => a is RollDice,
        advanceOnEvents: (events, _) => _saw<DiceRolled>(events),
      ),
      TutorialStep(
        id: 'seven',
        text: 'Seven! No hex ever pays on a seven - it summons the bandit '
            'instead.',
        targets: const {TutorialTarget.sumButton},
        allows: (a) => a is ChooseActivation && a.mode == ActivationMode.sum,
        advanceOnEvents: (_, state) => state.phase == Phase.awaitingBandit,
      ),
      TutorialStep(
        id: 'placeBandit',
        text: 'Drop him on Bertram\'s camp. While he squats there, that '
            'hex produces nothing.',
        highlightHexes: {TutorialScenario.rivalCamp},
        allows: (a) =>
            a is PlaceBandit && a.target == TutorialScenario.rivalCamp,
        advanceOnEvents: (events, _) => _saw<BanditPlaced>(events),
      ),
      TutorialStep(
        id: 'shopOpen',
        text: 'Landmarks are permanent works - a point apiece, and a power '
            'besides. Open the shop.',
        targets: const {TutorialTarget.shopButton},
        allows: _allowsMarketHall,
        advanceOnUi: TutorialUiSignal.shopOpened,
      ),
      TutorialStep(
        id: 'buyLandmark',
        text: 'Buy the Market Hall: 2 wood and 2 grain now, a grain every '
            'turn after.',
        allows: _allowsMarketHall,
        advanceOnEvents: (events, _) => _saw<LandmarkPurchased>(events),
      ),
      TutorialStep(
        id: 'objective',
        text: 'Every realm keeps a secret task. Yours is the King\'s Road '
            '- 3 hexes in a straight line - and you stand at 2.',
        targets: const {TutorialTarget.taskChip},
        showNext: true,
        advanceOnUi: TutorialUiSignal.next,
      ),
      TutorialStep(
        id: 'tradeOpen',
        text: 'The bank takes 3 of a kind for any 1 you please. Open the '
            'trade.',
        targets: const {TutorialTarget.tradeButton},
        allows: _allowsBrickForStone,
        advanceOnUi: TutorialUiSignal.tradeOpened,
      ),
      TutorialStep(
        id: 'trade',
        text: 'Sell your 3 brick and take a stone for them.',
        allows: _allowsBrickForStone,
        advanceOnEvents: (events, _) => _saw<TradeCompleted>(events),
      ),
      TutorialStep(
        id: 'endTurn3',
        text: 'End your turn, and watch the bandit earn his keep.',
        targets: const {TutorialTarget.endTurnButton},
        allows: (a) => a is EndTurn,
        advanceOnEvents: (events, _) => _saw<TurnEnded>(events),
      ),
      TutorialStep(
        id: 'botBandit',
        text: 'Bertram rolls his 5 - and the bandit eats it. Now it costs '
            'him 2 resources to be rid of the man.',
        advanceOnEvents: (events, _) => _saw<BanditRemoved>(events),
      ),
      TutorialStep(
        id: 'closing',
        text: 'That is the whole of it. Reach 15 points and the realm is '
            'yours on the spot - else the richest realm wins when round 15 '
            'turns. The glowing forest would finish your King\'s Road. Go '
            'and take a realm of your own.',
        highlightHexes: {TutorialScenario.roadFinisher},
        showNext: true,
        advanceOnUi: TutorialUiSignal.next,
      ),
    ];

bool _allowsBounty(GameAction a) =>
    a is PlayCard && a.cardId == 'bounty' && a.resource == Resource.grain;

bool _allowsMarketHall(GameAction a) =>
    a is BuyLandmark && a.landmarkId == 'market_hall';

bool _allowsBrickForStone(GameAction a) =>
    a is BankTrade && a.give == Resource.brick && a.get == Resource.stone;

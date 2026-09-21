import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../art/art_store.dart';
import '../audio/sound_store.dart';
import '../board/board_geometry.dart';
import '../board/board_painter.dart';
import '../board/board_widget.dart';
import '../widgets/adjust_die_dialog.dart';
import '../widgets/bandit_fly_overlay.dart';
import '../widgets/bot_card_overlay.dart';
import '../widgets/card_fan_overlay.dart';
import '../widgets/chrome.dart';
import '../widgets/dice_roll_overlay.dart';
import '../widgets/game_end_overlay.dart';
import '../widgets/match_point_overlay.dart';
import '../widgets/option_picker_dialog.dart';
import '../widgets/resource_icon.dart';
import '../widgets/settings_overlay.dart';
import '../widgets/shop_overlay.dart';
import '../widgets/task_reveal_overlay.dart';
import '../widgets/trade_overlay.dart';
import '../widgets/production_overlay.dart';
import '../widgets/tile_inspector.dart';
import '../widgets/turn_splash_overlay.dart';
import '../widgets/tutorial_banner.dart';
import '../widgets/welcome_card.dart';
import '../state/game_controller.dart';
import '../tutorial/tutorial_director.dart';
import 'game_over_screen.dart';

class GameScreen extends StatefulWidget {
  final GameController controller;

  /// Non-null runs the board in guided mode: the director narrows what the
  /// player may do and narrates each step.
  final TutorialDirector? tutorial;

  const GameScreen({super.key, required this.controller, this.tutorial});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

/// Free band kept under the board: the grid sits high and the strip below
/// it stays clear for the bottom chrome.
const double _boardBottomReserve = 282;

/// How near the victory target counts as match point: within this many
/// points, a player is called out and their score chip goes crimson.
const int _matchPointRange = 3;

/// How many points short of victory [playerId] stands while inside match
/// point range, else null. Live scores only - the secret-objective bonus is
/// nobody's business until the game ends.
int? _matchPointStep(GameState state, int playerId) {
  final away = state.targetVp - scoreFor(state, playerId);
  return away >= 1 && away <= _matchPointRange ? away : null;
}

class _GameScreenState extends State<GameScreen> {
  Hex? _selected;
  bool _navigatedToGameOver = false;

  /// A card awaiting a tile tap (drought/charter/brigand).
  String? _pendingCardId;

  /// Dice currently tumbling on screen; the game waits until they settle.
  (int, int)? _rollingDice;
  Duration _rollDuration = Duration.zero;
  Duration _holdDuration = Duration.zero;
  Completer<void>? _rollCompleter;

  /// Bandit fly-in target; the game waits until it lands.
  Hex? _banditFlyTarget;
  Completer<void>? _banditCompleter;

  /// Production payout being floated over the board right now.
  (
    List<ProductionGrant>,
    String,
    List<({int playerId, Resource resource})>
  )? _production;
  Completer<void>? _productionCompleter;

  /// Bot card play being revealed; the game waits until it fades.
  CardPlayed? _botCardPlay;
  Completer<void>? _botCardCompleter;

  /// Whose-turn splash on screen: (label, player color).
  (String, Color)? _turnSplash;
  Completer<void>? _turnSplashCompleter;

  /// Match-point warning on screen: (line, player color).
  (String, Color)? _matchPointWarning;
  Completer<void>? _matchPointCompleter;

  /// Closest proximity step already called out per player, so each step
  /// toward the target is announced once. Per screen, hence per game: a new
  /// game builds a new GameScreen.
  final Map<int, int> _announcedProximity = {};

  /// Game-end beat held over the board before the scoreboard: (line, whether
  /// it is your win to celebrate). Null once it has played.
  (String, bool)? _endMoment;

  /// Defensive: a screen that somehow mounts on a finished game skips the
  /// beat and goes straight to the scoreboard.
  bool _skipEndMoment = false;

  /// Board canvas size from the last layout, for overlay positioning.
  Size _boardSize = Size.zero;

  /// Game-start briefing: card shows 500ms after the board appears; the
  /// HUD stays tucked away until the player hits Start.
  bool _showWelcome = false;
  bool _hudVisible = true;

  /// Contextual tip balloon, on by default, toggleable, persisted.
  bool _tipsOn = true;

  GameController get controller => widget.controller;
  GameState get state => controller.state!;

  /// What the player may actually do right now. Identical to the engine's
  /// [legalActions] in a normal game; in the tutorial the director narrows
  /// it to the one move the current lesson is about. Every button, glow and
  /// tap target reads this, never [legalActions] directly, so gating the
  /// tutorial is one decision rather than a dozen.
  List<GameAction> get _allowed {
    final actions = legalActions(state);
    return widget.tutorial == null
        ? actions
        : widget.tutorial!.filter(actions);
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_onStateChanged);
    controller.eventDelegate = _presentEvents;
    widget.tutorial?.addListener(_onTutorialStep);
    SoundStore.instance.startMusic(MusicTrack.game);
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _tipsOn = prefs.getBool('tips_on') ?? true);
    });
    _skipEndMoment = state.phase == Phase.gameOver;
    // Seeded from the state we were handed: a resumed game only calls out
    // the steps this screen actually watches happen.
    for (final p in state.players) {
      final step = _matchPointStep(state, p.id);
      if (step != null) _announcedProximity[p.id] = step;
    }
    // The tutorial does its own briefing, one banner at a time.
    final fresh = widget.tutorial == null &&
        state.round == 1 &&
        state.diceHistory.isEmpty &&
        controller.isHumanTurn;
    if (fresh) {
      _hudVisible = false;
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _showWelcome = true);
      });
    }
  }

  /// Whether the card fan is on screen (game-start reveal or icon tap).
  bool _cardFanOpen = false;

  /// Game-start secret-task reveal: armed when the welcome card is
  /// dismissed, and it runs once the opening card fan is out of the way.
  bool _taskRevealPending = false;
  bool _taskRevealActive = false;

  /// Landmark shop, bank trade, and settings overlays.
  bool _shopOpen = false;
  bool _tradeOpen = false;
  bool _settingsOpen = false;

  /// Anchors for the fan's fly-to-icon animation and the task reveal's
  /// fly-to-chip one.
  final GlobalKey _screenStackKey = GlobalKey();
  final GlobalKey _cardIconKey = GlobalKey();
  final GlobalKey _taskChipKey = GlobalKey();

  /// Icon center relative to screen center: where the fan shrinks to.
  Offset _fanFlyOffset() {
    final stackBox =
        _screenStackKey.currentContext?.findRenderObject() as RenderBox?;
    final iconBox =
        _cardIconKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || iconBox == null || !iconBox.hasSize) {
      final size = MediaQuery.sizeOf(context);
      return Offset(size.width * 0.18, size.height * 0.38);
    }
    final iconCenter = iconBox.localToGlobal(
      iconBox.size.center(Offset.zero),
      ancestor: stackBox,
    );
    return iconCenter - stackBox.size.center(Offset.zero);
  }

  /// Task chip center in the root stack's space: where the reveal lands.
  Offset _taskFlyTarget() {
    final stackBox =
        _screenStackKey.currentContext?.findRenderObject() as RenderBox?;
    final chipBox =
        _taskChipKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || chipBox == null || !chipBox.hasSize) {
      final size = MediaQuery.sizeOf(context);
      return Offset(size.width * 0.22, size.height - 150);
    }
    return chipBox.localToGlobal(
      chipBox.size.center(Offset.zero),
      ancestor: stackBox,
    );
  }

  void _dismissWelcome() {
    setState(() {
      _showWelcome = false;
      _hudVisible = true;
      final human = state.players.firstWhere((p) => !p.isBot);
      _cardFanOpen = human.hand.isNotEmpty;
      // The task reveal queues behind the fan - one ceremony at a time - so
      // it only arms when there is a fan to dismiss.
      _taskRevealPending =
          _cardFanOpen && objectiveCatalog[human.objectiveId] != null;
    });
  }

  /// Executes a card chosen from the fan, mirroring the old sheet logic:
  /// direct plays dispatch, target cards enter tap-a-tile mode, and
  /// multi-option cards ask via a small dialog.
  Future<void> _handleCardPlay(String cardId) async {
    final options = _allowed
        .whereType<PlayCard>()
        .where((a) => a.cardId == cardId)
        .toList();
    if (options.isEmpty) return;
    // Banish is excluded: there is only one bandit, so its single legal
    // target needs no tap - it dispatches directly below.
    if (const {'drought', 'charter', 'brigand'}.contains(cardId)) {
      setState(() => _pendingCardId = cardId);
      return;
    }
    if (cardId == 'cutpurse' && options.length > 1) {
      await _pickOption('Steal from…', [
        for (final o in options)
          PickerOption(
            leading: PlayerSwatch(BoardPainter.playerColors[o.targetPlayer!]),
            label: state.players[o.targetPlayer!].name,
            value: o,
          ),
      ]);
      return;
    }
    if (cardId == 'bounty') {
      await _pickOption('Take 2 of…', [
        for (final o in options)
          PickerOption(
            // The HUD's resource art, same asset and same emoji fallback.
            leading: ResourceIcon(o.resource!, size: 22),
            label: capitalized(o.resource!.name),
            value: o,
          ),
      ]);
      return;
    }
    if (cardId == 'omen' && options.length > 1) {
      final (d1, d2) = state.lastDice!;
      final action = await showParchmentDialog<PlayCard>(
        context: context,
        builder: (_) => AdjustDieDialog(d1: d1, d2: d2, options: options),
      );
      if (action != null) await _tryDispatch(action);
      return;
    }
    await _tryDispatch(options.first);
  }

  /// Asks which of several plays of one card to make. Tapping outside
  /// answers nothing and dispatches nothing.
  Future<void> _pickOption(
      String title, List<PickerOption<PlayCard>> options) async {
    final action = await showOptionPicker<PlayCard>(
      context: context,
      title: title,
      options: options,
    );
    if (action != null) await _tryDispatch(action);
  }

  /// Buying the bandit off costs two resources off the top, so it asks
  /// first - and names the price it is about to take.
  Future<void> _confirmRemoveBandit(RemoveBandit action) async {
    final ok = await showConfirmDialog(
      context: context,
      title: 'Pay off the bandit?',
      message: 'Chase him off your land for:',
      body: ResourceCostRow(action.spend),
      confirmLabel: 'Pay',
    );
    if (ok == true) await _tryDispatch(action);
  }

  void _toggleTips() {
    setState(() => _tipsOn = !_tipsOn);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool('tips_on', _tipsOn));
  }

  @override
  void dispose() {
    controller.removeListener(_onStateChanged);
    widget.tutorial?.removeListener(_onTutorialStep);
    if (controller.eventDelegate == _presentEvents) {
      controller.eventDelegate = null;
    }
    super.dispose();
  }

  /// A lesson turned over: repaint, and drop any tile the previous step had
  /// the player inspecting so the inspector does not follow them around.
  /// The step that reads the inspector out loud opens right after the tap
  /// that filled it, so that one keeps the selection.
  void _onTutorialStep() {
    if (!mounted) return;
    setState(() {
      if (!widget.tutorial!.current.keepSelection) _selected = null;
    });
  }

  /// Closes the guided game: remembers that the offer was made, then walks
  /// back to the menu. The tutorial's own controller and its NullSaveStore
  /// go with the route - the real autosave was never touched.
  Future<void> _finishTutorial() async {
    final navigator = Navigator.of(context);
    SoundStore.instance.startMusic(MusicTrack.menu);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(tutorialPromptSeenKey, true);
    navigator.popUntil((r) => r.isFirst);
  }

  /// Awaited by the controller after every action: plays presentation
  /// animations (dice roll, bandit fly-in) for human and bot actions alike.
  Future<void> _presentEvents(List<GameEvent> events) async {
    if (!mounted) return;
    // A bot's card play is revealed before its consequences (re-rolls,
    // bandits, steals) animate. Human plays were seen in the hand fan.
    final cardPlays = events.whereType<CardPlayed>();
    if (cardPlays.isNotEmpty &&
        state.players[cardPlays.first.playerId].isBot) {
      final completer = Completer<void>();
      setState(() {
        _botCardPlay = cardPlays.first;
        _botCardCompleter = completer;
      });
      await completer.future;
    }
    if (!mounted) return;
    final rolls = events.whereType<DiceRolled>();
    if (rolls.isNotEmpty) {
      final roll = rolls.first;
      final isBot = state.currentPlayer.isBot;
      // Once every hex is claimed the game is about tempo - tighten the
      // dice ceremony so late rounds stop dragging.
      final boardFull = state.tiles.values.every((t) => t.ownerId != null);
      final completer = Completer<void>();
      SoundStore.instance.playSfx(Sfx.diceRoll);
      setState(() {
        _rollingDice = (roll.d1, roll.d2);
        _rollDuration = Duration(
            milliseconds: boardFull ? (isBot ? 450 : 800) : (isBot ? 800 : 1200));
        _holdDuration = Duration(
            milliseconds: boardFull ? (isBot ? 250 : 500) : (isBot ? 500 : 1000));
        _rollCompleter = completer;
      });
      await completer.future;
    }
    if (!mounted) return;
    // Payout moment: float the gains (or the whiff) after an activation.
    // The harvest card produces outside any roll, so it triggers the same
    // ceremony off its CardPlayed event.
    final chosen = events.whereType<ActivationChosen>();
    final harvestPlayed = cardPlays.any((c) => c.cardId == 'harvest');
    if (chosen.isNotEmpty || harvestPlayed) {
      final grants = [
        for (final e in events.whereType<ResourcesProduced>()) ...e.grants,
      ];
      var emptyMessage = '';
      if (harvestPlayed && chosen.isEmpty) {
        emptyMessage = 'The harvest came up empty';
      } else if (chosen.isNotEmpty) {
        final numbers = chosen.first.activatedNumbers;
        // Distinguish "the number isn't on the board" from "nobody owns it".
        final numbersOnBoard = state.tiles.values
            .any((t) => t.number != null && numbers.contains(t.number));
        final label = numbers.toSet().join(' or ');
        emptyMessage = numbersOnBoard
            ? 'No one owns a hex numbered $label yet'
            : 'No hex is numbered $label';
      }
      final completer = Completer<void>();
      // The whiff ("no hexes matched the roll") rides the same ceremony, and
      // a coin sound over it would promise a payout that never came.
      if (grants.isNotEmpty) SoundStore.instance.playSfx(Sfx.production);
      setState(() {
        _production = (grants, emptyMessage, const []);
        _productionCompleter = completer;
      });
      await completer.future;
    }
    if (!mounted) return;
    // Refill rounds top up every hand: say so before play resumes.
    final dealt = events.whereType<CardsDealt>();
    if (dealt.isNotEmpty) {
      final completer = Completer<void>();
      setState(() {
        _production = (
          const [],
          'Round ${dealt.first.round} - everyone draws a card',
          const []
        );
        _productionCompleter = completer;
      });
      await completer.future;
    }
    if (!mounted) return;
    // The periodic bank giveaway pays everyone at once: show it as chips.
    final giveaway = events.whereType<ResourceGiveaway>().firstOrNull;
    if (giveaway != null) {
      final completer = Completer<void>();
      setState(() {
        _production = (
          const [],
          'Round ${giveaway.round} - free resource giveaway!',
          giveaway.grants,
        );
        _productionCompleter = completer;
      });
      await completer.future;
    }
    if (!mounted) return;
    await _announceMatchPoint();
    if (!mounted) return;
    // Hand-over beat: name whoever is up next before their play animates.
    final turnEnded = events.whereType<TurnEnded>().firstOrNull;
    if (turnEnded != null && state.phase != Phase.gameOver) {
      final next = state.players[turnEnded.nextPlayerIndex];
      final completer = Completer<void>();
      setState(() {
        _turnSplash = (
          next.isBot ? "${next.name}'s turn" : 'Your turn',
          BoardPainter.playerColors[next.id],
        );
        _turnSplashCompleter = completer;
      });
      await completer.future;
    }
    if (!mounted) return;
    final banditPlacements = events.whereType<BanditPlaced>();
    if (banditPlacements.isNotEmpty && _boardSize != Size.zero) {
      final completer = Completer<void>();
      SoundStore.instance.playSfx(Sfx.bandit);
      setState(() {
        _banditFlyTarget = banditPlacements.first.target;
        _banditCompleter = completer;
      });
      await completer.future;
    }
    if (!mounted) return;
    // Last of all: the guide only turns the page once the ceremonies that
    // illustrate the lesson have finished playing.
    widget.tutorial?.notifyEvents(events, state);
  }

  /// Calls out every player who just moved a step closer to the target, one
  /// banner each. Silent once the game is over: that moment has its own.
  Future<void> _announceMatchPoint() async {
    if (state.phase == Phase.gameOver) return;
    for (final p in state.players) {
      final step = _matchPointStep(state, p.id);
      if (step == null) continue;
      final announced = _announcedProximity[p.id];
      if (announced != null && announced <= step) continue;
      _announcedProximity[p.id] = step;
      final completer = Completer<void>();
      // Every step gets its banner, only the last one gets the horn: heard at
      // 3 and 2 away as well, it stops meaning anything by the time it counts.
      if (step == 1) SoundStore.instance.playSfx(Sfx.matchPoint);
      setState(() {
        _matchPointWarning = (
          '${p.isBot ? '${p.name} is' : 'You are'} $step '
              'point${step == 1 ? '' : 's'} from victory!',
          BoardPainter.playerColors[p.id],
        );
        _matchPointCompleter = completer;
      });
      await completer.future;
      if (!mounted) return;
    }
  }

  void _onDiceSettled() {
    _rollCompleter?.complete();
    if (mounted) {
      setState(() {
        _rollingDice = null;
        _rollCompleter = null;
      });
    }
  }

  void _onProductionShown() {
    _productionCompleter?.complete();
    if (mounted) {
      setState(() {
        _production = null;
        _productionCompleter = null;
      });
    }
  }

  void _onBotCardShown() {
    _botCardCompleter?.complete();
    if (mounted) {
      setState(() {
        _botCardPlay = null;
        _botCardCompleter = null;
      });
    }
  }

  void _onTurnSplashShown() {
    _turnSplashCompleter?.complete();
    if (mounted) {
      setState(() {
        _turnSplash = null;
        _turnSplashCompleter = null;
      });
    }
  }

  void _onMatchPointShown() {
    _matchPointCompleter?.complete();
    if (mounted) {
      setState(() {
        _matchPointWarning = null;
        _matchPointCompleter = null;
      });
    }
  }

  void _onBanditLanded() {
    _banditCompleter?.complete();
    if (mounted) {
      setState(() {
        _banditFlyTarget = null;
        _banditCompleter = null;
      });
    }
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
    final finished = controller.state;
    // The scripted game tops out at 3 points, so this is belt and braces:
    // the scoreboard records a high score the moment it mounts, and no
    // rehearsal may ever land on the leaderboard.
    if (widget.tutorial != null) return;
    if (finished?.phase == Phase.gameOver && !_navigatedToGameOver) {
      _navigatedToGameOver = true;
      if (_skipEndMoment) {
        _goToGameOver();
        return;
      }
      // The engine only reports who won, so the winner's live score is what
      // tells a claimed target from a game the seasons ran out on.
      final winnerId = finished!.winnerId;
      final claimed = winnerId != null &&
          scoreFor(finished, winnerId) >= finished.targetVp;
      final humanWon = winnerId != null && !finished.players[winnerId].isBot;
      SoundStore.instance.playSfx(humanWon ? Sfx.victory : Sfx.defeat);
      setState(() => _endMoment = (
            claimed ? 'The realm is claimed!' : 'The seasons have turned.',
            humanWon,
          ));
    }
  }

  void _goToGameOver() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameOverScreen(controller: controller),
      ),
    );
  }

  /// One-shot for the move the player just committed. Fired ahead of the
  /// dispatch, not after it: dispatch awaits the whole ceremony chain (and the
  /// bot turns behind it), so a sound queued after it would land beats late.
  /// The legality check is the same one dispatch would make.
  void _playActionSound(GameAction action) {
    final sfx = switch (action) {
      PlayCard() => Sfx.cardPlay,
      // A seize is a hostile claim - same stake-in-the-ground sound.
      ClaimHex() || SeizeHex() => Sfx.claim,
      UpgradeHex() => Sfx.upgrade,
      _ => null,
    };
    if (sfx != null && legalActions(state).contains(action)) {
      SoundStore.instance.playSfx(sfx);
    }
  }

  Future<void> _tryDispatch(GameAction action) async {
    try {
      _selected = null;
      _playActionSound(action);
      await controller.dispatch(action);
    } on IllegalActionException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Amber glow: claimable tiles, bandit targets, card targets.
  Set<Hex> get _highlighted {
    // The guide points at exactly one thing at a time, whoever's turn it is.
    if (widget.tutorial != null) return widget.tutorial!.current.highlightHexes;
    if (!controller.isHumanTurn) return const {};
    final actions = _allowed;
    if (_pendingCardId != null) {
      return actions
          .whereType<PlayCard>()
          .where((a) => a.cardId == _pendingCardId && a.targetHex != null)
          .map((a) => a.targetHex!)
          .toSet();
    }
    return {
      if (state.phase == Phase.awaitingBandit)
        ...actions.whereType<PlaceBandit>().map((a) => a.target)
      else
        ...actions.whereType<ClaimHex>().map((a) => a.target),
    };
  }

  /// True while a ceremony owns the screen - hints stay quiet until it ends.
  bool get _busy =>
      _rollingDice != null ||
      _banditFlyTarget != null ||
      _production != null ||
      _botCardPlay != null ||
      _turnSplash != null ||
      _matchPointWarning != null;

  /// Crimson glow: rival hexes you could seize right now.
  Set<Hex> get _seizeHighlighted {
    if (!controller.isHumanTurn || _pendingCardId != null) return const {};
    if (state.phase == Phase.awaitingBandit) return const {};
    return _allowed
        .whereType<SeizeHex>()
        .map((a) => a.target)
        .toSet();
  }

  void _onTapHex(Hex hex) {
    if (!controller.isHumanTurn) return;
    final actions = _allowed;
    final tutorial = widget.tutorial;
    if (tutorial != null) {
      // One tile matters per step: the bandit's mark, the hex the inspect
      // lesson asks about, or whichever the guide is pointing at - that last
      // one only fills the panel, where the claim button waits. Everything
      // else is a dead tap.
      if (actions.contains(PlaceBandit(hex))) {
        _tryDispatch(PlaceBandit(hex));
      } else if (tutorial.current.inspectHex == hex) {
        _selectForViewing(hex);
        tutorial.notifyHexInspected(hex);
      } else if (tutorial.current.highlightHexes.contains(hex)) {
        _selectForViewing(hex == _selected ? null : hex);
      }
      return;
    }
    if (_pendingCardId != null) {
      // Capture before clearing: the where() filter is lazy and would
      // otherwise see the nulled field and match nothing.
      final pending = _pendingCardId;
      setState(() => _pendingCardId = null);
      final action = actions
          .whereType<PlayCard>()
          .where((a) => a.cardId == pending && a.targetHex == hex);
      if (action.isNotEmpty) _tryDispatch(action.first);
      return;
    }
    if (state.phase == Phase.awaitingBandit) {
      if (actions.contains(PlaceBandit(hex))) {
        _tryDispatch(PlaceBandit(hex));
      }
      return;
    }
    final seize = actions
        .whereType<SeizeHex>()
        .where((a) => a.target == hex)
        .toList();
    if (seize.isNotEmpty) {
      _confirmSeize(seize.first);
      return;
    }
    _selectForViewing(hex == _selected ? null : hex);
  }

  /// Selects (or clears) the inspector's tile. The knock is the sound of
  /// picking a tile up for a look, so it rides the selection only - a second
  /// tap putting it back down is silent.
  void _selectForViewing(Hex? hex) {
    if (hex != null) SoundStore.instance.playSfx(Sfx.tileTap);
    setState(() => _selected = hex);
  }

  /// Upgrades from the inspector and keeps the tile selected, so the panel
  /// shows it reaching Level 2 instead of emptying out.
  Future<void> _upgradeSelected(Hex hex) async {
    await _tryDispatch(UpgradeHex(hex));
    if (!mounted || !state.tiles.containsKey(hex)) return;
    setState(() => _selected = hex);
  }

  /// Taking a rival's hex is the most expensive thing on the board, so it
  /// asks first and names the whole price.
  Future<void> _confirmSeize(SeizeHex action) async {
    final tile = state.tiles[action.target]!;
    final victim = state.players[tile.ownerId!];
    final ok = await showConfirmDialog(
      context: context,
      title: 'Seize from ${victim.name}?',
      message: 'Take their Level-${tile.level} hex for:',
      body: ResourceCostRow(action.spend),
      confirmLabel: 'Seize',
    );
    if (ok == true) await _tryDispatch(action);
  }

  /// One short sentence about the current moment; null hides the balloon.
  String? _currentTip() {
    // In the tutorial the guide banner is the only voice.
    if (widget.tutorial != null) return null;
    if (_rollingDice != null || _banditFlyTarget != null) return null;
    if (_pendingCardId != null) return null;
    if (!controller.isHumanTurn) {
      return 'Rival rolls pay you too - your hexes always earn.';
    }
    final actions = _allowed;
    final canBuyLandmark = actions.any((a) => a is BuyLandmark);
    switch (state.phase) {
      case Phase.awaitingRoll:
        if (canBuyLandmark) {
          return 'You can afford a landmark - tap the shop before rolling!';
        }
        return 'Roll - every hex matching the dice pays its owner.';
      case Phase.awaitingChoice:
        final (d1, d2) = state.lastDice!;
        return d1 + d2 == 7
            ? 'Sum is 7: unleash the bandit, or split instead.'
            : 'Activate the sum, or each die on its own.';
      case Phase.awaitingBandit:
        return 'Drop the bandit on a rival hex to block it.';
      case Phase.main:
        final canClaim = actions.any((a) => a is ClaimHex);
        final canUpgrade = actions.any((a) => a is UpgradeHex);
        final canTrade = actions.any((a) => a is BankTrade);
        if (canBuyLandmark) {
          return 'You can afford a landmark - tap the shop!';
        }
        if (canClaim && canUpgrade) {
          return 'Claim an amber hex, or select one of yours to upgrade.';
        }
        if (canClaim) {
          return 'Claim a glowing hex for 1 wood + 1 brick.';
        }
        if (canUpgrade) {
          return 'Select a hex with a blue ↑, then hit Upgrade below.';
        }
        final canSeize = actions.any((a) => a is SeizeHex);
        if (canSeize) {
          return 'No free land left - seize a crimson rival hex!';
        }
        if (canTrade) {
          return 'Trade spare resources (handshake) to fund an upgrade.';
        }
        final boardFull =
            state.tiles.values.every((t) => t.ownerId != null);
        if (boardFull) {
          return 'Save up 5+ resources to seize a rival hex.';
        }
        return 'Save up for an upgrade (2 grain + 1 stone).';
      case Phase.gameOver:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final human = state.players.firstWhere((p) => !p.isBot);
    // Glow hints: something is actually buyable/tradeable right now, and no
    // ceremony is running that would steal the eye.
    final allowed = _allowed;
    final hints =
        controller.isHumanTurn && !_busy ? allowed : const <GameAction>[];
    // In guided mode the glow follows the lesson, not the purse: the step
    // says which button to press, and only that one lights up.
    final tutorial = widget.tutorial;
    final targets = tutorial?.current.targets ?? const <TutorialTarget>{};
    final shopGlow = tutorial != null
        ? targets.contains(TutorialTarget.shopButton)
        : hints.any((a) => a is BuyLandmark);
    final tradeGlow = tutorial != null
        ? targets.contains(TutorialTarget.tradeButton)
        : hints.any((a) => a is BankTrade);
    return Scaffold(
      backgroundColor: const Color(0xFF2E4034),
      body: Stack(
        key: _screenStackKey,
        children: [
          // Every piece of chrome floats over the board, so the hex grid
          // never shifts as buttons and banners come and go. The board box
          // stops short of the bottom: the grid rides high and the reserved
          // band under it stays free.
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The grid centers in its box, so an inset at the top both
                // clears the tip balloon and pulls the grid's bottom edge
                // closer to the inspector. Eased off on short screens, where
                // the board is the first thing to lose.
                final boardTop =
                    (constraints.maxHeight * 0.15).clamp(72.0, 112.0);
                _boardSize = Size(
                  constraints.maxWidth,
                  (constraints.maxHeight - boardTop - _boardBottomReserve)
                      .clamp(120.0, constraints.maxHeight),
                );
                // Board and overlays share one box and one geometry, so
                // payout chips and the bandit land on the hexes they name.
                final geometry = BoardGeometry(_boardSize);
                return Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: boardTop,
                      width: _boardSize.width,
                      height: _boardSize.height,
                      child: BoardWidget(
                        state: state,
                        highlighted: _highlighted,
                        seizeHighlighted: _seizeHighlighted,
                        humanPlayerId: human.id,
                        upgradeAffordable: human.canAfford(Rules.upgradeCost),
                        selected: _selected,
                        hideBanditAt: _banditFlyTarget,
                        onTapHex: _onTapHex,
                        // Long press is pure inspection: a claimable or
                        // seizable hex can be studied without acting on it.
                        onLongPressHex: _selectForViewing,
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 8,
                      child: _TopLeftChrome(
                        human: human,
                        tipsOn: _tipsOn,
                        tip: _currentTip(),
                        // Clears the toggle column on its left and the
                        // round/score cluster on its right.
                        tipMaxWidth:
                            (constraints.maxWidth - 158).clamp(140.0, 420.0),
                        resourcesMaxWidth:
                            (constraints.maxWidth - 116).clamp(140.0, 480.0),
                        onToggleTips: _toggleTips,
                        onOpenSettings: () {
                          SoundStore.instance.playSfx(Sfx.uiTap);
                          setState(() => _settingsOpen = true);
                        },
                      ),
                    ),
                    Positioned(
                      right: 10,
                      top: 8,
                      child: _TopRightChrome(state: state),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedSlide(
                        offset:
                            _hudVisible ? Offset.zero : const Offset(0, 1.4),
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        // Opacity as well as the slide: the safe-area inset
                        // still paints, so a slid-down cluster would peek
                        // under the welcome card.
                        child: AnimatedOpacity(
                          opacity: _hudVisible ? 1 : 0,
                          duration: const Duration(milliseconds: 250),
                          // Hand, shop and trade live here as one row; the
                          // glow state rides in the keys so widget tests can
                          // assert it.
                          child: _BottomCluster(
                            controller: controller,
                            rolling: _rollingDice != null,
                            onAction: _tryDispatch,
                            onRemoveBandit: _confirmRemoveBandit,
                            onOpenCards: () {
                              setState(() => _cardFanOpen = true);
                              tutorial?.notifyUi(TutorialUiSignal.fanOpened);
                            },
                            onOpenShop: () {
                              setState(() => _shopOpen = true);
                              tutorial?.notifyUi(TutorialUiSignal.shopOpened);
                            },
                            onOpenTrade: () {
                              setState(() => _tradeOpen = true);
                              tutorial?.notifyUi(TutorialUiSignal.tradeOpened);
                            },
                            tutorialTargets: tutorial == null ? null : targets,
                            shopGlow: shopGlow,
                            tradeGlow: tradeGlow,
                            cardIconKey: _cardIconKey,
                            taskChipKey: _taskChipKey,
                            // Hidden but still laid out: the reveal flies to
                            // the chip's spot and only then uncovers it.
                            taskHidden:
                                _taskRevealPending || _taskRevealActive,
                            pendingCardId: _pendingCardId,
                            onCancelPending: () =>
                                setState(() => _pendingCardId = null),
                            selectedTile: _selected == null
                                ? null
                                : state.tiles[_selected!],
                            humanPlayerId: human.id,
                            allowed: allowed,
                            upgradeEnabled: _selected != null &&
                                controller.isHumanTurn &&
                                allowed.contains(UpgradeHex(_selected!)),
                            onUpgrade: () => _upgradeSelected(_selected!),
                            claimEnabled: _selected != null &&
                                controller.isHumanTurn &&
                                allowed.contains(ClaimHex(_selected!)),
                            onClaim: () => _tryDispatch(ClaimHex(_selected!)),
                          ),
                        ),
                      ),
                    ),
                    // Ceremonies paint last: they own the screen while they
                    // run, chrome included.
                    if (_rollingDice != null)
                      Positioned(
                        left: 0,
                        top: boardTop,
                        width: _boardSize.width,
                        height: _boardSize.height,
                        child: Center(
                          child: DiceRollOverlay(
                            key: ValueKey(state.diceHistory.length),
                            d1: _rollingDice!.$1,
                            d2: _rollingDice!.$2,
                            rollDuration: _rollDuration,
                            holdDuration: _holdDuration,
                            // Tumble over the board, then fly down into the
                            // reserved band below it.
                            flyOffset: Offset(0, _boardSize.height / 2 + 30),
                            onDone: _onDiceSettled,
                          ),
                        ),
                      ),
                    // Hex-anchored ceremonies get the board's own box: they
                    // fill their parent, so without it they would paint
                    // their chips a whole inset above the hexes.
                    if (_production != null)
                      Positioned(
                        left: 0,
                        top: boardTop,
                        width: _boardSize.width,
                        height: _boardSize.height,
                        child: Stack(
                          children: [
                            ProductionOverlay(
                              key: ValueKey(state.diceHistory.length * 100 +
                                  _production!.$1.length),
                              geometry: geometry,
                              grants: _production!.$1,
                              emptyMessage: _production!.$2,
                              bonuses: _production!.$3,
                              playerNames: [
                                for (final p in state.players)
                                  p.isBot ? p.name : 'You',
                              ],
                              onDone: _onProductionShown,
                            ),
                          ],
                        ),
                      ),
                    if (_botCardPlay != null)
                      BotCardOverlay(
                        key: ValueKey(_botCardPlay),
                        cardId: _botCardPlay!.cardId,
                        playerName: state.players[_botCardPlay!.playerId].name,
                        playerColor:
                            BoardPainter.playerColors[_botCardPlay!.playerId],
                        onDone: _onBotCardShown,
                      ),
                    if (_turnSplash != null)
                      TurnSplashOverlay(
                        key: ValueKey(_turnSplash),
                        text: _turnSplash!.$1,
                        playerColor: _turnSplash!.$2,
                        onDone: _onTurnSplashShown,
                      ),
                    if (_matchPointWarning != null)
                      MatchPointOverlay(
                        key: ValueKey(_matchPointWarning),
                        text: _matchPointWarning!.$1,
                        playerColor: _matchPointWarning!.$2,
                        onDone: _onMatchPointShown,
                      ),
                    if (_banditFlyTarget != null)
                      Positioned(
                        left: 0,
                        top: boardTop,
                        width: _boardSize.width,
                        height: _boardSize.height,
                        child: Stack(
                          children: [
                            BanditFlyOverlay(
                              key: ValueKey(_banditFlyTarget),
                              start: Offset(_boardSize.width / 2,
                                  _boardSize.height / 2),
                              // Landing size and offset mirror BoardPainter's
                              // bandit metrics - change one, change both.
                              target: geometry.centerOf(_banditFlyTarget!) -
                                  Offset(0, geometry.hexSize * 0.02),
                              endSize: geometry.hexSize *
                                  (ArtStore.instance.banditImage != null
                                      ? 1.1
                                      : 0.80),
                              onDone: _onBanditLanded,
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          // The guide strip takes the tip balloon's slot: clear of the
          // toggle column on its left, so settings (and the way out of the
          // tutorial) stays reachable behind it.
          if (tutorial != null && !tutorial.finished)
            Positioned(
              left: 48,
              right: 12,
              top: MediaQuery.paddingOf(context).top + 44,
              child: TutorialBanner(
                key: ValueKey(tutorial.current.id),
                text: tutorial.current.text,
                buttonLabel: !tutorial.current.showNext
                    ? null
                    : tutorial.isLastStep
                        ? 'Finish'
                        : 'Next',
                onButton: tutorial.isLastStep
                    ? _finishTutorial
                    : () => tutorial.notifyUi(TutorialUiSignal.next),
              ),
            ),
          if (_showWelcome)
            WelcomeOverlay(state: state, onStart: _dismissWelcome),
          if (_cardFanOpen)
            CardFanOverlay(
              cardIds: human.hand,
              flyOffset: _fanFlyOffset(),
              playableCardIds: controller.isHumanTurn
                  ? allowed
                      .whereType<PlayCard>()
                      .map((a) => a.cardId)
                      .toSet()
                  : const {},
              replaceableCardIds: controller.isHumanTurn
                  ? allowed
                      .whereType<ReplaceCard>()
                      .map((a) => a.cardId)
                      .toSet()
                  : const {},
              onReplace: (id) => _tryDispatch(ReplaceCard(id)),
              onPlay: _handleCardPlay,
              onDone: () => setState(() {
                _cardFanOpen = false;
                if (_taskRevealPending) {
                  _taskRevealPending = false;
                  _taskRevealActive = true;
                }
              }),
            ),
          if (_taskRevealActive && objectiveCatalog[human.objectiveId] != null)
            TaskRevealOverlay(
              description: objectiveCatalog[human.objectiveId]!.description,
              target: _taskFlyTarget(),
              onDone: () => setState(() => _taskRevealActive = false),
            ),
          if (_shopOpen)
            ShopOverlay(
              state: state,
              buyableIds: allowed
                  .whereType<BuyLandmark>()
                  .map((a) => a.landmarkId)
                  .toSet(),
              onBuy: (id) {
                SoundStore.instance.playSfx(Sfx.uiTap);
                setState(() => _shopOpen = false);
                _tryDispatch(BuyLandmark(id));
              },
              onClose: () => setState(() => _shopOpen = false),
            ),
          if (_settingsOpen)
            SettingsOverlay(
              quitTitle: tutorial == null ? null : 'Leave the tutorial?',
              quitMessage: tutorial == null
                  ? null
                  : 'You can start it again from the menu whenever you '
                      'like.',
              onClose: () => setState(() => _settingsOpen = false),
              onQuitToMenu: () {
                SoundStore.instance.startMusic(MusicTrack.menu);
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          if (_tradeOpen)
            TradeOverlay(
              state: state,
              legalTrades: allowed.whereType<BankTrade>().toList(),
              // A normal game leaves the counter open for a second trade;
              // the tutorial's next lesson is elsewhere, so it shuts.
              onTrade: (t) {
                if (tutorial != null) setState(() => _tradeOpen = false);
                _tryDispatch(t);
              },
              onClose: () => setState(() => _tradeOpen = false),
            ),
          // The last ceremony of all: it paints over every other overlay and
          // hands off to the scoreboard when it ends.
          if (_endMoment != null)
            GameEndOverlay(
              text: _endMoment!.$1,
              celebrate: _endMoment!.$2,
              onDone: () {
                setState(() => _endMoment = null);
                _goToGameOver();
              },
            ),
        ],
      ),
    );
  }
}

/// Circular parchment button for the floating board actions. [glow] marks
/// the ones with something on offer right now.
class _RoundActionButton extends StatelessWidget {
  final bool enabled;
  final bool glow;
  final double size;
  final VoidCallback onTap;
  final Widget child;

  const _RoundActionButton({
    super.key,
    required this.enabled,
    required this.onTap,
    required this.child,
    this.glow = false,
    this.size = 50,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: const Color(0xFFF4EAD4),
      shape: CircleBorder(
        side: BorderSide(
          color: glow ? const Color(0xFFFFC107) : const Color(0xFF8A6F4D),
          width: glow ? 2.5 : 2,
        ),
      ),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled
            ? () {
                SoundStore.instance.playSfx(Sfx.uiTap);
                onTap();
              }
            : null,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: child),
        ),
      ),
    );
    // Static glow, not a pulse: a repeating controller would keep widget
    // tests from ever settling.
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: glow
          ? DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.85),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: button,
            )
          : button,
    );
  }
}

/// Floating top-left chrome: the human's resources on one line, the tips
/// and settings toggles stacked under them, and the contextual tip balloon
/// beside the toggles.
class _TopLeftChrome extends StatelessWidget {
  final PlayerState human;
  final bool tipsOn;
  final String? tip;
  final double tipMaxWidth;
  final double resourcesMaxWidth;
  final VoidCallback onToggleTips;
  final VoidCallback onOpenSettings;

  const _TopLeftChrome({
    required this.human,
    required this.tipsOn,
    required this.tip,
    required this.tipMaxWidth,
    required this.resourcesMaxWidth,
    required this.onToggleTips,
    required this.onOpenSettings,
  });

  /// The counters, icons included, render at this size.
  static const _fontSize = 15.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scales down rather than running into the round counter on the
        // narrowest phones.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: resourcesMaxWidth),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: chromePill(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final r in Resource.values)
                    Padding(
                      padding: EdgeInsets.only(
                          right: r == Resource.values.last ? 0 : 10),
                      child: Text.rich(
                        TextSpan(children: [
                          resourceSpan(r, _fontSize),
                          TextSpan(text: ' ${human.countOf(r)}'),
                        ]),
                        style: const TextStyle(
                            color: Colors.white, fontSize: _fontSize),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Toggles hug the left edge; the balloon sits beside them, anchored
        // to the bulb it belongs to.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _toggle(
                  onTap: onToggleTips,
                  background: tipsOn
                      ? Colors.amber.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.08),
                  icon: Icon(
                    Icons.lightbulb,
                    size: 17,
                    color: tipsOn ? Colors.amber : Colors.white38,
                  ),
                ),
                const SizedBox(height: 6),
                _toggle(
                  onTap: onOpenSettings,
                  background: Colors.black.withValues(alpha: 0.35),
                  icon: const Icon(Icons.settings,
                      size: 17, color: Colors.white70),
                ),
              ],
            ),
            if (tipsOn && tip != null) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: tipMaxWidth),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: chromePill(),
                  child: Text(
                    tip!,
                    maxLines: 3,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _toggle({
    required VoidCallback onTap,
    required Color background,
    required Widget icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: icon,
      ),
    );
  }
}

/// Floating top-right chrome: the round counter with the score chips
/// stacked under it.
class _TopRightChrome extends StatelessWidget {
  final GameState state;

  const _TopRightChrome({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: chromePill(),
          child: Text(
            'Round ${state.round}/${state.roundCap}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        const SizedBox(height: 6),
        for (final p in state.players)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _PlayerChip(
              label: '${p.isBot ? p.name.substring(0, 1) : 'You'} '
                  '${scoreFor(state, p.id)}',
              color: BoardPainter.playerColors[p.id],
              active: state.currentPlayerIndex == p.id,
              matchPointStep: _matchPointStep(state, p.id),
            ),
          ),
      ],
    );
  }
}

/// One score chip. Within match point range it keeps a crimson border and
/// breathes for a few beats. Bounded, not a repeat(): a forever-running
/// controller would keep widget tests from ever settling.
class _PlayerChip extends StatefulWidget {
  final String label;
  final Color color;
  final bool active;

  /// Points short of victory while inside the warning range, else null.
  final int? matchPointStep;

  const _PlayerChip({
    required this.label,
    required this.color,
    required this.active,
    required this.matchPointStep,
  });

  @override
  State<_PlayerChip> createState() => _PlayerChipState();
}

class _PlayerChipState extends State<_PlayerChip>
    with SingleTickerProviderStateMixin {
  /// The crimson the board uses for seizable hexes - one warning color.
  static const _warning = Color(0xFFE05252);
  static const _beats = 3;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800 * _beats),
  );

  @override
  void initState() {
    super.initState();
    if (widget.matchPointStep != null) _pulse.forward();
  }

  @override
  void didUpdateWidget(_PlayerChip old) {
    super.didUpdateWidget(old);
    // Every step closer breathes again; sitting on the same step does not.
    if (widget.matchPointStep != null &&
        widget.matchPointStep != old.matchPointStep) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final atMatchPoint = widget.matchPointStep != null;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        // Full cosine beats: the border starts and ends bright, dipping
        // between, so the resting chip is never caught mid-fade.
        final beat = atMatchPoint
            ? 0.5 + 0.5 * cos(_pulse.value * 2 * pi * _beats)
            : 1.0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: widget.active
                ? widget.color
                : Colors.black.withValues(alpha: 0.35),
            border: Border.all(
              color: atMatchPoint
                  ? _warning.withValues(alpha: 0.45 + 0.55 * beat)
                  : widget.color,
              width: atMatchPoint ? 2 : 1.5,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: atMatchPoint
                ? [
                    BoxShadow(
                      color: _warning.withValues(alpha: 0.35 * beat),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.active ? Colors.white : Colors.white70,
              fontWeight: widget.active ? FontWeight.w800 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        );
      },
    );
  }
}

/// Floating bottom chrome: the secret-task line and the hand/shop/trade
/// buttons on one row, with the action row alone on the line below it.
class _BottomCluster extends StatelessWidget {
  final GameController controller;
  final bool rolling;
  final Future<void> Function(GameAction) onAction;

  /// Routed to the screen rather than dispatched here: paying the bandit
  /// off asks for confirmation first, and the dialog needs the screen's
  /// context (same shape as the seize confirmation).
  final void Function(RemoveBandit) onRemoveBandit;
  final VoidCallback onOpenCards;
  final VoidCallback onOpenShop;
  final VoidCallback onOpenTrade;
  final bool shopGlow;
  final bool tradeGlow;
  final GlobalKey? cardIconKey;

  /// Anchor for the game-start task reveal's flight, and whether that reveal
  /// is still holding the task line for itself.
  final GlobalKey? taskChipKey;
  final bool taskHidden;

  /// Card waiting for a tile tap; its banner rides above the cluster.
  final String? pendingCardId;
  final VoidCallback onCancelPending;

  /// Inspector feed: the selected tile (null = nothing selected) and the
  /// upgrade it offers.
  final Tile? selectedTile;
  final int humanPlayerId;
  final bool upgradeEnabled;
  final VoidCallback onUpgrade;
  final bool claimEnabled;
  final VoidCallback onClaim;

  /// What the player may do right now - the engine's legal moves, or the
  /// tutorial's narrowed slice of them. Buttons enable off this, never off
  /// [legalActions].
  final List<GameAction> allowed;

  /// Null outside the tutorial. Inside it, the chrome the current step
  /// points at: those buttons glow and work, the rest go dead.
  final Set<TutorialTarget>? tutorialTargets;

  const _BottomCluster({
    required this.controller,
    required this.rolling,
    required this.onAction,
    required this.onRemoveBandit,
    required this.allowed,
    required this.onOpenCards,
    required this.onOpenShop,
    required this.onOpenTrade,
    required this.shopGlow,
    required this.tradeGlow,
    required this.pendingCardId,
    required this.onCancelPending,
    required this.selectedTile,
    required this.humanPlayerId,
    required this.upgradeEnabled,
    required this.onUpgrade,
    required this.claimEnabled,
    required this.onClaim,
    this.cardIconKey,
    this.taskChipKey,
    this.taskHidden = false,
    this.tutorialTargets,
  });

  /// Shared size for the hand/shop/trade trio so they read as one family.
  static const _buttonSize = 44.0;

  /// Whether the guide is pointing at [target] right now.
  bool _aims(TutorialTarget target) =>
      tutorialTargets?.contains(target) ?? false;

  /// A button is live when the game allows it and - in the tutorial - when
  /// the current lesson is actually about it.
  bool _live(bool base, TutorialTarget target) =>
      base && (tutorialTargets == null || _aims(target));

  @override
  Widget build(BuildContext context) {
    final state = controller.state!;
    final human = state.players.firstWhere((p) => !p.isBot);
    final buttonsEnabled = controller.isHumanTurn && !rolling;
    // Tablet cap: the controls stay centered instead of smearing edge to
    // edge. Inert on phones (below 640px).
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TileInspector(
                state: state,
                tile: selectedTile,
                humanPlayerId: humanPlayerId,
                upgradeEnabled: upgradeEnabled,
                onUpgrade: onUpgrade,
                claimEnabled: claimEnabled,
                onClaim: onClaim,
              ),
              const SizedBox(height: 8),
              if (pendingCardId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade800,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${cardCatalog[pendingCardId]!.name}: '
                            'tap a glowing tile',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        TextButton(
                          onPressed: onCancelPending,
                          child: const Text('Cancel',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                children: [
                  // Expanded (not Flexible beside a Spacer): with both
                  // claiming flex the pill was sized to half the free width
                  // while its text painted on past the background.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _taskLine(state, human),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _RoundActionButton(
                    key: cardIconKey,
                    size: _buttonSize,
                    enabled: _live(buttonsEnabled, TutorialTarget.cardsButton),
                    glow: _aims(TutorialTarget.cardsButton),
                    onTap: onOpenCards,
                    // The painter is drawn at 44x32; fit it to the disc.
                    child: SizedBox(
                      width: 30,
                      height: 22,
                      child: FittedBox(
                        child: CardFanIcon(count: human.hand.length),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _RoundActionButton(
                    key: ValueKey(shopGlow ? 'shop-glow' : 'shop'),
                    size: _buttonSize,
                    enabled: _live(buttonsEnabled, TutorialTarget.shopButton),
                    glow: shopGlow,
                    onTap: onOpenShop,
                    child: const Text('🏛', style: TextStyle(fontSize: 21)),
                  ),
                  const SizedBox(width: 8),
                  _RoundActionButton(
                    key: ValueKey(tradeGlow ? 'trade-glow' : 'trade'),
                    size: _buttonSize,
                    enabled: _live(buttonsEnabled, TutorialTarget.tradeButton),
                    glow: tradeGlow,
                    onTap: onOpenTrade,
                    child: const Icon(Icons.handshake,
                        size: 21, color: Color(0xFF3A2E20)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Fixed height: buttons coming and going must never move the
              // board underneath.
              SizedBox(
                height: 84,
                child: Center(child: _actionRow(context, state)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Live objective progress: the count alone, never truncated. The
  /// objective's name lives in the tooltip and the opening briefing.
  /// Turns gold on the round it completes.
  Widget _taskLine(GameState state, PlayerState human) {
    final objective = objectiveCatalog[human.objectiveId];
    if (objective == null) return const SizedBox(height: _buttonSize);
    final (current, target) = objective.progress(state, human.id);
    final done = current >= target;
    return Visibility(
      visible: !taskHidden,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: Tooltip(
        message: objective.description,
        child: TutorialGlow(
          active: _aims(TutorialTarget.taskChip),
          radius: 12,
          child: Container(
            key: taskChipKey,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: chromePill(),
            child: Text.rich(
              TextSpan(children: [
                taskSpan(14),
                TextSpan(
                  text: ' ${done ? target : current}/$target '
                      '${objective.shortLabel}${done ? ' ✓' : ''}',
                ),
              ]),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: done ? const Color(0xFFFFCA28) : Colors.white70,
                fontSize: 14,
                fontWeight: done ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Status text needs its own backing out here over the board art. One
  /// line only: the action slot has a fixed height so the board never
  /// shifts, and the tip balloon carries the longer wording.
  Widget _statusPill(String text, {Color color = Colors.white70}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: chromePill(),
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 12.5),
        ),
      );

  Widget _actionRow(BuildContext context, GameState state) {
    if (rolling) return _statusPill('Rolling…');
    if (!controller.isHumanTurn) {
      return _statusPill('${state.currentPlayer.name} is playing…');
    }
    switch (state.phase) {
      case Phase.awaitingRoll:
        return TutorialGlow(
          active: _aims(TutorialTarget.rollButton),
          child: FilledButton.icon(
            onPressed: allowed.contains(const RollDice())
                ? () {
                    SoundStore.instance.playSfx(Sfx.uiTap);
                    onAction(const RollDice());
                  }
                : null,
            icon: const Text('🎲', style: TextStyle(fontSize: 20)),
            label: const Text('Roll the dice'),
          ),
        );
      case Phase.awaitingChoice:
        final (d1, d2) = state.lastDice!;
        final sum = d1 + d2;
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MiniDie(d1),
              const SizedBox(width: 5),
              MiniDie(d2),
              const SizedBox(width: 12),
              TutorialGlow(
                active: _aims(TutorialTarget.sumButton),
                child: FilledButton(
                  onPressed: allowed
                          .contains(const ChooseActivation(ActivationMode.sum))
                      ? () =>
                          onAction(const ChooseActivation(ActivationMode.sum))
                      : null,
                  child: Text(sum == 7 ? 'Bandit!' : 'Sum $sum'),
                ),
              ),
              const SizedBox(width: 8),
              TutorialGlow(
                active: _aims(TutorialTarget.splitButton),
                child: FilledButton.tonal(
                  onPressed: allowed.contains(
                          const ChooseActivation(ActivationMode.split))
                      ? () =>
                          onAction(const ChooseActivation(ActivationMode.split))
                      : null,
                  child: Text('Split $d1 & $d2'),
                ),
              ),
            ],
          ),
        );
      case Phase.awaitingBandit:
        return _statusPill('Place the bandit: tap any claimed tile',
            color: Colors.amber);
      case Phase.main:
        final canRemoveBandit =
            allowed.whereType<RemoveBandit>().isNotEmpty;
        final canBuild =
            allowed.any((a) => a is ClaimHex || a is UpgradeHex);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The guide banner is the tutorial's only running commentary -
            // a second line reading off the purse would contradict it.
            if (tutorialTargets == null)
              _statusPill(
                canBuild
                    ? 'Tap a glowing tile, then press Claim'
                    : 'Nothing affordable - end your turn',
              ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canRemoveBandit)
                    FilledButton.tonal(
                      onPressed: () => onRemoveBandit(
                          allowed.whereType<RemoveBandit>().first),
                      child: const Text('Pay off bandit'),
                    ),
                  const SizedBox(width: 8),
                  TutorialGlow(
                    active: _aims(TutorialTarget.endTurnButton),
                    child: FilledButton(
                      onPressed: allowed.contains(const EndTurn())
                          ? () => onAction(const EndTurn())
                          : null,
                      child: const Text('End Turn'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      case Phase.gameOver:
        return const SizedBox.shrink();
    }
  }
}

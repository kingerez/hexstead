import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../board/board_geometry.dart';
import '../board/board_painter.dart';
import '../board/board_widget.dart';
import '../widgets/adjust_die_dialog.dart';
import '../widgets/bandit_fly_overlay.dart';
import '../widgets/bot_card_overlay.dart';
import '../widgets/card_fan_overlay.dart';
import '../widgets/chrome.dart';
import '../widgets/dice_roll_overlay.dart';
import '../widgets/settings_overlay.dart';
import '../widgets/shop_overlay.dart';
import '../widgets/trade_overlay.dart';
import '../widgets/production_overlay.dart';
import '../widgets/tile_inspector.dart';
import '../widgets/turn_splash_overlay.dart';
import '../widgets/welcome_card.dart';
import '../state/game_controller.dart';
import 'game_over_screen.dart';

class GameScreen extends StatefulWidget {
  final GameController controller;

  const GameScreen({super.key, required this.controller});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

/// Free band kept under the board: the grid sits high and the strip below
/// it stays clear for the bottom chrome.
const double _boardBottomReserve = 282;

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

  @override
  void initState() {
    super.initState();
    controller.addListener(_onStateChanged);
    controller.eventDelegate = _presentEvents;
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _tipsOn = prefs.getBool('tips_on') ?? true);
    });
    final fresh = state.round == 1 &&
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

  /// Second line under the fan title; only the game-start reveal sets it.
  String? _fanSubtitle;

  /// Landmark shop, bank trade, and settings overlays.
  bool _shopOpen = false;
  bool _tradeOpen = false;
  bool _settingsOpen = false;

  /// Anchors for the fan's fly-to-icon animation.
  final GlobalKey _screenStackKey = GlobalKey();
  final GlobalKey _cardIconKey = GlobalKey();

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

  void _dismissWelcome() {
    setState(() {
      _showWelcome = false;
      _hudVisible = true;
      final human = state.players.firstWhere((p) => !p.isBot);
      _cardFanOpen = human.hand.isNotEmpty;
      // The opening reveal restates the secret task: the welcome card is
      // already gone by the time the cards are in view.
      final objective = objectiveCatalog[human.objectiveId];
      _fanSubtitle = objective == null
          ? null
          : '🎯 Secret task: ${objective.description}';
    });
  }

  /// Executes a card chosen from the fan, mirroring the old sheet logic:
  /// direct plays dispatch, target cards enter tap-a-tile mode, and
  /// multi-option cards ask via a small dialog.
  Future<void> _handleCardPlay(String cardId) async {
    final options = legalActions(state)
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
      await _pickOption('Steal from…',
          [for (final o in options) (state.players[o.targetPlayer!].name, o)]);
      return;
    }
    if (cardId == 'bounty') {
      await _pickOption(
          'Take 2 of…', [for (final o in options) (o.resource!.name, o)]);
      return;
    }
    if (cardId == 'omen' && options.length > 1) {
      final (d1, d2) = state.lastDice!;
      final action = await showDialog<PlayCard>(
        context: context,
        builder: (_) => AdjustDieDialog(d1: d1, d2: d2, options: options),
      );
      if (action != null) await _tryDispatch(action);
      return;
    }
    await _tryDispatch(options.first);
  }

  Future<void> _pickOption(
      String title, List<(String, PlayCard)> options) async {
    final action = await showDialog<PlayCard>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          for (final (label, a) in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, a),
              child: Text(label),
            ),
        ],
      ),
    );
    if (action != null) await _tryDispatch(action);
  }

  void _toggleTips() {
    setState(() => _tipsOn = !_tipsOn);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool('tips_on', _tipsOn));
  }

  @override
  void dispose() {
    controller.removeListener(_onStateChanged);
    if (controller.eventDelegate == _presentEvents) {
      controller.eventDelegate = null;
    }
    super.dispose();
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
      setState(() {
        _banditFlyTarget = banditPlacements.first.target;
        _banditCompleter = completer;
      });
      await completer.future;
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
    if (controller.state?.phase == Phase.gameOver && !_navigatedToGameOver) {
      _navigatedToGameOver = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GameOverScreen(controller: controller),
        ),
      );
    }
  }

  Future<void> _tryDispatch(GameAction action) async {
    try {
      _selected = null;
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
    if (!controller.isHumanTurn) return const {};
    final actions = legalActions(state);
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
      _turnSplash != null;

  /// Crimson glow: rival hexes you could seize right now.
  Set<Hex> get _seizeHighlighted {
    if (!controller.isHumanTurn || _pendingCardId != null) return const {};
    if (state.phase == Phase.awaitingBandit) return const {};
    return legalActions(state)
        .whereType<SeizeHex>()
        .map((a) => a.target)
        .toSet();
  }

  void _onTapHex(Hex hex) {
    if (!controller.isHumanTurn) return;
    final actions = legalActions(state);
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
    if (actions.contains(ClaimHex(hex))) {
      _tryDispatch(ClaimHex(hex));
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
    setState(() => _selected = _selected == hex ? null : hex);
  }

  /// Upgrades from the inspector and keeps the tile selected, so the panel
  /// shows it reaching Level 2 instead of emptying out.
  Future<void> _upgradeSelected(Hex hex) async {
    await _tryDispatch(UpgradeHex(hex));
    if (!mounted || !state.tiles.containsKey(hex)) return;
    setState(() => _selected = hex);
  }

  Future<void> _confirmSeize(SeizeHex action) async {
    const emoji = {
      Resource.wood: '🪵',
      Resource.grain: '🌾',
      Resource.brick: '🧱',
      Resource.stone: '🪨',
    };
    final tile = state.tiles[action.target]!;
    final victim = state.players[tile.ownerId!];
    final counts = <Resource, int>{};
    for (final r in action.spend) {
      counts[r] = (counts[r] ?? 0) + 1;
    }
    final costText =
        counts.entries.map((e) => '${e.value} ${emoji[e.key]}').join('  ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Seize from ${victim.name}?'),
        content: Text(
            'Take their Level-${tile.level} hex for:\n\n$costText'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Seize'),
          ),
        ],
      ),
    );
    if (ok == true) await _tryDispatch(action);
  }

  /// One short sentence about the current moment; null hides the balloon.
  String? _currentTip() {
    if (_rollingDice != null || _banditFlyTarget != null) return null;
    if (_pendingCardId != null) return null;
    if (!controller.isHumanTurn) {
      return 'Rival rolls pay you too - your hexes always earn.';
    }
    final actions = legalActions(state);
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
    final hints = controller.isHumanTurn && !_busy
        ? legalActions(state)
        : const <GameAction>[];
    final shopGlow = hints.any((a) => a is BuyLandmark);
    final tradeGlow = hints.any((a) => a is BankTrade);
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
                        onLongPressHex: (hex) =>
                            setState(() => _selected = hex),
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
                        onOpenSettings: () =>
                            setState(() => _settingsOpen = true),
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
                            onOpenCards: () =>
                                setState(() => _cardFanOpen = true),
                            onOpenShop: () => setState(() => _shopOpen = true),
                            onOpenTrade: () =>
                                setState(() => _tradeOpen = true),
                            shopGlow: shopGlow,
                            tradeGlow: tradeGlow,
                            cardIconKey: _cardIconKey,
                            pendingCardId: _pendingCardId,
                            onCancelPending: () =>
                                setState(() => _pendingCardId = null),
                            selectedTile: _selected == null
                                ? null
                                : state.tiles[_selected!],
                            humanPlayerId: human.id,
                            upgradeEnabled: _selected != null &&
                                controller.isHumanTurn &&
                                legalActions(state)
                                    .contains(UpgradeHex(_selected!)),
                            onUpgrade: () => _upgradeSelected(_selected!),
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
                              target: geometry.centerOf(_banditFlyTarget!),
                              endSize: geometry.hexSize * 0.80,
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
          if (_showWelcome)
            WelcomeOverlay(state: state, onStart: _dismissWelcome),
          if (_cardFanOpen)
            CardFanOverlay(
              cardIds: human.hand,
              subtitle: _fanSubtitle,
              flyOffset: _fanFlyOffset(),
              playableCardIds: controller.isHumanTurn
                  ? legalActions(state)
                      .whereType<PlayCard>()
                      .map((a) => a.cardId)
                      .toSet()
                  : const {},
              replaceableCardIds: controller.isHumanTurn
                  ? legalActions(state)
                      .whereType<ReplaceCard>()
                      .map((a) => a.cardId)
                      .toSet()
                  : const {},
              onReplace: (id) => _tryDispatch(ReplaceCard(id)),
              onPlay: _handleCardPlay,
              onDone: () => setState(() {
                _cardFanOpen = false;
                _fanSubtitle = null;
              }),
            ),
          if (_shopOpen)
            ShopOverlay(
              state: state,
              buyableIds: legalActions(state)
                  .whereType<BuyLandmark>()
                  .map((a) => a.landmarkId)
                  .toSet(),
              onBuy: (id) {
                setState(() => _shopOpen = false);
                _tryDispatch(BuyLandmark(id));
              },
              onClose: () => setState(() => _shopOpen = false),
            ),
          if (_settingsOpen)
            SettingsOverlay(
              onClose: () => setState(() => _settingsOpen = false),
              onQuitToMenu: () =>
                  Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          if (_tradeOpen)
            TradeOverlay(
              state: state,
              legalTrades:
                  legalActions(state).whereType<BankTrade>().toList(),
              onTrade: _tryDispatch,
              onClose: () => setState(() => _tradeOpen = false),
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
        onTap: enabled ? onTap : null,
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

  static const resourceEmoji = {
    Resource.wood: '🪵',
    Resource.grain: '🌾',
    Resource.brick: '🧱',
    Resource.stone: '🪨',
  };

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
                      child: Text(
                        '${resourceEmoji[r]} ${human.countOf(r)}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
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
            child: _playerChip(p),
          ),
      ],
    );
  }

  Widget _playerChip(PlayerState p) {
    final active = state.currentPlayerIndex == p.id;
    final color = BoardPainter.playerColors[p.id];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? color : Colors.black.withValues(alpha: 0.35),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${p.isBot ? p.name.substring(0, 1) : 'You'} ${scoreFor(state, p.id)}',
        style: TextStyle(
          color: active ? Colors.white : Colors.white70,
          fontWeight: active ? FontWeight.w800 : FontWeight.w500,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Floating bottom chrome: the secret-task line and the hand/shop/trade
/// buttons on one row, with the action row alone on the line below it.
class _BottomCluster extends StatelessWidget {
  final GameController controller;
  final bool rolling;
  final Future<void> Function(GameAction) onAction;
  final VoidCallback onOpenCards;
  final VoidCallback onOpenShop;
  final VoidCallback onOpenTrade;
  final bool shopGlow;
  final bool tradeGlow;
  final GlobalKey? cardIconKey;

  /// Card waiting for a tile tap; its banner rides above the cluster.
  final String? pendingCardId;
  final VoidCallback onCancelPending;

  /// Inspector feed: the selected tile (null = nothing selected) and the
  /// upgrade it offers.
  final Tile? selectedTile;
  final int humanPlayerId;
  final bool upgradeEnabled;
  final VoidCallback onUpgrade;

  const _BottomCluster({
    required this.controller,
    required this.rolling,
    required this.onAction,
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
    this.cardIconKey,
  });

  /// Shared size for the hand/shop/trade trio so they read as one family.
  static const _buttonSize = 44.0;

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
                    enabled: buttonsEnabled,
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
                    enabled: buttonsEnabled,
                    glow: shopGlow,
                    onTap: onOpenShop,
                    child: const Text('🏛', style: TextStyle(fontSize: 21)),
                  ),
                  const SizedBox(width: 8),
                  _RoundActionButton(
                    key: ValueKey(tradeGlow ? 'trade-glow' : 'trade'),
                    size: _buttonSize,
                    enabled: buttonsEnabled,
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
    return Tooltip(
      message: objective.description,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: chromePill(),
        child: Text(
          '🎯 ${done ? target : current}/$target ${objective.shortLabel}'
          '${done ? ' ✓' : ''}',
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
        return FilledButton.icon(
          onPressed: () => onAction(const RollDice()),
          icon: const Text('🎲', style: TextStyle(fontSize: 20)),
          label: const Text('Roll the dice'),
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
              FilledButton(
                onPressed: () =>
                    onAction(const ChooseActivation(ActivationMode.sum)),
                child: Text(sum == 7 ? 'Bandit!' : 'Sum $sum'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () =>
                    onAction(const ChooseActivation(ActivationMode.split)),
                child: Text('Split $d1 & $d2'),
              ),
            ],
          ),
        );
      case Phase.awaitingBandit:
        return _statusPill('Place the bandit: tap any claimed tile',
            color: Colors.amber);
      case Phase.main:
        final canRemoveBandit =
            legalActions(state).whereType<RemoveBandit>().isNotEmpty;
        final canBuild =
            legalActions(state).any((a) => a is ClaimHex || a is UpgradeHex);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _statusPill(
              canBuild
                  ? 'Tap a glowing tile to claim it'
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
                      onPressed: () => onAction(
                          legalActions(state).whereType<RemoveBandit>().first),
                      child: const Text('Pay off bandit'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => onAction(const EndTurn()),
                    child: const Text('End Turn'),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../board/board_geometry.dart';
import '../board/board_painter.dart';
import '../board/board_widget.dart';
import '../widgets/adjust_die_dialog.dart';
import '../widgets/bandit_fly_overlay.dart';
import '../widgets/card_fan_overlay.dart';
import '../widgets/dice_roll_overlay.dart';
import '../widgets/shop_overlay.dart';
import '../widgets/trade_overlay.dart';
import '../widgets/production_overlay.dart';
import '../widgets/tile_info_sheet.dart';
import '../widgets/welcome_card.dart';
import '../state/game_controller.dart';
import 'game_over_screen.dart';

class GameScreen extends StatefulWidget {
  final GameController controller;

  const GameScreen({super.key, required this.controller});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  Hex? _selected;
  bool _navigatedToGameOver = false;

  /// A card awaiting a tile tap (drought/charter/banish/brigand).
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
  (List<ProductionGrant>, String)? _production;
  Completer<void>? _productionCompleter;

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

  /// Landmark shop and bank trade overlays.
  bool _shopOpen = false;
  bool _tradeOpen = false;

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
      final hand = state.players.firstWhere((p) => !p.isBot).hand;
      _cardFanOpen = hand.isNotEmpty;
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
    if (const {'drought', 'charter', 'banish', 'brigand'}.contains(cardId)) {
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
    final rolls = events.whereType<DiceRolled>();
    if (rolls.isNotEmpty) {
      final roll = rolls.first;
      final isBot = state.currentPlayer.isBot;
      final completer = Completer<void>();
      setState(() {
        _rollingDice = (roll.d1, roll.d2);
        _rollDuration = Duration(milliseconds: isBot ? 800 : 1200);
        _holdDuration = Duration(milliseconds: isBot ? 500 : 1000);
        _rollCompleter = completer;
      });
      await completer.future;
    }
    if (!mounted) return;
    // Payout moment: float the gains (or the whiff) after an activation.
    final chosen = events.whereType<ActivationChosen>();
    if (chosen.isNotEmpty) {
      final grants = [
        for (final e in events.whereType<ResourcesProduced>()) ...e.grants,
      ];
      final numbers = chosen.first.activatedNumbers;
      // Distinguish "the number isn't on the board" from "nobody owns it".
      final numbersOnBoard = state.tiles.values
          .any((t) => t.number != null && numbers.contains(t.number));
      final label = numbers.toSet().join(' or ');
      final emptyMessage = numbersOnBoard
          ? 'No one owns a hex numbered $label yet'
          : 'No hex is numbered $label';
      final completer = Completer<void>();
      setState(() {
        _production = (grants, emptyMessage);
        _productionCompleter = completer;
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
      else ...[
        ...actions.whereType<ClaimHex>().map((a) => a.target),
        ...actions.whereType<UpgradeHex>().map((a) => a.target),
      ],
    };
  }

  void _onTapHex(Hex hex) {
    if (!controller.isHumanTurn) return;
    final actions = legalActions(state);
    if (_pendingCardId != null) {
      final action = actions.whereType<PlayCard>().where(
          (a) => a.cardId == _pendingCardId && a.targetHex == hex);
      setState(() => _pendingCardId = null);
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
    } else if (actions.contains(UpgradeHex(hex))) {
      _tryDispatch(UpgradeHex(hex));
    } else {
      setState(() => _selected = _selected == hex ? null : hex);
    }
  }

  /// One short sentence about the current moment; null hides the balloon.
  String? _currentTip() {
    if (_rollingDice != null || _banditFlyTarget != null) return null;
    if (_pendingCardId != null) return null;
    if (!controller.isHumanTurn) {
      return 'Rival rolls pay you too - your hexes always earn.';
    }
    switch (state.phase) {
      case Phase.awaitingRoll:
        return 'Roll - every hex matching the dice pays its owner.';
      case Phase.awaitingChoice:
        final (d1, d2) = state.lastDice!;
        return d1 + d2 == 7
            ? 'Sum is 7: unleash the bandit, or split instead.'
            : 'Activate the sum, or each die on its own.';
      case Phase.awaitingBandit:
        return 'Drop the bandit on a rival hex to block it.';
      case Phase.main:
        final actions = legalActions(state);
        final canClaim = actions.any((a) => a is ClaimHex);
        final canUpgrade = actions.any((a) => a is UpgradeHex);
        if (canClaim && canUpgrade) {
          return 'Claim a glowing hex, or upgrade yours to produce x2.';
        }
        if (canClaim) {
          return 'Claim a glowing hex for 1 wood + 1 brick.';
        }
        if (canUpgrade) {
          return 'Upgrade a glowing hex you own - x2 output, more points.';
        }
        return 'Save up - big connected regions score big.';
      case Phase.gameOver:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2E4034),
      body: Stack(
        key: _screenStackKey,
        children: [
          SafeArea(
        child: Column(
          children: [
            _TopBar(state: state),
            _TipBar(
              tipsOn: _tipsOn,
              tip: _currentTip(),
              onToggle: _toggleTips,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _boardSize =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  final geometry = BoardGeometry(_boardSize);
                  return Stack(
                    children: [
                      BoardWidget(
                        state: state,
                        highlighted: _highlighted,
                        selected: _selected,
                        hideBanditAt: _banditFlyTarget,
                        onTapHex: _onTapHex,
                        onLongPressHex: (hex) => showModalBottomSheet<void>(
                          context: context,
                          builder: (_) => TileInfoSheet(
                              state: state, tile: state.tiles[hex]!),
                        ),
                      ),
                      if (_rollingDice != null)
                        Center(
                          child: DiceRollOverlay(
                            key: ValueKey(state.diceHistory.length),
                            d1: _rollingDice!.$1,
                            d2: _rollingDice!.$2,
                            rollDuration: _rollDuration,
                            holdDuration: _holdDuration,
                            flyOffset:
                                Offset(0, constraints.maxHeight / 2 + 30),
                            onDone: _onDiceSettled,
                          ),
                        ),
                      if (_production != null)
                        ProductionOverlay(
                          key: ValueKey(state.diceHistory.length * 100 +
                              _production!.$1.length),
                          geometry: geometry,
                          grants: _production!.$1,
                          emptyMessage: _production!.$2,
                          onDone: _onProductionShown,
                        ),
                      if (_banditFlyTarget != null)
                        BanditFlyOverlay(
                          key: ValueKey(_banditFlyTarget),
                          start: Offset(constraints.maxWidth / 2,
                              constraints.maxHeight / 2),
                          target: geometry.centerOf(_banditFlyTarget!),
                          endSize: geometry.hexSize * 0.80,
                          onDone: _onBanditLanded,
                        ),
                      // Card-targeting banner floats over the board so the
                      // layout (and the hex grid) never shifts.
                      if (_pendingCardId != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            color: Colors.amber.shade800,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${cardCatalog[_pendingCardId]!.name}: '
                                    'tap a glowing tile',
                                    style:
                                        const TextStyle(color: Colors.white),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _pendingCardId = null),
                                  child: const Text('Cancel',
                                      style:
                                          TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // Always-visible shop and trade buttons, floating in
                      // the board's corner so the layout never shifts.
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Column(
                          children: [
                            _RoundActionButton(
                              enabled: controller.isHumanTurn &&
                                  _rollingDice == null,
                              onTap: () => setState(() => _shopOpen = true),
                              child: const Text('🏛',
                                  style: TextStyle(fontSize: 24)),
                            ),
                            const SizedBox(height: 10),
                            _RoundActionButton(
                              enabled: controller.isHumanTurn &&
                                  _rollingDice == null,
                              onTap: () => setState(() => _tradeOpen = true),
                              child: const Icon(Icons.handshake,
                                  size: 24, color: Color(0xFF3A2E20)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            AnimatedSlide(
              offset: _hudVisible ? Offset.zero : const Offset(0, 1.1),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              child: _Hud(
                controller: controller,
                rolling: _rollingDice != null,
                onAction: _tryDispatch,
                onOpenCards: () => setState(() => _cardFanOpen = true),
                cardIconKey: _cardIconKey,
              ),
            ),
          ],
        ),
          ),
          if (_showWelcome)
            WelcomeOverlay(state: state, onStart: _dismissWelcome),
          if (_cardFanOpen)
            CardFanOverlay(
              cardIds: state.players.firstWhere((p) => !p.isBot).hand,
              flyOffset: _fanFlyOffset(),
              playableCardIds: controller.isHumanTurn
                  ? legalActions(state)
                      .whereType<PlayCard>()
                      .map((a) => a.cardId)
                      .toSet()
                  : const {},
              onPlay: _handleCardPlay,
              onDone: () => setState(() => _cardFanOpen = false),
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

/// Circular parchment button for the floating board actions.
class _RoundActionButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  const _RoundActionButton({
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: Material(
        color: const Color(0xFFF4EAD4),
        shape: const CircleBorder(
          side: BorderSide(color: Color(0xFF8A6F4D), width: 2),
        ),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 50,
            height: 50,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Fixed-height strip under the turn banner: a lightbulb toggle plus a
/// short balloon explaining what is going on right now.
class _TipBar extends StatelessWidget {
  final bool tipsOn;
  final String? tip;
  final VoidCallback onToggle;

  const _TipBar({
    required this.tipsOn,
    required this.tip,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(15),
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tipsOn
                      ? Colors.amber.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lightbulb,
                  size: 17,
                  color: tipsOn ? Colors.amber : Colors.white38,
                ),
              ),
            ),
            if (tipsOn && tip != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    tip!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final GameState state;

  const _TopBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final current = state.currentPlayer;
    final currentColor = BoardPainter.playerColors[current.id];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Round ${state.round}/${state.roundCap}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final p in state.players) _playerChip(p),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Whose-turn banner in the active player's color.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: currentColor.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              state.phase == Phase.gameOver
                  ? 'Game over'
                  : current.isBot
                      ? '${current.name} is playing…'
                      : 'Your turn',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerChip(PlayerState p) {
    final active = state.currentPlayerIndex == p.id;
    final color = BoardPainter.playerColors[p.id];
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? color : Colors.transparent,
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

class _Hud extends StatelessWidget {
  final GameController controller;
  final bool rolling;
  final Future<void> Function(GameAction) onAction;
  final VoidCallback onOpenCards;
  final GlobalKey? cardIconKey;

  const _Hud({
    required this.controller,
    required this.rolling,
    required this.onAction,
    required this.onOpenCards,
    this.cardIconKey,
  });

  static const resourceEmoji = {
    Resource.wood: '🪵',
    Resource.grain: '🌾',
    Resource.brick: '🧱',
    Resource.stone: '🪨',
  };

  @override
  Widget build(BuildContext context) {
    final state = controller.state!;
    final human = state.players.firstWhere((p) => !p.isBot);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF243329),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Every row has a FIXED height so the HUD (and the board above it)
          // never shifts as buttons come and go.
          SizedBox(
            height: 40,
            child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final r in Resource.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Text(
                        '${resourceEmoji[r]} ${human.countOf(r)}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (controller.isHumanTurn)
                    InkWell(
                      key: cardIconKey,
                      onTap: onOpenCards,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        child: CardFanIcon(count: human.hand.length),
                      ),
                    ),
                ],
              ),
            ),
            ),
          ),
          SizedBox(
            height: 18,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                human.objectiveId == null
                    ? ''
                    : '🎯 ${objectiveCatalog[human.objectiveId]!.description}'
                        ' · +${objectiveCatalog[human.objectiveId]!.bonusVp} at game end',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 72,
            child: Center(child: _actionRow(context, state)),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(BuildContext context, GameState state) {
    if (rolling) {
      return const Text('Rolling…', style: TextStyle(color: Colors.white54));
    }
    if (!controller.isHumanTurn) {
      return Text(
        '${state.currentPlayer.name} is playing…',
        style: const TextStyle(color: Colors.white54),
      );
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
        return const Text(
          'Place the bandit: tap any claimed tile',
          style: TextStyle(color: Colors.amber),
        );
      case Phase.main:
        final canRemoveBandit =
            legalActions(state).whereType<RemoveBandit>().isNotEmpty;
        final canBuild = legalActions(state)
            .any((a) => a is ClaimHex || a is UpgradeHex);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              canBuild
                  ? 'Tap a glowing tile to claim or upgrade it'
                  : 'Nothing affordable - end your turn',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              overflow: TextOverflow.ellipsis,
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

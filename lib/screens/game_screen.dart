import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../board/board_geometry.dart';
import '../board/board_painter.dart';
import '../board/board_widget.dart';
import '../widgets/bandit_fly_overlay.dart';
import '../widgets/dice_roll_overlay.dart';
import '../widgets/hand_sheet.dart';
import '../widgets/tile_info_sheet.dart';
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

  /// Board canvas size from the last layout, for overlay positioning.
  Size _boardSize = Size.zero;

  GameController get controller => widget.controller;
  GameState get state => controller.state!;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onStateChanged);
    controller.eventDelegate = _presentEvents;
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
        _holdDuration = Duration(milliseconds: isBot ? 800 : 1500);
        _rollCompleter = completer;
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

  Future<void> _openSheet(Widget sheet) async {
    final action = await showModalBottomSheet<GameAction>(
      context: context,
      isScrollControlled: true,
      builder: (_) => sheet,
    );
    if (action == null) return;
    if (action is PlayCard &&
        action.targetHex == null &&
        const {'drought', 'charter', 'banish', 'brigand'}
            .contains(action.cardId)) {
      setState(() => _pendingCardId = action.cardId);
      return;
    }
    await _tryDispatch(action);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2E4034),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(state: state),
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
                      if (_banditFlyTarget != null)
                        BanditFlyOverlay(
                          key: ValueKey(_banditFlyTarget),
                          start: Offset(constraints.maxWidth / 2,
                              constraints.maxHeight / 2),
                          target: geometry.centerOf(_banditFlyTarget!),
                          endSize: geometry.hexSize * 0.80,
                          onDone: _onBanditLanded,
                        ),
                    ],
                  );
                },
              ),
            ),
            if (_pendingCardId != null)
              Container(
                width: double.infinity,
                color: Colors.amber.shade800,
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${cardCatalog[_pendingCardId]!.name}: tap a glowing tile',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _pendingCardId = null),
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            _Hud(
              controller: controller,
              rolling: _rollingDice != null,
              onAction: _tryDispatch,
              onOpenCards: () => _openSheet(HandSheet(state: state)),
              onOpenLandmarks: () => _openSheet(LandmarkSheet(state: state)),
            ),
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
  final VoidCallback onOpenLandmarks;

  const _Hud({
    required this.controller,
    required this.rolling,
    required this.onAction,
    required this.onOpenCards,
    required this.onOpenLandmarks,
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
          Align(
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
                    TextButton(
                      onPressed: onOpenCards,
                      child: Text('🎴 ${human.hand.length}'),
                    ),
                  if (controller.isHumanTurn && state.phase == Phase.main)
                    TextButton(
                      onPressed: onOpenLandmarks,
                      child: Text('🏛 ${state.landmarkOffer.length}'),
                    ),
                  if (controller.isHumanTurn &&
                      state.phase == Phase.main &&
                      Resource.values.any((r) =>
                          human.countOf(r) >=
                          Rules.effectiveTradeRate(human)))
                    TextButton(
                      onPressed: () => _showTradeSheet(context, human),
                      child:
                          Text('Trade ${Rules.effectiveTradeRate(human)}:1'),
                    ),
                ],
              ),
            ),
          ),
          if (human.objectiveId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '🎯 ${objectiveCatalog[human.objectiveId]!.name}: '
                  '${objectiveCatalog[human.objectiveId]!.description}'
                  ' (+${objectiveCatalog[human.objectiveId]!.bonusVp}, secret)',
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
                  : 'Nothing affordable — end your turn',
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

  void _showTradeSheet(BuildContext context, PlayerState human) {
    final rate = Rules.effectiveTradeRate(human);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bank trade: give $rate, take 1',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final give in Resource.values)
                if (human.countOf(give) >= rate)
                  Row(
                    children: [
                      Text('$rate ${resourceEmoji[give]} →'),
                      for (final get in Resource.values)
                        if (get != give)
                          TextButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              onAction(BankTrade(give: give, get: get));
                            },
                            child: Text(resourceEmoji[get]!),
                          ),
                    ],
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

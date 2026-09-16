import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../board/board_painter.dart';
import '../board/board_widget.dart';
import '../widgets/hand_sheet.dart';
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

  GameController get controller => widget.controller;
  GameState get state => controller.state!;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onStateChanged);
    super.dispose();
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
              child: BoardWidget(
                state: state,
                highlighted: _highlighted,
                selected: _selected,
                onTapHex: _onTapHex,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            'Round ${state.round}/${state.roundCap}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const Spacer(),
          for (final p in state.players)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: BoardPainter.playerColors[p.id],
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${scoreFor(state, p.id)}',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: state.currentPlayerIndex == p.id
                          ? FontWeight.w800
                          : FontWeight.w400,
                    ),
                  ),
                  if (state.currentPlayerIndex == p.id)
                    const Text(' ◂',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  final GameController controller;
  final Future<void> Function(GameAction) onAction;
  final VoidCallback onOpenCards;
  final VoidCallback onOpenLandmarks;

  const _Hud({
    required this.controller,
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
          Row(
            children: [
              for (final r in Resource.values)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Text(
                    '${resourceEmoji[r]} ${human.countOf(r)}',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              const Spacer(),
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
                      human.countOf(r) >= Rules.effectiveTradeRate(human)))
                TextButton(
                  onPressed: () => _showTradeSheet(context, human),
                  child: Text(
                      'Trade ${Rules.effectiveTradeRate(human)}:1'),
                ),
            ],
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
            height: 48,
            child: Center(child: _actionRow(context, state)),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(BuildContext context, GameState state) {
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
          label: const Text('Roll'),
        );
      case Phase.awaitingChoice:
        final (d1, d2) = state.lastDice!;
        final sum = d1 + d2;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🎲 $d1 + $d2  ',
                style: const TextStyle(color: Colors.white, fontSize: 16)),
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
        );
      case Phase.awaitingBandit:
        return const Text(
          'Place the bandit: tap any claimed tile',
          style: TextStyle(color: Colors.amber),
        );
      case Phase.main:
        final canRemoveBandit =
            legalActions(state).whereType<RemoveBandit>().isNotEmpty;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tap a glowing tile to claim/upgrade',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(width: 10),
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

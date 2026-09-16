import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

class InMemorySaveStore implements SaveStore {
  String? saved;
  int writes = 0;

  @override
  Future<void> save(String json) async {
    saved = json;
    writes++;
  }

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> clear() async => saved = null;
}

GameController _controller(SaveStore store) => GameController(
      saveStore: store,
      botStepDelay: Duration.zero,
    );

const _setup = [
  PlayerSetup(name: 'You', isBot: false),
  PlayerSetup(name: 'Rival', isBot: true),
];

void main() {
  test('startNewGame produces a human turn and autosaves', () async {
    final store = InMemorySaveStore();
    final c = _controller(store);
    await c.startNewGame(seed: 1, players: _setup);
    expect(c.state, isNotNull);
    expect(c.isHumanTurn, isTrue);
    expect(c.state!.phase, Phase.awaitingRoll);
    expect(store.saved, isNotNull);
  });

  test('after human ends turn, bots play automatically back to human',
      () async {
    final store = InMemorySaveStore();
    final c = _controller(store);
    await c.startNewGame(seed: 2, players: _setup);

    // Human turn: roll, choose, end.
    await c.dispatch(const RollDice());
    await c.dispatch(legalActions(c.state!).first);
    while (c.state!.phase == Phase.awaitingBandit) {
      await c.dispatch(legalActions(c.state!).first);
    }
    await c.dispatch(const EndTurn());

    // Bot turn must have fully resolved.
    expect(
      c.isHumanTurn || c.state!.phase == Phase.gameOver,
      isTrue,
    );
    expect(c.state!.round, 2);
    expect(store.writes, greaterThan(3));
  });

  test('resume restores the exact saved state', () async {
    final store = InMemorySaveStore();
    final c1 = _controller(store);
    await c1.startNewGame(seed: 3, players: _setup);
    await c1.dispatch(const RollDice());
    final savedJson = store.saved;

    final c2 = _controller(store);
    final resumed = await c2.resume();
    expect(resumed, isTrue);
    expect(gameStateToJson(c2.state!), gameStateToJson(c1.state!));
    expect(savedJson, isNotNull);
  });

  test('resume returns false with no save', () async {
    final c = _controller(InMemorySaveStore());
    expect(await c.resume(), isFalse);
    expect(c.state, isNull);
  });

  test('illegal human action throws and leaves state untouched', () async {
    final store = InMemorySaveStore();
    final c = _controller(store);
    await c.startNewGame(seed: 4, players: _setup);
    final before = gameStateToJson(c.state!);
    expect(
      () => c.dispatch(const EndTurn()),
      throwsA(isA<IllegalActionException>()),
    );
    expect(gameStateToJson(c.state!), before);
  });

  test('a game driven to completion reaches gameOver with a winner',
      () async {
    final store = InMemorySaveStore();
    final c = _controller(store);
    await c.startNewGame(seed: 5, players: _setup);
    var guard = 0;
    while (c.state!.phase != Phase.gameOver) {
      // Human plays stub-bot moves too, for the test.
      await c.dispatch(StubBot.chooseAction(c.state!));
      expect(++guard, lessThan(2000));
    }
    expect(c.state!.winnerId, isNotNull);
  });
}

import 'dart:convert';

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
    // A finished game must not leave an autosave behind.
    expect(store.saved, isNull);
  });

  test('hasResumableGame is true mid-game, false with no save or after over',
      () async {
    final store = InMemorySaveStore();
    final c = _controller(store);
    expect(await c.hasResumableGame(), isFalse);

    await c.startNewGame(seed: 6, players: _setup);
    expect(await c.hasResumableGame(), isTrue);

    var guard = 0;
    while (c.state!.phase != Phase.gameOver) {
      await c.dispatch(StubBot.chooseAction(c.state!));
      expect(++guard, lessThan(2000));
    }
    expect(await c.hasResumableGame(), isFalse);
  });

  test('resume clears a stale finished-game save and returns false',
      () async {
    final store = InMemorySaveStore();
    final c = _controller(store);
    await c.startNewGame(seed: 7, players: _setup);
    var guard = 0;
    while (c.state!.phase != Phase.gameOver) {
      await c.dispatch(StubBot.chooseAction(c.state!));
      expect(++guard, lessThan(2000));
    }
    // Simulate an old build that autosaved the finished state.
    store.saved = jsonEncode(gameStateToJson(c.state!));

    final c2 = _controller(store);
    expect(await c2.resume(), isFalse);
    expect(store.saved, isNull);
  });
}

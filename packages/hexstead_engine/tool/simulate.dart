// Bot-vs-bot balance harness.
//
// Usage: dart run tool/simulate.dart [--games N] [--seats hard,easy,...]
//        [--target VP] [--cap ROUNDS]
//
// Reports win rates per seat and difficulty, game length distribution,
// score stats, and card/landmark usage - the tuning loop for eval weights
// and rule constants.
import 'package:hexstead_engine/hexstead_engine.dart';

void main(List<String> args) {
  final games = _intArg(args, '--games') ?? 500;
  final target = _intArg(args, '--target') ?? Rules.defaultTargetVp;
  final cap = _intArg(args, '--cap') ?? Rules.defaultRoundCap;
  final seatSpec = _stringArg(args, '--seats') ?? 'hard,hard,hard';
  final difficulties = [
    for (final name in seatSpec.split(','))
      BotDifficulty.values.byName(name.trim()),
  ];

  final seatWins = List.filled(difficulties.length, 0);
  final roundCounts = <int, int>{};
  final scoresBySeat = List.generate(difficulties.length, (_) => <int>[]);
  final landmarkBuys = <String, int>{};
  final landmarkWins = <String, int>{};
  final cardPlays = <String, int>{};
  var instantWins = 0;
  var totalActions = 0;
  final sw = Stopwatch()..start();

  for (var seed = 0; seed < games; seed++) {
    var s = GameState.newGame(
      seed: seed,
      targetVp: target,
      roundCap: cap,
      players: [
        for (final (i, d) in difficulties.indexed)
          PlayerSetup(name: 'S$i', isBot: true, difficulty: d),
      ],
    );
    final playedLandmarks = <String, int>{}; // landmark -> buyer
    while (s.phase != Phase.gameOver) {
      final action = SmartBot.chooseAction(s);
      final result = apply(s, action);
      totalActions++;
      for (final e in result.events) {
        if (e is LandmarkPurchased) {
          landmarkBuys[e.landmarkId] = (landmarkBuys[e.landmarkId] ?? 0) + 1;
          playedLandmarks[e.landmarkId] = e.playerId;
        }
        if (e is CardPlayed) {
          cardPlays[e.cardId] = (cardPlays[e.cardId] ?? 0) + 1;
        }
      }
      s = result.state;
    }
    if (s.round < cap) instantWins++;
    seatWins[s.winnerId!]++;
    roundCounts[s.round] = (roundCounts[s.round] ?? 0) + 1;
    for (var i = 0; i < difficulties.length; i++) {
      scoresBySeat[i].add(finalScoreFor(s, i));
    }
    for (final e in playedLandmarks.entries) {
      if (e.value == s.winnerId) {
        landmarkWins[e.key] = (landmarkWins[e.key] ?? 0) + 1;
      }
    }
  }
  sw.stop();

  print('=== $games games, seats [$seatSpec], target $target, cap $cap ===');
  print('wall clock: ${sw.elapsedMilliseconds}ms '
      '(${(sw.elapsedMicroseconds / games / 1000).toStringAsFixed(1)}ms/game, '
      '${(totalActions / games).toStringAsFixed(0)} actions/game)');
  print('');
  for (var i = 0; i < difficulties.length; i++) {
    final scores = scoresBySeat[i]..sort();
    final mean =
        scores.fold(0, (a, b) => a + b) / scores.length;
    print('seat $i (${difficulties[i].name}): '
        'wins ${(seatWins[i] / games * 100).toStringAsFixed(1)}%  '
        'score mean ${mean.toStringAsFixed(1)} '
        'median ${scores[scores.length ~/ 2]}');
  }
  print('');
  print('instant VP wins: ${(instantWins / games * 100).toStringAsFixed(1)}%');
  final rounds = roundCounts.keys.toList()..sort();
  print('rounds: ${[for (final r in rounds) '$r:${roundCounts[r]}'].join(' ')}');
  print('');
  print('landmarks (buys / % of buyers who won):');
  for (final id in landmarkCatalog.keys) {
    final buys = landmarkBuys[id] ?? 0;
    final wins = landmarkWins[id] ?? 0;
    final rate = buys == 0 ? '-' : '${(wins / buys * 100).toStringAsFixed(0)}%';
    print('  ${id.padRight(14)} $buys / $rate');
  }
  print('cards played:');
  for (final id in cardCatalog.keys) {
    print('  ${id.padRight(14)} ${cardPlays[id] ?? 0}');
  }
}

int? _intArg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? int.parse(args[i + 1]) : null;
}

String? _stringArg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

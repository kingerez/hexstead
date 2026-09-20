import 'dart:convert';

import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One finished game's result on the local leaderboard.
class ScoreEntry {
  final int score;
  final double multiplier;
  final int finalScore;
  final String botSummary;
  final DateTime date;

  const ScoreEntry({
    required this.score,
    required this.multiplier,
    required this.finalScore,
    required this.botSummary,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'score': score,
        'multiplier': multiplier,
        'finalScore': finalScore,
        'botSummary': botSummary,
        'date': date.toIso8601String(),
      };

  factory ScoreEntry.fromJson(Map<String, dynamic> json) => ScoreEntry(
        score: json['score'] as int,
        multiplier: (json['multiplier'] as num).toDouble(),
        finalScore: json['finalScore'] as int,
        botSummary: json['botSummary'] as String,
        date: DateTime.parse(json['date'] as String),
      );
}

/// Polytopia-style reward for harder setups: each bot adds to the multiplier
/// by difficulty (easy +1, medium +2, hard +3), so it is always a whole
/// number - ×2 for a lone easy bot up to ×10 for three cruel ones.
int difficultyMultiplier(List<PlayerState> players) {
  var total = 1;
  for (final p in players) {
    if (!p.isBot) continue;
    total += switch (p.difficulty) {
      BotDifficulty.easy => 1,
      BotDifficulty.medium => 2,
      BotDifficulty.hard => 3,
    };
  }
  return total;
}

class HighScoreStore {
  static const _key = 'high_scores_v1';
  static const _maxEntries = 10;

  /// Records a finished game. Returns true when it is a new personal best.
  Future<bool> record(ScoreEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final scores = await load();
    final isBest =
        scores.isEmpty || entry.finalScore > scores.first.finalScore;
    final updated = [...scores, entry]
      ..sort((a, b) => b.finalScore.compareTo(a.finalScore));
    await prefs.setString(
      _key,
      jsonEncode([
        for (final e in updated.take(_maxEntries)) e.toJson(),
      ]),
    );
    return isBest;
  }

  Future<List<ScoreEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    return [
      for (final e in jsonDecode(raw) as List)
        ScoreEntry.fromJson(e as Map<String, dynamic>),
    ];
  }
}

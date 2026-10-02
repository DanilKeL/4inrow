import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/levels/model/game_level.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class LevelRepository {
  new(this._preferences);
  final SharedPreferences _preferences;
  List<GameLevel>? _cache;

  Future<List<GameLevel>> load() async {
    if (_cache case final cache?) return cache;
    final decoded = jsonDecode(
      await rootBundle.loadString('assets/data/levels.json'),
    ) as List;
    return _cache = [
      for (final value in decoded)
        GameLevel.fromJson(value as Map<String, dynamic>),
    ];
  }

  Future<GameLevel?> get(int id) async =>
      (await load()).where((level) => level.id == id).firstOrNull;

  Future<Map<int, int>> best() async {
    final String? encoded = _preferences.getString('four-cubed-levels-v1');
    if (encoded == null) return {};
    try {
      final Object? decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return {};
      final result = <int, int>{};
      for (final MapEntry<String, dynamic> entry in decoded.entries) {
        final Object? value = entry.value;
        final int? id = int.tryParse(entry.key);
        if (id != null && value is int && value > 0 && value <= 63) {
          result[id] = value;
        }
      }
      return result;
    } on FormatException {
      return {};
    }
  }

  Future<void> record(GameLevel level, GameSnapshot snapshot) async {
    if (snapshot.winner != Player.one) return;
    final int moves = snapshot.history
        .skip(level.preset.length)
        .where((move) => move.player == Player.one)
        .length;
    final Map<int, int> values = await best();
    if ((values[level.id] ?? 1 << 20) <= moves) return;
    values[level.id] = moves;
    await _preferences.setString(
      'four-cubed-levels-v1',
      jsonEncode({
        for (final entry in values.entries) '${entry.key}': entry.value,
      }),
    );
  }

  GameSnapshot position(GameLevel level) => GameEngine.replay(level.preset);
}

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/levels/model/game_level.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class LevelRepository {
  new(this._preferences, [this._restClient]);
  final SharedPreferences _preferences;
  final RestClient? _restClient;
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

  Future<Map<int, int>> sync(String owner) async {
    final RestClient? client = _restClient;
    if (client == null) throw StateError('Level sync is unavailable.');
    final Map<int, int> local = await best();
    final Map<String, dynamic> response = await client.post(
      '/auth/levels',
      data: <String, Object?>{
        'owner': owner,
        'best': <String, int>{
          for (final entry in local.entries) '${entry.key}': entry.value,
        },
      },
    );
    final Object? raw = response['best'];
    if (raw is! Map<String, dynamic>) return local;
    final Map<int, int> merged = <int, int>{...local};
    for (final MapEntry<String, dynamic> entry in raw.entries) {
      final int? id = int.tryParse(entry.key);
      final Object? moves = entry.value;
      if (id != null && moves is int && moves > 0 && moves <= 63) {
        merged[id] = (merged[id] ?? 64) < moves ? merged[id]! : moves;
      }
    }
    await _preferences.setString(
      'four-cubed-levels-v1',
      jsonEncode(<String, int>{
        for (final entry in merged.entries) '${entry.key}': entry.value,
      }),
    );
    return merged;
  }

  GameSnapshot position(GameLevel level) => GameEngine.replay(level.preset);
}

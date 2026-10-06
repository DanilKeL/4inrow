import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:four3/src/feature/levels/domain/model/game_level.dart';

abstract interface class LevelAssetDatasource {
  const new();

  Future<List<GameLevel>> load();
}

final class LevelAssetDatasource$Bundle implements LevelAssetDatasource {
  new();

  List<GameLevel>? _cache;

  String get _assetPath => 'assets/data/levels.json';

  @override
  Future<List<GameLevel>> load() async {
    if (_cache case final cache?) return cache;
    final Object? decoded = jsonDecode(await rootBundle.loadString(_assetPath));
    if (decoded is! List) {
      throw const FormatException('Invalid levels payload');
    }
    return _cache = [
      for (final Object? value in decoded)
        GameLevel.fromJson(value! as Map<String, dynamic>),
    ];
  }
}

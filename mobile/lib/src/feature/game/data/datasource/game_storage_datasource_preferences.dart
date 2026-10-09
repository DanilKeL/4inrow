import 'dart:convert';

import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/feature/game/data/datasource/game_storage_datasource.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/game/model/saved_game.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';

final class GameStorageDatasource$Preferences implements GameStorageDatasource {
  const new({required this.preferencesDatasourceTool});

  final PreferencesDatasourceTool preferencesDatasourceTool;

  String get _activeGameKey => 'four-cubed-active-game-v1';
  String get _legacyActiveGameKey => 'four-cubed-active-game';

  @override
  SavedGame? load() {
    final String? value = preferencesDatasourceTool.getString(_activeGameKey);
    if (value == null) return _loadLegacy();
    try {
      final Object? decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid saved game');
      }
      return SavedGame.fromJson(decoded);
    } on Object {
      preferencesDatasourceTool.removeKey(_activeGameKey).ignore();
      return null;
    }
  }

  SavedGame? _loadLegacy() {
    final String? value = preferencesDatasourceTool.getString(
      _legacyActiveGameKey,
    );
    if (value == null) return null;
    try {
      final GameSnapshot snapshot = GameEngine.deserialize(value);
      if (snapshot.status != GameStatus.playing || snapshot.history.isEmpty) {
        throw const FormatException('Invalid legacy saved game');
      }
      final SavedGame game = SavedGame.fromViewData(
        GameViewData(
          snapshot: snapshot,
          recordId: 'legacy-${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
      preferencesDatasourceTool.removeKey(_legacyActiveGameKey).ignore();
      save(game).ignore();
      return game;
    } on Object {
      preferencesDatasourceTool.removeKey(_legacyActiveGameKey).ignore();
      return null;
    }
  }

  @override
  Future<void> save(SavedGame game) => preferencesDatasourceTool.setString(
    _activeGameKey,
    jsonEncode(game.toJson()),
  );

  @override
  Future<void> clear() async {
    await preferencesDatasourceTool.removeKey(_activeGameKey);
    await preferencesDatasourceTool.removeKey(_legacyActiveGameKey);
  }
}

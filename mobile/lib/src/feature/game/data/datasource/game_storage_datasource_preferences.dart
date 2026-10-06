import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/feature/game/data/datasource/game_storage_datasource.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';

final class GameStorageDatasource$Preferences implements GameStorageDatasource {
  const new({required this.preferencesDatasourceTool});

  final PreferencesDatasourceTool preferencesDatasourceTool;

  String get _activeGameKey => 'four-cubed-active-game';

  @override
  GameSnapshot? load() {
    final String? value = preferencesDatasourceTool.getString(_activeGameKey);
    if (value == null) return null;
    try {
      return GameEngine.deserialize(value);
    } on FormatException {
      preferencesDatasourceTool.removeKey(_activeGameKey).ignore();
      return null;
    }
  }

  @override
  Future<void> save(GameSnapshot snapshot) => preferencesDatasourceTool
      .setString(_activeGameKey, GameEngine.serialize(snapshot));

  @override
  Future<void> clear() => preferencesDatasourceTool.removeKey(_activeGameKey);
}

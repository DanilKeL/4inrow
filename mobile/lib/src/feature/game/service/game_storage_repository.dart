import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class GameStorageRepository {
  const new(this._preferences);
  static const _key = 'four-cubed-active-game';
  final SharedPreferences _preferences;

  GameSnapshot? load() {
    final String? value = _preferences.getString(_key);
    if (value == null) return null;
    try {
      return GameEngine.deserialize(value);
    } on FormatException {
      _preferences.remove(_key);
      return null;
    }
  }

  Future<void> save(GameSnapshot snapshot) =>
      _preferences.setString(_key, GameEngine.serialize(snapshot));

  Future<void> clear() => _preferences.remove(_key);
}

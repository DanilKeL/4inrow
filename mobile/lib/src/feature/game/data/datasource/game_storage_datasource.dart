import 'package:four3/src/feature/game/model/saved_game.dart';

abstract interface class GameStorageDatasource {
  const new();

  SavedGame? load();
  Future<void> save(SavedGame game);
  Future<void> clear();
}

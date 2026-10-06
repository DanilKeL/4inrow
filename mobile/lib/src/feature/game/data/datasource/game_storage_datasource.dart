import 'package:four3/src/feature/game/model/game_models.dart';

abstract interface class GameStorageDatasource {
  const new();

  GameSnapshot? load();
  Future<void> save(GameSnapshot snapshot);
  Future<void> clear();
}

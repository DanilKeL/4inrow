import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/levels/domain/model/game_level.dart';

abstract interface class LevelRepository {
  const new();

  Future<List<GameLevel>> load();
  Future<GameLevel?> get(int id);
  Future<Map<int, int>> best();
  Future<void> record(GameLevel level, GameSnapshot snapshot);
  Future<Map<int, int>> sync(String owner);
  GameSnapshot position(GameLevel level);
}

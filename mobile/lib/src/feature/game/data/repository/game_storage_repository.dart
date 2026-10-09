import 'package:four3/src/feature/game/data/datasource/game_storage_datasource.dart';
import 'package:four3/src/feature/game/domain/repository/game_storage_repository.dart';
import 'package:four3/src/feature/game/model/saved_game.dart';

final class GameStorageRepository$Local implements GameStorageRepository {
  const new({required this.datasource});

  final GameStorageDatasource datasource;

  @override
  SavedGame? load() => datasource.load();

  @override
  Future<void> save(SavedGame game) => datasource.save(game);

  @override
  Future<void> clear() => datasource.clear();
}

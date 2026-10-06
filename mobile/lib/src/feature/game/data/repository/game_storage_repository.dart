import 'package:four3/src/feature/game/data/datasource/game_storage_datasource.dart';
import 'package:four3/src/feature/game/domain/repository/game_storage_repository.dart';
import 'package:four3/src/feature/game/model/game_models.dart';

final class GameStorageRepository$Local implements GameStorageRepository {
  const new({required this.datasource});

  final GameStorageDatasource datasource;

  @override
  GameSnapshot? load() => datasource.load();

  @override
  Future<void> save(GameSnapshot snapshot) => datasource.save(snapshot);

  @override
  Future<void> clear() => datasource.clear();
}

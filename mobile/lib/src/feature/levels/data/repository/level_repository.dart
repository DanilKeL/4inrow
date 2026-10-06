import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/levels/data/datasource/level_asset_datasource.dart';
import 'package:four3/src/feature/levels/data/datasource/level_datasource_rest_client.dart';
import 'package:four3/src/feature/levels/data/datasource/level_preferences_datasource.dart';
import 'package:four3/src/feature/levels/domain/model/game_level.dart';
import 'package:four3/src/feature/levels/domain/repository/level_repository.dart';

final class LevelRepository$Local implements LevelRepository {
  const new({
    required this.assetDatasource,
    required this.preferencesDatasource,
    this.remoteDatasource,
  });

  final LevelAssetDatasource assetDatasource;
  final LevelPreferencesDatasource preferencesDatasource;
  final LevelRemoteDatasource? remoteDatasource;

  @override
  Future<List<GameLevel>> load() => assetDatasource.load();

  @override
  Future<GameLevel?> get(int id) async =>
      (await load()).where((level) => level.id == id).firstOrNull;

  @override
  Future<Map<int, int>> best() async => preferencesDatasource.loadBest();

  @override
  Future<void> record(GameLevel level, GameSnapshot snapshot) async {
    if (snapshot.winner != Player.one) return;
    final int moves = snapshot.history
        .skip(level.preset.length)
        .where((move) => move.player == Player.one)
        .length;
    final Map<int, int> values = await best();
    if ((values[level.id] ?? 1 << 20) <= moves) return;
    values[level.id] = moves;
    await preferencesDatasource.saveBest(values);
  }

  @override
  Future<Map<int, int>> sync(String owner) async {
    final LevelRemoteDatasource? remote = remoteDatasource;
    if (remote == null) throw StateError('Level sync is unavailable.');
    final Map<int, int> local = await best();
    final Map<String, dynamic> response = await remote.sync(
      owner: owner,
      best: local,
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
    await preferencesDatasource.saveBest(merged);
    return merged;
  }

  @override
  GameSnapshot position(GameLevel level) => GameEngine.replay(level.preset);
}

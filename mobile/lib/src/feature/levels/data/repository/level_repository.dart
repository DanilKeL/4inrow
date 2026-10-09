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
  Future<Map<int, int>> best(String? owner) async =>
      preferencesDatasource.load().bestFor(owner);

  @override
  Future<void> record(
    GameLevel level,
    GameSnapshot snapshot,
    String? owner,
  ) async {
    if (snapshot.winner != Player.one) return;
    final int moves = snapshot.history
        .skip(level.preset.length)
        .where((move) => move.player == Player.one)
        .length;
    final LevelProgressCache cache = preferencesDatasource.load();
    final Map<int, int> values = cache.bestFor(owner);
    if ((values[level.id] ?? 1 << 20) <= moves) return;
    values[level.id] = moves;
    await preferencesDatasource.save(
      owner == null
          ? cache.copyWith(guestBest: values)
          : cache.copyWith(
              accounts: <String, Map<int, int>>{
                ...cache.accounts,
                owner: values,
              },
              dirtyAccounts: <String>{...cache.dirtyAccounts, owner},
            ),
    );
  }

  @override
  bool needsSync(String owner) =>
      preferencesDatasource.load().dirtyAccounts.contains(owner);

  @override
  Future<Map<int, int>> sync(String owner) async {
    final LevelRemoteDatasource? remote = remoteDatasource;
    if (remote == null) throw StateError('Level sync is unavailable.');
    LevelProgressCache before = preferencesDatasource.load();
    final Map<int, int> local = before.bestFor(owner);
    final Set<String> dirtyAccounts = <String>{...before.dirtyAccounts, owner};
    if (before.legacyPending) {
      _merge(local, before.guestBest);
    }
    before = before.copyWith(
      accounts: <String, Map<int, int>>{...before.accounts, owner: local},
      legacyPending: false,
      dirtyAccounts: dirtyAccounts,
    );
    await preferencesDatasource.save(before);
    final Map<String, dynamic> response = await remote.sync(
      owner: owner,
      best: local,
    );
    if (response['username'] != owner) throw StateError('Account changed.');
    final Object? raw = response['best'];
    if (raw is! Map<String, dynamic>) return local;
    final LevelProgressCache current = preferencesDatasource.load();
    final Map<int, int> merged = current.bestFor(owner);
    final Map<int, int> server = <int, int>{};
    for (final MapEntry<String, dynamic> entry in raw.entries) {
      final int? id = int.tryParse(entry.key);
      final Object? moves = entry.value;
      if (id != null &&
          id >= 1 &&
          id <= 40 &&
          moves is int &&
          moves > 0 &&
          moves <= 63) {
        server[id] = moves;
        merged[id] = (merged[id] ?? 64) < moves ? merged[id]! : moves;
      }
    }
    final Set<String> nextDirty = <String>{...current.dirtyAccounts};
    if (merged.entries.any((entry) => server[entry.key] != entry.value)) {
      nextDirty.add(owner);
    } else {
      nextDirty.remove(owner);
    }
    await preferencesDatasource.save(
      current.copyWith(
        accounts: <String, Map<int, int>>{...current.accounts, owner: merged},
        legacyPending: false,
        dirtyAccounts: nextDirty,
      ),
    );
    return merged;
  }

  static void _merge(Map<int, int> target, Map<int, int> source) {
    for (final MapEntry<int, int> entry in source.entries) {
      final int? existing = target[entry.key];
      if (existing == null || entry.value < existing) {
        target[entry.key] = entry.value;
      }
    }
  }

  @override
  GameSnapshot position(GameLevel level) => GameEngine.replay(level.preset);
}

import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/match_history/data/datasource/match_history_datasource.dart';
import 'package:four3/src/feature/match_history/domain/model/match_history_models.dart';
import 'package:four3/src/feature/match_history/domain/repository/match_history_repository.dart';

final class MatchHistoryRepository$Api implements MatchHistoryRepository {
  const new({required this.datasource});

  final MatchHistoryDatasource datasource;

  @override
  Future<MatchHistorySnapshot> load() async =>
      MatchHistorySnapshot.fromJson(await datasource.load());

  @override
  Future<MatchHistorySnapshot> save(
    String owner,
    String id,
    GameViewData data,
  ) async => MatchHistorySnapshot.fromJson(
    await datasource.save(<String, Object?>{
      'owner': owner,
      'id': id,
      'names': data.names,
      'mode': data.mode.name,
      'elapsed': data.elapsed,
      'game': GameEngine.serialize(data.snapshot),
    }),
  );

  @override
  Future<MatchHistorySnapshot> rename(
    String owner,
    String id,
    String title,
  ) async => MatchHistorySnapshot.fromJson(
    await datasource.rename(<String, Object?>{
      'owner': owner,
      'id': id,
      'title': title,
    }),
  );

  @override
  Future<MatchHistorySnapshot> remove(String owner, String id) async =>
      MatchHistorySnapshot.fromJson(
        await datasource.remove(<String, Object?>{'owner': owner, 'id': id}),
      );
}

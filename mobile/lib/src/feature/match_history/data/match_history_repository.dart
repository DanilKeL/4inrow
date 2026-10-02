import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/match_history/data/match_history_datasource.dart';
import 'package:four3/src/feature/match_history/model/match_history_models.dart';

final class MatchHistoryRepository {
  const new({required this._datasource});

  final MatchHistoryDatasource _datasource;

  Future<MatchHistorySnapshot> load() async =>
      MatchHistorySnapshot.fromJson(await _datasource.load());

  Future<MatchHistorySnapshot> save(
    String owner,
    String id,
    GameViewData data,
  ) async => MatchHistorySnapshot.fromJson(
    await _datasource.save(<String, Object?>{
      'owner': owner,
      'id': id,
      'names': data.names,
      'mode': data.mode.name,
      'elapsed': data.elapsed,
      'game': GameEngine.serialize(data.snapshot),
    }),
  );

  Future<MatchHistorySnapshot> rename(
    String owner,
    String id,
    String title,
  ) async => MatchHistorySnapshot.fromJson(
    await _datasource.rename(<String, Object?>{
      'owner': owner,
      'id': id,
      'title': title,
    }),
  );

  Future<MatchHistorySnapshot> remove(String owner, String id) async =>
      MatchHistorySnapshot.fromJson(
        await _datasource.remove(<String, Object?>{'owner': owner, 'id': id}),
      );
}

import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/match_history/domain/model/match_history_models.dart';

abstract interface class MatchHistoryRepository {
  const new();

  Future<MatchHistorySnapshot> load();
  Future<MatchHistorySnapshot> save(String owner, String id, GameViewData data);
  Future<MatchHistorySnapshot> rename(String owner, String id, String title);
  Future<MatchHistorySnapshot> remove(String owner, String id);
}

import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/match_history/domain/model/match_history_models.dart';

abstract interface class MatchHistoryRepository {
  const new();

  Future<MatchHistorySnapshot> load(String owner);
  Future<MatchHistorySnapshot?> save(
    String owner,
    String? currentOwner,
    String id,
    GameViewData data,
  );
  Future<MatchHistorySnapshot?> flush(String? owner);
  Future<MatchHistorySnapshot> rename(String owner, String id, String title);
  Future<MatchHistorySnapshot> remove(String owner, String id);
}

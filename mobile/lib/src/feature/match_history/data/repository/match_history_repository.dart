import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/match_history/data/datasource/match_history_datasource.dart';
import 'package:four3/src/feature/match_history/data/datasource/match_history_preferences_datasource.dart';
import 'package:four3/src/feature/match_history/domain/model/match_history_models.dart';
import 'package:four3/src/feature/match_history/domain/repository/match_history_repository.dart';

final class MatchHistoryRepository$Api implements MatchHistoryRepository {
  const new({required this.datasource, required this.preferences});

  final MatchHistoryDatasource datasource;
  final MatchHistoryPreferencesDatasource preferences;

  @override
  Future<MatchHistorySnapshot> load(String owner) async {
    final MatchHistorySnapshot? flushed = await flush(owner);
    final MatchHistorySnapshot snapshot =
        flushed ?? MatchHistorySnapshot.fromJson(await datasource.load());
    if (snapshot.username != owner) throw StateError('Account changed.');
    return snapshot;
  }

  @override
  Future<MatchHistorySnapshot?> save(
    String owner,
    String? currentOwner,
    String id,
    GameViewData data,
  ) async {
    final PendingMatch entry = PendingMatch(
      owner: owner,
      id: id,
      names: data.names,
      mode: data.mode.name,
      elapsed: data.elapsed,
      game: data.snapshot,
    );
    final List<PendingMatch> pending = <PendingMatch>[
      ...preferences.loadPending().where(
        (value) => value.owner != owner || value.id != id,
      ),
      entry,
    ];
    await preferences.savePending(
      pending.length <= 100 ? pending : pending.sublist(pending.length - 100),
    );
    if (owner != currentOwner) return null;
    return flush(owner);
  }

  @override
  Future<MatchHistorySnapshot?> flush(String? owner) async {
    if (owner == null) return null;
    List<PendingMatch> pending = preferences.loadPending();
    MatchHistorySnapshot? latest;
    for (final PendingMatch entry
        in pending.where((value) => value.owner == owner).toList()) {
      latest = MatchHistorySnapshot.fromJson(
        await datasource.save(entry.toRequest()),
      );
      if (latest.username != owner) throw StateError('Account changed.');
      pending = pending.where((value) => value.id != entry.id).toList();
      await preferences.savePending(pending);
    }
    return latest;
  }

  @override
  Future<MatchHistorySnapshot> rename(
    String owner,
    String id,
    String title,
  ) async {
    final MatchHistorySnapshot snapshot = MatchHistorySnapshot.fromJson(
      await datasource.rename(<String, Object?>{
        'owner': owner,
        'id': id,
        'title': title,
      }),
    );
    if (snapshot.username != owner) throw StateError('Account changed.');
    return snapshot;
  }

  @override
  Future<MatchHistorySnapshot> remove(String owner, String id) async {
    final MatchHistorySnapshot snapshot = MatchHistorySnapshot.fromJson(
      await datasource.remove(<String, Object?>{'owner': owner, 'id': id}),
    );
    if (snapshot.username != owner) throw StateError('Account changed.');
    return snapshot;
  }
}

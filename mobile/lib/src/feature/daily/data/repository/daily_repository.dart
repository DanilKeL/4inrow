import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/daily/data/datasource/daily_datasource.dart';
import 'package:four3/src/feature/daily/data/datasource/daily_preferences_datasource.dart';
import 'package:four3/src/feature/daily/domain/model/daily_models.dart';
import 'package:four3/src/feature/daily/domain/repository/daily_repository.dart';
import 'package:four3/src/feature/game/model/game_models.dart';

final class DailyRepository$Api implements DailyRepository {
  const new({required this.remote, required this.preferences});

  final DailyRemoteDatasource remote;
  final DailyPreferencesDatasource preferences;

  @override
  Future<DailySnapshot> load() async {
    try {
      final DailySnapshot snapshot = DailySnapshot.fromJson(
        await remote.load(),
      );
      await preferences.saveCached(snapshot);
      return snapshot;
    } on Object {
      final DailySnapshot? cached = preferences.loadCached();
      if (cached != null && cached.isCurrent) return cached;
      rethrow;
    }
  }

  @override
  Future<DailySubmission> saveWin({
    required String id,
    required DailyChallenge challenge,
    required GameSnapshot game,
    required String? owner,
    required String? currentOwner,
  }) async {
    if (game.status != GameStatus.won || game.winner != Player.one) {
      return DailySubmission(id: id, status: DailySubmissionStatus.failed);
    }
    if (owner == null) {
      return DailySubmission(id: id, status: DailySubmissionStatus.guest);
    }
    final List<MoveCandidate> moves = game.history
        .skip(challenge.preset.length)
        .where((move) => move.player == Player.one)
        .map((move) => MoveCandidate(move.x, move.y))
        .toList(growable: false);
    final PendingDailyResult entry = PendingDailyResult(
      id: id,
      owner: owner,
      challengeId: challenge.id,
      expiresAt: challenge.expiresAt,
      moves: moves,
    );
    final List<PendingDailyResult> pending = <PendingDailyResult>[
      ...preferences.loadPending().where((value) => value.id != id),
      entry,
    ];
    await preferences.savePending(
      pending.length <= 20 ? pending : pending.sublist(pending.length - 20),
    );
    if (owner != currentOwner) {
      return DailySubmission(id: id, status: DailySubmissionStatus.pending);
    }
    try {
      final DailyFlushResult result = await flush(owner);
      if (result.verifiedIds.contains(id)) {
        return DailySubmission(
          id: id,
          status: DailySubmissionStatus.verified,
          snapshot: result.snapshot,
        );
      }
      if (result.failure?.id == id) return result.failure!;
      return DailySubmission(id: id, status: DailySubmissionStatus.pending);
    } on Object {
      return DailySubmission(
        id: id,
        status: DailySubmissionStatus.failed,
        retryable: true,
      );
    }
  }

  @override
  Future<DailyFlushResult> flush(String? owner) async {
    if (owner == null) return const DailyFlushResult();
    List<PendingDailyResult> pending = preferences.loadPending();
    DailySnapshot? latest;
    final Set<String> verified = <String>{};
    for (final PendingDailyResult entry
        in pending.where((value) => value.owner == owner).toList()) {
      try {
        latest = DailySnapshot.fromJson(
          await remote.submit(
            owner: owner,
            challengeId: entry.challengeId,
            moves: <Map<String, int>>[
              for (final MoveCandidate move in entry.moves)
                <String, int>{'x': move.x, 'y': move.y},
            ],
          ),
        );
        pending = pending.where((value) => value.id != entry.id).toList();
        await preferences.savePending(pending);
        await preferences.saveCached(latest);
        verified.add(entry.id);
      } on RestClientException catch (error) {
        final bool retryable = !<int>{
          400,
          404,
          409,
          410,
          422,
        }.contains(error.statusCode);
        if (!retryable) {
          pending = pending.where((value) => value.id != entry.id).toList();
          await preferences.savePending(pending);
        }
        return DailyFlushResult(
          snapshot: latest,
          verifiedIds: verified,
          failure: DailySubmission(
            id: entry.id,
            status: DailySubmissionStatus.failed,
            message: error.message,
            retryable: retryable,
          ),
        );
      } on Object {
        return DailyFlushResult(
          snapshot: latest,
          verifiedIds: verified,
          failure: DailySubmission(
            id: entry.id,
            status: DailySubmissionStatus.failed,
            retryable: true,
          ),
        );
      }
    }
    return DailyFlushResult(snapshot: latest, verifiedIds: verified);
  }
}

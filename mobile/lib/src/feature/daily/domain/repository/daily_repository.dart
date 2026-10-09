import 'package:four3/src/feature/daily/domain/model/daily_models.dart';
import 'package:four3/src/feature/game/model/game_models.dart';

enum DailySubmissionStatus { guest, pending, verified, failed }

final class DailySubmission {
  const new({
    required this.id,
    required this.status,
    this.snapshot,
    this.message = '',
    this.retryable = false,
  });

  final String id;
  final DailySubmissionStatus status;
  final DailySnapshot? snapshot;
  final String message;
  final bool retryable;
}

final class DailyFlushResult {
  const new({this.snapshot, this.verifiedIds = const <String>{}, this.failure});

  final DailySnapshot? snapshot;
  final Set<String> verifiedIds;
  final DailySubmission? failure;
}

abstract interface class DailyRepository {
  const new();

  Future<DailySnapshot> load();
  Future<DailySubmission> saveWin({
    required String id,
    required DailyChallenge challenge,
    required GameSnapshot game,
    required String? owner,
    required String? currentOwner,
  });
  Future<DailyFlushResult> flush(String? owner);
}

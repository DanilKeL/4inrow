import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/daily/data/datasource/daily_datasource.dart';
import 'package:four3/src/feature/daily/data/datasource/daily_preferences_datasource.dart';
import 'package:four3/src/feature/daily/data/repository/daily_repository.dart';
import 'package:four3/src/feature/daily/domain/model/daily_models.dart';
import 'package:four3/src/feature/daily/domain/repository/daily_repository.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeDailyRemote remote;
  late DailyPreferencesDatasource$Preferences preferences;
  late DailyRepository$Api repository;
  late Map<String, dynamic> response;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences shared = await SharedPreferences.getInstance();
    preferences = DailyPreferencesDatasource$Preferences(
      preferencesDatasourceTool: PreferencesDatasourceTool$Shared(
        sharedPreferences: shared,
      ),
    );
    response = _dailyResponse('alice');
    remote = _FakeDailyRemote(response);
    repository = DailyRepository$Api(remote: remote, preferences: preferences);
  });

  test('loads a server challenge and falls back to its valid cache', () async {
    final DailySnapshot loaded = await repository.load();
    expect(loaded.username, 'alice');
    expect(loaded.challenge.isCurrent, isTrue);

    remote.failure = const RestClientException(
      '',
      failure: RestClientFailure.network,
    );
    final DailySnapshot cached = await repository.load();
    expect(cached, loaded);
  });

  test(
    'keeps a result under its starting owner until that owner returns',
    () async {
      final DailyChallenge challenge = DailyChallenge.fromJson(
        response['challenge'] as Map<String, dynamic>,
      );
      final GameSnapshot win = _winningSnapshot(challenge);

      final DailySubmission queued = await repository.saveWin(
        id: 'daily-attempt-1',
        challenge: challenge,
        game: win,
        owner: 'alice',
        currentOwner: 'bob',
      );
      expect(queued.status, DailySubmissionStatus.pending);
      expect(remote.submits, 0);
      expect(preferences.loadPending().single.owner, 'alice');

      await repository.flush('bob');
      expect(remote.submits, 0);
      expect(preferences.loadPending(), hasLength(1));

      final DailyFlushResult verified = await repository.flush('alice');
      expect(verified.snapshot?.rank, 1);
      expect(remote.submits, 1);
      expect(preferences.loadPending(), isEmpty);
    },
  );

  test('keeps separate pending entries for separate attempts', () async {
    final DailyChallenge challenge = DailyChallenge.fromJson(
      response['challenge'] as Map<String, dynamic>,
    );
    final GameSnapshot win = _winningSnapshot(challenge);

    await repository.saveWin(
      id: 'daily-attempt-1',
      challenge: challenge,
      game: win,
      owner: 'alice',
      currentOwner: 'bob',
    );
    await repository.saveWin(
      id: 'daily-attempt-2',
      challenge: challenge,
      game: win,
      owner: 'alice',
      currentOwner: 'bob',
    );

    expect(preferences.loadPending().map((entry) => entry.id), <String>[
      'daily-attempt-1',
      'daily-attempt-2',
    ]);
  });

  test('only offers retry while a failed result remains queued', () async {
    final DailyChallenge challenge = DailyChallenge.fromJson(
      response['challenge'] as Map<String, dynamic>,
    );
    final GameSnapshot win = _winningSnapshot(challenge);
    remote.submitFailure = const RestClientException(
      '',
      failure: RestClientFailure.network,
    );

    final DailySubmission transient = await repository.saveWin(
      id: 'daily-transient',
      challenge: challenge,
      game: win,
      owner: 'alice',
      currentOwner: 'alice',
    );
    expect(transient.status, DailySubmissionStatus.failed);
    expect(transient.retryable, isTrue);
    expect(preferences.loadPending(), hasLength(1));

    remote.submitFailure = null;
    await repository.flush('alice');
    expect(preferences.loadPending(), isEmpty);

    remote.submitFailure = const RestClientException('', statusCode: 410);
    final DailySubmission permanent = await repository.saveWin(
      id: 'daily-expired',
      challenge: challenge,
      game: win,
      owner: 'alice',
      currentOwner: 'alice',
    );
    expect(permanent.status, DailySubmissionStatus.failed);
    expect(permanent.retryable, isFalse);
    expect(preferences.loadPending(), isEmpty);
  });

  test('rejects a changed deadline and an altered saved preset', () {
    final Map<String, dynamic> raw = Map<String, dynamic>.from(
      response['challenge'] as Map<String, dynamic>,
    );
    expect(
      () => DailyChallenge.fromJson(<String, dynamic>{
        ...raw,
        'expiresAt': (raw['expiresAt'] as int) + 1,
      }),
      throwsFormatException,
    );
  });
}

final class _FakeDailyRemote implements DailyRemoteDatasource {
  new(this.response);

  final Map<String, dynamic> response;
  Exception? failure;
  Exception? submitFailure;
  int submits = 0;

  @override
  Future<Map<String, dynamic>> load() async {
    if (failure case final error?) throw error;
    return response;
  }

  @override
  Future<Map<String, dynamic>> submit({
    required String owner,
    required String challengeId,
    required List<Map<String, int>> moves,
  }) async {
    if (submitFailure case final error?) throw error;
    submits++;
    return <String, dynamic>{...response, 'rank': 1};
  }
}

Map<String, dynamic> _dailyResponse(String? username) {
  final DateTime nowMoscow = DateTime.now().toUtc().add(
    const Duration(hours: 3),
  );
  final String date =
      '${nowMoscow.year.toString().padLeft(4, '0')}-'
      '${nowMoscow.month.toString().padLeft(2, '0')}-'
      '${nowMoscow.day.toString().padLeft(2, '0')}';
  final int expiresAt = DateTime.utc(
    nowMoscow.year,
    nowMoscow.month,
    nowMoscow.day,
  ).add(const Duration(hours: 21)).millisecondsSinceEpoch;
  return <String, dynamic>{
    'username': username,
    'challenge': <String, dynamic>{
      'id': 'daily-1-$date',
      'date': date,
      'version': 1,
      'preset': <Map<String, int>>[
        <String, int>{'x': 0, 'y': 0},
        <String, int>{'x': 0, 'y': 1},
        <String, int>{'x': 1, 'y': 0},
        <String, int>{'x': 1, 'y': 1},
        <String, int>{'x': 2, 'y': 0},
        <String, int>{'x': 4, 'y': 4},
        <String, int>{'x': 2, 'y': 2},
        <String, int>{'x': 4, 'y': 3},
        <String, int>{'x': 1, 'y': 2},
        <String, int>{'x': 3, 'y': 4},
        <String, int>{'x': 0, 'y': 2},
        <String, int>{'x': 3, 'y': 3},
      ],
      'expiresAt': expiresAt,
    },
    'leaderboard': <Map<String, Object>>[],
    'ownBest': null,
    'now': DateTime.now().millisecondsSinceEpoch,
  };
}

GameSnapshot _winningSnapshot(DailyChallenge challenge) {
  final List<GameMove> history = <GameMove>[
    for (final (int index, MoveCandidate move) in challenge.preset.indexed)
      GameMove(
        x: move.x,
        y: move.y,
        z: 0,
        player: index.isEven ? Player.one : Player.two,
        index: index,
      ),
    GameMove(
      x: 2,
      y: 3,
      z: 0,
      player: Player.one,
      index: challenge.preset.length,
    ),
  ];
  return GameSnapshot(
    board: List<int>.filled(GameEngine.volume, 0),
    heights: List<int>.filled(GameEngine.area, 0),
    currentPlayer: Player.one,
    history: history,
    status: GameStatus.won,
    winner: Player.one,
    winningLines: const <List<BoardPosition>>[],
  );
}

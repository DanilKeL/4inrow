import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/match_history/data/datasource/match_history_datasource.dart';
import 'package:four3/src/feature/match_history/data/datasource/match_history_preferences_datasource.dart';
import 'package:four3/src/feature/match_history/data/repository/match_history_repository.dart';
import 'package:four3/src/feature/match_history/domain/model/match_history_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeHistoryDatasource remote;
  late MatchHistoryPreferencesDatasource$Preferences preferences;
  late MatchHistoryRepository$Api repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences shared = await SharedPreferences.getInstance();
    preferences = MatchHistoryPreferencesDatasource$Preferences(
      preferencesDatasourceTool: PreferencesDatasourceTool$Shared(
        sharedPreferences: shared,
      ),
    );
    remote = _FakeHistoryDatasource();
    repository = MatchHistoryRepository$Api(
      datasource: remote,
      preferences: preferences,
    );
  });

  test('queues a completed game for its starting account', () async {
    final GameViewData game = _completedGame('alice');

    final MatchHistorySnapshot? result = await repository.save(
      'alice',
      'bob',
      'local-1',
      game,
    );

    expect(result, isNull);
    expect(remote.saves, 0);
    expect(preferences.loadPending().single.owner, 'alice');

    await repository.flush('bob');
    expect(remote.saves, 0);
    final MatchHistorySnapshot? synced = await repository.flush('alice');
    expect(synced?.username, 'alice');
    expect(remote.saves, 1);
    expect(preferences.loadPending(), isEmpty);
  });

  test('keeps the outbox when the server is unavailable', () async {
    remote.failure = const RestClientException(
      '',
      failure: RestClientFailure.network,
    );

    await expectLater(
      repository.save('alice', 'alice', 'local-2', _completedGame('alice')),
      throwsA(isA<RestClientException>()),
    );
    expect(preferences.loadPending(), hasLength(1));
  });
}

final class _FakeHistoryDatasource implements MatchHistoryDatasource {
  Exception? failure;
  int saves = 0;

  Map<String, dynamic> _response(String owner) => <String, dynamic>{
    'username': owner,
    'matches': <Object>[],
    'statistics': <String, int>{'total': 1, 'wins': 1, 'losses': 0, 'draws': 0},
    'rating': <String, int>{'points': 1000, 'games': 0},
  };

  @override
  Future<Map<String, dynamic>> load() async => _response('alice');

  @override
  Future<Map<String, dynamic>> save(Map<String, Object?> data) async {
    if (failure case final error?) throw error;
    saves++;
    return _response(data['owner']! as String);
  }

  @override
  Future<Map<String, dynamic>> rename(Map<String, Object?> data) async =>
      _response(data['owner']! as String);

  @override
  Future<Map<String, dynamic>> remove(Map<String, Object?> data) async =>
      _response(data['owner']! as String);
}

GameViewData _completedGame(String owner) => GameViewData(
  snapshot: GameEngine.replay(const <MoveCandidate>[
    MoveCandidate(0, 0),
    MoveCandidate(4, 4),
    MoveCandidate(0, 0),
    MoveCandidate(4, 4),
    MoveCandidate(0, 0),
    MoveCandidate(4, 4),
    MoveCandidate(0, 0),
  ]),
  names: const <String>['Alice', 'Bot'],
  accountAtStart: owner,
);

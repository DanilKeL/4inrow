import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/levels/data/datasource/level_asset_datasource.dart';
import 'package:four3/src/feature/levels/data/datasource/level_datasource_rest_client.dart';
import 'package:four3/src/feature/levels/data/datasource/level_preferences_datasource.dart';
import 'package:four3/src/feature/levels/data/repository/level_repository.dart';
import 'package:four3/src/feature/levels/domain/model/game_level.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LevelRepository$Local repository;
  late _FakeLevelRemote remote;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences shared = await SharedPreferences.getInstance();
    remote = _FakeLevelRemote();
    repository = LevelRepository$Local(
      assetDatasource: const _FakeLevelAssets(),
      preferencesDatasource: LevelPreferencesDatasource$Preferences(
        preferencesDatasourceTool: PreferencesDatasourceTool$Shared(
          sharedPreferences: shared,
        ),
      ),
      remoteDatasource: remote,
    );
  });

  test('keeps guest and account records isolated', () async {
    const GameLevel level = GameLevel(
      id: 1,
      chapter: LevelChapter.firstSteps,
      preset: <MoveCandidate>[],
    );

    await repository.record(level, _win(3), null);
    await repository.record(level, _win(5), 'alice');
    await repository.record(level, _win(4), 'bob');

    expect(await repository.best(null), <int, int>{1: 3});
    expect(await repository.best('alice'), <int, int>{1: 5});
    expect(await repository.best('bob'), <int, int>{1: 4});
  });

  test('merges the server record only into its owner', () async {
    const GameLevel level = GameLevel(
      id: 1,
      chapter: LevelChapter.firstSteps,
      preset: <MoveCandidate>[],
    );
    await repository.record(level, _win(5), 'alice');
    await repository.record(level, _win(4), 'bob');
    expect(repository.needsSync('alice'), isTrue);
    remote.best = <String, int>{'1': 2};

    final Map<int, int> merged = await repository.sync('alice');

    expect(merged, <int, int>{1: 2});
    expect(await repository.best('alice'), <int, int>{1: 2});
    expect(await repository.best('bob'), <int, int>{1: 4});
    expect(remote.sent, <int, int>{1: 5});
    expect(repository.needsSync('alice'), isFalse);
  });
}

GameSnapshot _win(int moves) => GameSnapshot(
  board: List<int>.filled(GameEngine.volume, 0),
  heights: List<int>.filled(GameEngine.area, 0),
  currentPlayer: Player.two,
  history: <GameMove>[
    for (int index = 0; index < moves; index++)
      GameMove(
        x: index % GameEngine.size,
        y: 0,
        z: 0,
        player: Player.one,
        index: index,
      ),
  ],
  status: GameStatus.won,
  winner: Player.one,
  winningLines: const <List<BoardPosition>>[],
);

final class _FakeLevelAssets implements LevelAssetDatasource {
  const new();

  @override
  Future<List<GameLevel>> load() async => const <GameLevel>[];
}

final class _FakeLevelRemote implements LevelRemoteDatasource {
  Map<String, int> best = <String, int>{};
  Map<int, int> sent = <int, int>{};

  @override
  Future<Map<String, dynamic>> sync({
    required String owner,
    required Map<int, int> best,
  }) async {
    sent = <int, int>{...best};
    return <String, dynamic>{'username': owner, 'best': this.best};
  }
}

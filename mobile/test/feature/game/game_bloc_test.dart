import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/bloc/game_event.dart';
import 'package:four3/src/feature/game/bloc/game_state.dart';
import 'package:four3/src/feature/game/data/datasource/game_storage_datasource_preferences.dart';
import 'package:four3/src/feature/game/data/repository/game_storage_repository.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/levels/data/datasource/level_asset_datasource.dart';
import 'package:four3/src/feature/levels/data/datasource/level_preferences_datasource.dart';
import 'package:four3/src/feature/levels/data/repository/level_repository.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GameBloc> createBloc() async {
    SharedPreferences.setMockInitialValues({});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return GameBloc(
      storage: GameStorageRepository$Local(
        datasource: GameStorageDatasource$Preferences(
          preferencesDatasourceTool: PreferencesDatasourceTool$Shared(
            sharedPreferences: preferences,
          ),
        ),
      ),
      levels: LevelRepository$Local(
        assetDatasource: LevelAssetDatasource$Bundle(),
        preferencesDatasource: LevelPreferencesDatasource$Preferences(
          preferencesDatasourceTool: PreferencesDatasourceTool$Shared(
            sharedPreferences: preferences,
          ),
        ),
      ),
      settings: () => const AppSettings(animations: false),
      playerName: () => 'Tester',
    );
  }

  test(
    'loads once, starts a local game and persists an authoritative move',
    () async {
      final GameBloc bloc = await createBloc();
      addTearDown(bloc.close);

      bloc.add(const GameEvent$Load());
      final GameState$Ready loaded = await bloc.stream
          .whereType<GameState$Ready>()
          .first;
      expect(loaded.data.phase, GamePhase.menu);
      expect(loaded.data.names.first, 'Tester');

      bloc.add(
        const GameEvent$Start(
          mode: GameMode.local,
          difficulty: Difficulty.medium,
          names: ['Alice', 'Bob'],
        ),
      );
      await bloc.stream.whereType<GameState$Ready>().firstWhere(
        (state) => state.data.phase == GamePhase.playing,
      );
      bloc.add(const GameEvent$MakeMove(2, 3));
      final GameState$Ready moved = await bloc.stream
          .whereType<GameState$Ready>()
          .firstWhere((state) => state.data.snapshot.history.length == 1);
      expect(
        moved.data.snapshot.history.single.position,
        const BoardPosition(2, 3, 0),
      );
      expect(moved.data.snapshot.currentPlayer, Player.two);
    },
  );

  test('undo and menu clear the active game', () async {
    final GameBloc bloc = await createBloc();
    addTearDown(bloc.close);
    bloc.add(const GameEvent$Load());
    await bloc.stream.whereType<GameState$Ready>().first;
    bloc.add(
      const GameEvent$Start(
        mode: GameMode.local,
        difficulty: Difficulty.easy,
        names: ['A', 'B'],
      ),
    );
    await bloc.stream.whereType<GameState$Ready>().firstWhere(
      (s) => s.data.phase == GamePhase.playing,
    );
    bloc.add(const GameEvent$MakeMove(0, 0));
    await bloc.stream.whereType<GameState$Ready>().firstWhere(
      (s) => s.data.snapshot.history.length == 1,
    );
    bloc.add(const GameEvent$Undo());
    final GameState$Ready undone = await bloc.stream
        .whereType<GameState$Ready>()
        .firstWhere((s) => s.data.snapshot.history.isEmpty);
    expect(undone.data.snapshot.currentPlayer, Player.one);
    bloc.add(const GameEvent$Menu());
    final GameState$Ready menu = await bloc.stream
        .whereType<GameState$Ready>()
        .firstWhere((s) => s.data.phase == GamePhase.menu);
    expect(menu.data.snapshot.history, isEmpty);
  });
}

extension on Stream<GameState> {
  Stream<T> whereType<T extends GameState>() =>
      where((state) => state is T).cast<T>();
}

import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/feature/daily/domain/model/daily_models.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/bloc/game_event.dart';
import 'package:four3/src/feature/game/bloc/game_state.dart';
import 'package:four3/src/feature/game/data/datasource/game_storage_datasource_preferences.dart';
import 'package:four3/src/feature/game/data/repository/game_storage_repository.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/levels/data/datasource/level_asset_datasource.dart';
import 'package:four3/src/feature/levels/data/datasource/level_preferences_datasource.dart';
import 'package:four3/src/feature/levels/data/repository/level_repository.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_analytics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GameBloc> createBloc({FakeAnalyticsService? analytics}) async {
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
      analytics: analytics ?? FakeAnalyticsService(),
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

  test('rejects every full-column attempt without changing the game', () async {
    final GameBloc bloc = await createBloc();
    addTearDown(bloc.close);
    bloc.add(const GameEvent$Load());
    await bloc.stream.whereType<GameState$Ready>().first;
    bloc.add(
      const GameEvent$Start(
        mode: GameMode.local,
        difficulty: Difficulty.medium,
        names: <String>['Alice', 'Bob'],
      ),
    );
    await bloc.stream.whereType<GameState$Ready>().firstWhere(
      (state) => state.data.phase == GamePhase.playing,
    );
    for (var move = 0; move < GameEngine.size; move++) {
      await _playMove(bloc, const MoveCandidate(2, 2));
    }

    final GameViewData before = bloc.data!;
    bloc.add(const GameEvent$MakeMove(2, 2));
    final GameState$Ready first = await bloc.stream
        .whereType<GameState$Ready>()
        .firstWhere((state) => state.data.noticeRevision == 1);
    expect(first.data.notice, GameNotice.columnFull);
    expect(first.data.phase, GamePhase.playing);
    expect(first.data.snapshot.currentPlayer, before.snapshot.currentPlayer);
    expect(identical(first.data.snapshot, before.snapshot), isTrue);

    bloc.add(const GameEvent$MakeMove(2, 2));
    final GameState$Ready second = await bloc.stream
        .whereType<GameState$Ready>()
        .firstWhere((state) => state.data.noticeRevision == 2);
    expect(second.data.notice, GameNotice.columnFull);
    expect(identical(second.data.snapshot, before.snapshot), isTrue);
  });

  test('an online move error keeps a connected match playable', () async {
    final GameBloc bloc = await createBloc();
    addTearDown(bloc.close);
    bloc.add(const GameEvent$Load());
    await bloc.stream.whereType<GameState$Ready>().first;
    final OnlineMatchSnapshot snapshot = OnlineMatchSnapshot(
      code: 'ABCDE',
      kind: 'lobby',
      game: GameEngine.replay(const <MoveCandidate>[
        MoveCandidate(2, 2),
        MoveCandidate(2, 2),
        MoveCandidate(2, 2),
        MoveCandidate(2, 2),
        MoveCandidate(2, 2),
      ]),
      players: const <OnlinePlayer?>[
        OnlinePlayer(name: 'Alice', connected: true),
        OnlinePlayer(name: 'Bob', connected: true),
      ],
      revision: 1,
      round: 1,
      startedAt: 1000,
      finishedAt: null,
      rematch: const <Player>[],
    );
    bloc.add(
      GameEvent$OnlineSnapshot(
        snapshot: snapshot,
        player: Player.two,
        connection: OnlineConnectionStatus.connected,
      ),
    );
    await bloc.stream.whereType<GameState$Ready>().firstWhere(
      (state) => state.data.mode == GameMode.online,
    );

    bloc.add(const GameEvent$MakeMove(2, 2));
    final GameState$Ready invalid = await bloc.stream
        .whereType<GameState$Ready>()
        .firstWhere((state) => state.data.noticeRevision == 1);
    expect(invalid.data.notice, GameNotice.columnFull);
    expect(identical(invalid.data.snapshot, snapshot.game), isTrue);

    bloc.add(const GameEvent$OnlineFailure('This column is full.'));
    final GameState$Ready failed = await bloc.stream
        .whereType<GameState$Ready>()
        .firstWhere((state) => state.data.remoteMessage.isNotEmpty);
    expect(failed.data.onlineConnection, OnlineConnectionStatus.connected);
    expect(failed.data.phase, GamePhase.playing);
    expect(failed.data.canPlace, isTrue);
    expect(identical(failed.data.snapshot, snapshot.game), isTrue);

    bloc.add(const GameEvent$MakeMove(0, 0));
    final GameState$Ready retrying = await bloc.stream
        .whereType<GameState$Ready>()
        .firstWhere(
          (state) =>
              state.data.notice == null && state.data.remoteMessage.isEmpty,
        );
    expect(retrying.data.canPlace, isTrue);
    expect(identical(retrying.data.snapshot, snapshot.game), isTrue);

    bloc.add(
      const GameEvent$OnlineFailure(
        'Connection closed.',
        connectionError: true,
      ),
    );
    final GameState$Ready disconnected = await bloc.stream
        .whereType<GameState$Ready>()
        .firstWhere(
          (state) =>
              state.data.onlineConnection == OnlineConnectionStatus.error,
        );
    expect(disconnected.data.canPlace, isFalse);
  });

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

  test(
    'restores a complete interrupted game only after confirmation',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final PreferencesDatasourceTool tool = PreferencesDatasourceTool$Shared(
        sharedPreferences: preferences,
      );
      final GameStorageRepository$Local storage = GameStorageRepository$Local(
        datasource: GameStorageDatasource$Preferences(
          preferencesDatasourceTool: tool,
        ),
      );
      final LevelRepository$Local levels = LevelRepository$Local(
        assetDatasource: LevelAssetDatasource$Bundle(),
        preferencesDatasource: LevelPreferencesDatasource$Preferences(
          preferencesDatasourceTool: tool,
        ),
      );
      GameBloc buildBloc(FakeAnalyticsService analytics) => GameBloc(
        storage: storage,
        levels: levels,
        settings: () => const AppSettings(animations: false),
        playerName: () => 'Tester',
        analytics: analytics,
      );

      final GameBloc first = buildBloc(FakeAnalyticsService());
      first.add(const GameEvent$Load());
      await first.stream.whereType<GameState$Ready>().first;
      first.add(
        const GameEvent$Start(
          mode: GameMode.local,
          difficulty: Difficulty.hard,
          names: <String>['Alice', 'Bob'],
        ),
      );
      await first.stream.whereType<GameState$Ready>().firstWhere(
        (state) => state.data.phase == GamePhase.playing,
      );
      first.add(const GameEvent$MakeMove(3, 4));
      await first.stream.whereType<GameState$Ready>().firstWhere(
        (state) => state.data.snapshot.history.length == 1,
      );
      first.add(const GameEvent$ToggleXray());
      await first.stream.whereType<GameState$Ready>().firstWhere(
        (state) => state.data.xray,
      );
      await first.close();

      final FakeAnalyticsService restoredAnalytics = FakeAnalyticsService();
      final GameBloc restored = buildBloc(restoredAnalytics);
      addTearDown(restored.close);
      restored.add(const GameEvent$Load());
      final GameState$Ready menu = await restored.stream
          .whereType<GameState$Ready>()
          .first;
      expect(menu.data.phase, GamePhase.menu);
      expect(menu.data.hasSavedGame, isTrue);
      final String restoredRecordId = menu.data.recordId;
      expect(menu.data.names, <String>['Alice', 'Bob']);
      expect(menu.data.difficulty, Difficulty.hard);
      expect(menu.data.xray, isTrue);
      expect(
        menu.data.snapshot.history.single.position,
        const BoardPosition(3, 4, 0),
      );

      restored.add(const GameEvent$ResumeSaved());
      final GameState$Ready resumed = await restored.stream
          .whereType<GameState$Ready>()
          .firstWhere((state) => state.data.phase == GamePhase.playing);
      expect(resumed.data.hasSavedGame, isFalse);
      expect(resumed.data.snapshot.history, hasLength(1));
      final RecordedAnalyticsEvent resumedEvent = await _waitForAnalytics(
        restoredAnalytics,
        'game_start',
      );
      expect(restoredAnalytics.events, hasLength(1));
      expect(resumedEvent.name, 'game_start');
      expect(resumedEvent.parameters, containsPair('mode', 'local'));
      expect(resumedEvent.parameters, containsPair('id', restoredRecordId));
    },
  );

  test('persists a newly started game before its first move', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final PreferencesDatasourceTool tool = PreferencesDatasourceTool$Shared(
      sharedPreferences: preferences,
    );
    final GameStorageRepository$Local storage = GameStorageRepository$Local(
      datasource: GameStorageDatasource$Preferences(
        preferencesDatasourceTool: tool,
      ),
    );
    final LevelRepository$Local levels = LevelRepository$Local(
      assetDatasource: LevelAssetDatasource$Bundle(),
      preferencesDatasource: LevelPreferencesDatasource$Preferences(
        preferencesDatasourceTool: tool,
      ),
    );
    GameBloc buildBloc() => GameBloc(
      storage: storage,
      levels: levels,
      settings: () => const AppSettings(animations: false),
      playerName: () => 'Tester',
      accountOwner: () => 'alice',
      analytics: FakeAnalyticsService(),
    );

    final GameBloc first = buildBloc();
    first.add(const GameEvent$Load());
    await first.stream.whereType<GameState$Ready>().first;
    first.add(
      const GameEvent$Start(
        mode: GameMode.ai,
        difficulty: Difficulty.medium,
        names: <String>['Alice', 'FOUR AI'],
      ),
    );
    await first.stream.whereType<GameState$Ready>().firstWhere(
      (state) => state.data.phase == GamePhase.playing,
    );
    await first.close();

    final GameBloc restored = buildBloc();
    addTearDown(restored.close);
    restored.add(const GameEvent$Load());
    final GameState$Ready menu = await restored.stream
        .whereType<GameState$Ready>()
        .first;
    expect(menu.data.hasSavedGame, isTrue);
    expect(menu.data.snapshot.history, isEmpty);
    expect(menu.data.accountAtStart, 'alice');
    expect(menu.data.recordId, isNotEmpty);
  });

  test('reports supported starts and ignores daily games', () async {
    final FakeAnalyticsService analytics = FakeAnalyticsService();
    final GameBloc bloc = await createBloc(analytics: analytics);
    addTearDown(bloc.close);
    bloc.add(const GameEvent$Load());
    await bloc.stream.whereType<GameState$Ready>().first;

    bloc.add(
      const GameEvent$Start(
        mode: GameMode.ai,
        difficulty: Difficulty.hard,
        names: <String>['Private Alice', 'FOUR AI'],
      ),
    );
    await bloc.stream.whereType<GameState$Ready>().firstWhere(
      (state) => state.data.mode == GameMode.ai,
    );
    final RecordedAnalyticsEvent aiStart = await _waitForAnalytics(
      analytics,
      'game_start',
    );
    expect(aiStart.parameters, containsPair('mode', 'ai'));
    expect(aiStart.parameters, containsPair('difficulty', 'hard'));
    expect(aiStart.parameters, contains('id'));
    expect(
      aiStart.parameters,
      isNot(contains(anyOf('name', 'username', 'email'))),
    );

    bloc.add(const GameEvent$Menu());
    await bloc.stream.whereType<GameState$Ready>().firstWhere(
      (state) => state.data.phase == GamePhase.menu,
    );
    bloc.add(const GameEvent$StartLevel(1));
    await bloc.stream.whereType<GameState$Ready>().firstWhere(
      (state) => state.data.mode == GameMode.level,
    );
    final RecordedAnalyticsEvent levelStart = await _waitForAnalytics(
      analytics,
      'game_start',
      occurrence: 2,
    );
    expect(levelStart.parameters, containsPair('mode', 'level'));
    expect(levelStart.parameters, containsPair('level', 1));

    bloc.add(const GameEvent$Menu());
    await bloc.stream.whereType<GameState$Ready>().firstWhere(
      (state) => state.data.phase == GamePhase.menu,
    );
    bloc.add(
      const GameEvent$StartDaily(
        DailyChallenge(
          id: 'private-daily-id',
          date: '2026-10-09',
          preset: <MoveCandidate>[],
          expiresAt: 0,
        ),
      ),
    );
    await bloc.stream.whereType<GameState$Ready>().firstWhere(
      (state) => state.data.mode == GameMode.daily,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      analytics.events.where((event) => event.name == 'game_start'),
      hasLength(2),
    );
  });

  test('reports one local finish with a server-compatible game', () async {
    final FakeAnalyticsService analytics = FakeAnalyticsService();
    final GameBloc bloc = await createBloc(analytics: analytics);
    addTearDown(bloc.close);
    bloc.add(const GameEvent$Load());
    await bloc.stream.whereType<GameState$Ready>().first;
    bloc.add(
      const GameEvent$Start(
        mode: GameMode.local,
        difficulty: Difficulty.medium,
        names: <String>['Alice', 'Bob'],
      ),
    );
    await bloc.stream.whereType<GameState$Ready>().firstWhere(
      (state) => state.data.phase == GamePhase.playing,
    );

    for (final MoveCandidate move in const <MoveCandidate>[
      MoveCandidate(0, 0),
      MoveCandidate(0, 1),
      MoveCandidate(1, 0),
      MoveCandidate(1, 1),
      MoveCandidate(2, 0),
      MoveCandidate(2, 1),
      MoveCandidate(3, 0),
    ]) {
      await _playMove(bloc, move);
    }

    final RecordedAnalyticsEvent finished = await _waitForAnalytics(
      analytics,
      'game_end',
    );
    final GameSnapshot serialized = GameEngine.deserialize(
      finished.parameters!['game']! as String,
    );
    expect(serialized.status, GameStatus.won);
    expect(serialized.history, hasLength(7));
    expect(finished.parameters, containsPair('id', bloc.data!.recordId));
    expect(finished.parameters, containsPair('elapsed', bloc.data!.elapsed));

    bloc.add(const GameEvent$Settle());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      analytics.events.where((event) => event.name == 'game_end'),
      hasLength(1),
    );
  });

  test(
    'reports meaningful abandonment once and ignores accidental starts',
    () async {
      final FakeAnalyticsService analytics = FakeAnalyticsService();
      final GameBloc bloc = await createBloc(analytics: analytics);
      addTearDown(bloc.close);
      bloc.add(const GameEvent$Load());
      await bloc.stream.whereType<GameState$Ready>().first;
      bloc.add(
        const GameEvent$Start(
          mode: GameMode.local,
          difficulty: Difficulty.medium,
          names: <String>['A', 'B'],
        ),
      );
      GameState$Ready active = await bloc.stream
          .whereType<GameState$Ready>()
          .firstWhere((state) => state.data.phase == GamePhase.playing);
      await _playMove(bloc, const MoveCandidate(0, 0));
      bloc.add(const GameEvent$Menu());
      await bloc.stream.whereType<GameState$Ready>().firstWhere(
        (state) => state.data.phase == GamePhase.menu,
      );
      expect(
        analytics.events.where((event) => event.name == 'game_abandon'),
        isEmpty,
      );

      bloc.add(
        const GameEvent$Start(
          mode: GameMode.local,
          difficulty: Difficulty.medium,
          names: <String>['A', 'B'],
        ),
      );
      active = await bloc.stream.whereType<GameState$Ready>().firstWhere(
        (state) =>
            state.data.phase == GamePhase.playing &&
            state.data.recordId != active.data.recordId,
      );
      await _playMove(bloc, const MoveCandidate(0, 0));
      await _playMove(bloc, const MoveCandidate(0, 1));
      final String abandonedId = bloc.data!.recordId;
      bloc.add(const GameEvent$Restart());
      await bloc.stream.whereType<GameState$Ready>().firstWhere(
        (state) =>
            state.data.phase == GamePhase.playing &&
            state.data.recordId != abandonedId,
      );

      final RecordedAnalyticsEvent abandoned = await _waitForAnalytics(
        analytics,
        'game_abandon',
      );
      expect(abandoned.parameters, containsPair('id', abandonedId));
      expect(abandoned.parameters, contains('elapsed'));
      expect(
        analytics.events.where((event) => event.name == 'game_end'),
        isEmpty,
      );
    },
  );

  test('does not report online games already recorded by the server', () async {
    final FakeAnalyticsService analytics = FakeAnalyticsService();
    final GameBloc bloc = await createBloc(analytics: analytics);
    addTearDown(bloc.close);
    bloc.add(const GameEvent$Load());
    await bloc.stream.whereType<GameState$Ready>().first;

    const OnlineRanking ranking = OnlineRanking(
      rated: true,
      points: <int>[1000, 1000],
    );
    final OnlineMatchSnapshot playing = OnlineMatchSnapshot(
      code: 'PRIVATE-CODE',
      kind: 'quick',
      game: GameEngine.create(),
      players: const <OnlinePlayer?>[
        OnlinePlayer(name: 'Private Alice', connected: true),
        OnlinePlayer(name: 'Private Bob', connected: true),
      ],
      revision: 1,
      round: 4,
      startedAt: 1000,
      finishedAt: null,
      rematch: const <Player>[],
      ranking: ranking,
    );
    bloc.add(
      GameEvent$OnlineSnapshot(
        snapshot: playing,
        player: Player.one,
        connection: OnlineConnectionStatus.connected,
      ),
    );
    await bloc.stream.whereType<GameState$Ready>().firstWhere(
      (state) => state.data.mode == GameMode.online,
    );
    final GameSnapshot won = GameEngine.replay(const <MoveCandidate>[
      MoveCandidate(0, 0),
      MoveCandidate(0, 1),
      MoveCandidate(1, 0),
      MoveCandidate(1, 1),
      MoveCandidate(2, 0),
      MoveCandidate(2, 1),
      MoveCandidate(3, 0),
    ]);
    final OnlineMatchSnapshot finished = OnlineMatchSnapshot(
      code: playing.code,
      kind: playing.kind,
      game: won,
      players: playing.players,
      revision: 2,
      round: playing.round,
      startedAt: playing.startedAt,
      finishedAt: 61000,
      rematch: const <Player>[],
      ranking: ranking,
    );
    bloc.add(
      GameEvent$OnlineSnapshot(
        snapshot: finished,
        player: Player.one,
        connection: OnlineConnectionStatus.connected,
      ),
    );
    await bloc.stream.whereType<GameState$Ready>().firstWhere(
      (state) => state.data.snapshot.status == GameStatus.won,
    );
    bloc.add(
      GameEvent$OnlineSnapshot(
        snapshot: finished,
        player: Player.one,
        connection: OnlineConnectionStatus.connected,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(analytics.events, isEmpty);
  });
}

Future<void> _playMove(GameBloc bloc, MoveCandidate move) async {
  final int expectedMoves = bloc.data!.snapshot.history.length + 1;
  bloc.add(GameEvent$MakeMove(move.x, move.y));
  final GameState$Ready moved = await bloc.stream
      .whereType<GameState$Ready>()
      .firstWhere(
        (state) => state.data.snapshot.history.length == expectedMoves,
      );
  await bloc.stream.whereType<GameState$Ready>().firstWhere(
    (state) =>
        state.data.snapshot.history.length == expectedMoves &&
        (moved.data.snapshot.status == GameStatus.playing
            ? state.data.phase == GamePhase.playing
            : state.data.phase == GamePhase.victory ||
                  state.data.phase == GamePhase.draw),
  );
}

Future<RecordedAnalyticsEvent> _waitForAnalytics(
  FakeAnalyticsService analytics,
  String name, {
  int occurrence = 1,
}) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    final List<RecordedAnalyticsEvent> matches = analytics.events
        .where((event) => event.name == name)
        .toList(growable: false);
    if (matches.length >= occurrence) return matches[occurrence - 1];
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TestFailure('Timed out waiting for analytics event $name');
}

extension on Stream<GameState> {
  Stream<T> whereType<T extends GameState>() =>
      where((state) => state is T).cast<T>();
}

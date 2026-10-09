import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/services/analytics/analytics_service.dart';
import 'package:four3/src/feature/daily/domain/model/daily_models.dart';
import 'package:four3/src/feature/game/bloc/game_event.dart';
import 'package:four3/src/feature/game/bloc/game_state.dart';
import 'package:four3/src/feature/game/domain/repository/game_storage_repository.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/game/model/saved_game.dart';
import 'package:four3/src/feature/game/service/ai_engine.dart';
import 'package:four3/src/feature/game/service/ai_move_runner.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/levels/domain/model/game_level.dart';
import 'package:four3/src/feature/levels/domain/repository/level_repository.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';

final class GameBloc extends Bloc<GameEvent, GameState> {
  static int _recordSequence = 0;

  new({
    required this._storage,
    required this._levels,
    required this._settings,
    required this._playerName,
    required this._analytics,
    String? Function()? accountOwner,
    AiMoveRunner? aiRunner,
  }) : _accountOwner = accountOwner ?? (() => null),
       _aiRunner = aiRunner ?? AiMoveRunner(),
       super(const GameState$Initial()) {
    on<GameEvent>(_onEvent, transformer: sequential());
  }

  final GameStorageRepository _storage;
  final LevelRepository _levels;
  final AppSettings Function() _settings;
  final String Function() _playerName;
  final String? Function() _accountOwner;
  final AnalyticsService _analytics;
  final AiMoveRunner _aiRunner;
  final Set<String> _startedGames = <String>{};
  final Set<String> _finishedGames = <String>{};
  final Set<String> _abandonedGames = <String>{};
  Timer? _settleTimer;
  Timer? _tickTimer;
  GameLevel? _activeLevel;

  GameViewData? get data => switch (state) {
    GameState$Ready(:final GameViewData data) => data,
    _ => null,
  };

  Future<void> _onEvent(GameEvent event, Emitter<GameState> emit) async {
    switch (event) {
      case GameEvent$Load():
        await _load(emit);
      case GameEvent$Start(:final mode, :final difficulty, :final names):
        await _start(emit, mode, difficulty, names);
      case GameEvent$StartLevel(:final id):
        await _startLevel(emit, id);
      case GameEvent$StartDaily(:final challenge):
        await _startDaily(emit, challenge);
      case GameEvent$ResumeSaved():
        await _resumeSaved(emit);
      case GameEvent$DiscardSaved():
        await _discardSaved(emit);
      case GameEvent$Persist():
        await _persistCurrent();
      case GameEvent$MakeMove(:final x, :final y):
        await _makeMove(emit, x, y);
      case GameEvent$Settle():
        await _settle(emit);
      case GameEvent$AiCompleted(
        :final move,
        :final expectedMoves,
        :final error,
      ):
        await _aiCompleted(emit, move, expectedMoves, error);
      case GameEvent$Pause():
        _pause(emit);
      case GameEvent$Resume():
        add(const GameEvent$Settle());
      case GameEvent$Undo():
        await _undo(emit);
      case GameEvent$Restart():
        await _restart(emit);
      case GameEvent$Menu():
        await _menu(emit);
      case GameEvent$Tick():
        _tick(emit);
      case GameEvent$ToggleXray():
        final GameViewData? current = data;
        if (current != null) {
          final GameViewData next = current.copyWith(xray: !current.xray);
          emit(GameState$Ready(next));
          await _persist(next);
        }
      case GameEvent$ToggleLayer(:final layer):
        _toggleLayer(emit, layer);
      case GameEvent$ShowAllLayers():
        final GameViewData? current = data;
        if (current != null) {
          final GameViewData next = current.copyWith(
            layers: const <int>[0, 1, 2, 3, 4],
          );
          emit(GameState$Ready(next));
          await _persist(next);
        }
      case GameEvent$View(:final view):
        final GameViewData? current = data;
        if (current != null) {
          final GameViewData next = current.copyWith(
            cameraView: view,
            cameraReset: current.cameraReset + 1,
          );
          emit(GameState$Ready(next));
          await _persist(next);
        }
      case GameEvent$OpenReplay():
        final GameViewData? current = data;
        if (current != null) {
          emit(
            GameState$Ready(
              current.copyWith(
                phase: GamePhase.replay,
                replayIndex: current.snapshot.history.length,
              ),
            ),
          );
        }
      case GameEvent$SeekReplay(:final index):
        final GameViewData? current = data;
        if (current != null) {
          emit(
            GameState$Ready(
              current.copyWith(
                replayIndex: index.clamp(0, current.snapshot.history.length),
              ),
            ),
          );
        }
      case GameEvent$CloseReplay():
        _closeReplay(emit);
      case GameEvent$ReplaySaved(:final snapshot, :final names):
        _cancelPending();
        emit(
          GameState$Ready(
            GameViewData(
              snapshot: snapshot,
              phase: GamePhase.replay,
              names: names.length == 2 ? names : const ['Player 1', 'Player 2'],
              replayIndex: snapshot.history.length,
              xray: _settings().xrayDefault,
              cameraReset: (data?.cameraReset ?? 0) + 1,
            ),
          ),
        );
      case GameEvent$OnlineSnapshot(
        :final snapshot,
        :final player,
        :final connection,
      ):
        _onlineSnapshot(emit, snapshot, player, connection);
      case GameEvent$OnlineFailure(:final message, :final connectionError):
        final GameViewData? current = data;
        if (current != null) {
          emit(
            GameState$Ready(
              current.copyWith(
                remoteMessage: message,
                onlineConnection: connectionError
                    ? OnlineConnectionStatus.error
                    : current.onlineConnection,
              ),
            ),
          );
        }
    }
  }

  Future<void> _load(Emitter<GameState> emit) async {
    final SavedGame? restored = _storage.load();
    final GameSnapshot snapshot = restored?.snapshot ?? GameEngine.create();
    emit(
      GameState$Ready(
        GameViewData(
          snapshot: snapshot,
          mode: restored?.mode ?? GameMode.local,
          difficulty: restored?.difficulty ?? Difficulty.medium,
          names: restored?.names ?? <String>[_playerName(), 'Player 2'],
          accountAtStart: restored?.accountAtStart,
          recordId: restored?.recordId ?? '',
          elapsed: restored?.elapsed ?? 0,
          xray: restored?.xray ?? _settings().xrayDefault,
          layers: restored?.layers ?? const <int>[0, 1, 2, 3, 4],
          cameraView: restored?.cameraView ?? CameraView.perspective,
          levelId: restored?.levelId,
          levelChapter: restored?.levelChapter,
          levelPresetLength: restored?.levelPresetLength ?? 0,
          levelBestBefore: restored?.levelBestBefore,
          dailyChallenge: restored?.dailyChallenge,
          dailyOwnerAtStart: restored?.dailyOwnerAtStart,
          hasSavedGame: restored != null,
        ),
      ),
    );
    _tickTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(const GameEvent$Tick()),
    );
  }

  Future<void> _start(
    Emitter<GameState> emit,
    GameMode mode,
    Difficulty difficulty,
    List<String> names,
  ) async {
    if (mode == GameMode.online ||
        mode == GameMode.level ||
        mode == GameMode.daily) {
      return;
    }
    _cancelPending();
    _activeLevel = null;
    await _storage.clear();
    final List<String> normalized = [
      if (names.first.trim().isEmpty) _playerName() else names.first.trim(),
      if (mode == GameMode.ai)
        'FOUR AI'
      else if (names.length < 2 || names[1].trim().isEmpty)
        'Player 2'
      else
        names[1].trim(),
    ];
    final value = GameViewData(
      snapshot: GameEngine.create(),
      phase: GamePhase.playing,
      mode: mode,
      difficulty: difficulty,
      names: normalized,
      accountAtStart: _accountOwner(),
      recordId: _newRecordId(),
      xray: _settings().xrayDefault,
      cameraReset: (data?.cameraReset ?? 0) + 1,
    );
    emit(GameState$Ready(value));
    await _persist(value);
    _reportGameStarted(value);
  }

  Future<void> _startLevel(Emitter<GameState> emit, int id) async {
    final GameLevel? level = await _levels.get(id);
    if (level == null) return;
    _cancelPending();
    _activeLevel = level;
    final Map<int, int> best = await _levels.best(_accountOwner());
    final value = GameViewData(
      snapshot: _levels.position(level),
      phase: GamePhase.playing,
      mode: GameMode.level,
      names: const ['You', 'Bot'],
      accountAtStart: _accountOwner(),
      recordId: _newRecordId(),
      xray: _settings().xrayDefault,
      cameraReset: (data?.cameraReset ?? 0) + 1,
      levelId: id,
      levelChapter: level.chapter,
      levelPresetLength: level.preset.length,
      levelBestBefore: best[id],
    );
    emit(GameState$Ready(value));
    await _persist(value);
    _reportGameStarted(value);
  }

  Future<void> _startDaily(
    Emitter<GameState> emit,
    DailyChallenge challenge,
  ) async {
    _cancelPending();
    _activeLevel = null;
    final GameViewData value = GameViewData(
      snapshot: GameEngine.replay(challenge.preset),
      phase: GamePhase.playing,
      mode: GameMode.daily,
      names: <String>[_playerName(), 'FOUR AI'],
      accountAtStart: _accountOwner(),
      recordId: _newRecordId(),
      xray: _settings().xrayDefault,
      cameraReset: (data?.cameraReset ?? 0) + 1,
      levelPresetLength: challenge.preset.length,
      dailyChallenge: challenge,
      dailyOwnerAtStart: _accountOwner(),
    );
    emit(GameState$Ready(value));
    await _persist(value);
    _reportGameStarted(value);
  }

  Future<void> _resumeSaved(Emitter<GameState> emit) async {
    final GameViewData? current = data;
    if (current == null ||
        !current.hasSavedGame ||
        current.accountAtStart != _accountOwner()) {
      return;
    }
    if (current.mode == GameMode.level && current.levelId != null) {
      final GameLevel? level = await _levels.get(current.levelId!);
      if (level == null ||
          current.levelPresetLength != level.preset.length ||
          current.snapshot.history.length < level.preset.length ||
          level.preset.indexed.any((entry) {
            final GameMove move = current.snapshot.history[entry.$1];
            return move.x != entry.$2.x || move.y != entry.$2.y;
          })) {
        await _discardSaved(emit);
        return;
      }
      _activeLevel = level;
    }
    final GameViewData resumed = current.copyWith(
      phase: GamePhase.playing,
      hasSavedGame: false,
      cameraReset: current.cameraReset + 1,
      levelChapter: _activeLevel?.chapter,
      levelPresetLength:
          _activeLevel?.preset.length ?? current.levelPresetLength,
    );
    emit(GameState$Ready(resumed));
    await _persist(resumed);
    // Re-registering the same id is idempotent on the server and also lets a
    // game saved before server analytics was enabled complete successfully.
    _reportGameStarted(resumed);
    add(const GameEvent$Settle());
  }

  Future<void> _discardSaved(Emitter<GameState> emit) async {
    final GameViewData current =
        data ?? GameViewData(snapshot: GameEngine.create());
    if (current.hasSavedGame && current.accountAtStart != _accountOwner()) {
      return;
    }
    if (current.hasSavedGame) {
      _reportGameAbandoned(current);
    }
    _cancelPending();
    _activeLevel = null;
    await _storage.clear();
    emit(
      GameState$Ready(
        GameViewData(
          snapshot: GameEngine.create(),
          xray: _settings().xrayDefault,
          cameraView: current.cameraView,
          cameraReset: current.cameraReset,
          names: <String>[_playerName(), 'Player 2'],
        ),
      ),
    );
  }

  Future<void> _makeMove(Emitter<GameState> emit, int x, int y) async {
    final GameViewData? current = data;
    if (current == null || !current.canPlace) return;
    final MoveResult result = GameEngine.makeMove(current.snapshot, x, y);
    switch (result) {
      case MoveResult$Invalid():
        emit(
          GameState$Ready(
            current.copyWith(
              notice: GameNotice.columnFull,
              noticeRevision: current.noticeRevision + 1,
            ),
          ),
        );
      case MoveResult$Valid(:final snapshot):
        if (current.mode == GameMode.online) {
          emit(
            GameState$Ready(current.copyWith(notice: null, remoteMessage: '')),
          );
          return;
        }
        final GameViewData next = current.copyWith(
          snapshot: snapshot,
          phase: GamePhase.animating,
          notice: null,
          remoteMessage: '',
          layers: const [0, 1, 2, 3, 4],
        );
        emit(GameState$Ready(next));
        await _persist(next);
        _scheduleSettle();
    }
  }

  Future<void> _settle(Emitter<GameState> emit) async {
    final GameViewData? current = data;
    if (current == null) return;
    if (current.snapshot.status != GameStatus.playing) {
      final GamePhase phase = current.snapshot.status == GameStatus.won
          ? GamePhase.victory
          : GamePhase.draw;
      emit(GameState$Ready(current.copyWith(phase: phase)));
      _reportGameFinished(current);
      if (_activeLevel case final level?) {
        final String? owner = _accountOwner();
        if (current.accountAtStart == owner) {
          await _levels.record(level, current.snapshot, owner);
          if (owner != null) {
            unawaited(_levels.sync(owner).catchError((_) => <int, int>{}));
          }
        }
      }
      await _storage.clear();
      return;
    }
    if ((current.mode != GameMode.ai &&
            current.mode != GameMode.level &&
            current.mode != GameMode.daily) ||
        current.snapshot.currentPlayer != Player.two) {
      emit(GameState$Ready(current.copyWith(phase: GamePhase.playing)));
      return;
    }
    emit(GameState$Ready(current.copyWith(phase: GamePhase.aiThinking)));
    final int expectedMoves = current.snapshot.history.length;
    final options =
        current.mode == GameMode.level || current.mode == GameMode.daily
        ? const BotOptions(deterministic: true)
        : const BotOptions();
    final Future<MoveCandidate?> calculation = _aiRunner.run(
      current.snapshot,
      current.mode == GameMode.level || current.mode == GameMode.daily
          ? Difficulty.medium
          : current.difficulty,
      options: options,
    );
    unawaited(
      Future.wait<Object?>(<Future<Object?>>[
            calculation,
            Future<void>.delayed(const Duration(milliseconds: 420)),
          ])
          .then(
            (values) => add(
              GameEvent$AiCompleted(
                values.first as MoveCandidate?,
                expectedMoves,
              ),
            ),
          )
          .catchError((Object error) {
            if (error is! AiMoveCancelled) {
              add(GameEvent$AiCompleted(null, expectedMoves, error));
            }
          }),
    );
  }

  Future<void> _aiCompleted(
    Emitter<GameState> emit,
    MoveCandidate? move,
    int expectedMoves,
    Object? error,
  ) async {
    final GameViewData? current = data;
    if (current == null ||
        current.phase != GamePhase.aiThinking ||
        current.snapshot.history.length != expectedMoves) {
      return;
    }
    if (error != null ||
        move == null ||
        !GameEngine.legalMoves(current.snapshot).contains(move)) {
      emit(
        GameState$Ready(
          current.copyWith(
            phase: GamePhase.paused,
            notice: GameNotice.aiMoveFailed,
          ),
        ),
      );
      return;
    }
    final MoveResult result = GameEngine.makeMove(
      current.snapshot,
      move.x,
      move.y,
    );
    if (result case MoveResult$Valid(snapshot: final snapshot)) {
      final GameViewData next = current.copyWith(
        snapshot: snapshot,
        phase: GamePhase.animating,
        layers: const <int>[0, 1, 2, 3, 4],
      );
      emit(GameState$Ready(next));
      await _persist(next);
      _scheduleSettle();
    }
  }

  void _scheduleSettle() {
    _settleTimer?.cancel();
    _settleTimer = Timer(
      Duration(milliseconds: _settings().animations ? 440 : 80),
      () => add(const GameEvent$Settle()),
    );
  }

  void _pause(Emitter<GameState> emit) {
    final GameViewData? current = data;
    if (current == null ||
        ![
          GamePhase.playing,
          GamePhase.animating,
          GamePhase.aiThinking,
        ].contains(current.phase)) {
      return;
    }
    _cancelPending();
    emit(GameState$Ready(current.copyWith(phase: GamePhase.paused)));
  }

  Future<void> _undo(Emitter<GameState> emit) async {
    final GameViewData? current = data;
    if (current == null ||
        current.mode == GameMode.online ||
        current.mode == GameMode.level ||
        current.mode == GameMode.daily ||
        current.snapshot.history.isEmpty) {
      return;
    }
    _cancelPending();
    GameSnapshot snapshot = GameEngine.undo(current.snapshot);
    if (current.mode == GameMode.ai &&
        snapshot.currentPlayer == Player.two &&
        snapshot.history.isNotEmpty) {
      snapshot = GameEngine.undo(snapshot);
    }
    final GameViewData next = current.copyWith(
      snapshot: snapshot,
      phase: GamePhase.playing,
      notice: null,
      remoteMessage: '',
      layers: const <int>[0, 1, 2, 3, 4],
    );
    emit(GameState$Ready(next));
    await _persist(next);
  }

  Future<void> _restart(Emitter<GameState> emit) async {
    final GameViewData? current = data;
    if (current == null) return;
    _reportGameAbandoned(current);
    if (current.mode == GameMode.level && current.levelId != null) {
      await _startLevel(emit, current.levelId!);
    } else if (current.mode == GameMode.daily &&
        current.dailyChallenge != null) {
      await _startDaily(emit, current.dailyChallenge!);
    } else if (current.mode != GameMode.online) {
      await _start(emit, current.mode, current.difficulty, current.names);
    }
  }

  Future<void> _menu(Emitter<GameState> emit) async {
    _cancelPending();
    _activeLevel = null;
    final GameViewData current =
        data ?? GameViewData(snapshot: GameEngine.create());
    _reportGameAbandoned(current);
    emit(
      GameState$Ready(
        current.copyWith(
          phase: GamePhase.menu,
          mode: GameMode.local,
          levelId: null,
          levelChapter: null,
          levelPresetLength: 0,
          levelBestBefore: null,
          dailyChallenge: null,
          dailyOwnerAtStart: null,
          accountAtStart: null,
          recordId: '',
          hasSavedGame: false,
          notice: null,
          remoteMessage: '',
        ),
      ),
    );
    await _storage.clear();
  }

  void _tick(Emitter<GameState> emit) {
    final GameViewData? current = data;
    if (current != null &&
        [
          GamePhase.playing,
          GamePhase.animating,
          GamePhase.aiThinking,
        ].contains(current.phase)) {
      emit(GameState$Ready(current.copyWith(elapsed: current.elapsed + 1)));
    }
  }

  void _toggleLayer(Emitter<GameState> emit, int layer) {
    final GameViewData? current = data;
    if (current == null || layer < 0 || layer > 4) return;
    final List<int> layers = [...current.layers];
    layers.contains(layer) ? layers.remove(layer) : layers.add(layer);
    layers.sort();
    final GameViewData next = current.copyWith(layers: layers);
    emit(GameState$Ready(next));
    unawaited(_persist(next));
  }

  Future<void> _persistCurrent() async {
    final GameViewData? current = data;
    if (current != null) await _persist(current);
  }

  String _newRecordId() =>
      'local-${DateTime.now().millisecondsSinceEpoch}-${_recordSequence++}';

  Future<void> _persist(GameViewData value) async {
    if (value.mode == GameMode.online) return;
    if (value.snapshot.status != GameStatus.playing) {
      await _storage.clear();
      return;
    }
    if (value.phase == GamePhase.menu) {
      return;
    }
    await _storage.save(SavedGame.fromViewData(value));
  }

  void _closeReplay(Emitter<GameState> emit) {
    final GameViewData? current = data;
    if (current == null) return;
    emit(
      GameState$Ready(
        current.copyWith(
          phase: switch (current.snapshot.status) {
            GameStatus.won => GamePhase.victory,
            GameStatus.draw => GamePhase.draw,
            GameStatus.playing => GamePhase.paused,
          },
        ),
      ),
    );
  }

  void _onlineSnapshot(
    Emitter<GameState> emit,
    OnlineMatchSnapshot snapshot,
    Player player,
    OnlineConnectionStatus connection,
  ) {
    _cancelPending();
    if (data?.mode != GameMode.online) unawaited(_storage.clear());
    final List<OnlinePlayer?> players = snapshot.players;
    final GamePhase phase = switch ((
      snapshot.game.status,
      snapshot.startedAt,
      connection,
      snapshot.pause?.endsAt,
    )) {
      (_, _, OnlineConnectionStatus.reconnecting, _) => GamePhase.waiting,
      (_, null, _, _) => GamePhase.waiting,
      (_, _, _, final int _) => GamePhase.paused,
      (GameStatus.won, _, _, _) => GamePhase.victory,
      (GameStatus.draw, _, _, _) => GamePhase.draw,
      _ => GamePhase.playing,
    };
    final GameViewData? previous = data;
    final GameViewData next = GameViewData(
      snapshot: snapshot.game,
      phase: phase,
      mode: GameMode.online,
      names: [players[0]?.name ?? 'Player 1', players[1]?.name ?? 'Waiting…'],
      accountAtStart: previous?.mode == GameMode.online
          ? previous?.accountAtStart
          : _accountOwner(),
      elapsed: previous?.mode == GameMode.online ? previous!.elapsed : 0,
      xray: previous?.xray ?? _settings().xrayDefault,
      cameraView: previous?.cameraView ?? CameraView.perspective,
      cameraReset:
          (previous?.mode == GameMode.online &&
              previous?.onlineCode == snapshot.code)
          ? previous!.cameraReset
          : (previous?.cameraReset ?? 0) + 1,
      notice: connection == OnlineConnectionStatus.reconnecting
          ? GameNotice.reconnecting
          : null,
      onlinePlayer: player,
      onlineConnection: connection,
      onlineCode: snapshot.code,
      onlineSnapshot: snapshot,
    );
    emit(GameState$Ready(next));
    if (snapshot.startedAt != null &&
        snapshot.game.status == GameStatus.playing) {
      _reportGameStarted(next);
    }
    if (previous != null &&
        _gameKey(previous) == _gameKey(next) &&
        previous.snapshot.status == GameStatus.playing &&
        snapshot.game.status != GameStatus.playing) {
      _reportGameFinished(next);
    }
  }

  void _reportGameStarted(GameViewData value) {
    final String? key = _gameKey(value);
    if (key == null || !_startedGames.add(key)) return;
    _reportAnalyticsSafely(
      () => _analytics.gameStarted(
        id: value.recordId,
        mode: value.mode.name,
        difficulty: value.mode == GameMode.ai ? value.difficulty.name : null,
        level: value.mode == GameMode.level ? value.levelId : null,
      ),
    );
  }

  void _reportGameFinished(GameViewData value) {
    final String? key = _gameKey(value);
    if (key == null ||
        value.snapshot.status == GameStatus.playing ||
        _abandonedGames.contains(key) ||
        !_finishedGames.add(key)) {
      return;
    }
    _reportAnalyticsSafely(
      () => _analytics.gameFinished(
        id: value.recordId,
        game: GameEngine.serialize(value.snapshot),
        elapsed: value.elapsed,
      ),
    );
  }

  void _reportGameAbandoned(GameViewData value) {
    if (!_analyticsMode(value.mode) ||
        value.snapshot.status != GameStatus.playing ||
        (_movesCount(value) < 2 && value.elapsed < 30)) {
      return;
    }
    final String? key = _gameKey(value);
    if (key == null ||
        _finishedGames.contains(key) ||
        !_abandonedGames.add(key)) {
      return;
    }
    _reportAnalyticsSafely(
      () =>
          _analytics.gameAbandoned(id: value.recordId, elapsed: value.elapsed),
    );
  }

  String? _gameKey(GameViewData value) {
    if (!_analyticsMode(value.mode) || value.recordId.isEmpty) return null;
    return value.recordId;
  }

  bool _analyticsMode(GameMode mode) =>
      mode == GameMode.local || mode == GameMode.ai || mode == GameMode.level;

  int _movesCount(GameViewData value) {
    final int preset =
        value.mode == GameMode.level || value.mode == GameMode.daily
        ? value.levelPresetLength
        : 0;
    final int count = value.snapshot.history.length - preset;
    return count < 0 ? 0 : count;
  }

  void _cancelPending() {
    _settleTimer?.cancel();
    _settleTimer = null;
    _aiRunner.cancel();
  }

  @override
  Future<void> close() {
    _cancelPending();
    _tickTimer?.cancel();
    _aiRunner.dispose();
    return super.close();
  }
}

void _reportAnalyticsSafely(Future<void> Function() report) {
  unawaited(() async {
    try {
      await report();
    } on Object {
      // Analytics is best-effort and must never affect product flows.
    }
  }());
}

import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/feature/game/bloc/game_event.dart';
import 'package:four3/src/feature/game/bloc/game_state.dart';
import 'package:four3/src/feature/game/domain/repository/game_storage_repository.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/game/service/ai_engine.dart';
import 'package:four3/src/feature/game/service/ai_move_runner.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/levels/domain/model/game_level.dart';
import 'package:four3/src/feature/levels/domain/repository/level_repository.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';

final class GameBloc extends Bloc<GameEvent, GameState> {
  new({
    required this._storage,
    required this._levels,
    required this._settings,
    required this._playerName,
    AiMoveRunner? aiRunner,
  }) : _aiRunner = aiRunner ?? AiMoveRunner(),
       super(const GameState$Initial()) {
    on<GameEvent>(_onEvent, transformer: sequential());
  }

  final GameStorageRepository _storage;
  final LevelRepository _levels;
  final AppSettings Function() _settings;
  final String Function() _playerName;
  final AiMoveRunner _aiRunner;
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
          emit(GameState$Ready(current.copyWith(xray: !current.xray)));
        }
      case GameEvent$ToggleLayer(:final layer):
        _toggleLayer(emit, layer);
      case GameEvent$ShowAllLayers():
        final GameViewData? current = data;
        if (current != null) {
          emit(
            GameState$Ready(current.copyWith(layers: const [0, 1, 2, 3, 4])),
          );
        }
      case GameEvent$View(:final view):
        final GameViewData? current = data;
        if (current != null) {
          emit(
            GameState$Ready(
              current.copyWith(
                cameraView: view,
                cameraReset: current.cameraReset + 1,
              ),
            ),
          );
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
      case GameEvent$OnlineFailure(:final message):
        final GameViewData? current = data;
        if (current != null) {
          emit(
            GameState$Ready(
              current.copyWith(
                remoteMessage: message,
                onlineConnection: OnlineConnectionStatus.error,
              ),
            ),
          );
        }
    }
  }

  Future<void> _load(Emitter<GameState> emit) async {
    final GameSnapshot? restored = _storage.load();
    final GameSnapshot snapshot = restored ?? GameEngine.create();
    emit(
      GameState$Ready(
        GameViewData(
          snapshot: snapshot,
          phase:
              restored != null &&
                  restored.history.isNotEmpty &&
                  restored.status == GameStatus.playing
              ? GamePhase.paused
              : GamePhase.menu,
          xray: _settings().xrayDefault,
          names: [_playerName(), 'Player 2'],
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
    if (mode == GameMode.online || mode == GameMode.level) return;
    _cancelPending();
    _activeLevel = null;
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
      xray: _settings().xrayDefault,
      cameraReset: (data?.cameraReset ?? 0) + 1,
    );
    emit(GameState$Ready(value));
    await _storage.save(value.snapshot);
  }

  Future<void> _startLevel(Emitter<GameState> emit, int id) async {
    final GameLevel? level = await _levels.get(id);
    if (level == null) return;
    _cancelPending();
    _activeLevel = level;
    final Map<int, int> best = await _levels.best();
    final value = GameViewData(
      snapshot: _levels.position(level),
      phase: GamePhase.playing,
      mode: GameMode.level,
      names: const ['You', 'Bot'],
      xray: _settings().xrayDefault,
      cameraReset: (data?.cameraReset ?? 0) + 1,
      levelId: id,
      levelChapter: level.chapter,
      levelPresetLength: level.preset.length,
      levelBestBefore: best[id],
    );
    emit(GameState$Ready(value));
    await _storage.save(value.snapshot);
  }

  Future<void> _makeMove(Emitter<GameState> emit, int x, int y) async {
    final GameViewData? current = data;
    if (current == null ||
        !current.canPlace ||
        current.mode == GameMode.online) {
      return;
    }
    final MoveResult result = GameEngine.makeMove(current.snapshot, x, y);
    switch (result) {
      case MoveResult$Invalid():
        emit(GameState$Ready(current.copyWith(notice: GameNotice.columnFull)));
      case MoveResult$Valid(:final snapshot):
        final GameViewData next = current.copyWith(
          snapshot: snapshot,
          phase: GamePhase.animating,
          notice: null,
          remoteMessage: '',
          layers: const [0, 1, 2, 3, 4],
        );
        emit(GameState$Ready(next));
        await _storage.save(snapshot);
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
      if (_activeLevel case final level?) {
        await _levels.record(level, current.snapshot);
      }
      return;
    }
    if ((current.mode != GameMode.ai && current.mode != GameMode.level) ||
        current.snapshot.currentPlayer != Player.two) {
      emit(GameState$Ready(current.copyWith(phase: GamePhase.playing)));
      return;
    }
    emit(GameState$Ready(current.copyWith(phase: GamePhase.aiThinking)));
    final int expectedMoves = current.snapshot.history.length;
    final options = current.mode == GameMode.level
        ? const BotOptions(deterministic: true)
        : const BotOptions();
    unawaited(
      _aiRunner
          .run(
            current.snapshot,
            current.mode == GameMode.level
                ? Difficulty.medium
                : current.difficulty,
            options: options,
          )
          .then((move) => add(GameEvent$AiCompleted(move, expectedMoves)))
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
      emit(
        GameState$Ready(
          current.copyWith(
            snapshot: snapshot,
            phase: GamePhase.animating,
            layers: const [0, 1, 2, 3, 4],
          ),
        ),
      );
      await _storage.save(snapshot);
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
    emit(
      GameState$Ready(
        current.copyWith(
          snapshot: snapshot,
          phase: GamePhase.playing,
          notice: null,
          remoteMessage: '',
          layers: const [0, 1, 2, 3, 4],
        ),
      ),
    );
    await _storage.save(snapshot);
  }

  Future<void> _restart(Emitter<GameState> emit) async {
    final GameViewData? current = data;
    if (current == null) return;
    if (current.mode == GameMode.level && current.levelId != null) {
      await _startLevel(emit, current.levelId!);
    } else if (current.mode != GameMode.online) {
      await _start(emit, current.mode, current.difficulty, current.names);
    }
  }

  Future<void> _menu(Emitter<GameState> emit) async {
    _cancelPending();
    _activeLevel = null;
    final GameViewData current =
        data ?? GameViewData(snapshot: GameEngine.create());
    emit(
      GameState$Ready(
        current.copyWith(
          phase: GamePhase.menu,
          mode: GameMode.local,
          levelId: null,
          levelChapter: null,
          levelPresetLength: 0,
          levelBestBefore: null,
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
    emit(GameState$Ready(current.copyWith(layers: layers)));
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
    emit(
      GameState$Ready(
        GameViewData(
          snapshot: snapshot.game,
          phase: phase,
          mode: GameMode.online,
          names: [
            players[0]?.name ?? 'Player 1',
            players[1]?.name ?? 'Waiting…',
          ],
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
        ),
      ),
    );
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

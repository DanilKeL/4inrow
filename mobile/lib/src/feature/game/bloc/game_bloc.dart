import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/ai_engine.dart';
import 'package:four3/src/feature/game/service/ai_move_runner.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/game/service/game_storage_repository.dart';
import 'package:four3/src/feature/levels/model/game_level.dart';
import 'package:four3/src/feature/levels/service/level_repository.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';
import 'package:four3/src/feature/settings/model/app_settings.dart';

const _unset = Object();

final class GameViewData extends Equatable {
  const new({
    required this.snapshot,
    this.phase = GamePhase.menu,
    this.mode = GameMode.local,
    this.difficulty = Difficulty.medium,
    this.names = const ['Игрок 1', 'Игрок 2'],
    this.elapsed = 0,
    this.xray = false,
    this.layers = const [0, 1, 2, 3, 4],
    this.cameraView = CameraView.perspective,
    this.cameraReset = 0,
    this.message = '',
    this.replayIndex = 0,
    this.levelId,
    this.levelBestBefore,
    this.onlinePlayer,
    this.onlineConnection = OnlineConnectionStatus.idle,
    this.onlineCode,
    this.onlineSnapshot,
  });

  final GameSnapshot snapshot;
  final GamePhase phase;
  final GameMode mode;
  final Difficulty difficulty;
  final List<String> names;
  final int elapsed;
  final bool xray;
  final List<int> layers;
  final CameraView cameraView;
  final int cameraReset;
  final String message;
  final int replayIndex;
  final int? levelId;
  final int? levelBestBefore;
  final Player? onlinePlayer;
  final OnlineConnectionStatus onlineConnection;
  final String? onlineCode;
  final OnlineMatchSnapshot? onlineSnapshot;

  bool get canPlace =>
      phase == GamePhase.playing &&
      (mode != GameMode.online ||
          (onlineConnection == OnlineConnectionStatus.connected &&
              onlinePlayer == snapshot.currentPlayer)) &&
      !((mode == GameMode.ai || mode == GameMode.level) &&
          snapshot.currentPlayer == Player.two);

  GameSnapshot get displayedSnapshot => phase == GamePhase.replay
      ? GameEngine.replayHistory(snapshot.history, count: replayIndex)
      : snapshot;

  GameViewData copyWith({
    GameSnapshot? snapshot,
    GamePhase? phase,
    GameMode? mode,
    Difficulty? difficulty,
    List<String>? names,
    int? elapsed,
    bool? xray,
    List<int>? layers,
    CameraView? cameraView,
    int? cameraReset,
    String? message,
    int? replayIndex,
    Object? levelId = _unset,
    Object? levelBestBefore = _unset,
    Object? onlinePlayer = _unset,
    OnlineConnectionStatus? onlineConnection,
    Object? onlineCode = _unset,
    Object? onlineSnapshot = _unset,
  }) => GameViewData(
    snapshot: snapshot ?? this.snapshot,
    phase: phase ?? this.phase,
    mode: mode ?? this.mode,
    difficulty: difficulty ?? this.difficulty,
    names: names ?? this.names,
    elapsed: elapsed ?? this.elapsed,
    xray: xray ?? this.xray,
    layers: layers ?? this.layers,
    cameraView: cameraView ?? this.cameraView,
    cameraReset: cameraReset ?? this.cameraReset,
    message: message ?? this.message,
    replayIndex: replayIndex ?? this.replayIndex,
    levelId: identical(levelId, _unset) ? this.levelId : levelId as int?,
    levelBestBefore: identical(levelBestBefore, _unset)
        ? this.levelBestBefore
        : levelBestBefore as int?,
    onlinePlayer: identical(onlinePlayer, _unset)
        ? this.onlinePlayer
        : onlinePlayer as Player?,
    onlineConnection: onlineConnection ?? this.onlineConnection,
    onlineCode: identical(onlineCode, _unset)
        ? this.onlineCode
        : onlineCode as String?,
    onlineSnapshot: identical(onlineSnapshot, _unset)
        ? this.onlineSnapshot
        : onlineSnapshot as OnlineMatchSnapshot?,
  );

  @override
  List<Object?> get props => [
    snapshot,
    phase,
    mode,
    difficulty,
    names,
    elapsed,
    xray,
    layers,
    cameraView,
    cameraReset,
    message,
    replayIndex,
    levelId,
    levelBestBefore,
    onlinePlayer,
    onlineConnection,
    onlineCode,
    onlineSnapshot,
  ];
}

sealed class GameEvent extends Equatable {
  const new();
  @override
  List<Object?> get props => const [];
}

final class GameEvent$Load extends GameEvent {
  const new();
}

final class GameEvent$Start extends GameEvent {
  const new({
    required this.mode,
    required this.difficulty,
    required this.names,
  });
  final GameMode mode;
  final Difficulty difficulty;
  final List<String> names;
  @override
  List<Object> get props => [mode, difficulty, names];
}

final class GameEvent$StartLevel extends GameEvent {
  const new(this.id);
  final int id;
  @override
  List<Object> get props => [id];
}

final class GameEvent$MakeMove extends GameEvent {
  const new(this.x, this.y);
  final int x;
  final int y;
  @override
  List<Object> get props => [x, y];
}

final class GameEvent$Settle extends GameEvent {
  const new();
}

final class GameEvent$AiCompleted extends GameEvent {
  const new(this.move, this.expectedMoves, [this.error]);
  final MoveCandidate? move;
  final int expectedMoves;
  final Object? error;
  @override
  List<Object?> get props => [move, expectedMoves, error];
}

final class GameEvent$Pause extends GameEvent {
  const new();
}

final class GameEvent$Resume extends GameEvent {
  const new();
}

final class GameEvent$Undo extends GameEvent {
  const new();
}

final class GameEvent$Restart extends GameEvent {
  const new();
}

final class GameEvent$Menu extends GameEvent {
  const new();
}

final class GameEvent$Tick extends GameEvent {
  const new();
}

final class GameEvent$ToggleXray extends GameEvent {
  const new();
}

final class GameEvent$ToggleLayer extends GameEvent {
  const new(this.layer);
  final int layer;
  @override
  List<Object> get props => [layer];
}

final class GameEvent$ShowAllLayers extends GameEvent {
  const new();
}

final class GameEvent$View extends GameEvent {
  const new(this.view);
  final CameraView view;
  @override
  List<Object> get props => [view];
}

final class GameEvent$OpenReplay extends GameEvent {
  const new();
}

final class GameEvent$SeekReplay extends GameEvent {
  const new(this.index);
  final int index;
  @override
  List<Object> get props => [index];
}

final class GameEvent$CloseReplay extends GameEvent {
  const new();
}

final class GameEvent$ReplaySaved extends GameEvent {
  const new({required this.snapshot, required this.names});
  final GameSnapshot snapshot;
  final List<String> names;
  @override
  List<Object> get props => [snapshot, names];
}

final class GameEvent$OnlineSnapshot extends GameEvent {
  const new({
    required this.snapshot,
    required this.player,
    required this.connection,
  });
  final OnlineMatchSnapshot snapshot;
  final Player player;
  final OnlineConnectionStatus connection;
  @override
  List<Object> get props => [snapshot, player, connection];
}

final class GameEvent$OnlineFailure extends GameEvent {
  const new(this.message);
  final String message;
  @override
  List<Object> get props => [message];
}

sealed class GameState extends Equatable {
  const new();
  @override
  List<Object?> get props => const [];
}

final class GameState$Initial extends GameState {
  const new();
}

final class GameState$Ready extends GameState {
  const new(this.data);
  final GameViewData data;
  @override
  List<Object> get props => [data];
}

final class GameState$Failure extends GameState {
  const new(this.message);
  final String message;
  @override
  List<Object> get props => [message];
}

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
              names: names.length == 2 ? names : const ['Игрок 1', 'Игрок 2'],
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
                message: message,
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
          names: [_playerName(), 'Игрок 2'],
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
        'Игрок 2'
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
      names: const ['Вы', 'Бот'],
      xray: _settings().xrayDefault,
      cameraReset: (data?.cameraReset ?? 0) + 1,
      levelId: id,
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
        emit(
          GameState$Ready(
            current.copyWith(message: 'Столбец заполнен. Выберите другой.'),
          ),
        );
      case MoveResult$Valid(:final snapshot):
        final GameViewData next = current.copyWith(
          snapshot: snapshot,
          phase: GamePhase.animating,
          message: '',
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
            message: 'Не удалось рассчитать ход. Нажмите «Продолжить», чтобы повторить.',
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
          message: '',
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
          levelBestBefore: null,
          message: '',
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
            players[0]?.name ?? 'Игрок 1',
            players[1]?.name ?? 'Ожидание…',
          ],
          elapsed: previous?.mode == GameMode.online ? previous!.elapsed : 0,
          xray: previous?.xray ?? _settings().xrayDefault,
          cameraView: previous?.cameraView ?? CameraView.perspective,
          cameraReset:
              (previous?.mode == GameMode.online &&
                  previous?.onlineCode == snapshot.code)
              ? previous!.cameraReset
              : (previous?.cameraReset ?? 0) + 1,
          message: connection == OnlineConnectionStatus.reconnecting
              ? 'Восстанавливаем соединение…'
              : '',
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

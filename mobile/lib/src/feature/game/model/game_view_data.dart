import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/daily/domain/model/daily_models.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/levels/domain/model/game_level.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';

const _unset = Object();

enum GameNotice { columnFull, aiMoveFailed, reconnecting }

final class GameViewData extends Equatable {
  const new({
    required this.snapshot,
    this.phase = GamePhase.menu,
    this.mode = GameMode.local,
    this.difficulty = Difficulty.medium,
    this.names = const ['Player 1', 'Player 2'],
    this.accountAtStart,
    this.recordId = '',
    this.elapsed = 0,
    this.xray = false,
    this.layers = const [0, 1, 2, 3, 4],
    this.cameraView = CameraView.perspective,
    this.cameraReset = 0,
    this.notice,
    this.noticeRevision = 0,
    this.remoteMessage = '',
    this.replayIndex = 0,
    this.levelId,
    this.levelChapter,
    this.levelPresetLength = 0,
    this.levelBestBefore,
    this.dailyChallenge,
    this.dailyOwnerAtStart,
    this.hasSavedGame = false,
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
  final String? accountAtStart;
  final String recordId;
  final int elapsed;
  final bool xray;
  final List<int> layers;
  final CameraView cameraView;
  final int cameraReset;
  final GameNotice? notice;
  final int noticeRevision;
  final String remoteMessage;
  final int replayIndex;
  final int? levelId;
  final LevelChapter? levelChapter;
  final int levelPresetLength;
  final int? levelBestBefore;
  final DailyChallenge? dailyChallenge;
  final String? dailyOwnerAtStart;
  final bool hasSavedGame;
  final Player? onlinePlayer;
  final OnlineConnectionStatus onlineConnection;
  final String? onlineCode;
  final OnlineMatchSnapshot? onlineSnapshot;

  int get levelMoves => snapshot.history
      .skip(levelPresetLength)
      .where((move) => move.player == Player.one)
      .length;

  bool get canPlace =>
      phase == GamePhase.playing &&
      (mode != GameMode.online ||
          (onlineConnection == OnlineConnectionStatus.connected &&
              onlinePlayer == snapshot.currentPlayer)) &&
      !((mode == GameMode.ai ||
              mode == GameMode.level ||
              mode == GameMode.daily) &&
          snapshot.currentPlayer == Player.two);

  int get challengeMoves => snapshot.history
      .skip(levelPresetLength)
      .where((move) => move.player == Player.one)
      .length;

  GameSnapshot get displayedSnapshot => phase == GamePhase.replay
      ? GameEngine.replayHistory(snapshot.history, count: replayIndex)
      : snapshot;

  GameViewData copyWith({
    GameSnapshot? snapshot,
    GamePhase? phase,
    GameMode? mode,
    Difficulty? difficulty,
    List<String>? names,
    Object? accountAtStart = _unset,
    String? recordId,
    int? elapsed,
    bool? xray,
    List<int>? layers,
    CameraView? cameraView,
    int? cameraReset,
    Object? notice = _unset,
    int? noticeRevision,
    String? remoteMessage,
    int? replayIndex,
    Object? levelId = _unset,
    Object? levelChapter = _unset,
    int? levelPresetLength,
    Object? levelBestBefore = _unset,
    Object? dailyChallenge = _unset,
    Object? dailyOwnerAtStart = _unset,
    bool? hasSavedGame,
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
    accountAtStart: identical(accountAtStart, _unset)
        ? this.accountAtStart
        : accountAtStart as String?,
    recordId: recordId ?? this.recordId,
    elapsed: elapsed ?? this.elapsed,
    xray: xray ?? this.xray,
    layers: layers ?? this.layers,
    cameraView: cameraView ?? this.cameraView,
    cameraReset: cameraReset ?? this.cameraReset,
    notice: identical(notice, _unset) ? this.notice : notice as GameNotice?,
    noticeRevision: noticeRevision ?? this.noticeRevision,
    remoteMessage: remoteMessage ?? this.remoteMessage,
    replayIndex: replayIndex ?? this.replayIndex,
    levelId: identical(levelId, _unset) ? this.levelId : levelId as int?,
    levelChapter: identical(levelChapter, _unset)
        ? this.levelChapter
        : levelChapter as LevelChapter?,
    levelPresetLength: levelPresetLength ?? this.levelPresetLength,
    levelBestBefore: identical(levelBestBefore, _unset)
        ? this.levelBestBefore
        : levelBestBefore as int?,
    dailyChallenge: identical(dailyChallenge, _unset)
        ? this.dailyChallenge
        : dailyChallenge as DailyChallenge?,
    dailyOwnerAtStart: identical(dailyOwnerAtStart, _unset)
        ? this.dailyOwnerAtStart
        : dailyOwnerAtStart as String?,
    hasSavedGame: hasSavedGame ?? this.hasSavedGame,
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
    accountAtStart,
    recordId,
    elapsed,
    xray,
    layers,
    cameraView,
    cameraReset,
    notice,
    noticeRevision,
    remoteMessage,
    replayIndex,
    levelId,
    levelChapter,
    levelPresetLength,
    levelBestBefore,
    dailyChallenge,
    dailyOwnerAtStart,
    hasSavedGame,
    onlinePlayer,
    onlineConnection,
    onlineCode,
    onlineSnapshot,
  ];
}

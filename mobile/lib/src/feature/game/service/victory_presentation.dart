import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';

const Duration winCameraDuration = Duration(milliseconds: 750);
const Duration winFallDuration = Duration(milliseconds: 1150);
const Duration winLineDuration = Duration(milliseconds: 700);
const Duration victoryCinematicDuration = Duration(milliseconds: 2600);
const Duration resultDelay = Duration(milliseconds: 3600);
const Duration reducedResultDelay = Duration(milliseconds: 1600);
const Duration drawResultDelay = Duration(milliseconds: 1100);
const Duration endedResultDelay = Duration(milliseconds: 600);

double _clamp(double value) => value.clamp(0, 1).toDouble();

double victorySmoothStep(double value) {
  final double progress = _clamp(value);
  return progress * progress * (3 - 2 * progress);
}

final class VictoryProgress {
  const new({
    required this.fallOffset,
    required this.lineProgress,
    required this.dimProgress,
    required this.ringProgress,
  });

  final double fallOffset;
  final double lineProgress;
  final double dimProgress;
  final double ringProgress;
}

VictoryProgress victoryProgress(Duration elapsed) {
  final double elapsedMs = elapsed.inMicroseconds / 1000;
  final double fall = _clamp(
    (elapsedMs - winCameraDuration.inMilliseconds) /
        winFallDuration.inMilliseconds,
  );
  final double reveal = _clamp(
    (elapsedMs -
            winCameraDuration.inMilliseconds -
            winFallDuration.inMilliseconds) /
        winLineDuration.inMilliseconds,
  );
  return VictoryProgress(
    fallOffset: 2.2 * (1 - fall * fall),
    lineProgress: victorySmoothStep(reveal),
    dimProgress: victorySmoothStep(reveal),
    ringProgress: victorySmoothStep(
      (elapsedMs -
              winCameraDuration.inMilliseconds -
              winFallDuration.inMilliseconds) /
          320,
    ),
  );
}

double victorySegmentProgress(double progress, int segment, int total) =>
    _clamp(progress * total - segment);

bool hasPhysicalVictory(GameViewData data) =>
    data.snapshot.status == GameStatus.won &&
    data.snapshot.winningLines.isNotEmpty &&
    data.onlineSnapshot?.endReason == null;

Duration gameResultDelay(GameViewData data, {required bool animations}) {
  if (hasPhysicalVictory(data)) {
    return animations ? resultDelay : reducedResultDelay;
  }
  return data.snapshot.status == GameStatus.draw
      ? drawResultDelay
      : endedResultDelay;
}

String victoryPresentationKey(GameViewData data) {
  final OnlineMatchSnapshot? online = data.onlineSnapshot;
  if (online != null) return '${online.code}-${online.round}';
  if (data.recordId.isNotEmpty) return data.recordId;
  final GameMove? last = data.snapshot.history.isEmpty
      ? null
      : data.snapshot.history.last;
  return last == null
      ? '${data.mode.name}-empty'
      : '${data.mode.name}-${last.index}-${last.x}-${last.y}-${last.z}-${last.player.value}';
}

/// A monotonic, pausable clock shared by the scene and result UI.
final class VictoryPresentationSession {
  new({required this.key, required this.animations}) {
    _clock.start();
  }

  final String key;
  final bool animations;
  final Stopwatch _clock = Stopwatch();

  Duration get elapsed => _clock.elapsed;
  bool get cameraLocked => animations && elapsed < victoryCinematicDuration;

  void pause() => _clock.stop();
  void resume() => _clock.start();
}

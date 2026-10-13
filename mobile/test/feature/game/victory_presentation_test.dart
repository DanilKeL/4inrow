import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/game/service/victory_presentation.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';

void main() {
  test('victory progress uses the exact web timeline', () {
    expect(victoryProgress(Duration.zero).fallOffset, 2.2);
    expect(victoryProgress(winCameraDuration).fallOffset, 2.2);

    final VictoryProgress falling = victoryProgress(
      winCameraDuration + winFallDuration ~/ 2,
    );
    expect(falling.fallOffset, closeTo(1.65, 1e-9));
    expect(falling.lineProgress, 0);

    final VictoryProgress landed = victoryProgress(
      winCameraDuration + winFallDuration,
    );
    expect(landed.fallOffset, 0);
    expect(landed.lineProgress, 0);
    expect(landed.ringProgress, 0);

    final VictoryProgress reveal = victoryProgress(
      winCameraDuration + winFallDuration + winLineDuration ~/ 2,
    );
    expect(reveal.lineProgress, .5);
    expect(reveal.dimProgress, .5);
    expect(reveal.ringProgress, 1);

    final VictoryProgress finished = victoryProgress(victoryCinematicDuration);
    expect(finished.lineProgress, 1);
    expect(finished.dimProgress, 1);
    expect(finished.ringProgress, 1);
  });

  test('segments reveal continuously in web order', () {
    expect(victorySegmentProgress(.25, 0, 4), 1);
    expect(victorySegmentProgress(.25, 1, 4), 0);
    expect(victorySegmentProgress(.375, 1, 4), .5);
    expect(victorySegmentProgress(1, 3, 4), 1);
  });

  test('result delays match physical, reduced, draw and remote endings', () {
    final GameSnapshot won = _wonSnapshot();
    final GameViewData local = GameViewData(snapshot: won, recordId: 'win');
    expect(gameResultDelay(local, animations: true), resultDelay);
    expect(gameResultDelay(local, animations: false), reducedResultDelay);

    final GameViewData draw = GameViewData(
      snapshot: GameSnapshot(
        board: List<int>.filled(GameEngine.volume, 0),
        heights: List<int>.filled(GameEngine.area, 0),
        currentPlayer: Player.one,
        history: const [],
        status: GameStatus.draw,
        winner: null,
        winningLines: const [],
      ),
    );
    expect(gameResultDelay(draw, animations: true), drawResultDelay);

    final OnlineMatchSnapshot ended = OnlineMatchSnapshot(
      code: 'ROOM',
      kind: 'ranked',
      game: won,
      players: const [null, null],
      revision: 1,
      round: 2,
      startedAt: null,
      finishedAt: 1,
      rematch: const [],
      endReason: 'resigned',
    );
    final GameViewData remote = GameViewData(
      snapshot: won,
      mode: GameMode.online,
      onlineSnapshot: ended,
    );
    expect(hasPhysicalVictory(remote), isFalse);
    expect(gameResultDelay(remote, animations: true), endedResultDelay);
  });
}

GameSnapshot _wonSnapshot() {
  final List<int> board = List<int>.filled(GameEngine.volume, 0);
  final List<GameMove> history = <GameMove>[];
  for (var x = 0; x < 4; x++) {
    board[x] = 1;
    history.add(GameMove(x: x, y: 0, z: 0, player: Player.one, index: x));
  }
  return GameSnapshot(
    board: board,
    heights: <int>[4, ...List<int>.filled(24, 0)],
    currentPlayer: Player.one,
    history: history,
    status: GameStatus.won,
    winner: Player.one,
    winningLines: [
      [for (var x = 0; x < 4; x++) BoardPosition(x, 0, 0)],
    ],
  );
}

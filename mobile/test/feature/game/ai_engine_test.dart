import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/ai_engine.dart';
import 'package:four3/src/feature/game/service/ai_move_runner.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';

GameSnapshot position(List<MoveCandidate> moves) => GameEngine.replay(moves);

GameSnapshot singleThreatAfterTenMoves() => position(const [
  MoveCandidate(0, 0),
  MoveCandidate(4, 4),
  MoveCandidate(1, 0),
  MoveCandidate(4, 3),
  MoveCandidate(2, 0),
  MoveCandidate(0, 4),
  MoveCandidate(2, 2),
  MoveCandidate(3, 3),
  MoveCandidate(1, 4),
  MoveCandidate(0, 2),
  MoveCandidate(2, 4),
]);

void main() {
  const deterministic = BotOptions(deterministic: true);

  group('bot tactics', () {
    for (final Difficulty difficulty in Difficulty.values) {
      test('$difficulty takes a win before blocking', () {
        final GameSnapshot snapshot = position(const [
          MoveCandidate(0, 0),
          MoveCandidate(0, 4),
          MoveCandidate(1, 0),
          MoveCandidate(1, 4),
          MoveCandidate(2, 0),
          MoveCandidate(2, 4),
        ]);
        expect(
          AiEngine.chooseMove(snapshot, difficulty, options: deterministic),
          const MoveCandidate(3, 0),
        );
      });

      test('$difficulty blocks an immediate loss', () {
        final GameSnapshot snapshot = position(const [
          MoveCandidate(0, 0),
          MoveCandidate(4, 4),
          MoveCandidate(1, 0),
          MoveCandidate(4, 3),
          MoveCandidate(2, 0),
        ]);
        expect(
          AiEngine.chooseMove(snapshot, difficulty, options: deterministic),
          const MoveCandidate(3, 0),
        );
      });

      test('$difficulty returns a legal move without mutation', () {
        final GameSnapshot snapshot = position(const [
          MoveCandidate(2, 2),
          MoveCandidate(2, 2),
          MoveCandidate(2, 2),
          MoveCandidate(2, 2),
          MoveCandidate(2, 2),
        ]);
        final String encoded = GameEngine.serialize(snapshot);
        final MoveCandidate? move = AiEngine.chooseMove(
          snapshot,
          difficulty,
          options: deterministic,
        );
        expect(GameEngine.legalMoves(snapshot), contains(move));
        expect(move, isNot(const MoveCandidate(2, 2)));
        expect(GameEngine.serialize(snapshot), encoded);
      });

      test('$difficulty finds a 3D diagonal win', () {
        final GameSnapshot snapshot = position(const [
          MoveCandidate(0, 0),
          MoveCandidate(1, 1),
          MoveCandidate(1, 1),
          MoveCandidate(2, 2),
          MoveCandidate(2, 2),
          MoveCandidate(3, 3),
          MoveCandidate(2, 2),
          MoveCandidate(3, 3),
          MoveCandidate(3, 3),
          MoveCandidate(4, 0),
        ]);
        expect(
          AiEngine.chooseMove(snapshot, difficulty, options: deterministic),
          const MoveCandidate(3, 3),
        );
      });
    }

    test(
      'medium misses one immediate defense in 7 of 100 evenly spaced rolls',
      () {
        final GameSnapshot snapshot = singleThreatAfterTenMoves();
        final String encoded = GameEngine.serialize(snapshot);
        var missed = 0;

        for (var index = 0; index < 100; index++) {
          final MoveCandidate? move = AiEngine.chooseMove(
            snapshot,
            Difficulty.medium,
            random: _FixedRandom((index + .5) / 100),
          );
          expect(GameEngine.legalMoves(snapshot), contains(move));
          if (move != const MoveCandidate(3, 0)) missed++;
        }

        expect(missed, 7);
        expect(GameEngine.serialize(snapshot), encoded);
      },
    );

    test('medium blocks at and above the 7% boundary', () {
      final GameSnapshot snapshot = singleThreatAfterTenMoves();
      for (final double roll in [.07, .070001, .999999]) {
        expect(
          AiEngine.chooseMove(
            snapshot,
            Difficulty.medium,
            random: _FixedRandom(roll),
          ),
          const MoveCandidate(3, 0),
        );
      }
    });

    test('medium blocks before ten completed moves without rolling', () {
      final _FixedRandom random = _FixedRandom(0);
      final GameSnapshot snapshot = position(
        singleThreatAfterTenMoves().history
            .take(9)
            .map((move) => MoveCandidate(move.x, move.y))
            .toList(),
      );

      expect(snapshot.history, hasLength(9));
      expect(
        AiEngine.chooseMove(snapshot, Difficulty.medium, random: random),
        const MoveCandidate(3, 0),
      );
      expect(random.calls, 0);
    });

    test('medium can first miss the block on the eleventh move', () {
      final GameSnapshot snapshot = position(const [
        MoveCandidate(4, 4),
        MoveCandidate(0, 0),
        MoveCandidate(4, 3),
        MoveCandidate(1, 0),
        MoveCandidate(0, 4),
        MoveCandidate(2, 0),
        MoveCandidate(3, 3),
        MoveCandidate(1, 4),
        MoveCandidate(0, 2),
        MoveCandidate(2, 4),
      ]);

      expect(snapshot.history, hasLength(10));
      expect(
        AiEngine.chooseMove(
          snapshot,
          Difficulty.medium,
          random: _FixedRandom(0),
        ),
        isNot(const MoveCandidate(3, 0)),
      );
    });

    test('deterministic medium always blocks without rolling', () {
      final _FixedRandom random = _FixedRandom(0);
      expect(
        AiEngine.chooseMove(
          singleThreatAfterTenMoves(),
          Difficulty.medium,
          options: deterministic,
          random: random,
        ),
        const MoveCandidate(3, 0),
      );
      expect(random.calls, 0);
    });

    for (final Difficulty difficulty in [Difficulty.easy, Difficulty.hard]) {
      test('$difficulty still blocks late threats without rolling', () {
        final _FixedRandom random = _FixedRandom(0);
        expect(
          AiEngine.chooseMove(
            singleThreatAfterTenMoves(),
            difficulty,
            random: random,
          ),
          const MoveCandidate(3, 0),
        );
        expect(random.calls, 0);
      });
    }

    test('medium still blocks multiple immediate threats without rolling', () {
      final _FixedRandom random = _FixedRandom(0);
      final GameSnapshot snapshot = position(const [
        MoveCandidate(1, 2),
        MoveCandidate(0, 0),
        MoveCandidate(2, 2),
        MoveCandidate(4, 4),
        MoveCandidate(3, 2),
        MoveCandidate(0, 4),
        MoveCandidate(2, 4),
        MoveCandidate(4, 0),
        MoveCandidate(1, 0),
        MoveCandidate(0, 1),
        MoveCandidate(3, 4),
      ]);

      expect(
        AiEngine.chooseMove(snapshot, Difficulty.medium, random: random),
        const MoveCandidate(0, 2),
      );
      expect(random.calls, 0);
    });

    test('medium takes its own late win without rolling', () {
      final _FixedRandom random = _FixedRandom(0);
      final GameSnapshot snapshot = position(const [
        MoveCandidate(0, 0),
        MoveCandidate(0, 4),
        MoveCandidate(1, 0),
        MoveCandidate(1, 4),
        MoveCandidate(2, 0),
        MoveCandidate(2, 4),
        MoveCandidate(2, 2),
        MoveCandidate(4, 3),
        MoveCandidate(3, 3),
        MoveCandidate(0, 2),
      ]);

      expect(
        AiEngine.chooseMove(snapshot, Difficulty.medium, random: random),
        const MoveCandidate(3, 0),
      );
      expect(random.calls, 0);
    });

    test('returns null for a terminal game', () {
      final GameSnapshot won = position(const [
        MoveCandidate(0, 0),
        MoveCandidate(0, 4),
        MoveCandidate(1, 0),
        MoveCandidate(1, 4),
        MoveCandidate(2, 0),
        MoveCandidate(2, 4),
        MoveCandidate(3, 0),
      ]);
      expect(AiEngine.chooseMove(won, Difficulty.hard), isNull);
    });
  });

  test('runner calculates in an isolate and can be reused', () async {
    final runner = AiMoveRunner();
    addTearDown(runner.dispose);
    final GameSnapshot snapshot = position(const [
      MoveCandidate(0, 0),
      MoveCandidate(4, 4),
      MoveCandidate(1, 0),
      MoveCandidate(4, 3),
      MoveCandidate(2, 0),
    ]);
    expect(
      await runner.run(snapshot, Difficulty.medium, options: deterministic),
      const MoveCandidate(3, 0),
    );
  });

  test('runner cancellation also wins while the isolate is spawning', () async {
    final AiMoveRunner runner = AiMoveRunner();
    final Future<MoveCandidate?> pending = runner.run(
      GameEngine.create(),
      Difficulty.hard,
    );
    final Future<void> cancellation = expectLater(
      pending,
      throwsA(isA<AiMoveCancelled>()),
    );

    runner.cancel();

    await cancellation;
    final MoveCandidate? next = await runner.run(
      GameEngine.create(),
      Difficulty.easy,
    );
    expect(next, isNotNull);
    runner.dispose();
  });
}

final class _FixedRandom implements math.Random {
  new(this.value);

  final double value;
  int calls = 0;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() {
    calls++;
    return value;
  }

  @override
  int nextInt(int max) {
    calls++;
    return 0;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/ai_engine.dart';
import 'package:four3/src/feature/game/service/ai_move_runner.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';

GameSnapshot position(List<MoveCandidate> moves) => GameEngine.replay(moves);

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

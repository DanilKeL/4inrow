import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';

GameSnapshot play(GameSnapshot snapshot, int x, int y) {
  final MoveResult result = GameEngine.makeMove(snapshot, x, y);
  return switch (result) {
    MoveResult$Valid(:final snapshot) => snapshot,
    MoveResult$Invalid(:final reason) => throw StateError(reason),
  };
}

const winMoves = [
  MoveCandidate(0, 0),
  MoveCandidate(0, 4),
  MoveCandidate(1, 0),
  MoveCandidate(1, 4),
  MoveCandidate(2, 0),
  MoveCandidate(2, 4),
  MoveCandidate(3, 0),
];

void main() {
  group('3D victory detection', () {
    test('covers exactly 13 unique undirected axes', () {
      expect(GameEngine.directions, hasLength(13));
      expect(GameEngine.directions.toSet(), hasLength(13));
      for (final BoardPosition direction in GameEngine.directions) {
        expect(
          GameEngine.directions,
          isNot(
            contains(BoardPosition(-direction.x, -direction.y, -direction.z)),
          ),
        );
      }
    });

    for (final BoardPosition direction in GameEngine.directions) {
      for (final length in const [4, 5]) {
        test('finds $length pieces on $direction from every position', () {
          final List<BoardPosition> positions = [
            for (var i = 0; i < length; i++)
              BoardPosition(
                (direction.x < 0 ? 4 : 0) + direction.x * i,
                (direction.y < 0 ? 4 : 0) + direction.y * i,
                (direction.z < 0 ? 4 : 0) + direction.z * i,
              ),
          ];
          for (final Player player in Player.values) {
            final List<int> board = [...GameEngine.create().board];
            for (final position in positions) {
              board[GameEngine.boardIndex(position)] = player.value;
            }
            for (final last in positions) {
              expect(GameEngine.detectWinningLines(board, last, player), [
                positions,
              ]);
            }
          }
        });
      }
    }

    test('returns simultaneous lines through the last move', () {
      final List<int> board = [...GameEngine.create().board];
      for (var i = 0; i < 5; i++) {
        board[GameEngine.boardIndex(BoardPosition(i, 2, 2))] = 1;
        board[GameEngine.boardIndex(BoardPosition(2, i, 2))] = 1;
        board[GameEngine.boardIndex(BoardPosition(2, 2, i))] = 1;
      }
      final List<List<BoardPosition>> lines = GameEngine.detectWinningLines(
        board,
        const BoardPosition(2, 2, 2),
        Player.one,
      );
      expect(lines, hasLength(3));
      expect(lines.every((line) => line.length == 5), isTrue);
    });
  });

  group('gravity, turns and persistence', () {
    test('starts with 125 cells, 25 columns and player one', () {
      final GameSnapshot snapshot = GameEngine.create();
      expect(snapshot.board, List<int>.filled(125, 0));
      expect(snapshot.heights, List<int>.filled(25, 0));
      expect(snapshot.currentPlayer, Player.one);
      expect(GameEngine.legalMoves(snapshot), hasLength(25));
    });

    test('stacks, alternates and rejects a full column', () {
      GameSnapshot snapshot = GameEngine.create();
      for (var z = 0; z < 5; z++) {
        snapshot = play(snapshot, 3, 2);
        expect(snapshot.history[z].z, z);
        expect(snapshot.history[z].player, Player.values[z % 2]);
      }
      expect(
        GameEngine.makeMove(snapshot, 3, 2),
        const MoveResult$Invalid('Column is full'),
      );
      expect(
        GameEngine.legalMoves(snapshot),
        isNot(contains(const MoveCandidate(3, 2))),
      );
    });

    test('detects horizontal, vertical and space diagonal wins', () {
      final GameSnapshot horizontal = GameEngine.replay(winMoves);
      expect(horizontal.status, GameStatus.won);
      expect(horizontal.winner, Player.one);

      final GameSnapshot vertical = GameEngine.replay(const [
        MoveCandidate(2, 2),
        MoveCandidate(0, 0),
        MoveCandidate(2, 2),
        MoveCandidate(4, 0),
        MoveCandidate(2, 2),
        MoveCandidate(0, 4),
        MoveCandidate(2, 2),
      ]);
      expect(vertical.winningLines.single.map((position) => position.z), [
        0,
        1,
        2,
        3,
      ]);

      final GameSnapshot diagonal = GameEngine.replay(const [
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
        MoveCandidate(3, 3),
      ]);
      expect(diagonal.winningLines.single, const [
        BoardPosition(0, 0, 0),
        BoardPosition(1, 1, 1),
        BoardPosition(2, 2, 2),
        BoardPosition(3, 3, 3),
      ]);
    });

    test('undo and serialization round-trip', () {
      final GameSnapshot won = GameEngine.replay(winMoves);
      final GameSnapshot previous = GameEngine.undo(won);
      expect(previous, GameEngine.replay(winMoves, count: 6));
      expect(GameEngine.deserialize(GameEngine.serialize(won)), won);
      expect(GameEngine.undo(GameEngine.create()), GameEngine.create());
    });

    test('rejects corrupt saves and illegal histories', () {
      for (final value in ['null', '{}', '[]', '"hello"', '{']) {
        expect(() => GameEngine.deserialize(value), throwsFormatException);
      }
      expect(
        () => GameEngine.replay(List.filled(6, const MoveCandidate(0, 0))),
        throwsFormatException,
      );
      expect(
        () => GameEngine.replay([...winMoves, const MoveCandidate(4, 4)]),
        throwsFormatException,
      );
    });
  });
}

import 'dart:convert';

import 'package:four3/src/feature/game/model/game_models.dart';

abstract final class GameEngine {
  static const int size = 5;
  static const int connect = 4;
  static const int area = size * size;
  static const int volume = area * size;

  static const List<BoardPosition> directions = [
    BoardPosition(1, 0, 0),
    BoardPosition(0, 1, 0),
    BoardPosition(0, 0, 1),
    BoardPosition(1, 1, 0),
    BoardPosition(1, -1, 0),
    BoardPosition(1, 0, 1),
    BoardPosition(1, 0, -1),
    BoardPosition(0, 1, 1),
    BoardPosition(0, 1, -1),
    BoardPosition(1, 1, 1),
    BoardPosition(1, 1, -1),
    BoardPosition(1, -1, 1),
    BoardPosition(1, -1, -1),
  ];

  static bool coordinate(int value) => value >= 0 && value < size;

  static bool inside(BoardPosition position) =>
      coordinate(position.x) &&
      coordinate(position.y) &&
      coordinate(position.z);

  static int boardIndex(BoardPosition position) =>
      position.x + position.y * size + position.z * area;

  static GameSnapshot create({Player firstPlayer = Player.one}) => GameSnapshot(
    board: List<int>.filled(volume, 0),
    heights: List<int>.filled(area, 0),
    currentPlayer: firstPlayer,
    history: const [],
    status: GameStatus.playing,
    winner: null,
    winningLines: const [],
  );

  static List<List<BoardPosition>> detectWinningLines(
    List<int> board,
    BoardPosition last,
    Player player,
  ) {
    if (!inside(last) || board[boardIndex(last)] != player.value) {
      return const [];
    }
    final lines = <List<BoardPosition>>[];
    for (final BoardPosition direction in directions) {
      final line = <BoardPosition>[last];
      for (final sign in const [-1, 1]) {
        for (var distance = 1; distance < size; distance++) {
          final position = BoardPosition(
            last.x + direction.x * distance * sign,
            last.y + direction.y * distance * sign,
            last.z + direction.z * distance * sign,
          );
          if (!inside(position) ||
              board[boardIndex(position)] != player.value) {
            break;
          }
          if (sign < 0) {
            line.insert(0, position);
          } else {
            line.add(position);
          }
        }
      }
      if (line.length >= connect) lines.add(line);
    }
    return lines;
  }

  static MoveResult makeMove(GameSnapshot snapshot, int x, int y) {
    if (snapshot.status != GameStatus.playing) {
      return const MoveResult$Invalid('Game is already finished');
    }
    if (!coordinate(x) || !coordinate(y)) {
      return const MoveResult$Invalid('Invalid column coordinates');
    }
    final int column = x + y * size;
    final int z = snapshot.heights[column];
    if (z >= size) return const MoveResult$Invalid('Column is full');

    final move = GameMove(
      x: x,
      y: y,
      z: z,
      player: snapshot.currentPlayer,
      index: snapshot.history.length,
    );
    final List<int> board = [...snapshot.board]
      ..[boardIndex(move.position)] = move.player.value;
    final List<int> heights = [...snapshot.heights]..[column] = z + 1;
    final List<List<BoardPosition>> winningLines = detectWinningLines(
      board,
      move.position,
      move.player,
    );
    final GameStatus status = winningLines.isNotEmpty
        ? GameStatus.won
        : heights.every((height) => height == size)
        ? GameStatus.draw
        : GameStatus.playing;
    return MoveResult$Valid(
      move: move,
      snapshot: GameSnapshot(
        board: board,
        heights: heights,
        currentPlayer: status == GameStatus.playing
            ? move.player.other
            : move.player,
        history: [...snapshot.history, move],
        status: status,
        winner: status == GameStatus.won ? move.player : null,
        winningLines: winningLines,
      ),
    );
  }

  static List<MoveCandidate> legalMoves(GameSnapshot snapshot) {
    if (snapshot.status != GameStatus.playing) return const [];
    return [
      for (var column = 0; column < area; column++)
        if (snapshot.heights[column] < size)
          MoveCandidate(column % size, column ~/ size),
    ];
  }

  static GameSnapshot replay(
    List<MoveCandidate> moves, {
    int? count,
    Player? firstPlayer,
  }) {
    final int length = count ?? moves.length;
    if (length < 0 || length > moves.length || length > volume) {
      throw const FormatException('Invalid replay length');
    }
    GameSnapshot snapshot = create(firstPlayer: firstPlayer ?? Player.one);
    for (var index = 0; index < length; index++) {
      final MoveCandidate move = moves[index];
      final MoveResult result = makeMove(snapshot, move.x, move.y);
      if (result case MoveResult$Valid(snapshot: final next)) {
        snapshot = next;
      } else if (result case MoveResult$Invalid(:final reason)) {
        throw FormatException('Invalid move at index $index: $reason');
      }
    }
    return snapshot;
  }

  static GameSnapshot replayHistory(
    List<GameMove> history, {
    int? count,
    Player? firstPlayer,
  }) => replay(
    history
        .map((move) => MoveCandidate(move.x, move.y))
        .toList(growable: false),
    count: count,
    firstPlayer:
        firstPlayer ?? (history.isEmpty ? Player.one : history.first.player),
  );

  static GameSnapshot undo(GameSnapshot snapshot) => replayHistory(
    snapshot.history,
    count: snapshot.history.isEmpty ? 0 : snapshot.history.length - 1,
  );

  static String serialize(GameSnapshot snapshot) => jsonEncode({
    'version': 1,
    'size': size,
    'connect': connect,
    'firstPlayer': snapshot.history.isEmpty
        ? snapshot.currentPlayer.value
        : snapshot.history.first.player.value,
    'moves': [
      for (final move in snapshot.history) {'x': move.x, 'y': move.y},
    ],
  });

  static GameSnapshot deserialize(String encoded) {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      throw const FormatException('Invalid saved game');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['size'] != size ||
        decoded['connect'] != connect ||
        decoded['moves'] is! List ||
        (decoded['moves'] as List).length > volume) {
      throw const FormatException('Unsupported or invalid saved game');
    }
    final Player firstPlayer = decoded['firstPlayer'] == null
        ? Player.one
        : Player.fromValue(decoded['firstPlayer']);
    final moves = <MoveCandidate>[];
    for (final entry in decoded['moves'] as List) {
      if (entry is! Map || entry['x'] is! num || entry['y'] is! num) {
        throw const FormatException('Invalid saved move');
      }
      final int x = (entry['x'] as num).toInt();
      final int y = (entry['y'] as num).toInt();
      if ((entry['x'] as num) != x ||
          (entry['y'] as num) != y ||
          !coordinate(x) ||
          !coordinate(y)) {
        throw const FormatException('Invalid saved coordinates');
      }
      moves.add(MoveCandidate(x, y));
    }
    return replay(moves, firstPlayer: firstPlayer);
  }
}

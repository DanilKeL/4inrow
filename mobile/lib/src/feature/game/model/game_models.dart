import 'dart:collection';

import 'package:equatable/equatable.dart';

enum Player {
  one,
  two;

  int get value => index + 1;

  Player get other => this == Player.one ? Player.two : Player.one;

  static Player fromValue(Object? value) => switch (value) {
    1 => Player.one,
    2 => Player.two,
    _ => throw const FormatException('Invalid player'),
  };
}

enum GameStatus { playing, won, draw }

enum GameMode { local, ai, online, level, daily }

enum GamePhase {
  menu,
  playing,
  animating,
  aiThinking,
  paused,
  victory,
  draw,
  replay,
  waiting,
  sending,
}

enum Difficulty { easy, medium, hard }

enum CameraView { perspective, top, front }

final class BoardPosition extends Equatable {
  const new(this.x, this.y, this.z);

  final int x;
  final int y;
  final int z;

  Map<String, int> toJson() => {'x': x, 'y': y, 'z': z};

  @override
  List<Object> get props => [x, y, z];
}

final class GameMove extends Equatable {
  const new({
    required this.x,
    required this.y,
    required this.z,
    required this.player,
    required this.index,
  });

  final int x;
  final int y;
  final int z;
  final Player player;
  final int index;

  BoardPosition get position => BoardPosition(x, y, z);

  @override
  List<Object> get props => [x, y, z, player, index];
}

final class GameSnapshot extends Equatable {
  new({
    required List<int> board,
    required List<int> heights,
    required this.currentPlayer,
    required List<GameMove> history,
    required this.status,
    required this.winner,
    required List<List<BoardPosition>> winningLines,
  }) : board = UnmodifiableListView(board),
       heights = UnmodifiableListView(heights),
       history = UnmodifiableListView(history),
       winningLines = UnmodifiableListView(
         winningLines.map(UnmodifiableListView.new),
       );

  final List<int> board;
  final List<int> heights;
  final Player currentPlayer;
  final List<GameMove> history;
  final GameStatus status;
  final Player? winner;
  final List<List<BoardPosition>> winningLines;

  @override
  List<Object?> get props => [
    board,
    heights,
    currentPlayer,
    history,
    status,
    winner,
    winningLines,
  ];
}

sealed class MoveResult extends Equatable {
  const new();
}

final class MoveResult$Valid extends MoveResult {
  const new({required this.snapshot, required this.move});

  final GameSnapshot snapshot;
  final GameMove move;

  @override
  List<Object> get props => [snapshot, move];
}

final class MoveResult$Invalid extends MoveResult {
  const new(this.reason);

  final String reason;

  @override
  List<Object> get props => [reason];
}

final class MoveCandidate extends Equatable {
  const new(this.x, this.y);

  final int x;
  final int y;

  @override
  List<Object> get props => [x, y];
}

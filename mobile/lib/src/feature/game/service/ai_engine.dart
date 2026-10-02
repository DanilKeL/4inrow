import 'dart:math' as math;
import 'dart:typed_data';

import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';

final class BotOptions {
  const new({this.deterministic = false, this.nodeBudget = 6000});

  final bool deterministic;
  final int nodeBudget;
}

abstract final class AiEngine {
  static const int _win = 1000000;
  static const List<int> _weights = [0, 3, 32, 180, _win];
  static final math.Random _random = math.Random();
  static final List<List<int>> _segments = _buildSegments();
  static final List<List<int>> _throughCell = _buildThroughCell();
  static final List<List<int>> _hashes = _buildHashes();
  static final List<int> _centrality = List.generate(
    GameEngine.area,
    (column) => (4 - (column % 5 - 2).abs() - (column ~/ 5 - 2).abs()) * 3,
  );

  static List<List<int>> _buildSegments() {
    final result = <List<int>>[];
    for (var z = 0; z < GameEngine.size; z++) {
      for (var y = 0; y < GameEngine.size; y++) {
        for (var x = 0; x < GameEngine.size; x++) {
          for (final BoardPosition direction in GameEngine.directions) {
            if (!GameEngine.coordinate(
                  x + direction.x * (GameEngine.connect - 1),
                ) ||
                !GameEngine.coordinate(
                  y + direction.y * (GameEngine.connect - 1),
                ) ||
                !GameEngine.coordinate(
                  z + direction.z * (GameEngine.connect - 1),
                )) {
              continue;
            }
            result.add([
              for (var i = 0; i < GameEngine.connect; i++)
                x +
                    direction.x * i +
                    (y + direction.y * i) * GameEngine.size +
                    (z + direction.z * i) * GameEngine.area,
            ]);
          }
        }
      }
    }
    return result;
  }

  static List<List<int>> _buildThroughCell() {
    final List<List<int>> result = List.generate(
      GameEngine.volume,
      (_) => <int>[],
    );
    for (var index = 0; index < _segments.length; index++) {
      for (final int cell in _segments[index]) {
        result[cell].add(index);
      }
    }
    return result;
  }

  static int _hashSeed = 0x51f15e;
  static int _randomHash() {
    _hashSeed ^= (_hashSeed << 13) & 0xffffffff;
    _hashSeed ^= _hashSeed >>> 17;
    _hashSeed ^= (_hashSeed << 5) & 0xffffffff;
    return _hashSeed & 0xffffffff;
  }

  static List<List<int>> _buildHashes() => List.generate(
    GameEngine.volume * 2,
    (_) => [_randomHash(), _randomHash()],
  );

  static MoveCandidate? chooseMove(
    GameSnapshot snapshot,
    Difficulty difficulty, {
    BotOptions options = const BotOptions(),
  }) {
    if (snapshot.status != GameStatus.playing) return null;
    final position = _Position(snapshot);
    if (position.legal().isEmpty) return null;
    final Player player = snapshot.currentPlayer;
    final List<int> wins = position.threats(player);
    final List<int> blocks = position.threats(player.other);
    late final int column;
    if (wins.isNotEmpty) {
      column = wins.first;
    } else if (blocks.isNotEmpty) {
      column = blocks.first;
    } else {
      final List<_RankedMove> ranked = _candidates(position, player);
      if (ranked.first.score == _win) {
        column = ranked.first.column;
      } else if (difficulty == Difficulty.easy) {
        final List<_RankedMove> safe = ranked
            .where((move) => move.score > -_win)
            .toList();
        final List<_RankedMove> pool = (safe.isNotEmpty ? safe : ranked)
            .take(4)
            .toList();
        column = pool[options.deterministic ? 0 : _random.nextInt(pool.length)]
            .column;
      } else {
        final List<_RankedMove> safe = ranked
            .where((move) => move.score > -_win)
            .toList();
        column = _searchMove(
          position,
          player,
          difficulty,
          ranked.first.column,
          (safe.isNotEmpty ? safe : ranked).map((move) => move.column).toList(),
          options,
        );
      }
    }
    return MoveCandidate(column % GameEngine.size, column ~/ GameEngine.size);
  }

  static List<_RankedMove> _candidates(_Position position, Player player) {
    final result = <_RankedMove>[];
    for (final int column in position.legal()) {
      position.put(column, player);
      final int enemyWins = position.threats(player.other).length;
      final int ownWins = position.threats(player).length;
      final int score = enemyWins > 0
          ? -_win
          : ownWins >= 2
          ? _win
          : position.evaluate(player).round() + ownWins * 1200;
      position.remove(column);
      result.add(_RankedMove(column, score));
    }
    result.sort((a, b) => b.score.compareTo(a.score));
    return result;
  }

  static int _searchMove(
    _Position position,
    Player player,
    Difficulty difficulty,
    int fallback,
    List<int> roots,
    BotOptions options,
  ) {
    final timer = Stopwatch()..start();
    final deadlineMs = difficulty == Difficulty.hard ? 650 : 180;
    final maxDepth = difficulty == Difficulty.hard ? 8 : 4;
    final margin = difficulty == Difficulty.hard ? 24 : 60;
    final table = <int, _Entry>{};
    var chosen = fallback;
    var alternatives = <_ScoredMove>[];
    var visited = 0;

    int negamax(Player turn, int depth, int alpha, int beta, int ply) {
      visited++;
      var lowerBound = alpha;
      var upperBound = beta;
      if (options.deterministic
          ? visited > options.nodeBudget
          : (visited & 31) == 0 && timer.elapsedMilliseconds >= deadlineMs) {
        throw const _SearchTimeout();
      }
      if (position.threats(turn).isNotEmpty) return _win - ply;
      final List<int> blocks = position.threats(turn.other);
      if (blocks.length >= 2) return -_win + ply + 1;
      final List<int> legal = blocks.isNotEmpty ? blocks : position.legal();
      if (legal.isEmpty) return 0;
      if (depth <= 0 && (blocks.isEmpty || depth <= -6)) {
        return position.evaluate(turn).round();
      }
      final _Entry? candidate = table[position.hash];
      final _Entry? entry =
          candidate?.lock == position.lock && candidate?.turn == turn
          ? candidate
          : null;
      if (depth > 0 && entry != null && entry.depth >= depth) {
        if (entry.bound == _Bound.exact) return entry.score;
        if (entry.bound == _Bound.lower) {
          lowerBound = math.max(lowerBound, entry.score);
        } else {
          upperBound = math.min(upperBound, entry.score);
        }
        if (lowerBound >= upperBound) return entry.score;
      }
      final int originalAlpha = lowerBound;
      final int originalBeta = upperBound;
      var best = -0x3fffffff;
      int bestMove = legal.first;
      for (final int column in position.ordered(
        turn,
        legal,
        entry?.move ?? -1,
      )) {
        position.put(column, turn);
        late final int score;
        try {
          score = -negamax(
            turn.other,
            depth - 1,
            -upperBound,
            -lowerBound,
            ply + 1,
          );
        } finally {
          position.remove(column);
        }
        if (score > best) {
          best = score;
          bestMove = column;
        }
        lowerBound = math.max(lowerBound, score);
        if (lowerBound >= upperBound) break;
      }
      if (depth > 0 && table.length < 60000) {
        table[position.hash] = _Entry(
          lock: position.lock,
          turn: turn,
          depth: depth,
          score: best,
          bound: best <= originalAlpha
              ? _Bound.upper
              : best >= originalBeta
              ? _Bound.lower
              : _Bound.exact,
          move: bestMove,
        );
      }
      return best;
    }

    for (var depth = 1; depth <= maxDepth; depth++) {
      var best = -0x3fffffff;
      var iterationMove = chosen;
      final scores = <_ScoredMove>[];
      try {
        for (final int column in position.ordered(player, roots, chosen)) {
          if (!options.deterministic &&
              timer.elapsedMilliseconds >= deadlineMs) {
            throw const _SearchTimeout();
          }
          position.put(column, player);
          late final int score;
          final int threshold = best - margin;
          try {
            score = -negamax(
              player.other,
              depth - 1,
              -0x3fffffff,
              -threshold,
              1,
            );
          } finally {
            position.remove(column);
          }
          scores.add(_ScoredMove(column, score, exact: score > threshold));
          if (score > best) {
            best = score;
            iterationMove = column;
          }
        }
        chosen = iterationMove;
        alternatives = depth < 2 || best.abs() > _win - 100
            ? []
            : (scores
                      .where(
                        (move) =>
                            move.exact &&
                            move.column != chosen &&
                            move.score >= best - margin &&
                            move.score > -_win + 100,
                      )
                      .toList()
                    ..sort((a, b) => b.score.compareTo(a.score)))
                  .take(3)
                  .toList();
        if (best.abs() > _win - 100) break;
      } on _SearchTimeout {
        break;
      }
    }
    final chance = difficulty == Difficulty.hard ? 0.25 : 0.35;
    if (!options.deterministic &&
        alternatives.isNotEmpty &&
        _random.nextDouble() < chance) {
      return alternatives[_random.nextInt(alternatives.length)].column;
    }
    return chosen;
  }
}

final class _Position {
  new(GameSnapshot snapshot)
    : board = [...snapshot.board],
      heights = [...snapshot.heights],
      counts = [
        Int8List(AiEngine._segments.length),
        Int8List(AiEngine._segments.length),
      ] {
    for (var cell = 0; cell < board.length; cell++) {
      if (board[cell] != 0) update(cell, Player.fromValue(board[cell]), 1);
    }
  }

  final List<int> board;
  final List<int> heights;
  final List<Int8List> counts;
  num score = 0;
  int hash = 0;
  int lock = 0;

  num lineScore(int line) {
    final int a = counts[0][line];
    final int b = counts[1][line];
    return a != 0 && b != 0 ? 0 : AiEngine._weights[a] - AiEngine._weights[b];
  }

  void update(int cell, Player player, int delta) {
    for (final int line in AiEngine._throughCell[cell]) {
      score -= lineScore(line);
      counts[player.index][line] += delta;
      score += lineScore(line);
    }
    score +=
        (player == Player.one ? 1 : -1) *
        delta *
        AiEngine._centrality[cell % 25];
    final List<int> values = AiEngine._hashes[cell * 2 + player.index];
    hash ^= values[0];
    lock ^= values[1];
  }

  List<int> legal() => [
    for (var column = 0; column < GameEngine.area; column++)
      if (heights[column] < GameEngine.size) column,
  ];

  void put(int column, Player player) {
    final int cell = column + heights[column]++ * GameEngine.area;
    board[cell] = player.value;
    update(cell, player, 1);
  }

  void remove(int column) {
    final int cell = column + --heights[column] * GameEngine.area;
    update(cell, Player.fromValue(board[cell]), -1);
    board[cell] = 0;
  }

  List<int> threats(Player player) => [
    for (var column = 0; column < GameEngine.area; column++)
      if (heights[column] < GameEngine.size &&
          AiEngine._throughCell[column + heights[column] * GameEngine.area].any(
            (line) =>
                counts[player.index][line] == GameEngine.connect - 1 &&
                counts[player.other.index][line] == 0,
          ))
        column,
  ];

  num evaluate(Player player) {
    num result = score;
    for (var line = 0; line < AiEngine._segments.length; line++) {
      final int a = counts[0][line];
      final int b = counts[1][line];
      if ((a != 0 && b != 0) || math.max(a, b) < 2) continue;
      var support = 0;
      for (final int cell in AiEngine._segments[line]) {
        if (board[cell] == 0) {
          support += cell ~/ GameEngine.area - heights[cell % GameEngine.area];
        }
      }
      final int pieces = math.max(a, b);
      final num adjustment = support == 0
          ? (pieces == 3 ? 700 : 16)
          : (-AiEngine._weights[pieces] * support) / (support + 2);
      result += (a != 0 ? 1 : -1) * adjustment;
    }
    return player == Player.one ? result : -result;
  }

  List<int> ordered(Player player, List<int> columns, int preferred) {
    final ranked = <_RankedMove>[];
    for (final column in columns) {
      put(column, player);
      final int value =
          (score * (player == Player.one ? 1 : -1)).round() +
          (column == preferred ? AiEngine._win * 2 : 0);
      remove(column);
      ranked.add(_RankedMove(column, value));
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked.map((move) => move.column).toList();
  }
}

final class _RankedMove {
  const new(this.column, this.score);
  final int column;
  final int score;
}

final class _ScoredMove {
  const new(this.column, this.score, {required this.exact});
  final int column;
  final int score;
  final bool exact;
}

enum _Bound { exact, lower, upper }

final class _Entry {
  const new({
    required this.lock,
    required this.turn,
    required this.depth,
    required this.score,
    required this.bound,
    required this.move,
  });
  final int lock;
  final Player turn;
  final int depth;
  final int score;
  final _Bound bound;
  final int move;
}

final class _SearchTimeout implements Exception {
  const new();
}

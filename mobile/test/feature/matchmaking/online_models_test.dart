import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';

void main() {
  test('parses the authoritative server lobby snapshot', () {
    final snapshot = OnlineMatchSnapshot.fromJson({
      'code': 'ABCDE',
      'kind': 'quick',
      'game': {
        'board': List<int>.filled(125, 0),
        'heights': List<int>.filled(25, 0),
        'currentPlayer': 1,
        'history': const <Object>[],
        'status': 'playing',
        'winner': null,
        'winningLines': const <Object>[],
      },
      'players': const [
        {'name': 'Alice', 'connected': true},
        {'name': 'Bob', 'connected': false},
      ],
      'revision': 4,
      'round': 2,
      'startedAt': 100,
      'finishedAt': null,
      'rematch': const [1],
      'ranking': const {
        'rated': true,
        'points': [1010, 990],
      },
    });
    expect(snapshot.code, 'ABCDE');
    expect(snapshot.game.currentPlayer, Player.one);
    expect(snapshot.players[1]!.connected, isFalse);
    expect(snapshot.rematch, [Player.one]);
    expect(snapshot.ranking!.points, [1010, 990]);
  });

  test('rejects malformed board arrays', () {
    expect(
      () => OnlineMatchSnapshot.fromJson({
        'code': 'ABCDE',
        'game': {
          'board': const [0],
          'heights': List<int>.filled(25, 0),
          'currentPlayer': 1,
          'history': const <Object>[],
          'status': 'playing',
          'winningLines': const <Object>[],
        },
      }),
      throwsFormatException,
    );
  });
}

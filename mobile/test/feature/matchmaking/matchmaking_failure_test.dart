import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_bloc.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_status.dart';
import 'package:four3/src/feature/matchmaking/widget/online_setup_view.dart';

void main() {
  test('normalizes pasted room codes', () {
    expect(normalizeRoomCode(' a-b c-de '), 'ABCDE');
  });

  test('maps every known server error code to a typed failure', () {
    expect(
      <String, MatchmakingFailure>{
            'LOBBY_NOT_FOUND': MatchmakingFailure.roomNotFound,
            'LOBBY_FULL': MatchmakingFailure.roomFull,
            'MATCH_NOT_FOUND': MatchmakingFailure.matchExpired,
            'ACCOUNT_BUSY': MatchmakingFailure.accountBusy,
            'ALREADY_MATCHING': MatchmakingFailure.alreadyMatching,
            'ALREADY_IN_LOBBY': MatchmakingFailure.alreadyMatching,
            'SERVER_FULL': MatchmakingFailure.serverFull,
          }
          .map(
            (code, failure) =>
                MapEntry(code, matchmakingFailureFromCode(code) == failure),
          )
          .values,
      everyElement(isTrue),
    );
    expect(matchmakingFailureFromCode('UNKNOWN'), MatchmakingFailure.generic);
  });

  test('search timer is stable and slow actions become cancellable at 9s', () {
    expect(formatMatchmakingElapsed(const Duration(seconds: 8)), '00:08');
    expect(formatMatchmakingElapsed(const Duration(seconds: 68)), '01:08');
    expect(formatMatchmakingElapsed(const Duration(days: 1)), '99:59');
    expect(shouldShowMatchmakingCancel(1000, now: 9999), isFalse);
    expect(shouldShowMatchmakingCancel(1000, now: 10000), isTrue);
  });
}

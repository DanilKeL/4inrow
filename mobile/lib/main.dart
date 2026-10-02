import 'package:flutter/material.dart';
import 'package:four3/src/app/four_app.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/initialization/widget/initialization_root_scope.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';
import 'package:four3/src/feature/leaderboard/widget/leaderboard_root_scope.dart';
import 'package:four3/src/feature/match_history/widget/match_history_root_scope.dart';
import 'package:four3/src/feature/matchmaking/widget/matchmaking_root_scope.dart';
import 'package:four3/src/feature/settings/widget/settings_root_scope.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const RootScope(
      child: InitializationRootScope(
        child: SettingsRootScope(
          child: AccountRootScope(
            child: GameRootScope(
              child: MatchmakingRootScope(
                child: MatchHistoryRootScope(
                  child: LeaderboardRootScope(child: FourApp()),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

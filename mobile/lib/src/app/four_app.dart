import 'package:flutter/widgets.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/game/widget/game_shell.dart';
import 'package:four3/src/feature/initialization/widget/initialization_root_scope.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';
import 'package:four3/src/feature/leaderboard/widget/leaderboard_root_scope.dart';
import 'package:four3/src/feature/match_history/widget/match_history_root_scope.dart';
import 'package:four3/src/feature/matchmaking/widget/matchmaking_root_scope.dart';
import 'package:four3/src/feature/settings/widget/settings_root_scope.dart';

class FourApp extends StatelessWidget {
  const new({super.key});

  static Widget _buildFeatureScopes(Widget child) => InitializationRootScope(
    child: SettingsRootScope(
      child: AccountRootScope(
        child: GameRootScope(
          child: MatchmakingRootScope(
            child: MatchHistoryRootScope(
              child: LeaderboardRootScope(child: child),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) =>
      const RootScope(scopesBuilder: _buildFeatureScopes, child: GameShell());
}

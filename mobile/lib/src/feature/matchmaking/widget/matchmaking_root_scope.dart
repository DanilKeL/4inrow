import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/bloc/game_event.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_bloc.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_event.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_state.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_status.dart';

class MatchmakingRootScope extends StatefulWidget {
  const new({required this.child, super.key});
  final Widget child;

  static MatchmakingBloc of(BuildContext context) =>
      context.inheritedOf<_InheritedMatchmakingScope>().bloc;

  @override
  State<MatchmakingRootScope> createState() => _MatchmakingRootScopeState();
}

class _MatchmakingRootScopeState extends State<MatchmakingRootScope>
    with WidgetsBindingObserver {
  late final MatchmakingBloc _bloc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bloc = MatchmakingBloc(transport: RootScope.of(context).onlineTransport)
      ..add(const MatchmakingEvent$Load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _bloc.add(const MatchmakingEvent$Foreground());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<MatchmakingBloc, MatchmakingState>(
        bloc: _bloc,
        listener: (context, state) {
          final GameBloc game = GameRootScope.of(context);
          switch (state) {
            case MatchmakingState$Match(
              :final snapshot,
              :final player,
              :final connection,
            ):
              game.add(
                GameEvent$OnlineSnapshot(
                  snapshot: snapshot,
                  player: player,
                  connection: connection,
                ),
              );
            case MatchmakingState$Failure(:final message, :final failure):
              if (game.data?.mode == GameMode.online) {
                game.add(
                  GameEvent$OnlineFailure(
                    _failureText(context, message, failure),
                  ),
                );
              }
            default:
              break;
          }
        },
        child: _InheritedMatchmakingScope(bloc: _bloc, child: widget.child),
      );
}

String _failureText(
  BuildContext context,
  String remoteMessage,
  MatchmakingFailure? failure,
) {
  if (remoteMessage.isNotEmpty) return remoteMessage;
  return switch (failure) {
    MatchmakingFailure.invalidCode => context.l10n.enterFiveLetterCode,
    MatchmakingFailure.moveNotSent => context.l10n.moveNotSent,
    MatchmakingFailure.invalidServerResponse =>
      context.l10n.invalidServerResponse,
    MatchmakingFailure.connectionLost => context.l10n.connectionLost,
    MatchmakingFailure.lobbyClosed => context.l10n.connectionClosed,
    MatchmakingFailure.generic || null => context.l10n.matchSearchFailed,
  };
}

class _InheritedMatchmakingScope extends InheritedWidget {
  const new({required this.bloc, required super.child});
  final MatchmakingBloc bloc;
  @override
  bool updateShouldNotify(covariant _InheritedMatchmakingScope oldWidget) =>
      false;
}

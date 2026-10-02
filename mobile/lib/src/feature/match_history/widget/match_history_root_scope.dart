import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';
import 'package:four3/src/feature/match_history/bloc/match_history_bloc.dart';

class MatchHistoryRootScope extends StatefulWidget {
  const new({required this.child, super.key});
  final Widget child;
  static MatchHistoryBloc of(BuildContext context) =>
      context.inheritedOf<_InheritedMatchHistoryScope>().bloc;
  @override
  State<MatchHistoryRootScope> createState() => _MatchHistoryRootScopeState();
}

class _MatchHistoryRootScopeState extends State<MatchHistoryRootScope> {
  late final MatchHistoryBloc _bloc;
  @override
  void initState() {
    super.initState();
    _bloc = MatchHistoryBloc(
      repository: RootScope.of(context).matchHistoryRepository,
      owner: () => AccountRootScope.of(context).profile?.username,
    );
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocListener<GameBloc, GameState>(
    bloc: GameRootScope.of(context),
    listenWhen: (previous, current) {
      final GameStatus before = previous is GameState$Ready
          ? previous.data.snapshot.status
          : GameStatus.playing;
      final GameStatus after = current is GameState$Ready
          ? current.data.snapshot.status
          : GameStatus.playing;
      return before == GameStatus.playing && after != GameStatus.playing;
    },
    listener: (context, state) {
      if (state case GameState$Ready(:final data)) {
        _bloc.add(MatchHistoryEvent$Save(data));
      }
    },
    child: _InheritedMatchHistoryScope(bloc: _bloc, child: widget.child),
  );
}

class _InheritedMatchHistoryScope extends InheritedWidget {
  const new({required this.bloc, required super.child});
  final MatchHistoryBloc bloc;
  @override
  bool updateShouldNotify(covariant _InheritedMatchHistoryScope oldWidget) =>
      false;
}

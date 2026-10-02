import 'package:flutter/widgets.dart';

import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';
import 'package:four3/src/feature/leaderboard/bloc/leaderboard_bloc.dart';

class LeaderboardRootScope extends StatefulWidget {
  const new({required this.child, super.key});
  final Widget child;
  static LeaderboardBloc of(BuildContext context) =>
      context.inheritedOf<_InheritedLeaderboardScope>().bloc;
  @override
  State<LeaderboardRootScope> createState() => _LeaderboardRootScopeState();
}

class _LeaderboardRootScopeState extends State<LeaderboardRootScope> {
  late final LeaderboardBloc _bloc;
  @override
  void initState() {
    super.initState();
    _bloc = LeaderboardBloc(RootScope.of(context).leaderboardRepository);
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _InheritedLeaderboardScope(bloc: _bloc, child: widget.child);
}

class _InheritedLeaderboardScope extends InheritedWidget {
  const new({required this.bloc, required super.child});
  final LeaderboardBloc bloc;
  @override
  bool updateShouldNotify(covariant _InheritedLeaderboardScope oldWidget) =>
      false;
}

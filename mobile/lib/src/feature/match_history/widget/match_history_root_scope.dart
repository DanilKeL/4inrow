import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/bloc/account_bloc.dart';
import 'package:four3/src/feature/account/bloc/account_state.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/bloc/game_state.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/initialization/bloc/initialization_bloc.dart';
import 'package:four3/src/feature/initialization/bloc/initialization_state.dart';
import 'package:four3/src/feature/initialization/widget/initialization_root_scope.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';
import 'package:four3/src/feature/match_history/bloc/match_history_bloc.dart';
import 'package:four3/src/feature/match_history/bloc/match_history_event.dart';

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
  StreamSubscription<AccountState>? _accountSubscription;
  Timer? _retryTimer;
  String? _owner;
  @override
  void initState() {
    super.initState();
    final AccountBloc account = AccountRootScope.of(context);
    _owner = account.profile?.username;
    _bloc = MatchHistoryBloc(
      repository: RootScope.of(context).matchHistoryRepository,
      owner: () => AccountRootScope.of(context).profile?.username,
    );
    _accountSubscription = account.stream.listen((_) {
      final String? owner = account.profile?.username;
      if (owner != _owner) {
        _owner = owner;
        _bloc.add(const MatchHistoryEvent$Load());
      }
    });
    _retryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _bloc.add(const MatchHistoryEvent$Flush()),
    );
  }

  @override
  void dispose() {
    _accountSubscription?.cancel();
    _retryTimer?.cancel();
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: <BlocListener<dynamic, dynamic>>[
      BlocListener<GameBloc, GameState>(
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
      ),
      BlocListener<InitializationBloc, InitializationState>(
        bloc: InitializationRootScope.of(context),
        listenWhen: (previous, current) =>
            current is InitializationState$Ready && current.foreground,
        listener: (context, state) => _bloc.add(const MatchHistoryEvent$Load()),
      ),
    ],
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

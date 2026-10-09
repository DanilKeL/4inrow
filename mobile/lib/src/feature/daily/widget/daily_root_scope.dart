import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/bloc/account_bloc.dart';
import 'package:four3/src/feature/account/bloc/account_state.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/daily/bloc/daily_bloc.dart';
import 'package:four3/src/feature/daily/bloc/daily_event.dart';
import 'package:four3/src/feature/daily/domain/model/daily_models.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/bloc/game_state.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/initialization/bloc/initialization_bloc.dart';
import 'package:four3/src/feature/initialization/bloc/initialization_state.dart';
import 'package:four3/src/feature/initialization/widget/initialization_root_scope.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';

class DailyRootScope extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  static DailyBloc of(BuildContext context) =>
      context.inheritedOf<_InheritedDailyScope>().bloc;

  @override
  State<DailyRootScope> createState() => _DailyRootScopeState();
}

class _DailyRootScopeState extends State<DailyRootScope> {
  late final DailyBloc _bloc;
  StreamSubscription<AccountState>? _accountSubscription;
  Timer? _retryTimer;
  String? _owner;

  @override
  void initState() {
    super.initState();
    final AccountBloc account = AccountRootScope.of(context);
    _owner = account.profile?.username;
    _bloc = DailyBloc(
      repository: RootScope.of(context).dailyRepository,
      owner: () => AccountRootScope.of(context).profile?.username,
    );
    _accountSubscription = account.stream.listen((_) {
      final String? owner = account.profile?.username;
      if (owner != _owner) {
        _owner = owner;
        _bloc.add(const DailyEvent$AccountChanged());
      }
    });
    _retryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _bloc.add(const DailyEvent$Flush()),
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
          if (previous is! GameState$Ready || current is! GameState$Ready) {
            return false;
          }
          return current.data.mode == GameMode.daily &&
              previous.data.snapshot.status == GameStatus.playing &&
              current.data.snapshot.status == GameStatus.won &&
              current.data.snapshot.winner == Player.one;
        },
        listener: (context, state) {
          if (state case GameState$Ready(:final data)) {
            final DailyChallenge? challenge = data.dailyChallenge;
            if (challenge != null) {
              _bloc.add(
                DailyEvent$SaveWin(
                  challenge: challenge,
                  game: data.snapshot,
                  ownerAtStart: data.dailyOwnerAtStart,
                  recordId: data.recordId,
                ),
              );
            }
          }
        },
      ),
      BlocListener<InitializationBloc, InitializationState>(
        bloc: InitializationRootScope.of(context),
        listenWhen: (previous, current) =>
            current is InitializationState$Ready &&
            current.foreground &&
            previous != current,
        listener: (context, state) => _bloc.add(const DailyEvent$Flush()),
      ),
    ],
    child: _InheritedDailyScope(bloc: _bloc, child: widget.child),
  );
}

class _InheritedDailyScope extends InheritedWidget {
  const new({required this.bloc, required super.child});

  final DailyBloc bloc;

  @override
  bool updateShouldNotify(covariant _InheritedDailyScope oldWidget) => false;
}

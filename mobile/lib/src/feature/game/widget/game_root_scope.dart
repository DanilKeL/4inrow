import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/bloc/account_bloc.dart';
import 'package:four3/src/feature/account/bloc/account_state.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/audio/service/audio_service.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/bloc/game_event.dart';
import 'package:four3/src/feature/game/bloc/game_state.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/initialization/bloc/initialization_bloc.dart';
import 'package:four3/src/feature/initialization/bloc/initialization_state.dart';
import 'package:four3/src/feature/initialization/domain/model/dependencies_container.dart';
import 'package:four3/src/feature/initialization/widget/initialization_root_scope.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';
import 'package:four3/src/feature/levels/domain/repository/level_repository.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';
import 'package:four3/src/feature/settings/widget/settings_root_scope.dart';

class GameRootScope extends StatefulWidget {
  const new({required this.child, super.key});
  final Widget child;

  static GameBloc of(BuildContext context) =>
      context.inheritedOf<_InheritedGameScope>().gameBloc;

  @override
  State<GameRootScope> createState() => _GameRootScopeState();
}

class _GameRootScopeState extends State<GameRootScope> {
  late final GameBloc _gameBloc;
  String? _levelOwner;
  Timer? _levelRetryTimer;

  @override
  void initState() {
    super.initState();
    final RootDependenciesContainer root = RootScope.of(context);
    _levelOwner = AccountRootScope.of(context).profile?.username;
    _gameBloc = GameBloc(
      storage: root.gameStorageRepository,
      levels: root.levelRepository,
      settings: () => SettingsRootScope.of(context).settings,
      playerName: () =>
          AccountRootScope.of(context).profile?.displayName ?? 'Player 1',
      accountOwner: () => AccountRootScope.of(context).profile?.username,
      analytics: root.analyticsService,
    )..add(const GameEvent$Load());
    _levelRetryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _syncLevels(context, onlyPending: true);
    });
  }

  @override
  void dispose() {
    _levelRetryTimer?.cancel();
    _gameBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: <BlocListener<dynamic, dynamic>>[
      BlocListener<GameBloc, GameState>(
        bloc: _gameBloc,
        listenWhen: (previous, current) {
          if (previous is! GameState$Ready || current is! GameState$Ready) {
            return false;
          }
          return current.data.snapshot.history.length >
                  previous.data.snapshot.history.length ||
              (previous.data.snapshot.status == GameStatus.playing &&
                  current.data.snapshot.status == GameStatus.won) ||
              (current.data.notice == GameNotice.columnFull &&
                  current.data.noticeRevision != previous.data.noticeRevision);
        },
        listener: (context, state) {
          if (state case GameState$Ready(:final data)) {
            final AppSettings settings = SettingsRootScope.of(context).settings;
            final SoundEffect effect = data.snapshot.status == GameStatus.won
                ? SoundEffect.win
                : data.notice == GameNotice.columnFull
                ? SoundEffect.invalid
                : SoundEffect.place;
            RootScope.of(context).audioService
                .play(effect, enabled: settings.sound, volume: settings.volume);
          }
        },
      ),
      BlocListener<InitializationBloc, InitializationState>(
        bloc: InitializationRootScope.of(context),
        listenWhen: (previous, current) =>
            current is InitializationState$Ready && !current.foreground,
        listener: (context, state) => _gameBloc.add(const GameEvent$Persist()),
      ),
      BlocListener<InitializationBloc, InitializationState>(
        bloc: InitializationRootScope.of(context),
        listenWhen: (previous, current) =>
            current is InitializationState$Ready && current.foreground,
        listener: (context, state) => _syncLevels(context),
      ),
      BlocListener<AccountBloc, AccountState>(
        bloc: AccountRootScope.of(context),
        listener: (context, state) {
          final String? owner = AccountRootScope.of(context).profile?.username;
          if (owner == _levelOwner) return;
          _levelOwner = owner;
          _syncLevels(context);
        },
      ),
    ],
    child: _InheritedGameScope(gameBloc: _gameBloc, child: widget.child),
  );

  void _syncLevels(BuildContext context, {bool onlyPending = false}) {
    final String? owner = AccountRootScope.of(context).profile?.username;
    if (owner == null) return;
    final LevelRepository repository = RootScope.of(context).levelRepository;
    if (onlyPending && !repository.needsSync(owner)) return;
    unawaited(
      repository.sync(owner).then<void>((_) {}).catchError((Object _) {}),
    );
  }
}

class _InheritedGameScope extends InheritedWidget {
  const new({required this.gameBloc, required super.child});
  final GameBloc gameBloc;

  @override
  bool updateShouldNotify(covariant _InheritedGameScope oldWidget) => false;
}

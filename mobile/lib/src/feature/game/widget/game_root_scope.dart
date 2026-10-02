import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/audio/service/audio_service.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';
import 'package:four3/src/feature/settings/model/app_settings.dart';
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

  @override
  void initState() {
    super.initState();
    final RootDependencies root = RootScope.of(context);
    _gameBloc = GameBloc(
      storage: root.gameStorageRepository,
      levels: root.levelRepository,
      settings: () => SettingsRootScope.of(context).settings,
      playerName: () =>
          AccountRootScope.of(context).profile?.displayName ?? 'Игрок 1',
    )..add(const GameEvent$Load());
  }

  @override
  void dispose() {
    _gameBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocListener<GameBloc, GameState>(
    bloc: _gameBloc,
    listenWhen: (previous, current) {
      if (previous is! GameState$Ready || current is! GameState$Ready) {
        return false;
      }
      return current.data.snapshot.history.length >
              previous.data.snapshot.history.length ||
          (previous.data.snapshot.status == GameStatus.playing &&
              current.data.snapshot.status == GameStatus.won) ||
          (current.data.message.contains('заполнен') &&
              current.data.message != previous.data.message);
    },
    listener: (context, state) {
      if (state case GameState$Ready(:final data)) {
        final AppSettings settings = SettingsRootScope.of(context).settings;
        final SoundEffect effect = data.snapshot.status == GameStatus.won
            ? SoundEffect.win
            : data.message.contains('заполнен')
            ? SoundEffect.invalid
            : SoundEffect.place;
        RootScope.of(context).audioService
            .play(effect, enabled: settings.sound, volume: settings.volume);
      }
    },
    child: _InheritedGameScope(gameBloc: _gameBloc, child: widget.child),
  );
}

class _InheritedGameScope extends InheritedWidget {
  const new({required this.gameBloc, required super.child});
  final GameBloc gameBloc;

  @override
  bool updateShouldNotify(covariant _InheritedGameScope oldWidget) => false;
}

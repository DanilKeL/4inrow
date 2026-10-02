import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/theme/app_theme.dart';
import 'package:four3/src/common/widget/app_dialog.dart';
import 'package:four3/src/feature/account/bloc/account_bloc.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/account/widget/account_view.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/game/widget/game_scene_view.dart';
import 'package:four3/src/feature/game/widget/game_setup_view.dart';
import 'package:four3/src/feature/leaderboard/widget/leaderboard_view.dart';
import 'package:four3/src/feature/levels/widget/levels_view.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_bloc.dart';
import 'package:four3/src/feature/matchmaking/widget/matchmaking_root_scope.dart';
import 'package:four3/src/feature/settings/bloc/settings_bloc.dart';
import 'package:four3/src/feature/settings/model/app_settings.dart';
import 'package:four3/src/feature/settings/widget/settings_root_scope.dart';
import 'package:four3/src/feature/settings/widget/settings_view.dart';
import 'package:four3/src/feature/tutorial/widget/tutorial_view.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class GameShell extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final GameBloc gameBloc = GameRootScope.of(context);
    final SettingsBloc settingsBloc = SettingsRootScope.of(context);
    return BlocBuilder<SettingsBloc, SettingsState>(
      bloc: settingsBloc,
      builder: (context, _) => BlocBuilder<GameBloc, GameState>(
        bloc: gameBloc,
        builder: (context, state) => switch (state) {
          GameState$Ready(:final data) => _GameShellBody(
            data: data,
            settings: settingsBloc.settings,
          ),
          GameState$Failure(:final message) => Scaffold(
            body: Center(child: Text(message)),
          ),
          _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
        },
      ),
    );
  }
}

class _GameShellBody extends StatelessWidget {
  const new({required this.data, required this.settings});
  final GameViewData data;
  final AppSettings settings;

  bool get isMenu => data.phase == GamePhase.menu;

  @override
  Widget build(BuildContext context) {
    final GameBloc gameBloc = GameRootScope.of(context);
    final GameViewData shownData = isMenu
        ? GameViewData(
            snapshot: _demoGame,
            cameraView: data.cameraView,
            cameraReset: data.cameraReset,
          )
        : data;
    return PopScope(
      canPop: isMenu,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestMenu(context);
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                _Header(
                  onBrand: () {
                    if (!isMenu) _requestMenu(context);
                  },
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final Widget scene = _SceneCard(
                        menu: isMenu,
                        child: GameSceneView(
                          data: shownData,
                          settings: settings,
                          demo: isMenu,
                          onPlace: (x, y) {
                            if (data.mode == GameMode.online) {
                              MatchmakingRootScope.of(context)
                                  .add(MatchmakingEvent$Move(x, y));
                            } else {
                              gameBloc.add(GameEvent$MakeMove(x, y));
                            }
                          },
                        ),
                      );
                      if (!isMenu) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              scene,
                              _PlayingOverlay(data: data),
                            ],
                          ),
                        );
                      }
                      final bool landscape =
                          constraints.maxWidth > constraints.maxHeight;
                      final Widget menu = _MenuHero(
                        compact: landscape,
                        onMode: (mode) => _openSetup(context, mode),
                      );
                      if (landscape) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            children: [
                              SizedBox(width: 230, child: menu),
                              const SizedBox(width: 10),
                              Expanded(child: scene),
                            ],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
                        child: Column(
                          children: [
                            Expanded(child: scene),
                            const SizedBox(height: 10),
                            menu,
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSetup(BuildContext context, GameMode mode) => showAppDialog<void>(
    context: context,
    title: 'Новая игра',
    child: GameSetupView(initialMode: mode),
  );

  void _requestMenu(BuildContext context) {
    final GameBloc bloc = GameRootScope.of(context);
    final online = data.mode == GameMode.online;
    if (data.snapshot.status == GameStatus.playing &&
        data.snapshot.history.isNotEmpty) {
      bloc.add(const GameEvent$Pause());
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Завершить текущую партию?'),
          content: const Text('Текущий прогресс этой партии будет очищен.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                bloc.add(const GameEvent$Resume());
              },
              child: const Text('Продолжить'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                if (online) {
                  MatchmakingRootScope.of(context)
                      .add(const MatchmakingEvent$Leave());
                }
                bloc.add(const GameEvent$Menu());
              },
              child: const Text('Выйти в меню'),
            ),
          ],
        ),
      );
    } else {
      if (online) {
        MatchmakingRootScope.of(context).add(const MatchmakingEvent$Leave());
      }
      bloc.add(const GameEvent$Menu());
    }
  }
}

class _Header extends StatelessWidget {
  const new({required this.onBrand});
  final VoidCallback onBrand;

  @override
  Widget build(BuildContext context) {
    final SettingsBloc settingsBloc = SettingsRootScope.of(context);
    final AccountBloc accountBloc = AccountRootScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool expanded = constraints.maxWidth >= 650;
        return Container(
          height: expanded ? 68 : 52,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: onBrand,
                child: Text.rich(
                  const TextSpan(
                    text: 'FOUR',
                    children: [
                      TextSpan(
                        text: '3',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 12,
                          height: .8,
                        ),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: expanded ? 28 : 27,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.6,
                  ),
                ),
              ),
              const Spacer(),
              BlocBuilder<AccountBloc, AccountState>(
                bloc: accountBloc,
                builder: (context, _) => _HeaderAction(
                  icon: LucideIcons.userRound,
                  label: accountBloc.profile?.displayName ?? 'Гость',
                  showLabel: expanded,
                  onTap: () => showAppDialog<void>(
                    context: context,
                    title: 'Личный кабинет',
                    wide: true,
                    child: const AccountView(),
                  ),
                ),
              ),
              _HeaderAction(
                icon: LucideIcons.circleHelp,
                label: 'Как играть',
                showLabel: expanded,
                onTap: () => showAppDialog<void>(
                  context: context,
                  title: 'Как играть',
                  wide: true,
                  child: const TutorialView(),
                ),
              ),
              Container(
                width: 1,
                height: 20,
                margin: EdgeInsets.symmetric(horizontal: expanded ? 10 : 2),
                color: AppColors.border,
              ),
              _HeaderAction(
                icon: settingsBloc.settings.sound
                    ? LucideIcons.volume2
                    : LucideIcons.volumeX,
                label: settingsBloc.settings.sound
                    ? 'Выключить звук'
                    : 'Включить звук',
                onTap: () => settingsBloc.add(
                  SettingsEvent$Update(
                    settingsBloc.settings.copyWith(
                      sound: !settingsBloc.settings.sound,
                    ),
                  ),
                ),
              ),
              _HeaderAction(
                icon: LucideIcons.settings2,
                label: 'Настройки',
                onTap: () => showAppDialog<void>(
                  context: context,
                  title: 'Настройки',
                  child: const SettingsView(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showLabel = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19),
              if (showLabel) ...[
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _SceneCard extends StatelessWidget {
  const new({required this.menu, required this.child});

  final bool menu;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(menu ? 14 : 12),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEBEAE7),
        borderRadius: BorderRadius.circular(menu ? 14 : 12),
        border: Border.all(color: const Color(0xFFE1E2DD)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (menu)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xEFFFFFFF),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0x8CFFFFFF)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.cuboid, size: 13),
                    SizedBox(width: 6),
                    Text(
                      '5 × 5 × 5',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _MenuHero extends StatelessWidget {
  const new({required this.onMode, required this.compact});
  final void Function(GameMode mode) onMode;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(compact ? 12 : 13),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(compact ? 13 : 14),
      border: Border.all(color: const Color(0xFFE4E6DF)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Четыре в ряд',
          style: TextStyle(
            fontSize: compact ? 20 : 21,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: -.8,
          ),
        ),
        if (compact) const SizedBox(height: 8),
        if (compact)
          const Text(
            'Классическая игра в новом трёхмерном измерении',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        SizedBox(height: compact ? 7 : 12),
        SizedBox(
          width: double.infinity,
          height: compact ? 39 : 45,
          child: FilledButton(
            onPressed: () => onMode(GameMode.online),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 13),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.search, size: 18),
                SizedBox(width: 11),
                Text('Рейтинговая игра'),
                Spacer(),
                Icon(LucideIcons.arrowRight, size: 18),
              ],
            ),
          ),
        ),
        SizedBox(height: compact ? 5 : 6),
        Row(
          children: [
            Expanded(
              child: _ModeButton(
                compact: compact,
                icon: LucideIcons.puzzle,
                label: 'Уровни',
                onTap: () => showAppDialog<void>(
                  context: context,
                  title: 'Уровни',
                  wide: true,
                  child: const LevelsView(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ModeButton(
                compact: compact,
                icon: LucideIcons.cpu,
                label: 'Против AI',
                onTap: () => onMode(GameMode.ai),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 5 : 6),
        Row(
          children: [
            Expanded(
              child: _ModeButton(
                compact: compact,
                icon: LucideIcons.usersRound,
                label: 'Вдвоём',
                onTap: () => onMode(GameMode.local),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ModeButton(
                compact: compact,
                icon: LucideIcons.globe2,
                label: 'Онлайн',
                onTap: () => onMode(GameMode.online),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 4 : 5),
        SizedBox(
          height: compact ? 30 : 32,
          child: TextButton.icon(
            onPressed: () => showAppDialog<void>(
              context: context,
              title: 'Рейтинг игроков',
              wide: true,
              child: const SizedBox(height: 520, child: LeaderboardView()),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              foregroundColor: const Color(0xFF697163),
              textStyle: const TextStyle(fontSize: 10),
            ),
            icon: const Icon(LucideIcons.trophy, size: 16),
            label: const Text('Рейтинг игроков'),
          ),
        ),
      ],
    ),
  );
}

class _ModeButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.compact,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: compact ? 37 : 42,
    child: OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
      icon: Icon(icon, size: 16, color: AppColors.accent),
      label: Text(label, maxLines: 1),
    ),
  );
}

class _PlayingOverlay extends StatelessWidget {
  const new({required this.data});
  final GameViewData data;

  String get _turnText {
    if (data.phase == GamePhase.aiThinking) {
      return data.mode == GameMode.level ? 'Ход бота…' : 'AI обдумывает ход…';
    }
    if (data.phase == GamePhase.animating) return 'Ход выполнен';
    if (data.phase == GamePhase.paused) return 'Пауза';
    if (data.phase == GamePhase.waiting) {
      return data.onlineCode == null
          ? 'Подключаемся…'
          : 'Лобби ${data.onlineCode} · ждём игрока';
    }
    if (data.phase == GamePhase.replay) {
      return 'Повтор · ход ${data.replayIndex}';
    }
    if (data.snapshot.status != GameStatus.playing) return 'Партия завершена';
    if (data.mode == GameMode.level) return 'Ваш ход';
    return 'Ходит ${data.names[data.snapshot.currentPlayer.index]}';
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        top: 16,
        left: 12,
        right: 12,
        child: Row(
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xF5FAFBF6),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFE6E9DE)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x10323E28),
                      blurRadius: 12,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: data.snapshot.currentPlayer == Player.one
                            ? const Color(0xFF30383A)
                            : const Color(0xFFF3ECDD),
                        border: Border.all(
                          color: data.snapshot.currentPlayer == Player.one
                              ? const Color(0xFF5E6868)
                              : const Color(0xFFC8BEA8),
                          width: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _turnText,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Пауза',
              onPressed: () => _pauseDialog(context),
              icon: const Icon(LucideIcons.pause, size: 19),
            ),
          ],
        ),
      ),
      Positioned(left: 0, right: 0, bottom: 0, child: _GamePanel(data: data)),
      if (data.message.isNotEmpty)
        Positioned(
          left: 24,
          right: 24,
          bottom: 182,
          child: Material(
            color: const Color(0xEE9A3F35),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                data.message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
    ],
  );

  void _pauseDialog(BuildContext context) {
    if (data.mode == GameMode.online) {
      MatchmakingRootScope.of(context).add(const MatchmakingEvent$Pause());
      return;
    }
    final GameBloc bloc = GameRootScope.of(context)
      ..add(const GameEvent$Pause());
    showAppDialog<void>(
      context: context,
      title: 'Пауза',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Время остановлено.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              bloc.add(const GameEvent$Resume());
            },
            child: const Text('Продолжить'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              bloc.add(const GameEvent$Restart());
            },
            icon: const Icon(LucideIcons.rotateCcw),
            label: const Text('Начать заново'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              bloc.add(const GameEvent$Menu());
            },
            icon: const Icon(LucideIcons.home),
            label: const Text('В главное меню'),
          ),
        ],
      ),
    ).whenComplete(() {
      if (bloc.data?.phase == GamePhase.paused) {
        bloc.add(const GameEvent$Resume());
      }
    });
  }
}

class _GamePanel extends StatelessWidget {
  const new({required this.data});
  final GameViewData data;

  @override
  Widget build(BuildContext context) {
    final GameBloc bloc = GameRootScope.of(context);
    final finished = data.snapshot.status != GameStatus.playing;
    final Player? winner = data.snapshot.winner;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      decoration: const BoxDecoration(
        color: Color(0xF7EEEEE8),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 30,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    finished
                        ? (winner == null
                              ? 'Ничья'
                              : 'Победа: ${data.names[winner.index]}')
                        : '● ${data.names[0]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                Text(
                  '${data.phase == GamePhase.replay ? data.replayIndex : data.snapshot.history.length} ходов',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Expanded(
                  child: Text(
                    '○ ${data.names[1]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Row(
            children: [
              if (data.phase == GamePhase.replay) ...[
                IconButton(
                  onPressed: data.replayIndex > 0
                      ? () =>
                            bloc.add(GameEvent$SeekReplay(data.replayIndex - 1))
                      : null,
                  icon: const Icon(LucideIcons.chevronLeft),
                ),
                IconButton(
                  onPressed: data.replayIndex < data.snapshot.history.length
                      ? () =>
                            bloc.add(GameEvent$SeekReplay(data.replayIndex + 1))
                      : null,
                  icon: const Icon(LucideIcons.chevronRight),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: () => bloc.add(const GameEvent$CloseReplay()),
                    child: const Text('Закрыть повтор'),
                  ),
                ),
              ] else ...[
                _Tool(
                  icon: LucideIcons.rotateCcw,
                  label: 'Отменить',
                  enabled:
                      data.mode != GameMode.level &&
                      data.mode != GameMode.online &&
                      data.phase == GamePhase.playing &&
                      data.snapshot.history.isNotEmpty,
                  onTap: () => bloc.add(const GameEvent$Undo()),
                ),
                _Tool(
                  icon: LucideIcons.eye,
                  label: 'Рентген',
                  selected: data.xray,
                  onTap: () => bloc.add(const GameEvent$ToggleXray()),
                ),
                _Tool(
                  icon: LucideIcons.layers3,
                  label: 'Вид',
                  onTap: () => _view(context),
                ),
                _Tool(
                  icon: LucideIcons.maximize,
                  label: '',
                  onTap: () =>
                      bloc.add(const GameEvent$View(CameraView.perspective)),
                ),
                if (finished)
                  _Tool(
                    icon: LucideIcons.play,
                    label: 'Повтор',
                    onTap: () => bloc.add(const GameEvent$OpenReplay()),
                  ),
              ],
            ],
          ),
          if (finished) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (data.mode == GameMode.online) {
                        MatchmakingRootScope.of(context)
                            .add(const MatchmakingEvent$Rematch());
                      } else {
                        bloc.add(const GameEvent$Restart());
                      }
                    },
                    child: Text(
                      data.mode == GameMode.online ? 'Реванш' : 'Сыграть ещё',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (data.mode == GameMode.online) {
                        MatchmakingRootScope.of(context)
                            .add(const MatchmakingEvent$Leave());
                      }
                      bloc.add(const GameEvent$Menu());
                    },
                    child: const Text('В меню'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _view(BuildContext context) {
    final GameBloc bloc = GameRootScope.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Камера',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              SegmentedButton<CameraView>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: CameraView.perspective,
                    label: Text('3D'),
                  ),
                  ButtonSegment(value: CameraView.top, label: Text('Сверху')),
                  ButtonSegment(
                    value: CameraView.front,
                    label: Text('Спереди'),
                  ),
                ],
                selected: {data.cameraView},
                onSelectionChanged: (value) {
                  bloc.add(GameEvent$View(value.first));
                },
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Показать слои',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Все'),
                    selected: data.layers.length == 5,
                    onSelected: (_) =>
                        bloc.add(const GameEvent$ShowAllLayers()),
                  ),
                  for (var layer = 0; layer < 5; layer++)
                    FilterChip(
                      label: Text('${layer + 1}'),
                      selected: data.layers.contains(layer),
                      onSelected: (_) => bloc.add(GameEvent$ToggleLayer(layer)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Включайте и скрывайте каждый слой. '
                'Новый ход вернёт все слои.',
                style: TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool selected;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: enabled ? 1 : .35,
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: selected ? Theme.of(context).colorScheme.primary : null,
              ),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 10),
                    maxLines: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

final GameSnapshot _demoGame = () {
  final GameSnapshot base = GameEngine.create();
  final List<int> board = [...base.board];
  final List<int> heights = [...base.heights];
  final history = <GameMove>[];
  const stacks = <(int, int, List<Player>)>[
    (0, 0, [Player.one]),
    (2, 0, [Player.two]),
    (3, 0, [Player.one, Player.two]),
    (4, 0, [Player.two]),
    (0, 1, [Player.two, Player.one]),
    (1, 1, [Player.one]),
    (3, 1, [Player.two, Player.one, Player.two]),
    (4, 1, [Player.one]),
    (1, 2, [Player.two, Player.one, Player.one]),
    (2, 2, [Player.one, Player.two, Player.one, Player.two]),
    (4, 2, [Player.two, Player.two]),
    (0, 3, [Player.one]),
    (2, 3, [Player.two, Player.one]),
    (3, 3, [Player.one, Player.two, Player.one]),
    (4, 4, [Player.two]),
    (1, 4, [Player.two]),
    (2, 4, [Player.one]),
  ];
  for (final (x, y, players) in stacks) {
    for (var z = 0; z < players.length; z++) {
      final move = GameMove(
        x: x,
        y: y,
        z: z,
        player: players[z],
        index: history.length,
      );
      board[GameEngine.boardIndex(move.position)] = move.player.value;
      heights[x + y * 5] = z + 1;
      history.add(move);
    }
  }
  return GameSnapshot(
    board: board,
    heights: heights,
    currentPlayer: Player.one,
    history: history,
    status: GameStatus.playing,
    winner: null,
    winningLines: const [],
  );
}();

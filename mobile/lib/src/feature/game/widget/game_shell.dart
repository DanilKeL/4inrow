import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:four3/src/feature/match_history/widget/match_history_view.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_bloc.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';
import 'package:four3/src/feature/matchmaking/widget/matchmaking_root_scope.dart';
import 'package:four3/src/feature/matchmaking/widget/online_setup_view.dart';
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
        body: Stack(
          children: [
            SafeArea(
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
                            final bool shortLandscape =
                                constraints.maxWidth >= 651 &&
                                constraints.maxHeight <= 550;
                            final bool result =
                                data.snapshot.status != GameStatus.playing ||
                                data.phase == GamePhase.replay;
                            final Widget board = Stack(
                              fit: StackFit.expand,
                              children: [
                                scene,
                                if (!shortLandscape)
                                  _PlayingOverlay(data: data),
                                if (shortLandscape && data.message.isNotEmpty)
                                  _GameMessage(message: data.message),
                                if (data.onlineSnapshot?.pause
                                    case final pause?)
                                  if (pause.requestId != null ||
                                      pause.endsAt != null)
                                    _OnlinePauseOverlay(data: data),
                              ],
                            );
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
                              child: shortLandscape
                                  ? Row(
                                      children: [
                                        if (result) ...[
                                          SizedBox(
                                            width: 210,
                                            child: _GamePanel(data: data),
                                          ),
                                          const SizedBox(width: 12),
                                        ],
                                        Expanded(child: board),
                                        if (!result) ...[
                                          const SizedBox(width: 10),
                                          SizedBox(
                                            width: 200,
                                            child: _LandscapeGameRail(
                                              data: data,
                                            ),
                                          ),
                                        ],
                                      ],
                                    )
                                  : board,
                            );
                          }
                          final bool landscape =
                              constraints.maxWidth > constraints.maxHeight;
                          final Widget menu = _MenuHero(
                            compact: landscape,
                            onMode: (mode) => _openSetup(context, mode),
                            onRated: () => _openRated(context),
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
            if (data.onlineSnapshot case final snapshot?)
              if (snapshot.game.status != GameStatus.playing &&
                  snapshot.ranking?.rated == true &&
                  snapshot.ranking?.changes != null)
                _RankedResultOverlay(
                  key: ValueKey('${snapshot.code}-${snapshot.round}'),
                  data: data,
                ),
          ],
        ),
      ),
    );
  }

  void _openSetup(BuildContext context, GameMode mode) => showAppDialog<void>(
    context: context,
    title: 'Новая игра',
    child: GameSetupView(initialMode: mode),
  );

  void _openRated(BuildContext context) {
    final String name =
        AccountRootScope.of(context).profile?.displayName ?? 'Игрок';
    MatchmakingRootScope.of(context).add(MatchmakingEvent$Find(name));
    showAppDialog<void>(
      context: context,
      title: 'Рейтинговая игра',
      child: const OnlineSetupView(),
    );
  }

  void _requestMenu(BuildContext context) {
    final GameBloc bloc = GameRootScope.of(context);
    final bool online = data.mode == GameMode.online;
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
        final bool expanded =
            constraints.maxWidth >= 650 &&
            MediaQuery.sizeOf(context).height > 550;
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
                  onTap: () => _openAccount(context),
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
                  child: TutorialView(
                    onDone: () {
                      settingsBloc.add(
                        SettingsEvent$Update(
                          settingsBloc.settings.copyWith(tutorialSeen: true),
                        ),
                      );
                      Navigator.pop(context);
                    },
                  ),
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

  Future<void> _openAccount(BuildContext context) async {
    var openHistory = false;
    await showAppDialog<void>(
      context: context,
      title: 'Личный кабинет',
      wide: true,
      child: AccountView(
        onHistory: () {
          openHistory = true;
          Navigator.pop(context);
        },
      ),
    );
    if (openHistory && context.mounted) {
      await showAppDialog<void>(
        context: context,
        title: 'История и статистика',
        wide: true,
        child: const MatchHistoryView(),
      );
    }
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
  const new({
    required this.onMode,
    required this.onRated,
    required this.compact,
  });
  final void Function(GameMode mode) onMode;
  final VoidCallback onRated;
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
            onPressed: onRated,
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

class _TurnStatus extends StatefulWidget {
  const new({required this.data, this.compact = false});
  final GameViewData data;
  final bool compact;

  @override
  State<_TurnStatus> createState() => _TurnStatusState();
}

class _TurnStatusState extends State<_TurnStatus> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.data.onlineSnapshot?.turnDeadline != null) {
        setState(() {});
      }
    });
  }

  String get _text {
    final GameViewData data = widget.data;
    if (data.phase == GamePhase.aiThinking) {
      return data.mode == GameMode.level ? 'Ход бота…' : 'AI обдумывает ход…';
    }
    if (data.phase == GamePhase.animating) return 'Ход выполнен';
    if (data.phase == GamePhase.paused) return 'Пауза';
    if (data.phase == GamePhase.replay) {
      return 'Повтор · ход ${data.replayIndex}';
    }
    if (data.snapshot.status != GameStatus.playing) return 'Партия завершена';
    if (data.mode == GameMode.online) {
      if (data.onlineConnection != OnlineConnectionStatus.connected) {
        return 'Нет соединения';
      }
      if (data.onlineSnapshot?.startedAt == null) return 'Ждём соперника';
      return data.onlinePlayer == data.snapshot.currentPlayer
          ? 'Ваш ход'
          : 'Ход соперника';
    }
    if (data.mode == GameMode.level) return 'Ваш ход';
    return 'Ходит ${data.names[data.snapshot.currentPlayer.index]}';
  }

  int? get _remaining {
    final OnlineMatchSnapshot? snapshot = widget.data.onlineSnapshot;
    if (snapshot == null || snapshot.turnDeadline == null) return null;
    final int deadline = snapshot.pause?.endsAt ?? snapshot.turnDeadline!;
    return ((deadline - DateTime.now().millisecondsSinceEpoch) / 1000)
        .ceil()
        .clamp(0, 999);
  }

  @override
  Widget build(BuildContext context) {
    final GameViewData data = widget.data;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 9 : 12,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: const Color(0xF5FAFBF6),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE6E9DE)),
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
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${data.levelId == null ? '' : 'Уровень ${data.levelId} · '}$_text',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
          if (data.mode == GameMode.online) ...[
            Container(
              height: 18,
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: AppColors.border,
            ),
            Text(
              _remaining == null ? '— сек' : '${_remaining!} сек',
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _OnlineBanner extends StatefulWidget {
  const new({required this.data, this.compact = false});
  final GameViewData data;
  final bool compact;

  @override
  State<_OnlineBanner> createState() => _OnlineBannerState();
}

class _OnlineBannerState extends State<_OnlineBanner> {
  String _copyStatus = '';

  @override
  Widget build(BuildContext context) {
    final GameViewData data = widget.data;
    final OnlineMatchSnapshot? snapshot = data.onlineSnapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final bool quick = snapshot.kind == 'quick';
    final int index = data.onlinePlayer?.index ?? 0;
    final OnlinePlayer? opponent = snapshot.players[index == 0 ? 1 : 0];
    final OnlineRanking? ranking = snapshot.ranking;
    final int? delta = ranking?.changes?[index];
    final String status = data.onlineConnection == OnlineConnectionStatus.error
        ? 'Соединение закрыто'
        : data.onlineConnection != OnlineConnectionStatus.connected
        ? 'Восстанавливаем соединение…'
        : opponent == null
        ? (quick
              ? 'Ждём соперника…'
              : 'Передайте код другу — ждём второго игрока')
        : !opponent.connected
        ? 'Соперник отключился. Ждём возвращения…'
        : 'Вы играете ${index == 0 ? 'графитом · ●' : 'светлыми · ○'}';
    return Container(
      padding: EdgeInsets.all(widget.compact ? 7 : 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9F4),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.globe2, size: 15),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  quick ? 'РЕЙТИНГОВАЯ ИГРА' : 'ЛОББИ',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
              ),
              if (!quick) ...[
                Text(
                  snapshot.code,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Скопировать код лобби',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: snapshot.code));
                    if (mounted) setState(() => _copyStatus = 'Код скопирован');
                  },
                  icon: const Icon(LucideIcons.copy, size: 15),
                ),
              ],
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Покинуть лобби',
                onPressed: () => _confirmOnlineLeave(context, data),
                icon: const Icon(LucideIcons.logOut, size: 15),
              ),
            ],
          ),
          Text(
            ranking?.rated == true
                ? 'Рейтинг: ${(ranking!.points[index]) + (delta ?? 0)}${delta == null ? '' : ' (${delta >= 0 ? '+' : ''}$delta)'}'
                : (ranking?.reason ?? status),
            style: const TextStyle(fontSize: 9, color: AppColors.muted),
          ),
          if (_copyStatus.isNotEmpty)
            Text(_copyStatus, style: const TextStyle(fontSize: 8)),
        ],
      ),
    );
  }
}

class _LandscapeGameRail extends StatelessWidget {
  const new({required this.data});
  final GameViewData data;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (data.mode == GameMode.online) ...[
        _OnlineBanner(data: data, compact: true),
        const SizedBox(height: 7),
      ],
      _TurnStatus(data: data, compact: true),
      const Spacer(),
      _PlayerStrip(data: data),
      const Divider(height: 1),
      _ToolBar(data: data),
    ],
  );
}

class _PlayerStrip extends StatelessWidget {
  const new({required this.data});
  final GameViewData data;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: Row(
      children: [
        Expanded(
          child: Text(
            '● ${data.names[0]}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9),
          ),
        ),
        Text(
          '${data.phase == GamePhase.replay ? data.replayIndex : data.snapshot.history.length} ходов',
          style: const TextStyle(fontSize: 9),
        ),
        Expanded(
          child: Text(
            '○ ${data.names[1]}',
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9),
          ),
        ),
      ],
    ),
  );
}

class _ToolBar extends StatelessWidget {
  const new({required this.data});
  final GameViewData data;

  @override
  Widget build(BuildContext context) {
    final GameBloc bloc = GameRootScope.of(context);
    return Row(
      children: [
        if (data.mode != GameMode.level)
          _Tool(
            icon: LucideIcons.rotateCcw,
            label: '',
            enabled:
                data.mode != GameMode.online &&
                data.phase == GamePhase.playing &&
                data.snapshot.history.isNotEmpty,
            onTap: () => bloc.add(const GameEvent$Undo()),
          ),
        _Tool(
          icon: LucideIcons.eye,
          label: '',
          selected: data.xray,
          onTap: () => bloc.add(const GameEvent$ToggleXray()),
        ),
        _Tool(
          icon: LucideIcons.layers3,
          label: '',
          onTap: () => _showViewControls(context, data),
        ),
        _Tool(
          icon: LucideIcons.maximize,
          label: '',
          onTap: () => bloc.add(const GameEvent$View(CameraView.perspective)),
        ),
      ],
    );
  }
}

class _GameMessage extends StatelessWidget {
  const new({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 24,
    right: 24,
    bottom: 76,
    child: Material(
      color: const Color(0xEE9A3F35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    ),
  );
}

class _OnlinePauseOverlay extends StatefulWidget {
  const new({required this.data});
  final GameViewData data;

  @override
  State<_OnlinePauseOverlay> createState() => _OnlinePauseOverlayState();
}

class _OnlinePauseOverlayState extends State<_OnlinePauseOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final OnlineMatchSnapshot snapshot = widget.data.onlineSnapshot!;
    final OnlinePause pause = snapshot.pause!;
    final Player player = widget.data.onlinePlayer!;
    final int deadline = pause.endsAt ?? pause.requestExpiresAt ?? 0;
    final int remaining =
        ((deadline - DateTime.now().millisecondsSinceEpoch) / 1000)
            .ceil()
            .clamp(0, pause.endsAt == null ? 30 : 120);
    final MatchmakingBloc bloc = MatchmakingRootScope.of(context);
    final bool own = pause.requestedBy == player;
    final bool ready = pause.ready.contains(player);
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x66323A33),
        child: Center(
          child: Container(
            width: 360,
            constraints: const BoxConstraints(maxWidth: 360),
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  pause.endsAt == null ? 'Запрос паузы' : 'Пауза · 2 минуты',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (pause.endsAt != null) ...[
                  Text(
                    '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Text(
                    'Оба готовы — продолжаем сразу. Иначе ждём окончания таймера.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: ready || remaining == 0
                        ? null
                        : () => bloc.add(const MatchmakingEvent$Ready()),
                    child: Text(ready ? 'Вы готовы' : 'Готов'),
                  ),
                ] else ...[
                  Text(
                    own
                        ? 'Ждём согласия соперника.'
                        : '${widget.data.names[pause.requestedBy?.index ?? 0]} предлагает паузу на 2 минуты.',
                  ),
                  Text(
                    'На ответ: $remaining сек. До принятия партия продолжается.',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!own)
                    FilledButton(
                      onPressed: remaining == 0
                          ? null
                          : () => bloc.add(
                              const MatchmakingEvent$PauseAnswer(accept: true),
                            ),
                      child: const Text('Принять паузу'),
                    ),
                  OutlinedButton(
                    onPressed: () => bloc.add(
                      const MatchmakingEvent$PauseAnswer(accept: false),
                    ),
                    child: Text(own ? 'Отменить запрос' : 'Отклонить'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _RankedResultOverlay extends StatefulWidget {
  const new({required this.data, super.key});
  final GameViewData data;

  @override
  State<_RankedResultOverlay> createState() => _RankedResultOverlayState();
}

class _RankedResultOverlayState extends State<_RankedResultOverlay> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final GameViewData data = widget.data;
    final OnlineMatchSnapshot snapshot = data.onlineSnapshot!;
    final int index = data.onlinePlayer!.index;
    final OnlineRanking ranking = snapshot.ranking!;
    final int delta = ranking.changes![index];
    final bool won = snapshot.game.winner == data.onlinePlayer;
    final bool lost = snapshot.game.winner != null && !won;
    final String opponent =
        snapshot.players[index == 0 ? 1 : 0]?.name ?? 'соперником';
    final bool waiting = snapshot.rematch.contains(data.onlinePlayer);
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x94313732),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                width: 440,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'РЕЙТИНГОВАЯ ПАРТИЯ ЗАВЕРШЕНА',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: won
                          ? AppColors.accent
                          : const Color(0xFF5F6761),
                      foregroundColor: Colors.white,
                      child: Icon(
                        delta >= 0
                            ? LucideIcons.trendingUp
                            : LucideIcons.trendingDown,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      won
                          ? 'Победа'
                          : lost
                          ? 'Поражение'
                          : 'Ничья',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      won
                          ? 'Вы обыграли $opponent'
                          : lost
                          ? '$opponent выиграл эту партию'
                          : 'Равная партия с $opponent',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    if (snapshot.endReason case final reason?)
                      Text(
                        reason,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                        ),
                      ),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F1EC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'ИЗМЕНЕНИЕ ELO',
                            style: TextStyle(fontSize: 9),
                          ),
                          Text(
                            '${delta >= 0 ? '+' : ''}$delta',
                            style: TextStyle(
                              color: delta >= 0
                                  ? AppColors.success
                                  : AppColors.danger,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${ranking.points[index]} → ${ranking.points[index] + delta}',
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: waiting
                          ? null
                          : () =>
                                MatchmakingRootScope.of(context)
                                    .add(const MatchmakingEvent$Rematch()),
                      icon: Icon(
                        waiting ? LucideIcons.clock3 : LucideIcons.rotateCcw,
                      ),
                      label: Text(
                        waiting
                            ? 'Ждём решения соперника'
                            : 'Сыграть ещё с $opponent',
                      ),
                    ),
                    const Text(
                      'Реванш не влияет на рейтинг',
                      style: TextStyle(fontSize: 9, color: AppColors.muted),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _dismissed = true),
                      icon: const Icon(LucideIcons.eye),
                      label: const Text('Посмотреть поле'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        MatchmakingRootScope.of(context)
                            .add(const MatchmakingEvent$Leave());
                        GameRootScope.of(context).add(const GameEvent$Menu());
                      },
                      icon: const Icon(LucideIcons.home),
                      label: const Text('Главное меню'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showViewControls(BuildContext context, GameViewData data) {
  final GameBloc bloc = GameRootScope.of(context);
  showAppDialog<void>(
    context: context,
    title: 'Вид',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Камера',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final value in CameraView.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: OutlinedButton(
                    onPressed: () => bloc.add(GameEvent$View(value)),
                    style: value == data.cameraView
                        ? OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFE8EDFE),
                          )
                        : null,
                    child: Text(switch (value) {
                      CameraView.perspective => '3D',
                      CameraView.top => 'Сверху',
                      CameraView.front => 'Спереди',
                    }),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Показать слои',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            OutlinedButton(
              onPressed: () => bloc.add(const GameEvent$ShowAllLayers()),
              child: const Text('Все'),
            ),
            for (var layer = 0; layer < 5; layer++)
              OutlinedButton(
                onPressed: () => bloc.add(GameEvent$ToggleLayer(layer)),
                child: Text('${layer + 1}'),
              ),
          ],
        ),
        const Text(
          'Включайте и скрывайте каждый слой отдельно. Новый ход вернёт все слои.',
          style: TextStyle(color: AppColors.muted, fontSize: 10),
        ),
      ],
    ),
  );
}

void _confirmOnlineLeave(BuildContext context, GameViewData data) {
  showAppDialog<void>(
    context: context,
    title: 'Выйти из лобби?',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          data.onlineSnapshot?.ranking?.rated == true &&
                  data.snapshot.status == GameStatus.playing
              ? 'Выход засчитается как поражение и уменьшит рейтинг. При потере соединения у вас до 60 секунд на возврат.'
              : 'Лобби закроется для обоих игроков.',
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            MatchmakingRootScope.of(context)
                .add(const MatchmakingEvent$Leave());
            GameRootScope.of(context).add(const GameEvent$Menu());
          },
          child: const Text('Выйти из лобби'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Остаться в игре'),
        ),
      ],
    ),
  );
}

class _PlayingOverlay extends StatelessWidget {
  const new({required this.data});
  final GameViewData data;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        top: 16,
        left: 12,
        right: 12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (data.mode == GameMode.online) ...[
              _OnlineBanner(data: data),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Flexible(child: _TurnStatus(data: data)),
                const Spacer(),
                IconButton(
                  tooltip: 'Пауза',
                  onPressed: () => _pauseDialog(context),
                  icon: const Icon(LucideIcons.pause, size: 19),
                ),
              ],
            ),
          ],
        ),
      ),
      Positioned(left: 0, right: 0, bottom: 0, child: _GamePanel(data: data)),
      if (data.message.isNotEmpty) _GameMessage(message: data.message),
    ],
  );

  void _pauseDialog(BuildContext context) {
    if (data.mode == GameMode.online) {
      showAppDialog<void>(
        context: context,
        title: 'Пауза',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Онлайн-партия продолжается, пока открыто меню.'),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: data.onlineSnapshot?.pause?.used == true
                  ? null
                  : () {
                      Navigator.pop(context);
                      MatchmakingRootScope.of(context)
                          .add(const MatchmakingEvent$Pause());
                    },
              child: Text(
                data.onlineSnapshot?.pause?.used == true
                    ? 'Пауза использована'
                    : 'Предложить паузу · 2 мин',
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Продолжить'),
            ),
            OutlinedButton.icon(
              onPressed: () => _confirmOnlineLeave(context, data),
              icon: const Icon(LucideIcons.home),
              label: const Text('Главное меню'),
            ),
          ],
        ),
      );
      return;
    }
    final GameBloc bloc = GameRootScope.of(context)
      ..add(const GameEvent$Pause());
    var resumeAfterDismiss = true;
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
              resumeAfterDismiss = false;
              Navigator.pop(context);
              bloc.add(const GameEvent$Resume());
            },
            child: const Text('Продолжить'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              resumeAfterDismiss = false;
              Navigator.pop(context);
              bloc.add(const GameEvent$Restart());
            },
            icon: const Icon(LucideIcons.rotateCcw),
            label: const Text('Начать заново'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              resumeAfterDismiss = false;
              Navigator.pop(context);
              bloc.add(const GameEvent$Menu());
            },
            icon: const Icon(LucideIcons.home),
            label: const Text('В главное меню'),
          ),
        ],
      ),
    ).whenComplete(() {
      // A barrier/back dismissal resumes the game, while explicit actions
      // own their transition. Checking the current bloc phase here races
      // with its sequential event queue (Menu could be followed by Resume).
      if (resumeAfterDismiss && bloc.data?.phase == GamePhase.paused) {
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
                  tooltip: 'В начало повтора',
                  onPressed: data.replayIndex > 0
                      ? () => bloc.add(const GameEvent$SeekReplay(0))
                      : null,
                  icon: const Icon(LucideIcons.chevronsLeft),
                ),
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
                IconButton(
                  tooltip: 'В конец повтора',
                  onPressed: data.replayIndex < data.snapshot.history.length
                      ? () => bloc.add(
                          GameEvent$SeekReplay(data.snapshot.history.length),
                        )
                      : null,
                  icon: const Icon(LucideIcons.chevronsRight),
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
                  onTap: () => _showViewControls(context, data),
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
          if (finished && data.mode == GameMode.level) ...[
            const SizedBox(height: 8),
            if (data.snapshot.winner == Player.one && (data.levelId ?? 40) < 40)
              FilledButton.icon(
                onPressed: () =>
                    bloc.add(GameEvent$StartLevel(data.levelId! + 1)),
                iconAlignment: IconAlignment.end,
                icon: const Icon(LucideIcons.chevronRight),
                label: const Text('Следующий уровень'),
              ),
            OutlinedButton.icon(
              onPressed: () => bloc.add(const GameEvent$Restart()),
              icon: const Icon(LucideIcons.rotateCcw),
              label: const Text('Повторить уровень'),
            ),
          ] else if (finished) ...[
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

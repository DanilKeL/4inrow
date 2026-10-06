import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/bloc/account_bloc.dart';
import 'package:four3/src/feature/account/bloc/account_state.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/account/widget/account_view.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/components/modals/app_dialog.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/bloc/game_event.dart';
import 'package:four3/src/feature/game/bloc/game_state.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/game/widget/game_scene_view.dart';
import 'package:four3/src/feature/game/widget/game_setup_view.dart';
import 'package:four3/src/feature/leaderboard/widget/leaderboard_view.dart';
import 'package:four3/src/feature/levels/widget/levels_view.dart';
import 'package:four3/src/feature/match_history/widget/match_history_view.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_bloc.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_event.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';
import 'package:four3/src/feature/matchmaking/widget/matchmaking_root_scope.dart';
import 'package:four3/src/feature/matchmaking/widget/online_setup_view.dart';
import 'package:four3/src/feature/settings/bloc/settings_bloc.dart';
import 'package:four3/src/feature/settings/bloc/settings_event.dart';
import 'package:four3/src/feature/settings/bloc/settings_state.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';
import 'package:four3/src/feature/settings/widget/settings_root_scope.dart';
import 'package:four3/src/feature/settings/widget/settings_view.dart';
import 'package:four3/src/feature/tutorial/widget/tutorial_view.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

String _gameMessage(BuildContext context, GameViewData data) {
  if (data.remoteMessage.isNotEmpty) return data.remoteMessage;
  return switch (data.notice) {
    GameNotice.columnFull => context.l10n.columnFull,
    GameNotice.aiMoveFailed => context.l10n.aiMoveFailed,
    GameNotice.reconnecting => context.l10n.reconnecting,
    null => '',
  };
}

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
        if (!didPop) _requestGameMenu(context, data);
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
                        if (!isMenu) _requestGameMenu(context, data);
                      },
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final Widget sceneView = GameSceneView(
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
                          );
                          if (!isMenu) {
                            final bool shortLandscape =
                                constraints.maxWidth >= 651 &&
                                constraints.maxHeight <= 550;
                            final bool result =
                                data.snapshot.status != GameStatus.playing ||
                                data.phase == GamePhase.replay;
                            final Widget board = shortLandscape
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _SceneCard(menu: false, child: sceneView),
                                      if (_gameMessage(
                                        context,
                                        data,
                                      ).isNotEmpty)
                                        _GameMessage(
                                          message: _gameMessage(context, data),
                                        ),
                                    ],
                                  )
                                : _PortraitGameBoard(
                                    data: data,
                                    scene: sceneView,
                                  );
                            final Widget content = result && !shortLandscape
                                ? Column(
                                    children: [
                                      Expanded(child: board),
                                      _GamePanel(data: data),
                                    ],
                                  )
                                : board;
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
                                  : content,
                            );
                          }
                          final Widget scene = _SceneCard(
                            menu: true,
                            child: sceneView,
                          );
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
            if (data.onlineSnapshot?.pause case final pause?)
              if (pause.requestId != null || pause.endsAt != null)
                _OnlinePauseOverlay(
                  key: ValueKey('${pause.requestId}-${pause.endsAt}'),
                  data: data,
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
    title: context.l10n.newGame,
    child: GameSetupView(initialMode: mode),
  );

  void _openRated(BuildContext context) {
    final String name =
        AccountRootScope.of(context).profile?.displayName ??
        context.l10n.player;
    MatchmakingRootScope.of(context).add(MatchmakingEvent$Find(name));
    showAppDialog<void>(
      context: context,
      title: context.l10n.rankedGame,
      child: const OnlineSetupView(quickOnly: true),
    );
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
                  label: accountBloc.profile?.displayName ?? context.l10n.guest,
                  showLabel: expanded,
                  onTap: () => _openAccount(context),
                ),
              ),
              _HeaderAction(
                icon: LucideIcons.circleHelp,
                label: context.l10n.howToPlay,
                showLabel: expanded,
                onTap: () => showAppDialog<void>(
                  context: context,
                  title: context.l10n.howToPlay,
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
                    ? context.l10n.turnOffSound
                    : context.l10n.turnOnSound,
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
                label: context.l10n.settings,
                onTap: () => showAppDialog<void>(
                  context: context,
                  title: context.l10n.settings,
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
      title: context.l10n.account,
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
        title: context.l10n.matchHistory,
        child: SizedBox(
          height: math.min(560, MediaQuery.sizeOf(context).height - 180),
          child: const MatchHistoryView(),
        ),
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
          context.l10n.gameName,
          style: TextStyle(
            fontSize: compact ? 20 : 21,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: -.8,
          ),
        ),
        if (compact) const SizedBox(height: 8),
        if (compact)
          Text(
            context.l10n.gameTagline,
            style: const TextStyle(
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
            child: Row(
              children: [
                const Icon(LucideIcons.search, size: 18),
                const SizedBox(width: 11),
                Text(context.l10n.rankedGame),
                const Spacer(),
                const Icon(LucideIcons.arrowRight, size: 18),
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
                label: context.l10n.levels,
                onTap: () => showAppDialog<void>(
                  context: context,
                  title: context.l10n.levels,
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
                label: context.l10n.versusAi,
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
                label: context.l10n.twoPlayers,
                onTap: () => onMode(GameMode.local),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ModeButton(
                compact: compact,
                icon: LucideIcons.globe2,
                label: context.l10n.online,
                onTap: () => onMode(GameMode.online),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 4 : 5),
        SizedBox(
          height: compact ? 30 : 32,
          child: TextButton(
            onPressed: () => showAppDialog<void>(
              context: context,
              title: context.l10n.playerRating,
              wide: true,
              child: const LeaderboardView(),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              foregroundColor: const Color(0xFF697163),
              textStyle: const TextStyle(fontSize: 10),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.trophy, size: 16),
                const SizedBox(width: 9),
                Text(context.l10n.playerRating),
                const Spacer(),
                const Icon(LucideIcons.arrowRight, size: 14),
              ],
            ),
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

  String _text(BuildContext context) {
    final GameViewData data = widget.data;
    if (data.phase == GamePhase.aiThinking) {
      return data.mode == GameMode.level
          ? context.l10n.botMoving
          : context.l10n.aiThinking;
    }
    if (data.phase == GamePhase.animating) return context.l10n.moveCompleted;
    if (data.phase == GamePhase.paused) return context.l10n.pause;
    if (data.phase == GamePhase.replay) {
      return context.l10n.replayMove(data.replayIndex);
    }
    if (data.snapshot.status != GameStatus.playing) {
      return context.l10n.gameFinished;
    }
    if (data.mode == GameMode.online) {
      if (data.onlineConnection != OnlineConnectionStatus.connected) {
        return context.l10n.noConnection;
      }
      if (data.onlineSnapshot?.startedAt == null) {
        return context.l10n.waitingForOpponent;
      }
      return data.onlinePlayer == data.snapshot.currentPlayer
          ? context.l10n.yourTurn
          : context.l10n.opponentTurn;
    }
    if (data.mode == GameMode.level) return context.l10n.yourTurn;
    return context.l10n.playerTurn(
      data.names[data.snapshot.currentPlayer.index],
    );
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
              '${data.levelId == null ? '' : '${context.l10n.levelNumber(data.levelId!)} · '}${_text(context)}',
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
            Text.rich(
              TextSpan(
                text: _remaining == null ? '—' : '${_remaining!}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                children: [
                  TextSpan(
                    text: context.l10n.secondsShort,
                    style: const TextStyle(
                      color: Color(0xFF858D7B),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
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
        ? context.l10n.connectionClosed
        : data.onlineConnection != OnlineConnectionStatus.connected
        ? context.l10n.reconnecting
        : opponent == null
        ? (quick
              ? context.l10n.waitingForOpponentEllipsis
              : context.l10n.shareLobbyCode)
        : !opponent.connected
        ? context.l10n.opponentDisconnected
        : index == 0
        ? context.l10n.playingGraphite
        : context.l10n.playingLight;
    final String rankedStatus = ranking?.rated == true
        ? '${context.l10n.ratingValue(ranking!.points[index] + (delta ?? 0))}'
              '${delta != null
                  ? ' (${delta >= 0 ? '+' : ''}$delta)'
                  : snapshot.pause?.endsAt != null
                  ? ' · ${context.l10n.pause}'
                  : ''}'
              '${snapshot.endReason != null
                  ? ' · ${snapshot.endReason}'
                  : opponent?.connected == false
                  ? ' · ${context.l10n.waitingForConnection}'
                  : ''}'
        : (ranking?.reason ?? status);
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
                  quick
                      ? context.l10n.rankedGameUpper
                      : context.l10n.lobbyUpper,
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
                  tooltip: context.l10n.copyLobbyCode,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: snapshot.code));
                    if (mounted) {
                      setState(() => _copyStatus = context.l10n.codeCopied);
                    }
                  },
                  icon: const Icon(LucideIcons.copy, size: 15),
                ),
              ],
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: context.l10n.leaveLobby,
                onPressed: () => _confirmOnlineLeave(context, data),
                icon: const Icon(LucideIcons.logOut, size: 15),
              ),
            ],
          ),
          Text(
            rankedStatus,
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

class _PortraitGameBoard extends StatelessWidget {
  const new({required this.data, required this.scene});

  final GameViewData data;
  final Widget scene;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEE8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDFE1D9)),
      ),
      child: Column(
        children: [
          if (data.mode == GameMode.online)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 5, 12, 0),
              child: _OnlineBanner(data: data),
            ),
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Row(
                children: [
                  Flexible(child: _TurnStatus(data: data)),
                  const Spacer(),
                  IconButton(
                    tooltip: context.l10n.pause,
                    onPressed: () => _showPauseDialog(context, data),
                    icon: const Icon(LucideIcons.pause, size: 19),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                scene,
                if (_gameMessage(context, data).isNotEmpty)
                  _GameMessage(message: _gameMessage(context, data), bottom: 8),
              ],
            ),
          ),
          _PlayerStrip(data: data),
          const Divider(height: 1),
          _ToolBar(data: data, labels: true),
        ],
      ),
    ),
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
          data.mode == GameMode.level
              ? context.l10n.moves(data.levelMoves)
              : context.l10n.moves(
                  data.phase == GamePhase.replay
                      ? data.replayIndex
                      : data.snapshot.history.length,
                ),
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
  const new({required this.data, this.labels = false});
  final GameViewData data;
  final bool labels;

  @override
  Widget build(BuildContext context) {
    final GameBloc bloc = GameRootScope.of(context);
    return Row(
      children: [
        if (data.mode != GameMode.level)
          _Tool(
            icon: LucideIcons.rotateCcw,
            label: labels ? context.l10n.undo : '',
            enabled:
                data.mode != GameMode.online &&
                data.phase == GamePhase.playing &&
                data.snapshot.history.isNotEmpty,
            onTap: () => bloc.add(const GameEvent$Undo()),
          ),
        _Tool(
          icon: LucideIcons.eye,
          label: labels ? context.l10n.xray : '',
          selected: data.xray,
          onTap: () => bloc.add(const GameEvent$ToggleXray()),
        ),
        _ViewTool(label: labels ? context.l10n.view : ''),
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
  const new({required this.message, this.bottom = 76});
  final String message;
  final double bottom;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 24,
    right: 24,
    bottom: bottom,
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
  const new({required this.data, super.key});
  final GameViewData data;

  @override
  State<_OnlinePauseOverlay> createState() => _OnlinePauseOverlayState();
}

class _OnlinePauseOverlayState extends State<_OnlinePauseOverlay> {
  Timer? _timer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
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
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          pause.endsAt == null
                              ? context.l10n.pauseRequest
                              : context.l10n.twoMinutePause,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.close,
                        onPressed: () => setState(() => _dismissed = true),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
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
                    Text(
                      context.l10n.pauseReadyHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed:
                          ready ||
                              remaining == 0 ||
                              widget.data.onlineConnection !=
                                  OnlineConnectionStatus.connected ||
                              !snapshot.players.every(
                                (player) => player?.connected ?? false,
                              )
                          ? null
                          : () => bloc.add(const MatchmakingEvent$Ready()),
                      child: Text(
                        ready ? context.l10n.youAreReady : context.l10n.ready,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ready
                          ? context.l10n.waitingOpponentReady
                          : pause.ready.any((value) => value != player)
                          ? context.l10n.opponentReady
                          : '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    if (widget.data.onlineConnection !=
                        OnlineConnectionStatus.connected)
                      Text(
                        context.l10n.reconnecting,
                        textAlign: TextAlign.center,
                      ),
                  ] else ...[
                    Text(
                      own
                          ? context.l10n.waitingOpponentApproval
                          : context.l10n.playerOffersPause(
                              widget.data.names[pause.requestedBy?.index ?? 0],
                            ),
                    ),
                    Text(
                      context.l10n.pauseAnswerTime(remaining),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!own)
                      FilledButton(
                        onPressed:
                            remaining == 0 ||
                                widget.data.onlineConnection !=
                                    OnlineConnectionStatus.connected
                            ? null
                            : () => bloc.add(
                                const MatchmakingEvent$PauseAnswer(
                                  accept: true,
                                ),
                              ),
                        child: Text(context.l10n.acceptPause),
                      ),
                    OutlinedButton(
                      onPressed:
                          widget.data.onlineConnection !=
                              OnlineConnectionStatus.connected
                          ? null
                          : () => bloc.add(
                              const MatchmakingEvent$PauseAnswer(accept: false),
                            ),
                      child: Text(
                        own ? context.l10n.cancelRequest : context.l10n.decline,
                      ),
                    ),
                  ],
                ],
              ),
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
    final String? opponent = snapshot.players[index == 0 ? 1 : 0]?.name;
    final bool waiting = snapshot.rematch.contains(data.onlinePlayer);
    final bool connected =
        data.onlineConnection == OnlineConnectionStatus.connected &&
        snapshot.players.every((player) => player?.connected ?? false);
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x94313732),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  width: 440,
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        right: 0,
                        height: 4,
                        child: ColoredBox(
                          color: won
                              ? AppColors.accent
                              : lost
                              ? const Color(0xFF9E4C43)
                              : const Color(0xFF737B71),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 25, 18, 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.l10n.rankedMatchFinished,
                              style: const TextStyle(
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
                                  ? context.l10n.win
                                  : lost
                                  ? context.l10n.loss
                                  : context.l10n.draw,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              opponent == null
                                  ? won
                                        ? context.l10n.youBeatFallbackOpponent
                                        : lost
                                        ? context.l10n.fallbackOpponentWon
                                        : context
                                              .l10n
                                              .evenMatchWithFallbackOpponent
                                  : won
                                  ? context.l10n.youBeatOpponent(opponent)
                                  : lost
                                  ? context.l10n.opponentWon(opponent)
                                  : context.l10n.evenMatch(opponent),
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
                                  Text(
                                    context.l10n.eloChange,
                                    style: const TextStyle(fontSize: 9),
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
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: waiting || !connected
                                    ? null
                                    : () => MatchmakingRootScope.of(
                                        context,
                                      ).add(const MatchmakingEvent$Rematch()),
                                icon: Icon(
                                  waiting
                                      ? LucideIcons.clock3
                                      : LucideIcons.rotateCcw,
                                ),
                                label: Text(
                                  waiting
                                      ? context.l10n.waitingOpponentDecision
                                      : connected
                                      ? opponent == null
                                            ? context
                                                  .l10n
                                                  .playAgainWithFallbackOpponent
                                            : context.l10n.playAgainWith(
                                                opponent,
                                              )
                                      : context.l10n.opponentOffline,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.l10n.rematchUnrated,
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    setState(() => _dismissed = true),
                                icon: const Icon(LucideIcons.eye),
                                label: Text(context.l10n.viewBoard),
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextButton.icon(
                              onPressed: () {
                                MatchmakingRootScope.of(context)
                                    .add(const MatchmakingEvent$Leave());
                                GameRootScope.of(context)
                                    .add(const GameEvent$Menu());
                              },
                              icon: const Icon(LucideIcons.home),
                              label: Text(context.l10n.mainMenu),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showViewControls(BuildContext context) {
  final GameBloc bloc = GameRootScope.of(context);
  final Size screen = MediaQuery.sizeOf(context);
  final EdgeInsets safeInsets = MediaQuery.viewPaddingOf(context);
  final double right = math.max(12, safeInsets.right);
  final double bottom = 48 + safeInsets.bottom;
  final double availableHeight = math.max(0, screen.height - bottom - 12);
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        alignment: Alignment.bottomRight,
        scale: Tween<double>(begin: .97, end: 1).animate(animation),
        child: child,
      ),
    ),
    pageBuilder: (context, _, _) => Stack(
      children: [
        Positioned(
          right: right,
          bottom: bottom,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(290, screen.width - 24),
              maxHeight: availableHeight,
            ),
            child: Material(
              color: const Color(0xFFFCFDF9),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xFFE2E7D8)),
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 12,
              shadowColor: const Color(0x22273C25),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: BlocBuilder<GameBloc, GameState>(
                  bloc: bloc,
                  builder: (context, state) {
                    final GameViewData? data = switch (state) {
                      GameState$Ready(:final data) => data,
                      _ => null,
                    };
                    if (data == null) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.l10n.camera,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: context.l10n.closeViewMenu,
                              visualDensity: VisualDensity.compact,
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(LucideIcons.x, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            for (final (view, label) in [
                              (
                                CameraView.perspective,
                                context.l10n.viewPerspective,
                              ),
                              (CameraView.top, context.l10n.viewTop),
                              (CameraView.front, context.l10n.viewFront),
                            ]) ...[
                              if (view != CameraView.perspective)
                                const SizedBox(width: 5),
                              Expanded(
                                child: _ViewChoice(
                                  label: label,
                                  selected: data.cameraView == view,
                                  onTap: () => bloc.add(GameEvent$View(view)),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.showLayers,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _LayerChoice(
                                label: context.l10n.allLayers,
                                selected: data.layers.length == 5,
                                onTap: () =>
                                    bloc.add(const GameEvent$ShowAllLayers()),
                              ),
                            ),
                            for (var layer = 0; layer < 5; layer++) ...[
                              const SizedBox(width: 5),
                              Expanded(
                                child: _LayerChoice(
                                  label: '${layer + 1}',
                                  selected: data.layers.contains(layer),
                                  onTap: () =>
                                      bloc.add(GameEvent$ToggleLayer(layer)),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.layersHint,
                          style: const TextStyle(
                            color: Color(0xFF959D89),
                            fontSize: 9,
                            height: 1.7,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _LayerChoice extends StatelessWidget {
  const new({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 40),
        backgroundColor: selected ? const Color(0xFFE8EDFE) : Colors.white,
        foregroundColor: selected ? AppColors.accent : AppColors.ink,
        side: BorderSide(
          color: selected ? const Color(0xFF9FB2F4) : const Color(0xFFDFE4D5),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        textStyle: const TextStyle(fontSize: 10),
      ),
      child: Text(label),
    ),
  );
}

class _ViewChoice extends StatelessWidget {
  const new({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      _LayerChoice(label: label, selected: selected, onTap: onTap);
}

Future<void> _requestGameMenu(
  BuildContext context,
  GameViewData fallback,
) async {
  final GameBloc bloc = GameRootScope.of(context);
  final GameViewData current = bloc.data ?? fallback;
  final bool online = current.mode == GameMode.online;
  final bool unfinished =
      current.snapshot.status == GameStatus.playing &&
      current.snapshot.history.isNotEmpty;
  if (!unfinished) {
    if (online) {
      MatchmakingRootScope.of(context).add(const MatchmakingEvent$Leave());
    }
    bloc.add(const GameEvent$Menu());
    return;
  }
  if (current.phase != GamePhase.paused) {
    bloc.add(const GameEvent$Pause());
  }
  final bool? leave = await showAppDialog<bool>(
    context: context,
    title: online
        ? context.l10n.leaveLobbyQuestion
        : context.l10n.finishGameQuestion,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          online && current.onlineSnapshot?.ranking?.rated == true
              ? context.l10n.rankedLeaveWarning
              : online
              ? context.l10n.lobbyLeaveWarning
              : context.l10n.movesWillBeLost,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 20),
        _ConfirmationActions(
          confirmLabel: online
              ? context.l10n.exitLobby
              : context.l10n.leaveToMenu,
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (leave == true) {
    if (online) {
      MatchmakingRootScope.of(context).add(const MatchmakingEvent$Leave());
    }
    bloc.add(const GameEvent$Menu());
  } else {
    bloc.add(const GameEvent$Resume());
  }
}

Future<void> _requestRestart(
  BuildContext context,
  GameViewData fallback,
) async {
  final GameBloc bloc = GameRootScope.of(context);
  final GameViewData current = bloc.data ?? fallback;
  if (current.snapshot.history.length <= 1) {
    bloc.add(const GameEvent$Restart());
    return;
  }
  final bool? restart = await showAppDialog<bool>(
    context: context,
    title: context.l10n.restartQuestion,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.movesWillBeLost,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 20),
        _ConfirmationActions(confirmLabel: context.l10n.restart),
      ],
    ),
  );
  if (restart == true) {
    bloc.add(const GameEvent$Restart());
  } else {
    bloc.add(const GameEvent$Resume());
  }
}

class _ConfirmationActions extends StatelessWidget {
  const new({required this.confirmLabel});

  final String confirmLabel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
        child: Text(confirmLabel, textAlign: TextAlign.center),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => Navigator.pop(context, false),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
        child: Text(context.l10n.stayInGame, textAlign: TextAlign.center),
      ),
    ],
  );
}

void _confirmOnlineLeave(BuildContext context, GameViewData data) {
  showAppDialog<bool>(
    context: context,
    title: context.l10n.leaveLobbyQuestion,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          data.onlineSnapshot?.ranking?.rated == true &&
                  data.snapshot.status == GameStatus.playing
              ? context.l10n.rankedLeaveWarning
              : context.l10n.lobbyLeaveWarning,
        ),
        const SizedBox(height: 14),
        _ConfirmationActions(confirmLabel: context.l10n.exitLobby),
      ],
    ),
  ).then((leave) {
    if (leave != true || !context.mounted) return;
    MatchmakingRootScope.of(context).add(const MatchmakingEvent$Leave());
    GameRootScope.of(context).add(const GameEvent$Menu());
  });
}

void _showPauseDialog(BuildContext context, GameViewData data) {
  final GameBloc bloc = GameRootScope.of(context);
  void afterClose(FutureOr<void> Function() action) {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) unawaited(Future<void>.sync(action));
    });
  }

  if (data.mode == GameMode.online) {
    showAppDialog<void>(
      context: context,
      title: context.l10n.pause,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.onlineContinuesInMenu),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: data.onlineSnapshot?.pause?.used == true
                ? null
                : () {
                    afterClose(
                      () =>
                          MatchmakingRootScope.of(context)
                              .add(const MatchmakingEvent$Pause()),
                    );
                  },
            child: Text(
              data.onlineSnapshot?.pause?.used == true
                  ? context.l10n.pauseUsed
                  : context.l10n.offerPause,
            ),
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            iconAlignment: IconAlignment.end,
            icon: const Icon(LucideIcons.arrowRight, size: 18),
            label: Text(context.l10n.continueAction),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => afterClose(
              () => showAppDialog<void>(
                context: context,
                title: context.l10n.settings,
                child: const SettingsView(),
              ),
            ),
            icon: const Icon(LucideIcons.settings2),
            label: Text(context.l10n.settings),
          ),
          TextButton.icon(
            onPressed: () => afterClose(() => _requestGameMenu(context, data)),
            icon: const Icon(LucideIcons.home),
            label: Text(context.l10n.mainMenu),
          ),
        ],
      ),
    );
    return;
  }
  bloc.add(const GameEvent$Pause());
  var resumeAfterDismiss = true;
  showAppDialog<void>(
    context: context,
    title: context.l10n.pause,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l10n.timeStopped),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {
            resumeAfterDismiss = false;
            Navigator.pop(context);
            bloc.add(const GameEvent$Resume());
          },
          iconAlignment: IconAlignment.end,
          icon: const Icon(LucideIcons.arrowRight, size: 18),
          label: Text(context.l10n.continueAction),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () {
            resumeAfterDismiss = false;
            afterClose(() => _requestRestart(context, data));
          },
          icon: const Icon(LucideIcons.rotateCcw),
          label: Text(context.l10n.restart),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            resumeAfterDismiss = false;
            afterClose(() async {
              await showAppDialog<void>(
                context: context,
                title: context.l10n.settings,
                child: const SettingsView(),
              );
              if (bloc.data?.phase == GamePhase.paused) {
                bloc.add(const GameEvent$Resume());
              }
            });
          },
          icon: const Icon(LucideIcons.settings2),
          label: Text(context.l10n.settings),
        ),
        if (data.mode == GameMode.level) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              resumeAfterDismiss = false;
              final int initialId = data.levelId ?? 1;
              bloc.add(const GameEvent$Menu());
              afterClose(
                () => showAppDialog<void>(
                  context: context,
                  title: context.l10n.levels,
                  wide: true,
                  child: LevelsView(initialId: initialId),
                ),
              );
            },
            icon: const Icon(LucideIcons.puzzle),
            label: Text(context.l10n.backToLevels),
          ),
        ],
        TextButton.icon(
          onPressed: () {
            resumeAfterDismiss = false;
            afterClose(() => _requestGameMenu(context, data));
          },
          icon: const Icon(LucideIcons.home),
          label: Text(context.l10n.mainMenu),
        ),
      ],
    ),
  ).whenComplete(() {
    // Pause and resume stay ordered in the bloc even if the dialog is
    // dismissed before the pause event has been reduced.
    if (resumeAfterDismiss) {
      bloc.add(const GameEvent$Resume());
    }
  });
}

class _GamePanel extends StatelessWidget {
  const new({required this.data});
  final GameViewData data;

  @override
  Widget build(BuildContext context) {
    final GameBloc bloc = GameRootScope.of(context);
    final Player? winner = data.snapshot.winner;
    final bool completedLevel =
        data.mode == GameMode.level && winner == Player.one;
    final bool hasNextLevel = completedLevel && (data.levelId ?? 40) < 40;
    final bool waitingForRematch =
        data.mode == GameMode.online &&
        data.onlinePlayer != null &&
        (data.onlineSnapshot?.rematch.contains(data.onlinePlayer) ?? false);
    final bool onlineConnected =
        data.onlineConnection == OnlineConnectionStatus.connected &&
        (data.onlineSnapshot?.players.every(
              (player) => player?.connected ?? false,
            ) ??
            false);
    void openLevels() {
      final int initialId = data.levelId ?? 1;
      bloc.add(const GameEvent$Menu());
      showAppDialog<void>(
        context: context,
        title: context.l10n.levels,
        wide: true,
        child: LevelsView(initialId: initialId),
      );
    }

    final String title = data.mode == GameMode.level
        ? completedLevel
              ? context.l10n.levelCompleted
              : winner == null
              ? context.l10n.draw
              : context.l10n.loss
        : winner == null
        ? context.l10n.draw
        : context.l10n.winnerName(data.names[winner.index]);
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: data.phase == GamePhase.replay
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _ReplayButton(
                      icon: LucideIcons.chevronsLeft,
                      tooltip: context.l10n.replayStart,
                      onPressed: data.replayIndex > 0
                          ? () => bloc.add(const GameEvent$SeekReplay(0))
                          : null,
                    ),
                    _ReplayButton(
                      icon: LucideIcons.chevronLeft,
                      tooltip: context.l10n.previousMove,
                      onPressed: data.replayIndex > 0
                          ? () => bloc.add(
                              GameEvent$SeekReplay(data.replayIndex - 1),
                            )
                          : null,
                    ),
                    _ReplayButton(
                      icon: LucideIcons.chevronRight,
                      tooltip: context.l10n.nextMove,
                      onPressed: data.replayIndex < data.snapshot.history.length
                          ? () => bloc.add(
                              GameEvent$SeekReplay(data.replayIndex + 1),
                            )
                          : null,
                    ),
                    _ReplayButton(
                      icon: LucideIcons.chevronsRight,
                      tooltip: context.l10n.replayEnd,
                      onPressed: data.replayIndex < data.snapshot.history.length
                          ? () => bloc.add(
                              GameEvent$SeekReplay(
                                data.snapshot.history.length,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.replayProgress(
                          data.replayIndex,
                          data.snapshot.history.length,
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            bloc.add(const GameEvent$CloseReplay()),
                        child: Text(context.l10n.finishReplay),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4,
                  ),
                ),
                if (completedLevel && MediaQuery.sizeOf(context).width > 650)
                  Text(
                    '${data.levelBestBefore == null || data.levelMoves < data.levelBestBefore! ? context.l10n.newRecord : context.l10n.win} · ${context.l10n.moves(data.levelMoves)}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                const SizedBox(height: 4),
                if (data.mode == GameMode.level) ...[
                  Row(
                    children: [
                      if (hasNextLevel) ...[
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => bloc.add(
                              GameEvent$StartLevel(data.levelId! + 1),
                            ),
                            iconAlignment: IconAlignment.end,
                            icon: const Icon(
                              LucideIcons.chevronRight,
                              size: 17,
                            ),
                            label: Text(context.l10n.nextLevel),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: hasNextLevel
                            ? OutlinedButton.icon(
                                onPressed: () =>
                                    bloc.add(const GameEvent$Restart()),
                                icon: const Icon(
                                  LucideIcons.rotateCcw,
                                  size: 16,
                                ),
                                label: Text(context.l10n.retryLevel),
                              )
                            : FilledButton.icon(
                                onPressed: () =>
                                    bloc.add(const GameEvent$Restart()),
                                icon: const Icon(
                                  LucideIcons.rotateCcw,
                                  size: 16,
                                ),
                                label: Text(context.l10n.retryLevel),
                              ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: openLevels,
                    child: Text(context.l10n.backToLevels),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              data.mode == GameMode.online &&
                                  (waitingForRematch || !onlineConnected)
                              ? null
                              : () {
                                  if (data.mode == GameMode.online) {
                                    MatchmakingRootScope.of(context)
                                        .add(const MatchmakingEvent$Rematch());
                                  } else {
                                    bloc.add(const GameEvent$Restart());
                                  }
                                },
                          icon: Icon(
                            waitingForRematch
                                ? LucideIcons.clock3
                                : LucideIcons.rotateCcw,
                            size: 17,
                          ),
                          label: Text(
                            waitingForRematch
                                ? context.l10n.waitingOpponentApproval
                                : context.l10n.anotherGame,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              bloc.add(const GameEvent$OpenReplay()),
                          icon: const Icon(LucideIcons.play, size: 17),
                          label: Text(context.l10n.replayGame),
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () {
                      if (data.mode == GameMode.online) {
                        MatchmakingRootScope.of(context)
                            .add(const MatchmakingEvent$Leave());
                      }
                      bloc.add(const GameEvent$Menu());
                    },
                    child: Text(context.l10n.mainMenu),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ReplayButton extends StatelessWidget {
  const new({required this.icon, required this.tooltip, this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: IconButton.outlined(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    ),
  );
}

class _ViewTool extends StatelessWidget {
  const new({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Builder(
      builder: (anchorContext) => InkWell(
        onTap: () => _showViewControls(anchorContext),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.layers3, size: 19),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 10)),
                const SizedBox(width: 3),
                const Icon(LucideIcons.chevronDown, size: 13),
              ],
            ],
          ),
        ),
      ),
    ),
  );
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

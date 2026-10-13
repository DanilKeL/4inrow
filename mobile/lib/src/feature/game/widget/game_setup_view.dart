import 'package:flutter/material.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/domain/model/account_profile.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/app_theme/utils/theme_context_extension.dart';
import 'package:four3/src/feature/components/buttons/app_action_button.dart';
import 'package:four3/src/feature/components/modals/app_dialog.dart';
import 'package:four3/src/feature/components/selectors/app_segmented_control.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/bloc/game_event.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_event.dart';
import 'package:four3/src/feature/matchmaking/widget/matchmaking_root_scope.dart';
import 'package:four3/src/feature/matchmaking/widget/online_setup_view.dart';
import 'package:four3/src/feature/settings/bloc/settings_bloc.dart';
import 'package:four3/src/feature/settings/bloc/settings_event.dart';
import 'package:four3/src/feature/settings/widget/settings_root_scope.dart';
import 'package:four3/src/feature/tutorial/widget/tutorial_view.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class GameSetupView extends StatefulWidget {
  const new({required this.initialMode, super.key});

  final GameMode initialMode;

  @override
  State<GameSetupView> createState() => _GameSetupViewState();
}

class _GameSetupViewState extends State<GameSetupView> {
  late GameMode _mode = widget.initialMode;
  Difficulty _difficulty = Difficulty.medium;

  @override
  Widget build(BuildContext context) {
    final AccountProfile? profile = AccountRootScope.of(context).profile;
    final AppLocalizations l10n = context.l10n;
    final String player = profile?.displayName ?? l10n.playerOne;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _ModeChoice(
                icon: LucideIcons.usersRound,
                title: l10n.twoPlayers,
                subtitle: l10n.sameDevice,
                selected: _mode == GameMode.local,
                onTap: () => setState(() => _mode = GameMode.local),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ModeChoice(
                icon: LucideIcons.cpu,
                title: l10n.versusAi,
                subtitle: l10n.threeDifficulties,
                selected: _mode == GameMode.ai,
                onTap: () => setState(() => _mode = GameMode.ai),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ModeChoice(
                icon: LucideIcons.globe2,
                title: l10n.online,
                subtitle: l10n.lobbyCodeMode,
                selected: _mode == GameMode.online,
                onTap: () => setState(() => _mode = GameMode.online),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _PlayerRow(label: l10n.playerLabel, value: player),
        if (_mode == GameMode.local) ...[
          const SizedBox(height: 4),
          _PlayerRow(label: l10n.playerTwoLabel, value: l10n.playerTwo),
        ],
        if (_mode == GameMode.ai) ...[
          const SizedBox(height: 20),
          Text(
            l10n.difficulty,
            style: context.textStyle.bodyStrong.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 8),
          AppSegmentedControl<Difficulty>(
            options: [
              AppSegment(value: Difficulty.easy, label: l10n.easy),
              AppSegment(value: Difficulty.medium, label: l10n.medium),
              AppSegment(value: Difficulty.hard, label: l10n.hard),
            ],
            selected: _difficulty,
            onChanged: (value) => setState(() => _difficulty = value),
          ),
        ],
        if (_mode == GameMode.online) ...[
          const SizedBox(height: 20),
          OnlineSetupView(onQuickStart: () => _openQuick(context, player)),
        ],
        if (_mode != GameMode.online) ...[
          const SizedBox(height: 20),
          AppActionButton(
            onPressed: () => _start(context, player),
            label: l10n.startGame,
            trailing: const Icon(LucideIcons.arrowRight, size: 18),
          ),
        ],
      ],
    );
  }

  void _start(BuildContext context, String player) {
    final GameBloc game = GameRootScope.of(context);
    final SettingsBloc settings = SettingsRootScope.of(context);
    final BuildContext appContext = Navigator.of(context).context;
    game.add(
      GameEvent$Start(
        mode: _mode,
        difficulty: _difficulty,
        names: <String>[player, context.l10n.playerTwo],
      ),
    );
    Navigator.pop(context);
    if (settings.settings.tutorialSeen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!appContext.mounted) return;
      game.add(const GameEvent$Pause());
      showAppDialog<void>(
        context: appContext,
        titleBuilder: (context) => context.l10n.howToPlay,
        wide: true,
        builder: (_) => TutorialView(
          starting: true,
          animations: settings.settings.animations,
          onDone: () {
            settings.add(
              SettingsEvent$Update(
                settings.settings.copyWith(tutorialSeen: true),
              ),
            );
            Navigator.pop(appContext);
            game.add(const GameEvent$Resume());
          },
        ),
      );
    });
  }

  void _openQuick(BuildContext context, String player) {
    final BuildContext appContext = Navigator.of(context).context;
    MatchmakingRootScope.of(context).add(MatchmakingEvent$Find(player));
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!appContext.mounted) return;
      showAppDialog<void>(
        context: appContext,
        titleBuilder: (context) =>
            AccountRootScope.of(context).profile?.username == null
            ? context.l10n.quickGame
            : context.l10n.rankedGame,
        showCloseButton: false,
        barrierDismissible: false,
        builder: (_) => const OnlineSetupView(quickOnly: true),
      );
    });
  }
}

class _ModeChoice extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Ink(
      height: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 108 : 84,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? context.colors.accentSubtle : context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          width: selected ? 1.5 : 1,
          color: selected ? context.colors.accent : context.colors.border,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: selected ? AppColors.accent : null),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.textStyle.bodyStrong.copyWith(
              fontSize: 11,
              height: 18 / 15,
              color: selected ? AppColors.accent : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: context.textStyle.caption.copyWith(
              fontSize: 8,
              height: 13 / 11,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PlayerRow extends StatelessWidget {
  const new({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(label, style: context.textStyle.caption),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: context.textStyle.captionStrong,
        ),
      ),
    ],
  );
}

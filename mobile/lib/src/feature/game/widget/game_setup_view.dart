import 'package:flutter/material.dart';
import 'package:four3/src/common/theme/app_theme.dart';
import 'package:four3/src/feature/account/model/account_profile.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/matchmaking/widget/online_setup_view.dart';
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
    final String player = profile?.displayName ?? 'Игрок 1';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _ModeChoice(
                icon: LucideIcons.usersRound,
                title: 'Вдвоём',
                subtitle: 'На одном устройстве',
                selected: _mode == GameMode.local,
                onTap: () => setState(() => _mode = GameMode.local),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ModeChoice(
                icon: LucideIcons.cpu,
                title: 'Против AI',
                subtitle: 'Три сложности',
                selected: _mode == GameMode.ai,
                onTap: () => setState(() => _mode = GameMode.ai),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ModeChoice(
                icon: LucideIcons.globe2,
                title: 'Онлайн',
                subtitle: 'По коду лобби',
                selected: _mode == GameMode.online,
                onTap: () => setState(() => _mode = GameMode.online),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text.rich(
              TextSpan(
                text: 'Вы играете как ',
                children: [
                  TextSpan(
                    text: player,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            if (_mode == GameMode.local)
              const Text.rich(
                TextSpan(
                  text: 'Второй игрок: ',
                  children: [
                    TextSpan(
                      text: 'Игрок 2',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
          ],
        ),
        if (_mode == GameMode.ai) ...[
          const SizedBox(height: 14),
          const Text('Сложность', style: TextStyle(fontSize: 11)),
          const SizedBox(height: 7),
          SegmentedButton<Difficulty>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: Difficulty.easy, label: Text('Легко')),
              ButtonSegment(value: Difficulty.medium, label: Text('Средне')),
              ButtonSegment(value: Difficulty.hard, label: Text('Сложно')),
            ],
            selected: <Difficulty>{_difficulty},
            onSelectionChanged: (value) =>
                setState(() => _difficulty = value.first),
          ),
        ],
        if (_mode == GameMode.online) ...[
          const SizedBox(height: 14),
          const OnlineSetupView(),
        ],
        if (_mode != GameMode.online) ...[
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: () {
                GameRootScope.of(context).add(
                  GameEvent$Start(
                    mode: _mode,
                    difficulty: _difficulty,
                    names: <String>[player, 'Игрок 2'],
                  ),
                );
                Navigator.pop(context);
              },
              iconAlignment: IconAlignment.end,
              icon: const Icon(LucideIcons.arrowRight, size: 18),
              label: const Text('Начать игру'),
            ),
          ),
        ],
      ],
    );
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
    borderRadius: BorderRadius.circular(10),
    child: Ink(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE8EDFE) : const Color(0xFFF4F5EF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? const Color(0xFF9FB2F4) : const Color(0xFFDCE0D4),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: selected ? AppColors.accent : null),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 1,
            style: TextStyle(
              color: selected ? AppColors.accent : null,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 8),
          ),
        ],
      ),
    ),
  );
}

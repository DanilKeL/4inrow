import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/theme/app_theme.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/leaderboard/bloc/leaderboard_bloc.dart';
import 'package:four3/src/feature/leaderboard/model/leaderboard_player.dart';
import 'package:four3/src/feature/leaderboard/widget/leaderboard_root_scope.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class LeaderboardView extends StatefulWidget {
  const new({super.key});
  @override
  State<LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends State<LeaderboardView> {
  @override
  void initState() {
    super.initState();
    LeaderboardRootScope.of(context).add(const LeaderboardEvent$Load());
  }

  @override
  Widget build(BuildContext context) {
    final LeaderboardBloc bloc = LeaderboardRootScope.of(context);
    final String? username = AccountRootScope.of(context).profile?.username;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.trophy, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Топ 100 · Elo',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
            IconButton.outlined(
              tooltip: 'Обновить рейтинг',
              onPressed: () => bloc.add(const LeaderboardEvent$Load()),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: BlocBuilder<LeaderboardBloc, LeaderboardState>(
            bloc: bloc,
            builder: (context, state) => switch (state) {
              LeaderboardState$Ready(:final players) =>
                players.isEmpty
                    ? const _StateText('В рейтинге пока нет игроков.')
                    : _LeaderboardTable(players: players, username: username),
              LeaderboardState$Failure() => _StateText(
                'Не удалось загрузить рейтинг.',
                action: () => bloc.add(const LeaderboardEvent$Load()),
              ),
              _ => const _StateText('Загрузка рейтинга…'),
            },
          ),
        ),
      ],
    );
  }
}

class _LeaderboardTable extends StatelessWidget {
  const new({required this.players, required this.username});
  final List<LeaderboardPlayer> players;
  final String? username;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFE1E5DC)),
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        const _TableRow(header: true),
        Expanded(
          child: ListView.builder(
            itemCount: players.length,
            itemBuilder: (context, index) => _TableRow(
              player: players[index],
              self: players[index].username == username,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TableRow extends StatelessWidget {
  const new({this.player, this.header = false, this.self = false});
  final LeaderboardPlayer? player;
  final bool header;
  final bool self;

  @override
  Widget build(BuildContext context) => Container(
    height: header ? 38 : 44,
    padding: const EdgeInsets.symmetric(horizontal: 7),
    decoration: BoxDecoration(
      color: header
          ? const Color(0xFFEEF0EA)
          : self
          ? const Color(0xFFEAF0FF)
          : null,
      border: const Border(bottom: BorderSide(color: Color(0xFFE8EBE3))),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 43,
          child: header
              ? const Text('Место', textAlign: TextAlign.center)
              : Center(
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: player!.rank <= 3
                        ? BoxDecoration(
                            color: const Color(0xFFEFE5CC),
                            borderRadius: BorderRadius.circular(9),
                          )
                        : null,
                    child: Text('${player!.rank}'),
                  ),
                ),
        ),
        Expanded(
          flex: 4,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  header ? 'Игрок' : player!.username,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: header ? FontWeight.w600 : FontWeight.w700,
                  ),
                ),
              ),
              if (self) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  color: AppColors.accent,
                  child: const Text(
                    'Вы',
                    style: TextStyle(color: Colors.white, fontSize: 8),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            header ? 'Elo' : '${player!.elo}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: header ? FontWeight.w600 : FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            header ? 'Игры' : '${player!.games}',
            textAlign: TextAlign.right,
          ),
        ),
      ],
    ),
  );
}

class _StateText extends StatelessWidget {
  const new(this.text, {this.action});
  final String text;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: const TextStyle(color: AppColors.muted)),
        if (action != null) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: action,
            child: const Text('Попробовать снова'),
          ),
        ],
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/theme/app_theme.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.trophy, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.leaderboardTop,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton.outlined(
                padding: EdgeInsets.zero,
                tooltip: context.l10n.refreshLeaderboard,
                onPressed: () => bloc.add(const LeaderboardEvent$Load()),
                style: IconButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFDFE3DA)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(LucideIcons.refreshCw, size: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        BlocBuilder<LeaderboardBloc, LeaderboardState>(
          bloc: bloc,
          builder: (context, state) => switch (state) {
            LeaderboardState$Ready(:final players) =>
              players.isEmpty
                  ? _StateText(context.l10n.leaderboardEmpty)
                  : SizedBox(
                      height:
                          ((MediaQuery.sizeOf(context).width <= 650
                                      ? 36.0
                                      : 42.0) *
                                  (players.length + 1))
                              .clamp(84.0, 500.0),
                      child: _LeaderboardTable(
                        players: players,
                        username: username,
                      ),
                    ),
            LeaderboardState$Failure() => _StateText(
              context.l10n.leaderboardFailed,
              action: () => bloc.add(const LeaderboardEvent$Load()),
            ),
            _ => _StateText(context.l10n.leaderboardLoading),
          },
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
              last: index == players.length - 1,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TableRow extends StatelessWidget {
  const new({
    this.player,
    this.header = false,
    this.self = false,
    this.last = false,
  });
  final LeaderboardPlayer? player;
  final bool header;
  final bool self;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width <= 650;
    return Container(
      height: compact ? 36 : 42,
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 14),
      decoration: BoxDecoration(
        color: header
            ? const Color(0xFFEEF0EA)
            : self
            ? const Color(0xFFEAF0FF)
            : null,
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFE8EBE3))),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: AppColors.ink,
          fontFamily: 'Manrope',
          fontSize: header ? (compact ? 10 : 11) : (compact ? 11 : 13),
        ),
        child: Row(
          children: [
            SizedBox(
              width: compact ? 43 : 65,
              child: header
                  ? Text(context.l10n.place, textAlign: TextAlign.center)
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
                      header ? context.l10n.player : player!.username,
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
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        context.l10n.you,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                        ),
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
                header ? context.l10n.rankedGames : '${player!.games}',
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 10),
          OutlinedButton(onPressed: action, child: Text(context.l10n.retry)),
        ],
      ],
    ),
  );
}

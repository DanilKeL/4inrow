import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
    return BlocBuilder<LeaderboardBloc, LeaderboardState>(
      bloc: bloc,
      builder: (context, state) => switch (state) {
        LeaderboardState$Ready(:final players) =>
          players.isEmpty
              ? const Center(child: Text('Рейтинг пока пуст.'))
              : ListView.separated(
                  itemCount: players.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final LeaderboardPlayer player = players[index];
                    return ListTile(
                      leading: SizedBox(
                        width: 36,
                        child: Center(
                          child: player.rank <= 3
                              ? const Icon(LucideIcons.medal)
                              : Text('#${player.rank}'),
                        ),
                      ),
                      title: Text(player.username),
                      subtitle: Text('${player.games} партий'),
                      trailing: Text(
                        '${player.elo}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    );
                  },
                ),
        LeaderboardState$Failure(:final message) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              OutlinedButton(
                onPressed: () => bloc.add(const LeaderboardEvent$Load()),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

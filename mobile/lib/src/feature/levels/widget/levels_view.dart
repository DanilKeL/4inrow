import 'package:flutter/material.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';
import 'package:four3/src/feature/levels/model/game_level.dart';
import 'package:four3/src/feature/levels/service/level_repository.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class LevelsView extends StatefulWidget {
  const new({super.key});

  @override
  State<LevelsView> createState() => _LevelsViewState();
}

class _LevelsViewState extends State<LevelsView> {
  late Future<(List<GameLevel>, Map<int, int>)> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final LevelRepository repository = RootScope.of(context).levelRepository;
    _future = (() async =>
        (await repository.load(), await repository.best()))();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<(List<GameLevel>, Map<int, int>)>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (List<GameLevel> levels, Map<int, int> best) = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '40 задач на тактику. Победите бота за минимальное число своих ходов.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: .92,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: levels.length,
                  itemBuilder: (context, index) {
                    final GameLevel level = levels[index];
                    final int? record = best[level.id];
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        GameRootScope.of(context)
                            .add(GameEvent$StartLevel(level.id));
                        Navigator.pop(context);
                      },
                      child: Ink(
                        decoration: BoxDecoration(
                          color: record == null
                              ? const Color(0xFFF1EEE8)
                              : const Color(0xFFE4EBDD),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x22242321)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    level.id.toString().padLeft(2, '0'),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (record != null)
                                    const Icon(LucideIcons.check, size: 16),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                level.chapter,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                              Text(
                                record == null
                                    ? 'Рекорд: —'
                                    : 'Рекорд: $record',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
}

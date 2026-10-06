import 'package:flutter/material.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/game/bloc/game_event.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';
import 'package:four3/src/feature/levels/domain/model/game_level.dart';
import 'package:four3/src/feature/levels/domain/repository/level_repository.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class LevelsView extends StatefulWidget {
  const new({this.initialId = 1, super.key});
  final int initialId;

  @override
  State<LevelsView> createState() => _LevelsViewState();
}

class _LevelsViewState extends State<LevelsView> {
  late int _page = (widget.initialId - 1) ~/ 8;
  late Future<(List<GameLevel>, Map<int, int>, String)> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final LevelRepository repository = RootScope.of(context).levelRepository;
    final String? owner = AccountRootScope.of(context).profile?.username;
    _future = _load(repository, owner);
  }

  Future<(List<GameLevel>, Map<int, int>, String)> _load(
    LevelRepository repository,
    String? owner,
  ) async {
    final List<GameLevel> levels = await repository.load();
    if (owner == null) return (levels, await repository.best(), '');
    try {
      return (levels, await repository.sync(owner), '');
    } on Exception {
      return (levels, await repository.best(), 'offline');
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<(List<GameLevel>, Map<int, int>, String)>(
    future: _future,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final (List<GameLevel>, Map<int, int>, String) value = snapshot.data!;
      final (List<GameLevel> levels, Map<int, int> best, String syncError) =
          value;
      final List<GameLevel> shown = levels
          .skip(_page * 8)
          .take(8)
          .toList(growable: false);
      final bool landscape =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      final bool short = MediaQuery.sizeOf(context).height <= 500;
      return SizedBox(
        height: landscape && short ? 230 : 395,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!(landscape && short)) ...[
              Text(
                context.l10n.levelsIntro,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    _chapter(context, shown.first.chapter),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  context.l10n.completedProgress(best.length, levels.length),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: landscape ? 4 : 2,
                  childAspectRatio: landscape ? 2.6 : 2.65,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: shown.length,
                itemBuilder: (context, index) {
                  final GameLevel level = shown[index];
                  final int? record = best[level.id];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      GameRootScope.of(context)
                          .add(GameEvent$StartLevel(level.id));
                      Navigator.pop(context);
                    },
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: record == null
                            ? const Color(0xFFF4F5EF)
                            : const Color(0xFFEDF1FB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: record == null
                              ? const Color(0xFFDCDED6)
                              : const Color(0xFFB8C7ED),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Text(
                                level.id.toString().padLeft(2, '0'),
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              if (record != null)
                                const Icon(
                                  LucideIcons.check,
                                  size: 15,
                                  color: AppColors.accent,
                                ),
                            ],
                          ),
                          Text(
                            record == null
                                ? context.l10n.recordEmpty
                                : context.l10n.recordValue(
                                    context.l10n.moves(record),
                                  ),
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PageButton(
                  onPressed: _page == 0 ? null : () => setState(() => _page--),
                  icon: const Icon(LucideIcons.chevronLeft),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('${_page + 1} / ${(levels.length / 8).ceil()}'),
                ),
                _PageButton(
                  onPressed: (_page + 1) * 8 >= levels.length
                      ? null
                      : () => setState(() => _page++),
                  icon: const Icon(LucideIcons.chevronRight),
                ),
              ],
            ),
            if (!(landscape && short))
              Text(
                AccountRootScope.of(context).profile?.username == null
                    ? context.l10n.levelSignInHint
                    : syncError.isNotEmpty
                    ? context.l10n.levelSyncOffline
                    : context.l10n.levelProgressSaved,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
          ],
        ),
      );
    },
  );
}

class _PageButton extends StatelessWidget {
  const new({required this.onPressed, required this.icon});
  final VoidCallback? onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 36,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(40, 36),
        padding: EdgeInsets.zero,
        side: const BorderSide(color: Color(0xFFDCDED6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: icon,
    ),
  );
}

String _chapter(BuildContext context, LevelChapter chapter) =>
    switch (chapter) {
      LevelChapter.firstSteps => context.l10n.chapterFirstSteps,
      LevelChapter.tactics => context.l10n.chapterTactics,
      LevelChapter.combinations => context.l10n.chapterCombinations,
      LevelChapter.counterattack => context.l10n.chapterCounterattack,
      LevelChapter.advanced => context.l10n.chapterAdvanced,
    };

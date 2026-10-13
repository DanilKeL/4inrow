import 'package:flutter/material.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/app_theme/utils/theme_context_extension.dart';
import 'package:four3/src/feature/components/progress/app_circular_progress_indicator.dart';
import 'package:four3/src/feature/game/bloc/game_event.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';
import 'package:four3/src/feature/levels/domain/model/game_level.dart';
import 'package:four3/src/feature/levels/domain/repository/level_repository.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum LevelCardState { available, current, completed }

class LevelsView extends StatefulWidget {
  const new({this.initialId = 1, this.onSignIn, super.key});

  final int initialId;
  final VoidCallback? onSignIn;

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
    if (owner == null) return (levels, await repository.best(null), '');
    try {
      return (levels, await repository.sync(owner), '');
    } on Exception {
      return (levels, await repository.best(owner), 'offline');
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<(List<GameLevel>, Map<int, int>, String)>(
    future: _future,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: AppCircularProgressIndicator());
      }
      final (List<GameLevel> levels, Map<int, int> best, String syncError) =
          snapshot.data!;
      final List<GameLevel> shown = levels
          .skip(_page * 8)
          .take(8)
          .toList(growable: false);
      final int? currentId = levels
          .where((level) => !best.containsKey(level.id))
          .firstOrNull
          ?.id;
      final bool compactLandscape =
          MediaQuery.orientationOf(context) == Orientation.landscape &&
          MediaQuery.sizeOf(context).height <= 500;
      final double textScale = MediaQuery.textScalerOf(context).scale(1);
      final Widget grid = GridView.builder(
        shrinkWrap: !compactLandscape,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: compactLandscape ? 4 : 2,
          mainAxisExtent: (56 + (textScale - 1) * 40).clamp(56, 96),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: shown.length,
        itemBuilder: (context, index) {
          final GameLevel level = shown[index];
          final int? record = best[level.id];
          final LevelCardState state = record != null
              ? LevelCardState.completed
              : level.id == currentId
              ? LevelCardState.current
              : LevelCardState.available;
          return LevelCard(
            level: level,
            record: record,
            state: state,
            onTap: () {
              GameRootScope.of(context).add(GameEvent$StartLevel(level.id));
              Navigator.pop(context);
            },
          );
        },
      );
      return SizedBox(
        height: compactLandscape ? 248 : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compactLandscape) ...[
              Text(
                context.l10n.levelsIntro,
                style: context.textStyle.body.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 18),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    _chapter(context, shown.first.chapter),
                    style: context.textStyle.bodyStrong,
                  ),
                ),
                Text(
                  context.l10n.completedProgress(best.length, levels.length),
                  style: context.textStyle.caption,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (compactLandscape) Expanded(child: grid) else grid,
            if (!compactLandscape) const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PageButton(
                  onPressed: _page == 0 ? null : () => setState(() => _page--),
                  icon: LucideIcons.chevronLeft,
                  label: MaterialLocalizations.of(context).previousPageTooltip,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    context.l10n.pageProgress(
                      _page + 1,
                      (levels.length / 8).ceil(),
                    ),
                    style: context.textStyle.caption,
                  ),
                ),
                _PageButton(
                  onPressed: (_page + 1) * 8 >= levels.length
                      ? null
                      : () => setState(() => _page++),
                  icon: LucideIcons.chevronRight,
                  label: MaterialLocalizations.of(context).nextPageTooltip,
                ),
              ],
            ),
            if (!compactLandscape) ...[
              const SizedBox(height: 16),
              if (AccountRootScope.of(context).profile?.username == null)
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: widget.onSignIn,
                      child: Text(context.l10n.signIn),
                    ),
                    Text(
                      context.l10n.levelSignInHint,
                      style: context.textStyle.caption,
                    ),
                  ],
                )
              else
                Text(
                  syncError.isNotEmpty
                      ? context.l10n.levelSyncOffline
                      : context.l10n.levelProgressSaved,
                  textAlign: TextAlign.center,
                  style: context.textStyle.caption,
                ),
            ],
          ],
        ),
      );
    },
  );
}

class LevelCard extends StatelessWidget {
  const new({
    required this.level,
    required this.state,
    required this.onTap,
    this.record,
    super.key,
  });

  final GameLevel level;
  final int? record;
  final LevelCardState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool highlighted = state == LevelCardState.current;
    final bool completed = state == LevelCardState.completed;
    return Semantics(
      button: true,
      enabled: true,
      selected: highlighted,
      label: context.l10n.levelNumber(level.id),
      value: record == null
          ? context.l10n.recordEmpty
          : context.l10n.recordValue(context.l10n.moves(record!)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: highlighted ? 15.5 : 16,
            vertical: highlighted ? 7.5 : 8,
          ),
          decoration: BoxDecoration(
            color: highlighted
                ? context.colors.accentSubtle
                : completed
                ? const Color(0xFFF1F4EC)
                : context.colors.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              width: highlighted ? 1.5 : 1,
              color: highlighted
                  ? context.colors.accent
                  : context.colors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      level.id.toString().padLeft(2, '0'),
                      style: context.textStyle.title.copyWith(
                        fontSize: 21,
                        height: 24 / 21,
                      ),
                    ),
                    Text(
                      record == null
                          ? context.l10n.recordEmpty
                          : context.l10n.recordValue(
                              context.l10n.moves(record!),
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyle.caption.copyWith(
                        color: context.colors.muted,
                        fontSize: 11,
                        height: 17 / 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (completed)
                Icon(LucideIcons.check, size: 18, color: context.colors.success)
              else if (highlighted)
                Icon(LucideIcons.play, size: 18, color: context.colors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const new({required this.onPressed, required this.icon, required this.label});

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 44,
    child: IconButton.outlined(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
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

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/theme/app_theme.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/common/widget/app_controls.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/match_history/bloc/match_history_bloc.dart';
import 'package:four3/src/feature/match_history/model/match_history_models.dart';
import 'package:four3/src/feature/match_history/widget/match_history_root_scope.dart';
import 'package:intl/intl.dart';

class MatchHistoryView extends StatefulWidget {
  const new({this.onSignIn, super.key});
  final VoidCallback? onSignIn;

  @override
  State<MatchHistoryView> createState() => _MatchHistoryViewState();
}

class _MatchHistoryViewState extends State<MatchHistoryView> {
  int _page = 0;
  String? _editing;
  final _title = TextEditingController();

  @override
  void initState() {
    super.initState();
    MatchHistoryRootScope.of(context).add(const MatchHistoryEvent$Load());
  }

  @override
  Widget build(BuildContext context) {
    final MatchHistoryBloc bloc = MatchHistoryRootScope.of(context);
    return BlocBuilder<MatchHistoryBloc, MatchHistoryState>(
      bloc: bloc,
      builder: (context, state) => switch (state) {
        MatchHistoryState$Loading() || MatchHistoryState$Initial() => Center(
          child: Text(
            context.l10n.historyLoading,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ),
        MatchHistoryState$Guest() => _Guest(onSignIn: widget.onSignIn),
        MatchHistoryState$Failure(:final message) => _Failure(
          message: message,
          retry: () => bloc.add(const MatchHistoryEvent$Load()),
        ),
        MatchHistoryState$Ready(:final data) => _history(context, bloc, data),
      },
    );
  }

  Widget _history(
    BuildContext context,
    MatchHistoryBloc bloc,
    MatchHistorySnapshot data,
  ) {
    final int pages = (data.matches.length / 2).ceil().clamp(1, 999);
    final int page = _page.clamp(0, pages - 1);
    final List<SavedMatch> shown = data.matches
        .skip(page * 2)
        .take(2)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: context.l10n.ratingPrefix,
            children: [
              TextSpan(
                text: '${data.rating.points}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(text: '. ${context.l10n.lastFiftyMatches}'),
            ],
          ),
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Stat(context.l10n.matchesStat, data.statistics.total),
            _Stat(context.l10n.winsStat, data.statistics.wins),
            _Stat(context.l10n.lossesStat, data.statistics.losses),
            _Stat(context.l10n.drawsStat, data.statistics.draws),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    context.l10n.historyEmpty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                )
              : ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => ExpandedMatchCard(
                    match: shown[index],
                    editing: _editing == shown[index].id,
                    title: _title,
                    onWatch: () {
                      GameRootScope.of(context).add(
                        GameEvent$ReplaySaved(
                          snapshot: shown[index].game,
                          names: shown[index].names,
                        ),
                      );
                      Navigator.pop(context);
                    },
                    onEdit: () {
                      if (_editing == shown[index].id) {
                        bloc.add(
                          MatchHistoryEvent$Rename(
                            shown[index].id,
                            _title.text,
                          ),
                        );
                        setState(() => _editing = null);
                      } else {
                        _title.text = shown[index].title.isEmpty
                            ? context.l10n.matchTitle
                            : shown[index].title;
                        setState(() => _editing = shown[index].id);
                      }
                    },
                    onRemove: () =>
                        bloc.add(MatchHistoryEvent$Remove(shown[index].id)),
                  ),
                ),
        ),
        if (data.matches.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton(
                onPressed: page == 0
                    ? null
                    : () => setState(() => _page = page - 1),
                style: _smallButtonStyle,
                child: Text(context.l10n.back),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('${page + 1} / $pages'),
              ),
              OutlinedButton(
                onPressed: page + 1 == pages
                    ? null
                    : () => setState(() => _page = page + 1),
                style: _smallButtonStyle,
                child: Text(context.l10n.next),
              ),
            ],
          ),
      ],
    );
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }
}

class _Stat extends StatelessWidget {
  const new(this.label, this.value);
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF0E7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF60675E), fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

class ExpandedMatchCard extends StatelessWidget {
  const new({
    required this.match,
    required this.editing,
    required this.title,
    required this.onWatch,
    required this.onEdit,
    required this.onRemove,
    super.key,
  });
  final SavedMatch match;
  final bool editing;
  final TextEditingController title;
  final VoidCallback onWatch;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final Player? winner = match.game.winner;
    final String mode = switch (match.mode) {
      'ai' => context.l10n.versusAi,
      'online' => context.l10n.online,
      _ => context.l10n.twoPlayers,
    };
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(match.date);
    final String formattedDate = DateFormat.yMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(date);
    final String result = winner == null
        ? context.l10n.draw
        : context.l10n.winnerName(match.names[winner.index]);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (editing)
            AppTextField(
              controller: title,
              autofocus: true,
              maxLength: 80,
              semanticLabel: context.l10n.matchTitleLabel,
              fontSize: 14,
              onSubmitted: (_) => onEdit(),
            )
          else
            Text(
              match.title.isEmpty ? context.l10n.matchTitle : match.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          Text(
            context.l10n.matchSummary(
              formattedDate,
              mode,
              context.l10n.moves(match.game.history.length),
            ),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              height: 1.6,
            ),
          ),
          Text(
            '$result${match.ratingChange == null ? '' : ' · ${match.ratingChange! >= 0 ? '+' : ''}${match.ratingChange} Elo'}${match.endReason == null ? '' : ' · ${context.l10n.earlyFinish}'}',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton(
                onPressed: onWatch,
                style: _smallButtonStyle.copyWith(
                  foregroundColor: const WidgetStatePropertyAll(
                    AppColors.accent,
                  ),
                ),
                child: Text(context.l10n.watch),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: onEdit,
                style: _smallButtonStyle,
                child: Text(
                  editing ? context.l10n.save : context.l10n.titleAction,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Tooltip(
                  message: context.l10n.removeHistoryHint,
                  child: OutlinedButton(
                    onPressed: onRemove,
                    style: _smallButtonStyle,
                    child: Text(context.l10n.delete),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Guest extends StatelessWidget {
  const new({required this.onSignIn});
  final VoidCallback? onSignIn;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.l10n.historyGuestHint,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 11,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: onSignIn,
        child: Text(context.l10n.signInOrRegister),
      ),
    ],
  );
}

final ButtonStyle _smallButtonStyle = OutlinedButton.styleFrom(
  minimumSize: const Size(0, 36),
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  side: const BorderSide(color: Color(0xFFD9DFD0)),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  textStyle: const TextStyle(fontSize: 11),
);

class _Failure extends StatelessWidget {
  const new({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        OutlinedButton(onPressed: retry, child: Text(context.l10n.retryShort)),
      ],
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/app_theme/utils/theme_context_extension.dart';
import 'package:four3/src/feature/components/progress/app_circular_progress_indicator.dart';
import 'package:four3/src/feature/daily/bloc/daily_bloc.dart';
import 'package:four3/src/feature/daily/bloc/daily_event.dart';
import 'package:four3/src/feature/daily/bloc/daily_state.dart';
import 'package:four3/src/feature/daily/domain/model/daily_models.dart';
import 'package:four3/src/feature/daily/widget/daily_root_scope.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/bloc/game_event.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DailyChallengeView extends StatefulWidget {
  const new({this.initialResults = false, super.key});

  final bool initialResults;

  @override
  State<DailyChallengeView> createState() => _DailyChallengeViewState();
}

class _DailyChallengeViewState extends State<DailyChallengeView> {
  late bool _results = widget.initialResults;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    DailyRootScope.of(context).add(const DailyEvent$Load());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {});
      final DailyBloc bloc = DailyRootScope.of(context);
      if (bloc.state.snapshot?.isCurrent == false && !bloc.state.loading) {
        bloc.add(const DailyEvent$Load());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final DailyBloc bloc = DailyRootScope.of(context);
    return BlocBuilder<DailyBloc, DailyState>(
      bloc: bloc,
      builder: (context, state) {
        final DailySnapshot? snapshot = state.snapshot;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _DailyTabs(
              results: _results,
              onChanged: (value) => setState(() => _results = value),
            ),
            const SizedBox(height: 18),
            if (state.loading && snapshot == null)
              const Center(child: AppCircularProgressIndicator())
            else if (state.error.isNotEmpty)
              _DailyError(
                message: state.error == 'offline' ? null : state.error,
                onRetry: () => bloc.add(const DailyEvent$Load()),
              )
            else if (snapshot == null)
              _DailyError(onRetry: () => bloc.add(const DailyEvent$Load()))
            else ...<Widget>[
              _DailyHeading(snapshot: snapshot),
              const SizedBox(height: 16),
              if (_results)
                _DailyLeaderboard(snapshot: snapshot)
              else
                _DailyTask(
                  snapshot: snapshot,
                  onStart: state.loading
                      ? null
                      : () => _start(context, snapshot.challenge),
                ),
            ],
          ],
        );
      },
    );
  }

  void _start(BuildContext context, DailyChallenge challenge) {
    final GameBloc game = GameRootScope.of(context);
    Navigator.pop(context);
    game.add(GameEvent$StartDaily(challenge));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _DailyTabs extends StatelessWidget {
  const new({required this.results, required this.onChanged});

  final bool results;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF1EB),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: <Widget>[
        Expanded(
          child: _DailyTab(
            label: context.l10n.dailyTaskTab,
            selected: !results,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _DailyTab(
            label: context.l10n.dailyResultsTab,
            selected: results,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    ),
  );
}

class _DailyTab extends StatelessWidget {
  const new({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(7),
    child: Ink(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        boxShadow: selected
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x0926331A),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: context.textStyle.caption.copyWith(
          color: selected ? AppColors.ink : AppColors.muted,
        ),
      ),
    ),
  );
}

class _DailyHeading extends StatelessWidget {
  const new({required this.snapshot});

  final DailySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final DateTime date = DateTime.parse(snapshot.challenge.date);
    final Duration remaining = Duration(
      milliseconds:
          (snapshot.challenge.expiresAt -
                  DateTime.now().millisecondsSinceEpoch -
                  snapshot.serverOffset)
              .clamp(0, 86400000),
    );
    return Row(
      children: <Widget>[
        const Icon(LucideIcons.calendarDays, size: 17),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            DateFormat.MMMMd(Localizations.localeOf(context).toLanguageTag())
                .format(date),
            style: context.textStyle.captionStrong,
          ),
        ),
        Text(
          context.l10n.dailyChangesIn(
            remaining.inHours,
            remaining.inMinutes.remainder(60),
          ),
          style: context.textStyle.micro.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

class _DailyTask extends StatelessWidget {
  const new({required this.snapshot, required this.onStart});

  final DailySnapshot snapshot;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(
        context.l10n.dailyGoal,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -.5,
        ),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F5EF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                context.l10n.dailyPersonalBest,
                style: context.textStyle.caption.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ),
            Text(
              snapshot.ownBest == null
                  ? '—'
                  : context.l10n.moves(snapshot.ownBest!),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: snapshot.isCurrent ? onStart : null,
          icon: const Icon(LucideIcons.play, size: 18),
          label: Text(context.l10n.dailyPlay),
        ),
      ),
    ],
  );
}

class _DailyLeaderboard extends StatelessWidget {
  const new({required this.snapshot});

  final DailySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final DailyBloc bloc = DailyRootScope.of(context);
    if (snapshot.leaderboard.isEmpty) {
      return Column(
        children: <Widget>[
          _DailyResultsHeader(
            loading: bloc.state.loading,
            onRefresh: () => bloc.add(const DailyEvent$Load()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              context.l10n.dailyNoResults,
              textAlign: TextAlign.center,
              style: context.textStyle.caption.copyWith(color: AppColors.muted),
            ),
          ),
        ],
      );
    }
    final String? owner = AccountRootScope.of(context).profile?.username;
    return Column(
      children: <Widget>[
        _DailyResultsHeader(
          loading: bloc.state.loading,
          onRefresh: () => bloc.add(const DailyEvent$Load()),
        ),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(maxHeight: 310),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE0E3DA)),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const _DailyTableRow(header: true),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: snapshot.leaderboard.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final DailyStanding row = snapshot.leaderboard[index];
                    return _DailyTableRow(
                      standing: row,
                      self: row.username == owner,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DailyResultsHeader extends StatelessWidget {
  const new({required this.loading, required this.onRefresh});

  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const Icon(LucideIcons.trophy, size: 17),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          context.l10n.dailyResultsTitle,
          style: context.textStyle.captionStrong,
        ),
      ),
      IconButton.outlined(
        tooltip: context.l10n.dailyRefreshResults,
        onPressed: loading ? null : onRefresh,
        style: IconButton.styleFrom(fixedSize: const Size.square(36)),
        icon: const Icon(LucideIcons.refreshCw, size: 16),
      ),
    ],
  );
}

class _DailyTableRow extends StatelessWidget {
  const new({this.standing, this.self = false, this.header = false});

  final DailyStanding? standing;
  final bool self;
  final bool header;

  @override
  Widget build(BuildContext context) => Container(
    color: header
        ? const Color(0xFFF4F6EF)
        : self
        ? const Color(0xFFEEF2FF)
        : Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 50,
          child: Text(
            header ? context.l10n.dailyPlace : '${standing!.rank}',
            style: header ? context.textStyle.micro : null,
          ),
        ),
        Expanded(
          child: Text(
            header ? context.l10n.dailyPlayer : standing!.username,
            overflow: TextOverflow.ellipsis,
            style: header
                ? context.textStyle.micro
                : self
                ? context.textStyle.captionStrong
                : null,
          ),
        ),
        Text(
          header ? context.l10n.dailyMovesHeader : '${standing!.moves}',
          style: header
              ? context.textStyle.micro
              : context.textStyle.captionStrong,
        ),
      ],
    ),
  );
}

class _DailyError extends StatelessWidget {
  const new({required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text(
        message?.isNotEmpty == true ? message! : context.l10n.dailyLoadFailed,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retryShort)),
    ],
  );
}

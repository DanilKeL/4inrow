import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/domain/model/account_profile.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/components/fields/app_text_field.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_bloc.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_event.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_state.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_status.dart';
import 'package:four3/src/feature/matchmaking/widget/matchmaking_root_scope.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class OnlineSetupView extends StatefulWidget {
  const new({this.quickOnly = false, this.onQuickStart, super.key});

  final bool quickOnly;
  final VoidCallback? onQuickStart;

  @override
  State<OnlineSetupView> createState() => _OnlineSetupViewState();
}

class _OnlineSetupViewState extends State<OnlineSetupView> {
  final _code = TextEditingController();
  late final MatchmakingBloc _bloc;
  late final Timer _clock;
  bool _handingOffQuickSearch = false;

  @override
  void initState() {
    super.initState();
    _bloc = MatchmakingRootScope.of(context);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _bloc.state is MatchmakingState$Found) setState(() {});
    });
  }

  @override
  void dispose() {
    if (!_handingOffQuickSearch &&
        _bloc.state is! MatchmakingState$Initial &&
        _bloc.state is! MatchmakingState$Idle &&
        _bloc.state is! MatchmakingState$Match) {
      _bloc.add(const MatchmakingEvent$Cancel());
    }
    _clock.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MatchmakingBloc bloc = _bloc;
    final AccountProfile? profile = AccountRootScope.of(context).profile;
    final String name = profile?.displayName ?? context.l10n.player;
    final bool signedIn = profile?.username != null;
    return BlocConsumer<MatchmakingBloc, MatchmakingState>(
      bloc: bloc,
      listener: (context, state) {
        if (state is MatchmakingState$Match && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) => switch (state) {
        MatchmakingState$Connecting(:final reconnecting)
            when widget.quickOnly =>
          _QuickSearching(
            signedIn: signedIn,
            reconnecting: reconnecting,
            onCancel: () => _cancelAndClose(context, bloc),
          ),
        MatchmakingState$Connecting() => _Setup(
          code: _code,
          connecting: true,
          onCreate: () {},
          onJoin: () {},
          onFind: _startQuickSearch,
        ),
        MatchmakingState$Searching() => _QuickSearching(
          signedIn: signedIn,
          onCancel: () => _cancelAndClose(context, bloc),
        ),
        MatchmakingState$Found(
          :final opponent,
          :final rating,
          :final rated,
          :final accepted,
          :final deadline,
        ) =>
          _QuickFound(
            opponent: opponent,
            rating: rating,
            rated: rated,
            accepted: accepted,
            seconds: _secondsLeft(deadline),
            onAccept: () => bloc.add(const MatchmakingEvent$Accept()),
            onDecline: () {
              bloc.add(const MatchmakingEvent$Decline());
              Navigator.maybePop(context);
            },
          ),
        MatchmakingState$Failure(:final message, :final failure)
            when widget.quickOnly =>
          _QuickFailure(
            message: _failureText(context, message, failure),
            onRetry: () => bloc.add(MatchmakingEvent$Find(name)),
            onMenu: () => _cancelAndClose(context, bloc),
          ),
        MatchmakingState$Failure(:final message, :final failure) => _Setup(
          code: _code,
          error: _failureText(context, message, failure),
          onCreate: () => bloc.add(MatchmakingEvent$Create(name)),
          onJoin: () => bloc.add(MatchmakingEvent$Join(name, _code.text)),
          onFind: widget.onQuickStart == null
              ? () => bloc.add(MatchmakingEvent$Find(name))
              : _startQuickSearch,
        ),
        _ when widget.quickOnly => _QuickSearching(
          signedIn: signedIn,
          onCancel: () => _cancelAndClose(context, bloc),
        ),
        _ => _Setup(
          code: _code,
          onCreate: () => bloc.add(MatchmakingEvent$Create(name)),
          onJoin: () => bloc.add(MatchmakingEvent$Join(name, _code.text)),
          onFind: widget.onQuickStart == null
              ? () => bloc.add(MatchmakingEvent$Find(name))
              : _startQuickSearch,
        ),
      },
    );
  }

  void _cancelAndClose(BuildContext context, MatchmakingBloc bloc) {
    bloc.add(const MatchmakingEvent$Cancel());
    Navigator.maybePop(context);
  }

  void _startQuickSearch() {
    _handingOffQuickSearch = true;
    widget.onQuickStart?.call();
  }
}

String _failureText(
  BuildContext context,
  String remoteMessage,
  MatchmakingFailure? failure,
) {
  if (remoteMessage.isNotEmpty) return remoteMessage;
  return switch (failure) {
    MatchmakingFailure.invalidCode => context.l10n.enterFiveLetterCode,
    MatchmakingFailure.moveNotSent => context.l10n.moveNotSent,
    MatchmakingFailure.invalidServerResponse =>
      context.l10n.invalidServerResponse,
    MatchmakingFailure.connectionLost => context.l10n.connectionLost,
    MatchmakingFailure.lobbyClosed => context.l10n.connectionClosed,
    MatchmakingFailure.generic || null => context.l10n.matchSearchFailed,
  };
}

int _secondsLeft(int deadline) =>
    ((deadline - DateTime.now().millisecondsSinceEpoch) / 1000).ceil().clamp(
      0,
      999,
    );

class _Setup extends StatelessWidget {
  const new({
    required this.code,
    required this.onCreate,
    required this.onJoin,
    required this.onFind,
    this.error,
    this.connecting = false,
  });
  final TextEditingController code;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onFind;
  final String? error;
  final bool connecting;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (error case final value?) ...[
        Text(
          value,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 6),
      ],
      OutlinedButton(
        onPressed: connecting ? null : onFind,
        child: Text(context.l10n.findRankedOpponent),
      ),
      const SizedBox(height: 6),
      FilledButton.icon(
        onPressed: connecting ? null : onCreate,
        iconAlignment: IconAlignment.end,
        icon: const Icon(LucideIcons.arrowRight, size: 18),
        label: Text(
          connecting ? context.l10n.connecting : context.l10n.createLobby,
        ),
      ),
      const SizedBox(height: 6),
      AppTextField(
        controller: code,
        label: context.l10n.lobbyCode,
        hintText: 'ABCDE',
        textCapitalization: TextCapitalization.characters,
        maxLength: 5,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
          _UpperCaseFormatter(),
        ],
        fontSize: 23,
        letterSpacing: 7,
        onSubmitted: (_) => onJoin(),
      ),
      const SizedBox(height: 6),
      ListenableBuilder(
        listenable: code,
        builder: (context, _) => OutlinedButton(
          onPressed: connecting || !RegExp(r'^[A-Z]{5}$').hasMatch(code.text)
              ? null
              : onJoin,
          child: Text(context.l10n.joinLobby),
        ),
      ),
    ],
  );
}

final class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

class _QuickSearching extends StatelessWidget {
  const new({
    required this.signedIn,
    required this.onCancel,
    this.reconnecting = false,
  });
  final bool signedIn;
  final VoidCallback onCancel;
  final bool reconnecting;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 12, 0, 2),
    child: Column(
      children: [
        const Icon(LucideIcons.search, size: 32, color: Color(0xFF2955E7)),
        const SizedBox(height: 14),
        Text(
          reconnecting
              ? context.l10n.restoringSearch
              : context.l10n.searchingOpponent,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        Text(
          reconnecting
              ? context.l10n.searchReconnectHint
              : signedIn
              ? context.l10n.ratedSearchHint
              : context.l10n.guestSearchHint,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF7A8073),
            fontSize: 11,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onCancel,
            child: Text(context.l10n.cancelSearch),
          ),
        ),
      ],
    ),
  );
}

class _QuickFound extends StatelessWidget {
  const new({
    required this.opponent,
    required this.rating,
    required this.rated,
    required this.accepted,
    required this.seconds,
    required this.onAccept,
    required this.onDecline,
  });
  final String opponent;
  final int? rating;
  final bool rated;
  final bool accepted;
  final int seconds;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 12, 0, 2),
    child: Column(
      children: [
        const Icon(LucideIcons.usersRound, size: 32, color: AppColors.accent),
        const SizedBox(height: 14),
        Text(
          context.l10n.opponentFound(opponent),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          rating == null
              ? context.l10n.guestUnratedGame
              : '${context.l10n.opponentRating(rating!)} · ${rated ? context.l10n.ratedLabel : context.l10n.unratedMeetingLimit}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 14),
        Text(
          rated
              ? context.l10n.confirmRatedMatch(seconds)
              : context.l10n.confirmMatch(seconds),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF7A8073),
            fontSize: 11,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: accepted || seconds == 0 ? null : onAccept,
            iconAlignment: IconAlignment.end,
            icon: accepted
                ? const SizedBox.shrink()
                : const Icon(LucideIcons.arrowRight, size: 18),
            label: Text(
              accepted
                  ? context.l10n.waitingMatchConfirmation
                  : context.l10n.acceptMatch,
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onDecline,
            child: Text(context.l10n.refuse),
          ),
        ),
      ],
    ),
  );
}

class _QuickFailure extends StatelessWidget {
  const new({
    required this.message,
    required this.onRetry,
    required this.onMenu,
  });
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        message.isEmpty ? context.l10n.matchSearchFailed : message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.danger, fontSize: 12),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: onRetry,
        iconAlignment: IconAlignment.end,
        icon: const Icon(LucideIcons.arrowRight, size: 18),
        label: Text(context.l10n.searchAgain),
      ),
      const SizedBox(height: 6),
      OutlinedButton(onPressed: onMenu, child: Text(context.l10n.toMainMenu)),
    ],
  );
}

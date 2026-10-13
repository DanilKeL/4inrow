import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/domain/model/account_profile.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/app_theme/utils/theme_context_extension.dart';
import 'package:four3/src/feature/components/buttons/app_action_button.dart';
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
  _PendingAction? _pending;
  int? _pendingStartedAt;

  @override
  void initState() {
    super.initState();
    _bloc = MatchmakingRootScope.of(context);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          (_bloc.state is MatchmakingState$Found ||
              _bloc.state is MatchmakingState$Searching ||
              _bloc.state is MatchmakingState$Connecting)) {
        setState(() {});
      }
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
          signedIn: signedIn,
          pending: _pending,
          slow: shouldShowMatchmakingCancel(_pendingStartedAt),
          onCancel: () => bloc.add(const MatchmakingEvent$Cancel()),
          onCreate: () => _start(_PendingAction.create, name),
          onJoin: () => _start(_PendingAction.join, name),
          onFind: () => _start(_PendingAction.find, name),
        ),
        MatchmakingState$Searching(:final startedAt) => _QuickSearching(
          signedIn: signedIn,
          elapsed: Duration(
            milliseconds: DateTime.now().millisecondsSinceEpoch - startedAt,
          ),
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
          signedIn: signedIn,
          error: _failureText(context, message, failure),
          failed: _pending,
          onCreate: () => _start(_PendingAction.create, name),
          onJoin: () => _start(_PendingAction.join, name),
          onFind: () => _start(_PendingAction.find, name),
        ),
        _ when widget.quickOnly => _QuickSearching(
          signedIn: signedIn,
          onCancel: () => _cancelAndClose(context, bloc),
        ),
        _ => _Setup(
          code: _code,
          signedIn: signedIn,
          onCreate: () => _start(_PendingAction.create, name),
          onJoin: () => _start(_PendingAction.join, name),
          onFind: () => _start(_PendingAction.find, name),
        ),
      },
    );
  }

  void _cancelAndClose(BuildContext context, MatchmakingBloc bloc) {
    bloc.add(const MatchmakingEvent$Cancel());
    Navigator.maybePop(context);
  }

  void _start(_PendingAction action, String name) {
    setState(() {
      _pending = action;
      _pendingStartedAt = DateTime.now().millisecondsSinceEpoch;
    });
    if (action == _PendingAction.find && widget.onQuickStart != null) {
      _handingOffQuickSearch = true;
      widget.onQuickStart!.call();
      return;
    }
    _bloc.add(switch (action) {
      _PendingAction.create => MatchmakingEvent$Create(name),
      _PendingAction.join => MatchmakingEvent$Join(name, _code.text),
      _PendingAction.find => MatchmakingEvent$Find(name),
    });
  }
}

enum _PendingAction { find, create, join }

String _failureText(
  BuildContext context,
  String remoteMessage,
  MatchmakingFailure? failure,
) {
  if (remoteMessage.isNotEmpty) return remoteMessage;
  return switch (failure) {
    MatchmakingFailure.invalidCode => context.l10n.enterFiveLetterCode,
    MatchmakingFailure.roomNotFound => context.l10n.roomNotFound,
    MatchmakingFailure.roomFull => context.l10n.roomFull,
    MatchmakingFailure.matchExpired => context.l10n.matchExpired,
    MatchmakingFailure.accountBusy => context.l10n.accountBusy,
    MatchmakingFailure.alreadyMatching => context.l10n.alreadyMatching,
    MatchmakingFailure.serverFull => context.l10n.serverFull,
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
    required this.signedIn,
    required this.onCreate,
    required this.onJoin,
    required this.onFind,
    this.error,
    this.pending,
    this.failed,
    this.slow = false,
    this.onCancel,
  });
  final TextEditingController code;
  final bool signedIn;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onFind;
  final String? error;
  final _PendingAction? pending;
  final _PendingAction? failed;
  final bool slow;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        signedIn ? context.l10n.rankedGame : context.l10n.quickGame,
        style: context.textStyle.bodyStrong,
      ),
      const SizedBox(height: 4),
      Text(
        signedIn
            ? context.l10n.rankedGameDescription
            : context.l10n.quickGameDescription,
        style: context.textStyle.caption.copyWith(color: context.colors.muted),
      ),
      const SizedBox(height: 12),
      AppActionButton(
        onPressed: pending == null ? onFind : null,
        loading: pending == _PendingAction.find,
        label: pending == _PendingAction.find
            ? context.l10n.searchingShort
            : context.l10n.findOpponent,
      ),
      if (error != null && failed == _PendingAction.find)
        _ActionError(message: error!, onRetry: onFind),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: Divider(color: context.colors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(context.l10n.or, style: context.textStyle.caption),
          ),
          Expanded(child: Divider(color: context.colors.border)),
        ],
      ),
      const SizedBox(height: 12),
      AppActionButton(
        style: AppActionStyle.secondary,
        onPressed: pending == null ? onCreate : null,
        loading: pending == _PendingAction.create,
        label: pending == _PendingAction.create
            ? context.l10n.creatingRoom
            : context.l10n.createLobby,
      ),
      if (error != null && failed == _PendingAction.create)
        _ActionError(message: error!, onRetry: onCreate),
      const SizedBox(height: 20),
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
        fontFamily: 'monospace',
        letterSpacing: 2,
        enabled: pending == null,
        onSubmitted: (_) {
          if (RegExp(r'^[A-Z]{5}$').hasMatch(code.text)) onJoin();
        },
      ),
      const SizedBox(height: 8),
      ListenableBuilder(
        listenable: code,
        builder: (context, _) => AppActionButton(
          style: AppActionStyle.secondary,
          loading: pending == _PendingAction.join,
          onPressed:
              pending != null || !RegExp(r'^[A-Z]{5}$').hasMatch(code.text)
              ? null
              : onJoin,
          label: pending == _PendingAction.join
              ? context.l10n.joiningRoom
              : context.l10n.joinLobby,
        ),
      ),
      if (error != null && failed == _PendingAction.join)
        _ActionError(message: error!, onRetry: onJoin),
      if (error != null && failed == null)
        _ActionError(message: error!, onRetry: onFind),
      if (slow && onCancel != null) ...[
        const SizedBox(height: 8),
        AppActionButton(
          style: AppActionStyle.text,
          compact: true,
          onPressed: onCancel,
          label: context.l10n.cancel,
        ),
      ],
    ],
  );
}

class _ActionError extends StatelessWidget {
  const new({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            message,
            style: context.textStyle.caption.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
      ],
    ),
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
    this.elapsed = Duration.zero,
    this.reconnecting = false,
  });
  final bool signedIn;
  final VoidCallback onCancel;
  final bool reconnecting;
  final Duration elapsed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Column(
      children: [
        const QuickSearchOrbitIcon(),
        const SizedBox(height: 14),
        Text(
          reconnecting
              ? context.l10n.restoringSearch
              : context.l10n.searchingOpponent,
          style: context.textStyle.headline,
        ),
        const SizedBox(height: 6),
        Text(
          reconnecting
              ? context.l10n.searchReconnectHint
              : signedIn
              ? context.l10n.ratedSearchHint
              : context.l10n.guestSearchHint,
          textAlign: TextAlign.center,
          style: context.textStyle.caption.copyWith(
            color: const Color(0xFF7A8073),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          formatMatchmakingElapsed(elapsed),
          style: context.textStyle.bodyStrong.copyWith(
            color: context.colors.accent,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: AppActionButton(
            style: AppActionStyle.secondary,
            onPressed: onCancel,
            label: context.l10n.cancelSearch,
          ),
        ),
      ],
    ),
  );
}

String formatMatchmakingElapsed(Duration elapsed) {
  final int seconds = elapsed.inSeconds.clamp(0, 99 * 60 + 59);
  final String minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  final String remainder = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$remainder';
}

bool shouldShowMatchmakingCancel(int? startedAt, {int? now}) =>
    startedAt != null &&
    (now ?? DateTime.now().millisecondsSinceEpoch) - startedAt >= 9000;

class QuickSearchOrbitIcon extends StatefulWidget {
  const new({super.key});

  @override
  State<QuickSearchOrbitIcon> createState() => _QuickSearchOrbitIconState();
}

class _QuickSearchOrbitIconState extends State<QuickSearchOrbitIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool _disabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool disabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _disabled = disabled;
    if (disabled) {
      _orbit
        ..stop()
        ..value = 0;
    } else if (!_orbit.isAnimating) {
      _orbit.repeat();
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 48,
    child: Center(
      child: AnimatedBuilder(
        animation: _orbit,
        builder: (context, child) {
          final double angle = _orbit.value * math.pi * 2;
          return Transform.translate(
            key: const ValueKey('quick-search-orbit'),
            offset: _disabled
                ? Offset.zero
                : Offset(math.cos(angle) * 6, math.sin(angle) * 6),
            child: child,
          );
        },
        child: const Icon(
          LucideIcons.search,
          size: 32,
          color: Color(0xFF2955E7),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }
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
          style: context.textStyle.headline,
        ),
        const SizedBox(height: 8),
        Text(
          rating == null
              ? context.l10n.guestUnratedGame
              : '${context.l10n.opponentRating(rating!)} · ${rated ? context.l10n.ratedLabel : context.l10n.unratedMeetingLimit}',
          textAlign: TextAlign.center,
          style: context.textStyle.caption.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: 14),
        Text(
          rated
              ? context.l10n.confirmRatedMatch(seconds)
              : context.l10n.confirmMatch(seconds),
          textAlign: TextAlign.center,
          style: context.textStyle.caption.copyWith(
            color: const Color(0xFF7A8073),
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
        style: context.textStyle.caption.copyWith(
          color: AppColors.danger,
          fontSize: 12,
        ),
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

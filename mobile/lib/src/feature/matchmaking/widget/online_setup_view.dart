import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/theme/app_theme.dart';
import 'package:four3/src/common/widget/app_controls.dart';
import 'package:four3/src/feature/account/model/account_profile.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_bloc.dart';
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
    final String name = profile?.displayName ?? 'Игрок';
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
        MatchmakingState$Failure(:final message) when widget.quickOnly =>
          _QuickFailure(
            message: message,
            onRetry: () => bloc.add(MatchmakingEvent$Find(name)),
            onMenu: () => _cancelAndClose(context, bloc),
          ),
        MatchmakingState$Failure(:final message) => _Setup(
          code: _code,
          error: message,
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
        child: const Text('Рейтинговая игра — найти соперника'),
      ),
      const SizedBox(height: 6),
      FilledButton.icon(
        onPressed: connecting ? null : onCreate,
        iconAlignment: IconAlignment.end,
        icon: const Icon(LucideIcons.arrowRight, size: 18),
        label: Text(connecting ? 'Подключаемся…' : 'Создать лобби'),
      ),
      const SizedBox(height: 6),
      AppTextField(
        controller: code,
        label: 'Код лобби',
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
          child: const Text('Войти в лобби'),
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
          reconnecting ? 'Восстанавливаем поиск…' : 'Ищем соперника…',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        Text(
          reconnecting
              ? 'Соединение прервалось. Поиск продолжится автоматически после подключения.'
              : '${signedIn ? 'Рейтинговый поиск среди аккаунтов.' : 'Поиск среди гостей, без рейтинга.'} На подтверждение — 15 секунд.',
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
            child: const Text('Отменить поиск'),
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
          'Соперник найден: $opponent',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          rating == null
              ? 'Гостевая игра без рейтинга'
              : 'Рейтинг соперника: $rating · ${rated ? 'На рейтинг' : 'Без очков: лимит встреч'}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 14),
        Text(
          'Подтвердите игру за $seconds сек. Матч начнётся, когда согласитесь оба.${rated ? ' На ход — 90 сек. Выход — поражение.' : ''}',
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
              accepted ? 'Ждём подтверждения соперника…' : 'Принять матч',
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onDecline,
            child: const Text('Отказаться'),
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
        message.isEmpty ? 'Не удалось найти игру.' : message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.danger, fontSize: 12),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: onRetry,
        iconAlignment: IconAlignment.end,
        icon: const Icon(LucideIcons.arrowRight, size: 18),
        label: const Text('Искать снова'),
      ),
      const SizedBox(height: 6),
      OutlinedButton(onPressed: onMenu, child: const Text('В главное меню')),
    ],
  );
}

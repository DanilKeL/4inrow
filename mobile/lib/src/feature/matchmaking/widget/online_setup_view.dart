import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_bloc.dart';
import 'package:four3/src/feature/matchmaking/widget/matchmaking_root_scope.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class OnlineSetupView extends StatefulWidget {
  const new({super.key});

  @override
  State<OnlineSetupView> createState() => _OnlineSetupViewState();
}

class _OnlineSetupViewState extends State<OnlineSetupView> {
  final _code = TextEditingController();
  late final MatchmakingBloc _bloc;
  late final Timer _clock;

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
    if (_bloc.state is! MatchmakingState$Initial &&
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
    final String name =
        AccountRootScope.of(context).profile?.displayName ?? 'Игрок';
    return BlocConsumer<MatchmakingBloc, MatchmakingState>(
      bloc: bloc,
      listener: (context, state) {
        if (state is MatchmakingState$Match && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) => switch (state) {
        MatchmakingState$Connecting() => const _Status(
          icon: LucideIcons.loaderCircle,
          title: 'Подключаемся…',
          subtitle: 'Проверяем соединение с сервером.',
        ),
        MatchmakingState$Searching() => _Status(
          icon: LucideIcons.search,
          title: 'Ищем соперника',
          subtitle: 'Поиск сохранится при кратком сворачивании приложения.',
          action: OutlinedButton(
            onPressed: () => bloc.add(const MatchmakingEvent$Cancel()),
            child: const Text('Отменить поиск'),
          ),
        ),
        MatchmakingState$Found(
          :final opponent,
          :final rating,
          :final rated,
          :final accepted,
          :final deadline,
        ) =>
          _Status(
            icon: LucideIcons.swords,
            title: 'Соперник найден',
            subtitle:
                '$opponent${rating == null ? '' : ' · $rating Elo'}\n${rated ? 'Рейтинговая партия' : 'Матч без изменения рейтинга'} · ${_secondsLeft(deadline)} сек.',
            action: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: accepted
                        ? null
                        : () => bloc.add(const MatchmakingEvent$Decline()),
                    child: const Text('Отказаться'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: accepted
                        ? null
                        : () => bloc.add(const MatchmakingEvent$Accept()),
                    child: Text(accepted ? 'Ждём соперника…' : 'Принять'),
                  ),
                ),
              ],
            ),
          ),
        MatchmakingState$Failure(:final message) => _Setup(
          name: name,
          code: _code,
          error: message,
          onCreate: () => bloc.add(MatchmakingEvent$Create(name)),
          onJoin: () => bloc.add(MatchmakingEvent$Join(name, _code.text)),
          onFind: () => bloc.add(MatchmakingEvent$Find(name)),
        ),
        _ => _Setup(
          name: name,
          code: _code,
          onCreate: () => bloc.add(MatchmakingEvent$Create(name)),
          onJoin: () => bloc.add(MatchmakingEvent$Join(name, _code.text)),
          onFind: () => bloc.add(MatchmakingEvent$Find(name)),
        ),
      },
    );
  }
}

int _secondsLeft(int deadline) =>
    ((deadline - DateTime.now().millisecondsSinceEpoch) / 1000).ceil().clamp(
      0,
      999,
    );

class _Setup extends StatelessWidget {
  const new({
    required this.name,
    required this.code,
    required this.onCreate,
    required this.onJoin,
    required this.onFind,
    this.error,
  });
  final String name;
  final TextEditingController code;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onFind;
  final String? error;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Вы играете как $name'),
      if (error case final value?) ...[
        const SizedBox(height: 10),
        Text(
          value,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: onFind,
        icon: const Icon(LucideIcons.search),
        label: const Text('Найти рейтинговую игру'),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('или'),
            ),
            Expanded(child: Divider()),
          ],
        ),
      ),
      OutlinedButton.icon(
        onPressed: onCreate,
        icon: const Icon(LucideIcons.plus),
        label: const Text('Создать приватное лобби'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: code,
        textCapitalization: TextCapitalization.characters,
        maxLength: 5,
        decoration: const InputDecoration(
          labelText: 'Код лобби',
          hintText: 'ABCDE',
          counterText: '',
        ),
        onSubmitted: (_) => onJoin(),
      ),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: onJoin, child: const Text('Войти по коду')),
    ],
  );
}

class _Status extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      children: [
        Icon(icon, size: 42),
        const SizedBox(height: 14),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(subtitle, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

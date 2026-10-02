import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/match_history/bloc/match_history_bloc.dart';
import 'package:four3/src/feature/match_history/model/match_history_models.dart';
import 'package:four3/src/feature/match_history/widget/match_history_root_scope.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MatchHistoryView extends StatefulWidget {
  const new({super.key});
  @override
  State<MatchHistoryView> createState() => _MatchHistoryViewState();
}

class _MatchHistoryViewState extends State<MatchHistoryView> {
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
        MatchHistoryState$Loading() || MatchHistoryState$Initial() =>
          const Center(child: CircularProgressIndicator()),
        MatchHistoryState$Guest() => const _Empty(
          icon: LucideIcons.logIn,
          text: 'Войдите в аккаунт, чтобы видеть историю и статистику.',
        ),
        MatchHistoryState$Failure(:final message) => _Empty(
          icon: LucideIcons.triangleAlert,
          text: message,
          action: () => bloc.add(const MatchHistoryEvent$Load()),
        ),
        MatchHistoryState$Ready(:final data) => _History(data: data),
      },
    );
  }
}

class _History extends StatelessWidget {
  const new({required this.data});
  final MatchHistorySnapshot data;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Stat(label: 'Elo', value: '${data.rating.points}'),
          _Stat(label: 'Партий', value: '${data.statistics.total}'),
          _Stat(label: 'Побед', value: '${data.statistics.wins}'),
          _Stat(label: 'Ничьих', value: '${data.statistics.draws}'),
        ],
      ),
      const SizedBox(height: 12),
      if (data.matches.isEmpty)
        const Expanded(
          child: _Empty(
            icon: LucideIcons.history,
            text: 'Завершённые партии появятся здесь.',
          ),
        )
      else
        Expanded(
          child: ListView.separated(
            itemCount: data.matches.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _MatchTile(match: data.matches[index]),
          ),
        ),
    ],
  );
}

class _MatchTile extends StatelessWidget {
  const new({required this.match});
  final SavedMatch match;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(match.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${match.names.join(' — ')} · ${match.game.history.length} ходов · ${_duration(match.elapsed)}',
    ),
    onTap: () {
      GameRootScope.of(context)
          .add(GameEvent$ReplaySaved(snapshot: match.game, names: match.names));
      Navigator.of(context).pop();
    },
    trailing: PopupMenuButton<String>(
      onSelected: (value) =>
          value == 'remove' ? _remove(context) : _rename(context),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('Переименовать')),
        PopupMenuItem(value: 'remove', child: Text('Удалить')),
      ],
    ),
  );
  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: match.title);
    final String? value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Название партии'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.trim().isNotEmpty && context.mounted) {
      MatchHistoryRootScope.of(context)
          .add(MatchHistoryEvent$Rename(match.id, value));
    }
  }

  void _remove(BuildContext context) =>
      MatchHistoryRootScope.of(context).add(MatchHistoryEvent$Remove(match.id));
}

class _Stat extends StatelessWidget {
  const new({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Chip(label: Text('$label · $value'));
}

class _Empty extends StatelessWidget {
  const new({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: action, child: const Text('Повторить')),
          ],
        ],
      ),
    ),
  );
}

String _duration(int value) =>
    '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';

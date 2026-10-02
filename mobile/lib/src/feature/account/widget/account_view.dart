import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/feature/account/bloc/account_bloc.dart';
import 'package:four3/src/feature/account/model/account_profile.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AccountView extends StatefulWidget {
  const new({this.onHistory, super.key});
  final VoidCallback? onHistory;

  @override
  State<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;

  @override
  Widget build(BuildContext context) {
    final AccountBloc bloc = AccountRootScope.of(context);
    return BlocBuilder<AccountBloc, AccountState>(
      bloc: bloc,
      builder: (context, state) {
        final AccountProfile? profile = bloc.profile;
        final loading = state is AccountState$Loading;
        final String failure = state is AccountState$Failure
            ? state.message
            : '';
        final String notice = state is AccountState$Ready ? state.notice : '';
        if (profile?.username case final username?) {
          return ListView(
            shrinkWrap: true,
            children: [
              CircleAvatar(
                radius: 34,
                child: Text(
                  username.characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 28),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                username,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (profile?.email case final email?)
                Text(email, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(LucideIcons.mailCheck),
                title: Text(
                  profile!.emailVerified
                      ? 'Email подтверждён'
                      : 'Email не подтверждён',
                ),
              ),
              ListTile(
                leading: const Icon(LucideIcons.history),
                title: const Text('История и статистика'),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: widget.onHistory,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: loading
                    ? null
                    : () => bloc.add(const AccountEvent$Logout()),
                icon: const Icon(LucideIcons.logOut),
                label: const Text('Выйти из аккаунта'),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Сейчас вы играете как ${profile?.guestName ?? 'гость'}. Войдите, чтобы сохранять уровни, рейтинг и историю.',
              ),
              const SizedBox(height: 18),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Вход')),
                  ButtonSegment(value: true, label: Text('Регистрация')),
                ],
                selected: {_register},
                onSelectionChanged: (value) =>
                    setState(() => _register = value.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _username,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Имя пользователя',
                ),
              ),
              if (_register) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Пароль'),
              ),
              if (failure.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  failure,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (notice.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(notice, style: const TextStyle(color: Color(0xFF426B4A))),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: loading
                    ? null
                    : () {
                        if (_register) {
                          bloc.add(
                            AccountEvent$Register(
                              _username.text,
                              _email.text,
                              _password.text,
                            ),
                          );
                        } else {
                          bloc.add(
                            AccountEvent$Login(_username.text, _password.text),
                          );
                        }
                      },
                child: Text(
                  loading
                      ? 'Подождите…'
                      : _register
                      ? 'Создать аккаунт'
                      : 'Войти',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }
}

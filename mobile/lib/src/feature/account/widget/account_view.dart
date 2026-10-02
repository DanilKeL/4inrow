import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/theme/app_theme.dart';
import 'package:four3/src/feature/account/bloc/account_bloc.dart';
import 'package:four3/src/feature/account/model/account_profile.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum _AccountMode { register, login, forgot }

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
  final _passwordRepeat = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _newPasswordRepeat = TextEditingController();
  _AccountMode _mode = _AccountMode.register;
  bool _security = false;
  String _localError = '';

  @override
  Widget build(BuildContext context) {
    final AccountBloc bloc = AccountRootScope.of(context);
    return BlocBuilder<AccountBloc, AccountState>(
      bloc: bloc,
      builder: (context, state) {
        final AccountProfile? profile = bloc.profile;
        final bool loading = state is AccountState$Loading;
        final String failure = state is AccountState$Failure
            ? state.message
            : _localError;
        final String notice = state is AccountState$Ready ? state.notice : '';
        if (state case AccountState$PasswordReset(:final token)) {
          return _resetView(bloc, token, loading, failure);
        }
        if (profile?.username != null) {
          return _signedView(bloc, profile!, loading, failure, notice);
        }
        return _guestView(bloc, profile, loading, failure, notice);
      },
    );
  }

  Widget _guestView(
    AccountBloc bloc,
    AccountProfile? profile,
    bool loading,
    String failure,
    String notice,
  ) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileIntro(name: profile?.guestName ?? 'Гость'),
        if (notice.isNotEmpty) _Notice(notice),
        const SizedBox(height: 14),
        if (_mode != _AccountMode.forgot) ...[
          _AuthTabs(
            mode: _mode,
            onChanged: (value) => setState(() {
              _mode = value;
              _localError = '';
              bloc.add(const AccountEvent$ClearMessage());
            }),
          ),
          const SizedBox(height: 16),
          _Field(
            label: 'Имя пользователя',
            controller: _username,
            autocorrect: false,
          ),
          if (_mode == _AccountMode.register) ...[
            const SizedBox(height: 5),
            const Text(
              'Английские буквы, цифры и _ · 3–24 символа',
              style: TextStyle(fontSize: 9, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            _Field(
              label: 'Email',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
            ),
          ],
          const SizedBox(height: 10),
          _Field(label: 'Пароль', controller: _password, obscureText: true),
        ] else ...[
          const Text(
            'Восстановление пароля',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          const Text(
            'Пришлём ссылку для создания нового пароля.',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 16),
          _Field(
            label: 'Email',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
        ],
        if (failure.isNotEmpty) _Error(failure),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: loading ? null : () => _submitGuest(bloc),
          child: Text(
            loading
                ? 'Подождите…'
                : switch (_mode) {
                    _AccountMode.register => 'Зарегистрироваться',
                    _AccountMode.login => 'Войти',
                    _AccountMode.forgot => 'Получить ссылку',
                  },
          ),
        ),
        const SizedBox(height: 8),
        if (_mode == _AccountMode.login) ...[
          OutlinedButton(
            onPressed: () => setState(() => _mode = _AccountMode.forgot),
            child: const Text('Забыли пароль?'),
          ),
          TextButton(
            onPressed: loading
                ? null
                : () => bloc.add(
                    AccountEvent$ResendVerification(
                      _email.text.trim().isEmpty ? _username.text : _email.text,
                    ),
                  ),
            child: const Text('Отправить подтверждение повторно'),
          ),
        ] else if (_mode == _AccountMode.forgot)
          OutlinedButton(
            onPressed: () => setState(() => _mode = _AccountMode.login),
            child: const Text('Вернуться ко входу'),
          ),
      ],
    ),
  );

  Widget _signedView(
    AccountBloc bloc,
    AccountProfile profile,
    bool loading,
    String failure,
    String notice,
  ) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SignedTabs(
          security: _security,
          onChanged: (value) => setState(() {
            _security = value;
            _localError = '';
          }),
        ),
        const SizedBox(height: 12),
        if (notice.isNotEmpty) _Notice(notice),
        if (!_security) ...[
          _SignedProfile(profile: profile),
          const SizedBox(height: 12),
          _ActionTile(
            icon: LucideIcons.history,
            title: 'История и статистика',
            subtitle: 'Рейтинг, результаты и сохранённые партии',
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
        ] else ...[
          const _SecurityIntro(),
          const SizedBox(height: 12),
          _Field(
            label: 'Текущий пароль',
            controller: _currentPassword,
            obscureText: true,
          ),
          const SizedBox(height: 10),
          _Field(
            label: 'Новый пароль',
            controller: _newPassword,
            obscureText: true,
          ),
          const SizedBox(height: 10),
          _Field(
            label: 'Повторите новый пароль',
            controller: _newPasswordRepeat,
            obscureText: true,
          ),
          if (failure.isNotEmpty) _Error(failure),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: loading ? null : () => _changePassword(bloc),
            icon: const Icon(LucideIcons.keyRound),
            label: Text(loading ? 'Сохраняем…' : 'Изменить пароль'),
          ),
        ],
      ],
    ),
  );

  Widget _resetView(
    AccountBloc bloc,
    String token,
    bool loading,
    String failure,
  ) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Новый пароль',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
          'Задайте новый пароль для аккаунта.',
          style: TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 16),
        _Field(label: 'Новый пароль', controller: _password, obscureText: true),
        const SizedBox(height: 10),
        _Field(
          label: 'Повторите пароль',
          controller: _passwordRepeat,
          obscureText: true,
        ),
        if (failure.isNotEmpty) _Error(failure),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: loading ? null : () => _completeReset(bloc, token),
          child: Text(loading ? 'Сохраняем…' : 'Изменить пароль'),
        ),
      ],
    ),
  );

  void _submitGuest(AccountBloc bloc) {
    setState(() => _localError = '');
    switch (_mode) {
      case _AccountMode.register:
        if (!RegExp(r'^[A-Za-z0-9_]{3,24}$').hasMatch(_username.text.trim())) {
          setState(
            () => _localError =
                'Используйте 3–24 английские буквы, цифры или символ _.',
          );
        } else if (_password.text.length < 8) {
          setState(
            () => _localError = 'Пароль должен содержать от 8 символов.',
          );
        } else {
          bloc.add(
            AccountEvent$Register(_username.text, _email.text, _password.text),
          );
        }
      case _AccountMode.login:
        bloc.add(AccountEvent$Login(_username.text, _password.text));
      case _AccountMode.forgot:
        bloc.add(AccountEvent$RequestPasswordReset(_email.text));
    }
  }

  void _completeReset(AccountBloc bloc, String token) {
    if (_password.text.length < 8 || _password.text != _passwordRepeat.text) {
      setState(
        () => _localError = _password.text.length < 8
            ? 'Пароль должен содержать от 8 символов.'
            : 'Пароли не совпадают.',
      );
      return;
    }
    bloc.add(AccountEvent$CompletePasswordReset(token, _password.text));
  }

  void _changePassword(AccountBloc bloc) {
    if (_newPassword.text.length < 8 ||
        _newPassword.text != _newPasswordRepeat.text ||
        _newPassword.text == _currentPassword.text) {
      setState(
        () => _localError = _newPassword.text.length < 8
            ? 'Новый пароль должен содержать от 8 символов.'
            : _newPassword.text != _newPasswordRepeat.text
            ? 'Новые пароли не совпадают.'
            : 'Новый пароль должен отличаться от текущего.',
      );
      return;
    }
    bloc.add(
      AccountEvent$ChangePassword(_currentPassword.text, _newPassword.text),
    );
  }

  @override
  void dispose() {
    for (final TextEditingController controller in [
      _username,
      _email,
      _password,
      _passwordRepeat,
      _currentPassword,
      _newPassword,
      _newPasswordRepeat,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }
}

class _ProfileIntro extends StatelessWidget {
  const new({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(LucideIcons.userRound, color: AppColors.accent),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ТЕКУЩИЙ ПРОФИЛЬ',
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted,
                ),
              ),
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    ),
  );
}

class _AuthTabs extends StatelessWidget {
  const new({required this.mode, required this.onChanged});
  final _AccountMode mode;
  final ValueChanged<_AccountMode> onChanged;
  @override
  Widget build(BuildContext context) => SegmentedButton<_AccountMode>(
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(value: _AccountMode.register, label: Text('Регистрация')),
      ButtonSegment(value: _AccountMode.login, label: Text('Вход')),
    ],
    selected: {mode},
    onSelectionChanged: (value) => onChanged(value.first),
  );
}

class _SignedTabs extends StatelessWidget {
  const new({required this.security, required this.onChanged});
  final bool security;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(
        value: false,
        icon: Icon(LucideIcons.activity),
        label: Text('Обзор'),
      ),
      ButtonSegment(
        value: true,
        icon: Icon(LucideIcons.shieldCheck),
        label: Text('Безопасность'),
      ),
    ],
    selected: {security},
    onSelectionChanged: (value) => onChanged(value.first),
  );
}

class _SignedProfile extends StatelessWidget {
  const new({required this.profile});
  final AccountProfile profile;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFF2F4ED), Colors.white, Color(0xFFEEF2FF)],
      ),
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              profile.username!.characters.take(2).join().toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ПРОФИЛЬ ИГРОКА',
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.2,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  profile.username!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Row(
                  children: [
                    const Icon(LucideIcons.mail, size: 13),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        profile.email ?? 'Локальный аккаунт',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    if (profile.emailVerified) ...[
                      const SizedBox(width: 5),
                      const Icon(
                        LucideIcons.circleCheck,
                        size: 13,
                        color: Color(0xFF2F7F49),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SecurityIntro extends StatelessWidget {
  const new();
  @override
  Widget build(BuildContext context) => const _ActionTile(
    icon: LucideIcons.shieldCheck,
    title: 'Пароль и активные сеансы',
    subtitle: 'После смены пароля остальные устройства выйдут из аккаунта. Текущий сеанс останется активным.',
  );
}

class _ActionTile extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Ink(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (onTap != null) const Icon(LucideIcons.chevronRight, size: 17),
        ],
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const new({
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.autocorrect = true,
    this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final bool autocorrect;
  final TextInputType? keyboardType;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscureText,
    autocorrect: autocorrect,
    keyboardType: keyboardType,
    decoration: InputDecoration(labelText: label),
  );
}

class _Notice extends StatelessWidget {
  const new(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(text, style: const TextStyle(color: Color(0xFF426B4A))),
  );
}

class _Error extends StatelessWidget {
  const new(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

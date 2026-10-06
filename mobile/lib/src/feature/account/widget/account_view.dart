import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/common/theme/app_theme.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/common/widget/app_controls.dart';
import 'package:four3/src/feature/account/bloc/account_bloc.dart';
import 'package:four3/src/feature/account/data/account_repository.dart';
import 'package:four3/src/feature/account/model/account_profile.dart';
import 'package:four3/src/feature/account/widget/account_root_scope.dart';
import 'package:four3/src/feature/match_history/bloc/match_history_bloc.dart';
import 'package:four3/src/feature/match_history/model/match_history_models.dart';
import 'package:four3/src/feature/match_history/widget/match_history_root_scope.dart';
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
  final _guestScrollController = ScrollController();
  _AccountMode _mode = _AccountMode.register;
  bool _security = false;
  String _localError = '';

  @override
  void initState() {
    super.initState();
    _username.addListener(_refreshIdentityActions);
    _email.addListener(_refreshIdentityActions);
  }

  void _refreshIdentityActions() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AccountBloc bloc = AccountRootScope.of(context);
    return BlocConsumer<AccountBloc, AccountState>(
      bloc: bloc,
      listenWhen: (previous, current) =>
          current is AccountState$Ready && current.registrationCompleted,
      listener: (context, state) {
        _password.clear();
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() {
          _mode = _AccountMode.login;
          _localError = '';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_guestScrollController.hasClients) {
            _guestScrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
        });
      },
      builder: (context, state) {
        final AccountProfile? profile = bloc.profile;
        final bool loading = state is AccountState$Loading;
        final String failure = state is AccountState$Failure
            ? _accountFailure(context, state)
            : _localError;
        final String notice = state is AccountState$Ready
            ? _accountNotice(context, state)
            : '';
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
    controller: _guestScrollController,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileIntro(name: profile?.guestName ?? context.l10n.guest),
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
            label: context.l10n.username,
            controller: _username,
            autocorrect: false,
          ),
          if (_mode == _AccountMode.register) ...[
            const SizedBox(height: 5),
            Text(
              context.l10n.usernameHint,
              style: const TextStyle(fontSize: 9, color: AppColors.muted),
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
          _Field(
            label: context.l10n.password,
            controller: _password,
            obscureText: true,
          ),
        ] else ...[
          Text(
            context.l10n.forgotPasswordHint,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              height: 1.5,
            ),
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
                ? _mode == _AccountMode.forgot
                      ? context.l10n.sending
                      : context.l10n.pleaseWait
                : switch (_mode) {
                    _AccountMode.register => context.l10n.register,
                    _AccountMode.login => context.l10n.signIn,
                    _AccountMode.forgot => context.l10n.getLink,
                  },
          ),
        ),
        const SizedBox(height: 8),
        if (_mode == _AccountMode.login) ...[
          OutlinedButton(
            onPressed: () => setState(() => _mode = _AccountMode.forgot),
            child: Text(context.l10n.forgotPassword),
          ),
          if (_email.text.trim().isNotEmpty || _username.text.trim().isNotEmpty)
            TextButton(
              onPressed: loading
                  ? null
                  : () => bloc.add(
                      AccountEvent$ResendVerification(
                        _email.text.trim().isEmpty
                            ? _username.text
                            : _email.text,
                      ),
                    ),
              child: Text(context.l10n.resendVerification),
            ),
        ] else if (_mode == _AccountMode.forgot)
          OutlinedButton(
            onPressed: () => setState(() => _mode = _AccountMode.login),
            child: Text(context.l10n.returnToSignIn),
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
          if (MediaQuery.sizeOf(context).height > 650) ...[
            _SignedProfile(profile: profile),
            const SizedBox(height: 9),
          ],
          _AccountOverviewCards(onHistory: widget.onHistory),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (widget.onHistory != null)
                TextButton.icon(
                  onPressed: widget.onHistory,
                  icon: const Icon(LucideIcons.history, size: 16),
                  label: Text(context.l10n.history),
                ),
              TextButton.icon(
                onPressed: loading
                    ? null
                    : () => bloc.add(const AccountEvent$Logout()),
                icon: const Icon(LucideIcons.logOut, size: 16),
                label: Text(context.l10n.signOut),
              ),
            ],
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFDDE1D8)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      LucideIcons.lockKeyhole,
                      size: 20,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 11),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.changePasswordUpper,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          context.l10n.updateCredentials,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                _Field(
                  label: context.l10n.currentPassword,
                  controller: _currentPassword,
                  obscureText: true,
                ),
                const SizedBox(height: 11),
                _Field(
                  label: context.l10n.newPassword,
                  controller: _newPassword,
                  obscureText: true,
                  maxLength: 128,
                ),
                const SizedBox(height: 5),
                Text(
                  context.l10n.passwordLengthHint,
                  style: const TextStyle(color: AppColors.muted, fontSize: 8),
                ),
                const SizedBox(height: 11),
                _Field(
                  label: context.l10n.repeatNewPassword,
                  controller: _newPasswordRepeat,
                  obscureText: true,
                  maxLength: 128,
                ),
                if (failure.isNotEmpty) _Error(failure),
                if (notice.isNotEmpty) _Notice(notice),
                const SizedBox(height: 11),
                FilledButton.icon(
                  onPressed: loading ? null : () => _changePassword(bloc),
                  icon: const Icon(LucideIcons.keyRound, size: 17),
                  label: Text(
                    loading ? context.l10n.saving : context.l10n.changePassword,
                  ),
                ),
              ],
            ),
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
        Text(
          context.l10n.setNewPasswordHint,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        _Field(
          label: context.l10n.newPassword,
          controller: _password,
          obscureText: true,
        ),
        const SizedBox(height: 10),
        _Field(
          label: context.l10n.repeatPassword,
          controller: _passwordRepeat,
          obscureText: true,
        ),
        if (failure.isNotEmpty) _Error(failure),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: loading ? null : () => _completeReset(bloc, token),
          child: Text(
            loading ? context.l10n.saving : context.l10n.changePassword,
          ),
        ),
      ],
    ),
  );

  void _submitGuest(AccountBloc bloc) {
    setState(() => _localError = '');
    switch (_mode) {
      case _AccountMode.register:
        if (!RegExp(r'^[A-Za-z0-9_]{3,24}$').hasMatch(_username.text.trim())) {
          setState(() => _localError = context.l10n.usernameValidation);
        } else if (_password.text.length < 8) {
          setState(() => _localError = context.l10n.passwordMinValidation);
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
            ? context.l10n.passwordMinValidation
            : context.l10n.passwordMismatch,
      );
      return;
    }
    bloc.add(AccountEvent$CompletePasswordReset(token, _password.text));
  }

  void _changePassword(AccountBloc bloc) {
    if (_newPassword.text.length < 8 ||
        _newPassword.text.length > 128 ||
        _newPassword.text != _newPasswordRepeat.text ||
        _newPassword.text == _currentPassword.text) {
      setState(
        () => _localError =
            _newPassword.text.length < 8 || _newPassword.text.length > 128
            ? context.l10n.newPasswordValidation
            : _newPassword.text != _newPasswordRepeat.text
            ? context.l10n.newPasswordsMismatch
            : context.l10n.passwordMustDiffer,
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
    _guestScrollController.dispose();
    super.dispose();
  }
}

class _ProfileIntro extends StatelessWidget {
  const new({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFF0F2EC),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(LucideIcons.userRound, size: 20, color: Color(0xFF687064)),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.currentProfileUpper,
                style: const TextStyle(
                  fontSize: 8,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted,
                ),
              ),
              Text(
                name,
                style: const TextStyle(
                  color: Color(0xFF2F342D),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
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
  Widget build(BuildContext context) => Row(
    children: [
      for (final (_AccountMode value, String label) in [
        (_AccountMode.register, context.l10n.registration),
        (_AccountMode.login, context.l10n.login),
      ]) ...[
        if (value != _AccountMode.register) const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () => onChanged(value),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.all(10),
              backgroundColor: Colors.white,
              foregroundColor: value == mode ? AppColors.accent : AppColors.ink,
              side: BorderSide(
                color: value == mode
                    ? AppColors.accent
                    : const Color(0xFFDCE0D4),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            child: Text(label),
          ),
        ),
      ],
    ],
  );
}

class _SignedTabs extends StatelessWidget {
  const new({required this.security, required this.onChanged});
  final bool security;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => AppSegmentedControl<bool>(
    options: [
      AppSegment(
        value: false,
        icon: LucideIcons.activity,
        label: context.l10n.overview,
      ),
      AppSegment(
        value: true,
        icon: LucideIcons.shieldCheck,
        label: context.l10n.security,
      ),
    ],
    selected: security,
    onChanged: onChanged,
    style: AppSegmentedStyle.pill,
  );
}

class _SignedProfile extends StatelessWidget {
  const new({required this.profile});
  final AccountProfile profile;
  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width <= 650;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF2F4ED), Colors.white, Color(0xFFEEF2FF)],
        ),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 17),
        child: Row(
          children: [
            Container(
              width: compact ? 45 : 56,
              height: compact ? 45 : 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(compact ? 12 : 16),
              ),
              child: Text(
                profile.username!.characters.take(2).join().toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 15 : 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(width: compact ? 10 : 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.playerProfileUpper,
                    style: const TextStyle(
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
                    style: TextStyle(
                      fontSize: compact ? 18 : 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(LucideIcons.mail, size: 13),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          profile.email ?? context.l10n.localAccount,
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
}

class _AccountOverviewCards extends StatelessWidget {
  const new({required this.onHistory});
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final MatchHistoryBloc bloc = MatchHistoryRootScope.of(context);
    if (bloc.state is MatchHistoryState$Initial ||
        bloc.state is MatchHistoryState$Guest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!bloc.isClosed) bloc.add(const MatchHistoryEvent$Load());
      });
    }
    return BlocBuilder<MatchHistoryBloc, MatchHistoryState>(
      bloc: bloc,
      builder: (context, state) {
        if (state case MatchHistoryState$Ready(:final data)) {
          return _OverviewData(data: data, onHistory: onHistory);
        }
        if (state case MatchHistoryState$Failure(:final message)) {
          return Text(
            message,
            style: const TextStyle(color: AppColors.danger, fontSize: 10),
          );
        }
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}

class _OverviewData extends StatelessWidget {
  const new({required this.data, required this.onHistory});
  final MatchHistorySnapshot data;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final (String, int, int, String) league = _league(
      context,
      data.rating.points,
    );
    final double progress =
        ((data.rating.points - league.$2) / (league.$3 - league.$2))
            .clamp(0, 1)
            .toDouble();
    final int winRate = data.statistics.total == 0
        ? 0
        : (data.statistics.wins * 100 / data.statistics.total).round();
    final bool short = MediaQuery.sizeOf(context).height <= 650;
    final bool compact = MediaQuery.sizeOf(context).width <= 650;
    final Widget ratingCard = Container(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF244BD0), Color(0xFF315EEA), Color(0xFF456DF0)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2853DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.ratingUpper,
                      style: const TextStyle(
                        color: Color(0xFFDBE3FF),
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      league.$1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                LucideIcons.trophy,
                size: 23,
                color: Color(0xFFDBE3FF),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${data.rating.points}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 27 : 34,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'ELO',
                style: TextStyle(
                  color: Color(0xFFDBE3FF),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: progress,
              color: Colors.white,
              backgroundColor: const Color(0x36FFFFFF),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            context.l10n.pointsToLeague(
              (league.$3 - data.rating.points).clamp(0, 9999),
              league.$4,
            ),
            style: const TextStyle(color: Color(0xFFDBE3FF), fontSize: 8),
          ),
        ],
      ),
    );
    final Widget statisticsCard = Container(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDE1D8)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.careerUpper,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      context.l10n.ratedMatches(data.rating.games),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.target, size: 22, color: AppColors.accent),
            ],
          ),
          SizedBox(height: compact ? 8 : 13),
          Row(
            children: [
              _MiniStat('${data.statistics.total}', context.l10n.matchesStat),
              _MiniStat('${data.statistics.wins}', context.l10n.winsStat),
              _MiniStat('$winRate%', context.l10n.winRate),
              _MiniStat('${data.statistics.losses}', context.l10n.lossesStat),
            ],
          ),
        ],
      ),
    );
    return Column(
      children: [
        if (compact) ...[
          ratingCard,
          const SizedBox(height: 9),
          statisticsCard,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 4, child: ratingCard),
              const SizedBox(width: 12),
              Expanded(flex: 6, child: statisticsCard),
            ],
          ),
        if (!short) ...[
          const SizedBox(height: 9),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFDDE1D8)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.recentMatchesUpper,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            context.l10n.recentForm,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onHistory != null)
                      TextButton.icon(
                        onPressed: onHistory,
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(LucideIcons.chevronRight, size: 15),
                        label: Text(
                          context.l10n.fullHistory,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 9),
                if (data.matches.isEmpty)
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF3F5F0),
                      borderRadius: BorderRadius.all(Radius.circular(9)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        context.l10n.firstMatchHint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  )
                else
                  _RecentMatch(
                    match: data.matches.first,
                    username: data.username,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const new(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 3.5),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4EE),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 8, color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _RecentMatch extends StatelessWidget {
  const new({required this.match, required this.username});
  final SavedMatch match;
  final String username;
  @override
  Widget build(BuildContext context) {
    final int seat = match.names.indexOf(username);
    final bool draw = match.game.winner == null;
    final bool won = !draw && match.game.winner!.index == seat;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBF8),
        border: Border.all(color: const Color(0xFFE4E7DF)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Container(
            width: 27,
            height: 27,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: draw
                  ? const Color(0xFFE8EBEE)
                  : won
                  ? const Color(0xFFE3F2E5)
                  : const Color(0xFFF7E7E4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              draw
                  ? context.l10n.drawShort
                  : won
                  ? context.l10n.winShort
                  : context.l10n.lossShort,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              draw
                  ? context.l10n.draw
                  : won
                  ? context.l10n.win
                  : context.l10n.loss,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10),
            ),
          ),
          if (match.ratingChange != null)
            Text(
              '${match.ratingChange! >= 0 ? '+' : ''}${match.ratingChange} Elo',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: match.ratingChange! >= 0
                    ? AppColors.success
                    : AppColors.danger,
              ),
            ),
        ],
      ),
    );
  }
}

(String, int, int, String) _league(BuildContext context, int points) {
  final AppLocalizations l10n = context.l10n;
  if (points < 900) {
    return (l10n.leagueBronze, 600, 900, l10n.leagueSilver);
  }
  if (points < 1100) {
    return (l10n.leagueSilver, 900, 1100, l10n.leagueGold);
  }
  if (points < 1300) {
    return (l10n.leagueGold, 1100, 1300, l10n.leaguePlatinum);
  }
  if (points < 1500) {
    return (l10n.leaguePlatinum, 1300, 1500, l10n.leagueMaster);
  }
  return (l10n.leagueMaster, 1500, 1800, l10n.leagueTop);
}

String _accountNotice(BuildContext context, AccountState$Ready state) {
  if (state.notice.isNotEmpty) return state.notice;
  return switch (state.clientNotice) {
    AccountNotice.emailVerified => context.l10n.emailVerified,
    AccountNotice.passwordChanged => context.l10n.passwordChanged,
    AccountNotice.accountCreatedVerify => context.l10n.accountCreatedVerify,
    AccountNotice.emailSent => context.l10n.emailSent,
    AccountNotice.passwordResetSent => context.l10n.passwordResetSent,
    null => '',
  };
}

String _accountFailure(BuildContext context, AccountState$Failure state) {
  if (state.message.isNotEmpty) return state.message;
  return switch (state.failure) {
    RestClientFailure.network => context.l10n.networkError,
    RestClientFailure.invalidResponse => context.l10n.invalidServerResponse,
    RestClientFailure.wrongType => context.l10n.serverWrongType,
    RestClientFailure.server || null => context.l10n.genericServerError,
  };
}

class _Field extends StatelessWidget {
  const new({
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.autocorrect = true,
    this.keyboardType,
    this.maxLength,
  });
  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final bool autocorrect;
  final TextInputType? keyboardType;
  final int? maxLength;
  @override
  Widget build(BuildContext context) => AppTextField(
    controller: controller,
    obscureText: obscureText,
    autocorrect: autocorrect,
    keyboardType: keyboardType,
    maxLength: maxLength,
    label: label,
  );
}

class _Notice extends StatelessWidget {
  const new(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F8EF),
      border: Border.all(color: const Color(0xFFC8DDC3)),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF315C2C),
        fontSize: 12,
        height: 1.45,
      ),
    ),
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
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: 12,
        height: 1.7,
      ),
    ),
  );
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/bloc/account_bloc.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';

class AccountRootScope extends StatefulWidget {
  const new({required this.child, super.key});
  final Widget child;

  static AccountBloc of(BuildContext context) =>
      context.inheritedOf<_InheritedAccountScope>().accountBloc;

  @override
  State<AccountRootScope> createState() => _AccountRootScopeState();
}

class _AccountRootScopeState extends State<AccountRootScope> {
  late final AccountBloc _accountBloc;
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    final RootDependencies root = RootScope.of(context);
    _accountBloc = AccountBloc(repository: root.accountRepository)
      ..add(const AccountEvent$Load());
    _links = root.deepLinkService.links.listen(_handleLink);
    if (root.deepLinkService.takeInitialLink() case final initial?) {
      _handleLink(initial);
    }
  }

  void _handleLink(Uri uri) {
    final String? token = uri.queryParameters['token'];
    if (token != null && token.isNotEmpty) {
      if (uri.host == 'verify' || uri.path.contains('verify')) {
        _accountBloc.add(AccountEvent$VerifyEmail(token));
      } else if (uri.host == 'reset' || uri.path.contains('password-reset')) {
        _accountBloc.add(AccountEvent$OpenPasswordReset(token));
      }
    }
    final String? reset = uri.queryParameters['reset'];
    if (reset != null && reset.isNotEmpty) {
      _accountBloc.add(AccountEvent$OpenPasswordReset(reset));
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    _accountBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _InheritedAccountScope(accountBloc: _accountBloc, child: widget.child);
}

class _InheritedAccountScope extends InheritedWidget {
  const new({required this.accountBloc, required super.child});
  final AccountBloc accountBloc;

  @override
  bool updateShouldNotify(covariant _InheritedAccountScope oldWidget) => false;
}

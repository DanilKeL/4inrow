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
    _links = root.deepLinkService.links.listen((uri) {
      final String? token = uri.queryParameters['token'];
      if (token != null &&
          token.isNotEmpty &&
          (uri.host == 'verify' || uri.path.contains('verify'))) {
        _accountBloc.add(AccountEvent$VerifyEmail(token));
      }
    });
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

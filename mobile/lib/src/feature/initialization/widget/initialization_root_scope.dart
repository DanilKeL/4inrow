import 'package:flutter/widgets.dart';

import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/initialization/bloc/initialization_bloc.dart';

class InitializationRootScope extends StatefulWidget {
  const new({required this.child, super.key});
  final Widget child;
  static InitializationBloc of(BuildContext context) =>
      context.inheritedOf<_InheritedInitializationScope>().bloc;
  @override
  State<InitializationRootScope> createState() =>
      _InitializationRootScopeState();
}

class _InitializationRootScopeState extends State<InitializationRootScope>
    with WidgetsBindingObserver {
  late final InitializationBloc _bloc;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bloc = InitializationBloc()..add(const InitializationEvent$Start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _bloc.add(const InitializationEvent$Foreground());
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _bloc.add(const InitializationEvent$Background());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _InheritedInitializationScope(bloc: _bloc, child: widget.child);
}

class _InheritedInitializationScope extends InheritedWidget {
  const new({required this.bloc, required super.child});
  final InitializationBloc bloc;
  @override
  bool updateShouldNotify(covariant _InheritedInitializationScope oldWidget) =>
      false;
}

import 'package:flutter/widgets.dart';

import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';
import 'package:four3/src/feature/settings/bloc/settings_bloc.dart';
import 'package:four3/src/feature/settings/bloc/settings_event.dart';

class SettingsRootScope extends StatefulWidget {
  const new({required this.child, super.key});
  final Widget child;

  static SettingsBloc of(BuildContext context) =>
      context.inheritedOf<_InheritedSettingsScope>().settingsBloc;

  @override
  State<SettingsRootScope> createState() => _SettingsRootScopeState();
}

class _SettingsRootScopeState extends State<SettingsRootScope> {
  late final SettingsBloc _settingsBloc;

  @override
  void initState() {
    super.initState();
    _settingsBloc = SettingsBloc(
      repository: RootScope.of(context).settingsRepository,
    )..add(const SettingsEvent$Load());
  }

  @override
  void dispose() {
    _settingsBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _InheritedSettingsScope(settingsBloc: _settingsBloc, child: widget.child);
}

class _InheritedSettingsScope extends InheritedWidget {
  const new({required this.settingsBloc, required super.child});
  final SettingsBloc settingsBloc;

  @override
  bool updateShouldNotify(covariant _InheritedSettingsScope oldWidget) => false;
}

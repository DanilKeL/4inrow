import 'package:flutter/widgets.dart';
import 'package:four3/l10n/generated/app_localizations.dart';

extension BuildContextX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  T inheritedOf<T extends InheritedWidget>() {
    final T? widget = getInheritedWidgetOfExactType<T>();
    assert(widget != null, 'No $T found above this context.');
    if (widget == null) throw StateError('No $T found above this context.');
    return widget;
  }

  T? maybeInheritedOf<T extends InheritedWidget>() =>
      getInheritedWidgetOfExactType<T>();
}

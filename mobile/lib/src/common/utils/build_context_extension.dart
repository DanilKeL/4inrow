import 'package:flutter/widgets.dart';

extension BuildContextX on BuildContext {
  T inheritedOf<T extends InheritedWidget>() {
    final T? widget = getInheritedWidgetOfExactType<T>();
    assert(widget != null, 'No $T found above this context.');
    if (widget == null) throw StateError('No $T found above this context.');
    return widget;
  }

  T? maybeInheritedOf<T extends InheritedWidget>() =>
      getInheritedWidgetOfExactType<T>();
}

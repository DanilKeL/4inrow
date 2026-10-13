import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:four3/src/feature/appearance/data/appearance_repository.dart';
import 'package:four3/src/feature/appearance/data/skin_image_cache.dart';
import 'package:four3/src/feature/appearance/domain/model/skin_catalog.dart';
import 'package:four3/src/feature/initialization/domain/model/dependencies_container.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';

class AppearanceRootScope extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  static AppearanceController of(BuildContext context) {
    final _InheritedAppearanceScope? scope = context
        .dependOnInheritedWidgetOfExactType<_InheritedAppearanceScope>();
    assert(scope != null, 'No AppearanceRootScope found above this context.');
    if (scope == null) throw StateError('No AppearanceRootScope found.');
    return scope.controller;
  }

  @override
  State<AppearanceRootScope> createState() => _AppearanceRootScopeState();
}

class _AppearanceRootScopeState extends State<AppearanceRootScope>
    with WidgetsBindingObserver {
  late final AppearanceController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final RootDependenciesContainer root = RootScope.of(context);
    _controller = AppearanceController(
      repository: root.appearanceRepository,
      imageCache: root.skinImageCache,
    )..start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.resume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _InheritedAppearanceScope(controller: _controller, child: widget.child);
}

final class AppearanceController extends ChangeNotifier {
  new({required this.repository, required this.imageCache})
    : _catalog = repository.cached();

  final AppearanceRepository repository;
  final SkinImageCache imageCache;
  SkinCatalog _catalog;
  StreamSubscription<SkinCatalog>? _events;
  bool _disposed = false;
  int _connectionGeneration = 0;

  SkinCatalog get catalog => _catalog;
  Skin get skin => _catalog.activeSkin;

  void start() {
    unawaited(_saveCurrent());
    _prefetch();
    unawaited(_refresh());
    _events = repository.events().listen(_accept);
  }

  void resume() {
    final int generation = ++_connectionGeneration;
    unawaited(_resume(generation));
  }

  void pause() {
    _connectionGeneration++;
    final StreamSubscription<SkinCatalog>? events = _events;
    _events = null;
    unawaited(events?.cancel() ?? Future<void>.value());
  }

  Future<void> _resume(int generation) async {
    await _refresh();
    if (_disposed || generation != _connectionGeneration) return;
    await _events?.cancel();
    if (_disposed || generation != _connectionGeneration) return;
    _events = repository.events().listen(_accept);
  }

  Future<void> _refresh() async {
    final SkinCatalog? catalog = await repository.refresh();
    if (catalog != null) _accept(catalog);
  }

  Future<void> _saveCurrent() async {
    try {
      await repository.save(_catalog);
    } on Object {
      // A full or unavailable preferences store must not block the game.
    }
  }

  void _accept(SkinCatalog next) {
    if (_disposed || next.revision < _catalog.revision || next == _catalog) {
      return;
    }
    _catalog = next;
    _prefetch();
    notifyListeners();
  }

  void _prefetch() =>
      unawaited(imageCache.preload(skin.design?.imageIds ?? const <String>{}));

  @override
  void dispose() {
    _disposed = true;
    _connectionGeneration++;
    unawaited(_events?.cancel() ?? Future<void>.value());
    _events = null;
    super.dispose();
  }
}

class _InheritedAppearanceScope
    extends InheritedNotifier<AppearanceController> {
  const new({required AppearanceController controller, required super.child})
    : super(notifier: controller);

  AppearanceController get controller => notifier!;
}

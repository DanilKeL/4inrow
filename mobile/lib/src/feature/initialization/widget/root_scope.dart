import 'package:flutter/material.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/app/locale_scope.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/initialization/domain/model/dependencies_container.dart';
import 'package:four3/src/feature/initialization/logic/composition_root.dart';

typedef AppScopesBuilder = Widget Function(Widget child);

class RootScope extends StatefulWidget {
  const new({required this.child, required this.scopesBuilder, super.key});

  final Widget child;
  final AppScopesBuilder scopesBuilder;

  static RootDependenciesContainer of(BuildContext context) =>
      context.inheritedOf<_InheritedRootScope>().dependencies;

  @override
  State<RootScope> createState() => _RootScopeState();
}

class _RootScopeState extends State<RootScope> {
  static const Duration _launchTransitionDuration = Duration(milliseconds: 650);

  late Future<RootDependenciesContainer> _future = const CompositionRoot()
      .compose();
  RootDependenciesContainer? _dependencies;
  LocaleController? _localeController;

  void _localeChanged() => setState(() {});

  void _bindDependencies(RootDependenciesContainer dependencies) {
    if (_dependencies != null) return;
    _dependencies = dependencies;
    _localeController = LocaleController(dependencies.appLocaleDatasource)
      ..addListener(_localeChanged);
  }

  @override
  void dispose() {
    _localeController?.removeListener(_localeChanged);
    _localeController?.dispose();
    _dependencies?.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<RootDependenciesContainer>(
    future: _future,
    builder: (context, snapshot) {
      late final Widget screen;
      if (snapshot.hasError) {
        screen = _LaunchScreen(
          key: const ValueKey<String>('launch-error'),
          failed: true,
          onRetry: () =>
              setState(() => _future = const CompositionRoot().compose()),
        );
      } else if (snapshot.data case final dependencies?) {
        _bindDependencies(dependencies);
        screen = KeyedSubtree(
          key: const ValueKey<String>('application'),
          child: widget.child,
        );
      } else {
        screen = const _LaunchScreen(key: ValueKey<String>('launch-loading'));
      }

      final bool animationsDisabled = WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations;
      return MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: _localeController?.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: appSupportedLocales,
        localeListResolutionCallback: resolveAppLocale,
        builder: (context, navigator) {
          final Widget navigatorChild = navigator ?? const SizedBox.shrink();
          final RootDependenciesContainer? dependencies = snapshot.data;
          final LocaleController? localeController = _localeController;
          if (dependencies == null || localeController == null) {
            return navigatorChild;
          }
          return _InheritedRootScope(
            dependencies: dependencies,
            child: AppLocaleScope(
              locale: localeController.locale,
              setLocale: localeController.setLocale,
              child: widget.scopesBuilder(navigatorChild),
            ),
          );
        },
        home: AnimatedSwitcher(
          duration: animationsDisabled
              ? Duration.zero
              : _launchTransitionDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final Widget scaledChild = ScaleTransition(
              scale: Tween<double>(begin: .985, end: 1).animate(animation),
              child: child,
            );
            if (child.key == const ValueKey<String>('application')) {
              return scaledChild;
            }
            return FadeTransition(opacity: animation, child: scaledChild);
          },
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [?currentChild, ...previousChildren],
          ),
          child: screen,
        ),
      );
    },
  );
}

class _LaunchScreen extends StatelessWidget {
  const new({this.failed = false, this.onRetry, super.key});
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3F2EE),
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text.rich(
              TextSpan(
                text: 'FOUR',
                children: [
                  TextSpan(
                    text: '3',
                    style: TextStyle(color: Color(0xFF2955E7), fontSize: 18),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -2,
              ),
            ),
            const SizedBox(height: 30),
            const _LoadingSculpture(),
            const SizedBox(height: 20),
            Text(
              failed ? context.l10n.loadBoardFailed : context.l10n.loadingGame,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                failed
                    ? context.l10n.checkConnection
                    : context.l10n.loadingBoard,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF777A75), fontSize: 12),
              ),
            ),
            const SizedBox(height: 20),
            if (!failed)
              const SizedBox(
                width: 128,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: Color(0xFF2955E7),
                  backgroundColor: Color(0xFFDDDFD7),
                ),
              )
            else
              FilledButton(onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ),
      ),
    ),
  );
}

class _LoadingSculpture extends StatefulWidget {
  const new();

  @override
  State<_LoadingSculpture> createState() => _LoadingSculptureState();
}

class _LoadingSculptureState extends State<_LoadingSculpture>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  double _offset(double delay) {
    if (MediaQuery.disableAnimationsOf(context)) return 0;
    final double progress = (_controller.value - delay) % 1;
    if (progress <= .25) return -14 * (progress / .25);
    if (progress <= .45) return -14 * (1 - (progress - .25) / .2);
    return 0;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    height: 170,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 15,
            bottom: 12,
            child: Stack(
              children: [
                Container(
                  width: 130,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFF353A3D),
                    borderRadius: BorderRadius.circular(65),
                  ),
                ),
                Container(
                  width: 130,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E2DA),
                    border: Border.all(color: const Color(0xFFD0CEC6)),
                    borderRadius: BorderRadius.circular(65),
                  ),
                ),
              ],
            ),
          ),
          _LoadingCoin(
            bottom: 42,
            offset: _offset(0),
            color: const Color(0xFF30353C),
            edge: const Color(0xFF202429),
            hole: const Color(0xFF9B9D9E),
          ),
          _LoadingCoin(
            bottom: 68,
            offset: _offset(.064),
            color: const Color(0xFFF8F1E3),
            edge: const Color(0xFFD9D0BF),
            hole: const Color(0xFF9B9D9E),
          ),
          _LoadingCoin(
            bottom: 94,
            offset: _offset(.128),
            color: const Color(0xFF416BED),
            edge: const Color(0xFF2955CE),
            hole: const Color(0xFFC7D2FA),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _LoadingCoin extends StatelessWidget {
  const new({
    required this.bottom,
    required this.offset,
    required this.color,
    required this.edge,
    required this.hole,
  });

  final double bottom;
  final double offset;
  final Color color;
  final Color edge;
  final Color hole;

  @override
  Widget build(BuildContext context) => Positioned(
    bottom: bottom,
    child: Transform.translate(
      offset: Offset(0, offset),
      child: SizedBox(
        width: 68,
        height: 35,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: edge,
                borderRadius: BorderRadius.circular(34),
              ),
            ),
            Container(
              height: 25,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(34),
              ),
            ),
            Positioned(
              top: 8,
              left: 30,
              child: Container(
                width: 7,
                height: 4,
                decoration: BoxDecoration(
                  border: Border.all(color: hole),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InheritedRootScope extends InheritedWidget {
  const new({required this.dependencies, required super.child});
  final RootDependenciesContainer dependencies;

  @override
  bool updateShouldNotify(covariant _InheritedRootScope oldWidget) => false;
}

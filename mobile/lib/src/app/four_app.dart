import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/app/locale_scope.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/game/widget/game_shell.dart';
import 'package:four3/src/feature/initialization/widget/root_scope.dart';

class FourApp extends StatefulWidget {
  const new({super.key});

  @override
  State<FourApp> createState() => _FourAppState();
}

class _FourAppState extends State<FourApp> {
  LocaleController? _controller;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _controller = LocaleController(RootScope.of(context).appLocaleDatasource)
      ..addListener(_localeChanged);
  }

  void _localeChanged() => setState(() {});

  @override
  void dispose() {
    _controller?.removeListener(_localeChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppLocaleScope(
    locale: _controller?.locale,
    setLocale: _controller!.setLocale,
    child: MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: _controller?.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: appSupportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      home: const GameShell(),
    ),
  );
}

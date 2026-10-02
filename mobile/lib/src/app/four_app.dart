import 'package:flutter/material.dart';

import 'package:four3/src/common/theme/app_theme.dart';
import 'package:four3/src/feature/game/widget/game_shell.dart';

class FourApp extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FOUR³',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const GameShell(),
  );
}
